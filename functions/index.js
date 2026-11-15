const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

// Satu kali inisialisasi untuk seluruh Cloud Functions.
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const DAY = {
  senin: 1, selasa: 2, rabu: 3, kamis: 4, jumat: 5, sabtu: 6, minggu: 7
};

async function tokensForSchedule(data) {
  const tokens = new Set();
  const uids = Array.isArray(data.anggotaUid) ? data.anggotaUid : [];
  for (const uid of uids) {
    const snap = await db.collection('users').doc(String(uid)).get();
    (snap.data()?.fcmTokens || []).forEach(t => tokens.add(t));
  }
  if (!uids.length) {
    const names = String(data.anggota || '').split(/[,;\n]/).map(x => x.trim()).filter(Boolean);
    for (const name of names) {
      const snap = await db.collection('users').where('nama', '==', name).limit(5).get();
      snap.docs.forEach(d => (d.data().fcmTokens || []).forEach(t => tokens.add(t)));
    }
  }
  return [...tokens];
}

async function sendScheduleMessage(data, title, body) {
  const tokens = await tokensForSchedule(data);
  if (!tokens.length) return;
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    const response = await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      notification: { title, body },
      data: { type: 'ronda', screen: 'ronda' },
      android: { priority: 'high' }
    });
    const invalid = [];
    response.responses.forEach((r, index) => {
      if (!r.success && [
        'messaging/invalid-registration-token',
        'messaging/registration-token-not-registered'
      ].includes(r.error?.code)) invalid.push(chunk[index]);
    });
    if (invalid.length) {
      const users = await db.collection('users').get();
      for (let start = 0; start < users.docs.length; start += 500) {
        const batch = db.batch();
        users.docs.slice(start, start + 500).forEach(doc => {
          const old = doc.data().fcmTokens || [];
          const next = old.filter(t => !invalid.includes(t));
          if (next.length !== old.length) batch.update(doc.ref, { fcmTokens: next });
        });
        await batch.commit();
      }
    }
  }
}

// ============================================================
// STATISTIK PENDUDUK
// ============================================================
async function rebuildPopulationStats(kampungId) {
  const snap = await db.collection('kampung').doc(kampungId).collection('sensus').get();
  let lakiLaki = 0;
  let perempuan = 0;
  const kk = new Set();
  for (const doc of snap.docs) {
    const d = doc.data();
    const gender = String(d.jenisKelamin || '').toLowerCase();
    if (gender.includes('laki') || gender === 'l') lakiLaki++;
    if (gender.includes('perempuan') || gender === 'p') perempuan++;
    const noKK = String(d.noKK || '').trim();
    if (noKK) kk.add(noKK);
  }
  await db.collection('kampung').doc(kampungId).collection('statistik').doc('penduduk').set({
    totalPenduduk: snap.size,
    lakiLaki,
    perempuan,
    totalKK: kk.size,
    diperbaruiPada: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });
}

exports.updatePopulationStats = onDocumentWritten(
  'kampung/{kampungId}/sensus/{residentId}',
  async event => { await rebuildPopulationStats(event.params.kampungId); }
);

exports.refreshPopulationStatsDaily = onSchedule(
  { schedule: 'every 24 hours', timeZone: 'Asia/Jakarta' },
  async () => { await rebuildPopulationStats('kiarajangkung'); }
);

// ============================================================
// NOTIFIKASI DAN PENGINGAT JADWAL RONDA
// ============================================================
exports.rondaScheduleChanged = onDocumentWritten(
  'kampung/{kampungId}/ronda/{scheduleId}',
  async event => {
    const after = event.data?.after?.data();
    if (!after) return;
    const before = event.data?.before?.data();
    if (before && JSON.stringify(before) === JSON.stringify(after)) return;
    const area = `RT ${after.rt || '-'} / RW ${after.rw || '-'}`;
    await sendScheduleMessage(
      after,
      'Perubahan Jadwal Ronda',
      `${after.hari || ''} • ${area} • ${after.jamMulai || '21.00'}–${after.jamSelesai || '04.00'}. Silakan periksa jadwal di aplikasi.`
    );
  }
);

exports.rondaReminders = onSchedule(
  { schedule: 'every 5 minutes', timeZone: 'Asia/Jakarta' },
  async () => {
    const now = new Date();
    const nowJakarta = new Date(now.getTime() + 7 * 60 * 60 * 1000);
    const snap = await db.collection('kampung').doc('kiarajangkung').collection('ronda').get();

    for (const doc of snap.docs) {
      const d = doc.data();
      const weekday = DAY[String(d.hari || '').toLowerCase()];
      const match = String(d.jamMulai || '21:00').match(/^(\d{1,2})[:.](\d{2})$/);
      if (!weekday || !match) continue;
      const [_, hour, minute] = match;

      for (let offset = 0; offset <= 7; offset++) {
        const date = new Date(nowJakarta.getTime() + offset * 86400000);
        if (date.getUTCDay() === weekday % 7) {
          const targetWallClock = Date.UTC(
            date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(),
            Number(hour), Number(minute), 0
          );
          const target = new Date(targetWallClock - 7 * 60 * 60 * 1000);
          const diff = target.getTime() - now.getTime();
          const kind = diff >= 23.9 * 3600000 && diff <= 24.1 * 3600000
            ? 'h1d'
            : diff >= 55 * 60000 && diff <= 65 * 60000 ? 'h1' : null;
          if (!kind) continue;

          const dateKey = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')}`;
          const marker = db.collection('kampung').doc('kiarajangkung')
            .collection('ronda_notifikasi').doc(`${doc.id}_${dateKey}_${kind}`);
          if ((await marker.get()).exists) continue;

          await sendScheduleMessage(
            d,
            kind === 'h1d' ? 'Pengingat Ronda Besok' : 'Pengingat Ronda 1 Jam Lagi',
            `${d.hari || ''}, ${dateKey} pukul ${d.jamMulai || '21.00'} • RT ${d.rt || '-'} / RW ${d.rw || '-'}. Jangan lupa hadir.`
          );
          await marker.set({
            scheduleId: doc.id, tanggal: dateKey, jenis: kind,
            sentAt: admin.firestore.FieldValue.serverTimestamp()
          });
        }
      }
    }
  }
);

// ============================================================
// NOTIFIKASI TAHAP 2 DAN TAHAP 3
// ============================================================
exports.sendKampungNotificationPush = onDocumentCreated(
  'kampung/kiarajangkung/notifikasi/{notificationId}',
  async event => {
    const data = event.data?.data();
    if (!data) return;
    const targetLevel = String(data.targetLevel || 'kampung').toLowerCase();
    const fieldByLevel = { kawil: 'kawilId', rw: 'rwId', rt: 'rtId' };
    let users = db.collection('users');

    if (fieldByLevel[targetLevel]) {
      const field = fieldByLevel[targetLevel];
      const value = String(data[field] || '');
      if (!value) {
        await event.data.ref.update({ status: 'gagal', error: `Target ${field} kosong` });
        return;
      }
      users = users.where(field, '==', value);
    }

    const userSnap = await users.get();
    const tokenSet = new Set();
    userSnap.docs.forEach(doc => {
      const user = doc.data() || {};
      if (String(user.status || 'Aktif').toLowerCase() !== 'aktif' || user.pushEnabled === false) return;
      (Array.isArray(user.fcmTokens) ? user.fcmTokens : []).forEach(token => {
        if (typeof token === 'string' && token.trim()) tokenSet.add(token.trim());
      });
    });

    const tokens = [...tokenSet];
    if (!tokens.length) {
      await event.data.ref.update({ status: 'tanpa_token', jumlahToken: 0 });
      return;
    }

    let sent = 0;
    let failed = 0;
    for (let i = 0; i < tokens.length; i += 500) {
      const chunk = tokens.slice(i, i + 500);
      const result = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: {
          title: String(data.judul || 'Informasi Kampung Kiarajangkung'),
          body: String(data.pesan || 'Ada informasi baru dari pengurus wilayah.')
        },
        data: {
          type: 'kampung',
          notificationId: event.params.notificationId,
          title: String(data.judul || '')
        },
        android: { priority: 'high' }
      });
      sent += result.successCount;
      failed += result.failureCount;
    }
    await event.data.ref.update({
      status: failed === 0 ? 'terkirim' : 'sebagian_terkirim',
      jumlahToken: tokens.length,
      berhasil: sent,
      gagal: failed,
      terkirimAt: admin.firestore.FieldValue.serverTimestamp()
    });
  }
);

// ============================================================
// RESET AKUN WARGA — OWNER ONLY
// ============================================================
function isOwnerProfile(profile) {
  const roles = Array.isArray(profile.roles)
    ? profile.roles.map(x => String(x).toLowerCase())
    : [];
  return String(profile.role || '').toLowerCase() === 'owner' || roles.includes('owner');
}

function passwordFromBirthDate(raw) {
  const value = String(raw || '').trim();
  let day, month, year;
  let match = value.match(/^(\d{2})[-/.](\d{2})[-/.](\d{4})$/);
  if (match) {
    day = Number(match[1]); month = Number(match[2]); year = Number(match[3]);
  } else {
    match = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (match) {
      year = Number(match[1]); month = Number(match[2]); day = Number(match[3]);
    }
  }
  if (!day || !month || !year) {
    throw new HttpsError('failed-precondition', 'Tanggal lahir Sensus harus DD-MM-YYYY atau YYYY-MM-DD.');
  }
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day || year < 1900) {
    throw new HttpsError('failed-precondition', 'Tanggal lahir di Sensus tidak valid.');
  }
  return `${String(day).padStart(2, '0')}${String(month).padStart(2, '0')}${year}`;
}

exports.resetResidentAccount = onCall(async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Silakan login kembali.');

  const callerRef = db.collection('users').doc(request.auth.uid);
  const callerSnap = await callerRef.get();
  if (!callerSnap.exists || !isOwnerProfile(callerSnap.data() || {})) {
    throw new HttpsError('permission-denied', 'Hanya Owner yang boleh mereset akun warga.');
  }

  const wargaId = String(request.data?.wargaId || '').trim();
  if (!wargaId || wargaId.length > 150) {
    throw new HttpsError('invalid-argument', 'ID dokumen warga tidak valid.');
  }

  const residentRef = db.collection('kampung').doc('kiarajangkung')
    .collection('sensus').doc(wargaId);
  const residentSnap = await residentRef.get();
  if (!residentSnap.exists) throw new HttpsError('not-found', 'Data warga tidak ditemukan.');

  const resident = residentSnap.data() || {};
  const uid = String(resident.accountUid || '').trim();
  const nik = String(resident.nik || '').replace(/\D/g, '');
  const nama = String(resident.nama || '').trim();

  if (!uid) {
    throw new HttpsError('failed-precondition', 'accountUid kosong. Reset dibatalkan agar tidak membuat akun duplikat.');
  }
  if (!/^\d{16}$/.test(nik)) throw new HttpsError('failed-precondition', 'NIK Sensus harus 16 digit.');
  if (!nama) throw new HttpsError('failed-precondition', 'Nama warga di Sensus kosong.');

  const statusWarga = String(resident.statusWarga || 'Aktif').trim().toLowerCase();
  if (['arsip', 'nonaktif', 'pindah', 'meninggal'].includes(statusWarga)) {
    throw new HttpsError('failed-precondition', 'Akun warga berstatus arsip/nonaktif tidak dapat direset dari daftar aktif.');
  }

  const password = passwordFromBirthDate(resident.tanggalLahir);
  const expectedEmail = `${nik}@login.kiarajangkung.id`;

  let authUser;
  try {
    authUser = await admin.auth().getUser(uid);
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      throw new HttpsError('failed-precondition', 'Akun Firebase Auth tidak ditemukan untuk accountUid ini. Tidak dibuat akun baru.');
    }
    throw new HttpsError('internal', `Gagal memeriksa akun Firebase: ${error.message}`);
  }

  if (String(authUser.email || '').toLowerCase() !== expectedEmail.toLowerCase()) {
    throw new HttpsError('failed-precondition',
      'Email Firebase tidak cocok dengan alias NIK. Reset dibatalkan tanpa mengubah akun.');
  }

  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  const oldProfile = userSnap.exists ? (userSnap.data() || {}) : {};

  // Profil lama dipertahankan sepenuhnya jika masih ada. Jika hilang,
  // jangan menebak jabatan: buat profil dasar Warga dan area dari Sensus.
  const roles = Array.isArray(oldProfile.roles) && oldProfile.roles.length
    ? oldProfile.roles.map(x => String(x).toLowerCase())
    : oldProfile.role ? [String(oldProfile.role).toLowerCase()] : ['warga'];
  const role = String(oldProfile.role || roles[0] || 'warga').toLowerCase();

  const restoredProfile = {
    ...oldProfile,
    uid,
    email: expectedEmail,
    nik,
    nama,
    wargaId,
    role,
    roles,
    status: oldProfile.status || 'Aktif',
    telepon: String(resident.telepon || oldProfile.telepon || ''),
    alamat: String(resident.alamat || oldProfile.alamat || ''),
    kawil: String(resident.kawil || oldProfile.kawil || ''),
    rw: String(resident.rw || oldProfile.rw || ''),
    rt: String(resident.rt || oldProfile.rt || ''),
    kawilId: String(resident.kawilId || oldProfile.kawilId || ''),
    rwId: String(resident.rwId || oldProfile.rwId || ''),
    rtId: String(resident.rtId || oldProfile.rtId || ''),
    mustChangePassword: true,
    passwordResetAt: admin.firestore.FieldValue.serverTimestamp(),
    passwordResetBy: request.auth.uid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };

  await admin.auth().updateUser(uid, { password });
  await userRef.set(restoredProfile, { merge: true });
  await residentRef.set({
    akunStatus: 'Aktif',
    akunResetAt: admin.firestore.FieldValue.serverTimestamp(),
    akunResetOleh: request.auth.uid
  }, { merge: true });

  return {
    ok: true,
    wargaId,
    uid,
    message: `Akun ${nama} berhasil direset. Username tetap NIK; password awal DDMMYYYY.`
  };
});
