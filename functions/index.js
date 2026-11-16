const { onDocumentWritten } = require('firebase-functions/v2/firestore');
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
    totalPenduduk: snap.size, lakiLaki, perempuan, totalKK: kk.size,
    diperbaruiPada: admin.firestore.FieldValue.serverTimestamp()
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
      const targetRoles = Array.isArray(data.targetRoles)
        ? data.targetRoles.map(x => String(x).toLowerCase())
        : ['ketua_rt', 'ketua_rw', 'perangkat_kawil', 'admin', 'owner'];
      const usersSnap = await db.collection('users').get();
      const tokens = new Set();
      const targetArea = ['kawilId', 'rwId', 'rtId'];
      let matchedUsers = 0;

      for (const userDoc of usersSnap.docs) {
        const user = userDoc.data() || {};
        const roles = Array.isArray(user.roles)
          ? user.roles.map(x => String(x).toLowerCase())
          : [String(user.role || '').toLowerCase()];
        if (!roles.some(role => targetRoles.includes(role))) continue;

        const sameArea = targetArea.every(key => {
          const requested = String(data[key] || '').trim();
          const actual = String(user[key] || '').trim();
          return !requested || !actual || requested === actual;
        });
        if (!sameArea) continue;

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
