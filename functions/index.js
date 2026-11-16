const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

const DAY = { senin: 1, selasa: 2, rabu: 3, kamis: 4, jumat: 5, sabtu: 6, minggu: 7 };

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
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { type: 'ronda', screen: 'ronda' },
    android: { priority: 'high' }
  });
  const invalid = [];
  response.responses.forEach((r, i) => {
    if (!r.success && ['messaging/invalid-registration-token','messaging/registration-token-not-registered'].includes(r.error?.code)) invalid.push(tokens[i]);
  });
  if (invalid.length) {
    const users = await db.collection('users').get();
    const batch = db.batch();
    users.docs.forEach(doc => {
      const old = doc.data().fcmTokens || [];
      const next = old.filter(t => !invalid.includes(t));
      if (next.length !== old.length) batch.update(doc.ref, { fcmTokens: next });
    });
    await batch.commit();
  }
}

// Statistik publik tanpa membuka seluruh dokumen Sensus kepada warga.
async function rebuildPopulationStats(kampungId) {
  const snap = await db.collection('kampung').doc(kampungId).collection('sensus').get();
  let total = 0;
  let male = 0;
  let female = 0;
  const kk = new Set();

  for (const doc of snap.docs) {
    const d = doc.data();
    const status = String(d.statusWarga || 'Aktif').trim().toLowerCase();
    if (['arsip', 'nonaktif', 'pindah', 'meninggal'].includes(status)) continue;

    total++;
    const gender = String(d.jenisKelamin || '').trim().toLowerCase();
    if (['laki-laki', 'laki laki', 'l', 'pria'].includes(gender)) male++;
    if (['perempuan', 'wanita', 'p'].includes(gender)) female++;

    const noKK = String(d.noKK || '').trim();
    if (noKK) kk.add(noKK);
  }

  // Gunakan dokumen ringkasan yang memang dibaca Dashboard warga.
  await db.collection('kampung').doc(kampungId)
    .collection('statistik_penduduk').doc('ringkasan').set({
      total,
      male,
      female,
      kk: kk.size,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
}
exports.updatePopulationStats = onDocumentWritten('kampung/{kampungId}/sensus/{residentId}', async event => {
  await rebuildPopulationStats(event.params.kampungId);
});
// Backfill awal dan pemeriksaan berkala agar statistik awal tetap terisi.
exports.refreshPopulationStatsDaily = onSchedule({ schedule: 'every 24 hours', timeZone: 'Asia/Jakarta' }, async () => {
  await rebuildPopulationStats('kiarajangkung');
});

exports.rondaScheduleChanged = onDocumentWritten('kampung/{kampungId}/ronda/{scheduleId}', async event => {
  const after = event.data?.after?.data();
  if (!after) return;
  const before = event.data?.before?.data();
  if (before && JSON.stringify(before) === JSON.stringify(after)) return;
  const area = `RT ${after.rt || '-'} / RW ${after.rw || '-'}`;
  await sendScheduleMessage(after, 'Perubahan Jadwal Ronda', `${after.hari || ''} • ${area} • ${after.jamMulai || '21.00'}–${after.jamSelesai || '04.00'}. Silakan periksa jadwal di aplikasi.`);
});

exports.rondaReminders = onSchedule({ schedule: 'every 5 minutes', timeZone: 'Asia/Jakarta' }, async () => {
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
        const targetWallClock = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), Number(hour), Number(minute), 0);
        const target = new Date(targetWallClock - 7 * 60 * 60 * 1000);
        const diff = target.getTime() - now.getTime();
        const kind = diff >= 23.9 * 3600000 && diff <= 24.1 * 3600000 ? 'h1d' :
                     diff >= 55 * 60000 && diff <= 65 * 60000 ? 'h1' : null;
        if (!kind) continue;
        const dateKey = `${date.getUTCFullYear()}-${String(date.getUTCMonth()+1).padStart(2,'0')}-${String(date.getUTCDate()).padStart(2,'0')}`;
        const marker = db.collection('kampung').doc('kiarajangkung').collection('ronda_notifikasi').doc(`${doc.id}_${dateKey}_${kind}`);
        if ((await marker.get()).exists) continue;
        await sendScheduleMessage(d, kind === 'h1d' ? 'Pengingat Ronda Besok' : 'Pengingat Ronda 1 Jam Lagi', `${d.hari || ''}, ${dateKey} pukul ${d.jamMulai || '21.00'} • RT ${d.rt || '-'} / RW ${d.rw || '-'}. Jangan lupa hadir.`);
        await marker.set({ scheduleId: doc.id, tanggal: dateKey, jenis: kind, sentAt: admin.firestore.FieldValue.serverTimestamp() });
      }
    }
  }
});


// Kirim push notification untuk laporan SOS kepada pengurus sesuai role dan wilayah.
exports.sosNotificationCreated = onDocumentCreated(
  'kampung/kiarajangkung/notifikasi/{notificationId}',
  async event => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() || {};
    if (String(data.jenis || '').toLowerCase() !== 'sos') return;

    const ref = snap.ref;
    const claimed = await db.runTransaction(async tx => {
      const current = await tx.get(ref);
      const status = String(current.data()?.pushStatus || '');
      if (status === 'terkirim' || status === 'memproses') return false;
      tx.update(ref, {
        pushStatus: 'memproses',
        pushAttemptAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return true;
    });
    if (!claimed) return;

    try {
      // Daftar penerima ditetapkan server. Jangan mempercayai targetRoles
      // dari dokumen yang dibuat warga karena dapat dipakai untuk broadcast massal.
      const targetRoles = ['ketua_rt', 'ketua_rw', 'perangkat_kawil', 'admin', 'owner'];
      const usersSnap = await db.collection('users').get();
      const tokens = new Set();
      const targetArea = ['kawilId', 'rwId', 'rtId'];
      let matchedUsers = 0;

      for (const userDoc of usersSnap.docs) {
        const user = userDoc.data() || {};
        // Firestore Rules menerima role utama maupun roles; gabungkan keduanya
        // agar perilaku notifikasi konsisten untuk akun multi-role.
        const roles = new Set([
          String(user.role || '').toLowerCase(),
          ...(Array.isArray(user.roles) ? user.roles.map(x => String(x).toLowerCase()) : [])
        ].filter(Boolean));
        if (![...roles].some(role => targetRoles.includes(role))) continue;

        const isGlobalManager = roles.has('admin') || roles.has('owner');
        const matchesArea = (keys) => keys.every(key => {
          const requested = String(data[key] || '').trim();
          const assigned = String(user[key] || '').trim();
          return requested.length > 0 && assigned.length > 0 && assigned === requested;
        });
        const hasRegionalRoleInArea =
          (roles.has('ketua_rt') && matchesArea(targetArea)) ||
          (roles.has('ketua_rw') && matchesArea(['kawilId', 'rwId'])) ||
          (roles.has('perangkat_kawil') && matchesArea(['kawilId']));
        if (!isGlobalManager && !hasRegionalRoleInArea) continue;

        const userTokens = Array.isArray(user.fcmTokens) ? user.fcmTokens : [];
        if (userTokens.length) matchedUsers++;
        userTokens.forEach(token => {
          if (typeof token === 'string' && token.trim()) tokens.add(token.trim());
        });
      }

      const tokenList = [...tokens];
      let sent = 0;
      let failed = 0;
      for (let i = 0; i < tokenList.length; i += 500) {
        const batch = tokenList.slice(i, i + 500);
        const result = await admin.messaging().sendEachForMulticast({
          tokens: batch,
          notification: {
            title: String(data.judul || 'SOS DARURAT'),
            body: String(data.pesan || 'Ada warga yang membutuhkan bantuan segera.')
          },
          data: {
            type: 'sos',
            screen: 'darurat',
            referensiId: String(data.referensiId || '')
          },
          android: { priority: 'high' },
          apns: { payload: { aps: { sound: 'default', contentAvailable: true } } }
        });
        sent += result.successCount;
        failed += result.failureCount;
      }

      await ref.update({
        pushStatus: 'terkirim',
        pushJumlahToken: tokenList.length,
        pushBerhasil: sent,
        pushGagal: failed,
        pushJumlahAkun: matchedUsers,
        pushSentAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (error) {
      await ref.update({
        pushStatus: 'gagal',
        pushError: String(error?.message || error).slice(0, 500),
        pushFailedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      throw error;
    }
  }
);

// Notifikasi pengaduan berjenjang. Dokumen inbox dibuat per pengguna
// dengan ID berbasis event agar retry Cloud Functions tidak menggandakan pesan.
function roleSet(user) {
  return new Set([
    String(user.role || '').toLowerCase(),
    ...(Array.isArray(user.roles) ? user.roles.map(x => String(x).toLowerCase()) : [])
  ].filter(Boolean));
}

function complaintRecipients(users, complaint, nextStatus, previousStatus) {
  const recipients = new Map();
  const add = (doc, user) => recipients.set(doc.id, { ref: doc.ref, user });
  const same = key => String(complaint[key] || '').trim();
  const hasRoleInArea = (user, role, keys) => {
    const roles = roleSet(user);
    return roles.has(role) && keys.every(key => same(key) && String(user[key] || '').trim() === same(key));
  };
  const stage = nextStatus === 'menunggu_validasi_rt' && (!previousStatus || previousStatus === 'perlu_perbaikan_rt') ? 'rt' :
    nextStatus === 'menunggu_validasi_rw' ? 'rw' :
    nextStatus === 'menunggu_validasi_kawil' ? 'kawil' : '';
  if (stage) {
    for (const doc of users.docs) {
      const user = doc.data() || {};
      const match = stage === 'rt'
        ? hasRoleInArea(user, 'ketua_rt', ['kawilId', 'rwId', 'rtId'])
        : stage === 'rw'
          ? hasRoleInArea(user, 'ketua_rw', ['kawilId', 'rwId'])
          : hasRoleInArea(user, 'perangkat_kawil', ['kawilId']);
      if (match) add(doc, user);
    }
  }
  if (previousStatus && nextStatus !== previousStatus) {
    const authorUid = String(complaint.pemohonUid || '');
    const author = users.docs.find(doc => doc.id === authorUid);
    if (author && ['menunggu_validasi_rw', 'menunggu_validasi_kawil', 'terverifikasi',
      'ditindaklanjuti', 'selesai', 'ditolak', 'perlu_perbaikan_rt', 'perlu_perbaikan_rw', 'perlu_perbaikan_kawil'].includes(nextStatus)) {
      add(author, author.data() || {});
    }
  }
  return [...recipients.entries()].map(([uid, value]) => ({ uid, ...value }));
}

exports.complaintNotificationChanged = onDocumentWritten(
  'kampung/kiarajangkung/pengaduan/{complaintId}',
  async event => {
    const before = event.data?.before?.data() || null;
    const after = event.data?.after?.data() || null;
    if (!after) return;
    const nextStatus = String(after.status || '');
    const previousStatus = String(before?.status || '');
    if (before && nextStatus === previousStatus) return;
    const users = await db.collection('users').get();
    const recipients = complaintRecipients(users, after, nextStatus, previousStatus);
    if (!recipients.length) return;

    const messages = {
      menunggu_validasi_rt: ['Pengaduan Baru', 'Ada pengaduan baru di wilayah Anda yang menunggu pemeriksaan Ketua RT.'],
      menunggu_validasi_rw: ['Pengaduan Diteruskan ke RW', 'Pengaduan telah divalidasi Ketua RT dan menunggu pemeriksaan Ketua RW.'],
      menunggu_validasi_kawil: ['Pengaduan Diteruskan ke Kawil', 'Pengaduan telah divalidasi Ketua RW dan menunggu pemeriksaan Kawil.'],
      terverifikasi: ['Pengaduan Terverifikasi', 'Pengaduan Anda telah melewati validasi berjenjang.'],
      ditindaklanjuti: ['Pengaduan Ditindaklanjuti', 'Pengaduan Anda mulai ditangani oleh Kawil.'],
      selesai: ['Pengaduan Selesai', 'Pengaduan Anda telah diselesaikan. Buka aplikasi untuk melihat catatan penyelesaian.'],
      perlu_perbaikan_rt: ['Pengaduan Perlu Diperbaiki', 'Ketua RT meminta perbaikan pada pengaduan Anda. Buka aplikasi untuk melihat alasannya.'],
      perlu_perbaikan_rw: ['Pengaduan Perlu Diperbaiki', 'Ketua RW meminta perbaikan pada pengaduan Anda. Buka aplikasi untuk melihat alasannya.'],
      perlu_perbaikan_kawil: ['Pengaduan Perlu Diperbaiki', 'Kawil meminta perbaikan pada pengaduan Anda. Buka aplikasi untuk melihat alasannya.'],
      ditolak: ['Pengaduan Tidak Dapat Dilanjutkan', 'Pengaduan Anda memerlukan perhatian. Buka aplikasi untuk melihat keterangannya.']
    };
    const [title, body] = messages[nextStatus] || ['Pembaruan Pengaduan', 'Ada pembaruan pada pengaduan Anda.'];
    const invalidByUid = new Map();
    for (const recipient of recipients) {
      const inboxRef = recipient.ref.collection('notifikasi').doc(String(event.id).replace(/[^a-zA-Z0-9_-]/g, '_'));
      const shouldSend = await db.runTransaction(async tx => {
        const existing = await tx.get(inboxRef);
        if (existing.exists) return false;
        tx.create(inboxRef, {
          kategori: 'pengaduan',
          jenis: 'pengaduan',
          judul: title,
          pesan: body,
          referensiJenis: 'pengaduan',
          referensiId: event.params.complaintId,
          statusPengaduan: nextStatus,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
        return true;
      });
      if (!shouldSend) continue;
      const tokens = Array.isArray(recipient.user.fcmTokens)
        ? [...new Set(recipient.user.fcmTokens.filter(t => typeof t === 'string' && t.trim()))]
        : [];
      if (!tokens.length) continue;
      const result = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: {
          type: 'pengaduan',
          screen: 'pelayanan',
          tab: 'pengaduan',
          referensiId: event.params.complaintId
        },
        android: { priority: 'high' }
      });
      const invalid = [];
      result.responses.forEach((response, index) => {
        if (!response.success && [
          'messaging/invalid-registration-token',
          'messaging/registration-token-not-registered'
        ].includes(response.error?.code)) invalid.push(tokens[index]);
      });
      if (invalid.length) invalidByUid.set(recipient.uid, invalid);
    }
    for (const [uid, invalid] of invalidByUid) {
      const userRef = db.collection('users').doc(uid);
      const current = (await userRef.get()).data()?.fcmTokens || [];
      await userRef.update({ fcmTokens: current.filter(token => !invalid.includes(token)) });
    }
  }
);

