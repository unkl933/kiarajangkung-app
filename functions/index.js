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

exports.rondaScheduleChanged = onDocumentWritten('kampung/{kampungId}/ronda/{scheduleId}', async event => {
  const after = event.data?.after?.data();
  if (!after) return;
  const before = event.data?.before?.data();
  if (before && JSON.stringify(before) === JSON.stringify(after)) return;
  const area = `RT ${after.rt || '-'} / RW ${after.rw || '-'}`;
  await sendScheduleMessage(after, 'Perubahan Jadwal Ronda', `${after.hari || ''} • ${area} • ${after.jamMulai || '21.00'}–${after.jamSelesai || '04.00'}. Silakan periksa jadwal di aplikasi.`);
});

exports.rondaReminders = onSchedule({ schedule: 'every 5 minutes', timeZone: 'Asia/Jakarta' }, async () => {
  const now = new Date(); // waktu absolut server
  const nowJakarta = new Date(now.getTime() + 7 * 60 * 60 * 1000); // jam dinding WIB
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
