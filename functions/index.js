from pathlib import Path

code = r"""const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

// Satu kali inisialisasi untuk seluruh Cloud Functions.
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const DAY = {
  senin: 1,
  selasa: 2,
  rabu: 3,
  kamis: 4,
  jumat: 5,
  sabtu: 6,
  minggu: 7
};

async function tokensForSchedule(data) {
  const tokens = new Set();
  const uids = Array.isArray(data.anggotaUid) ? data.anggotaUid : [];

  for (const uid of uids) {
    const snap = await db.collection('users').doc(String(uid)).get();
    (snap.data()?.fcmTokens || []).forEach(t => tokens.add(t));
  }

  if (!uids.length) {
    const names = String(data.anggota || '')
      .split(/[,;\n]/)
      .map(x => x.trim())
      .filter(Boolean);

    for (const name of names) {
      const snap = await db.collection('users')
        .where('nama', '==', name)
        .limit(5)
        .get();

      snap.docs.forEach(d =>
        (d.data().fcmTokens || []).forEach(t => tokens.add(t))
      );
    }
  }

  return [...tokens];
}

async function sendScheduleMessage(data, title, body) {
  const tokens = await tokensForSchedule(data);
  if (!tokens.length) return;

  // Maksimal 500 token per pengiriman.
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
      if (
        !r.success &&
        [
          'messaging/invalid-registration-token',
          'messaging/registration-token-not-registered'
        ].includes(r.error?.code)
      ) {
        invalid.push(chunk[index]);
      }
    });

    if (invalid.length) {
      const users = await db.collection('users').get();

      for (let start = 0; start < users.docs.length; start += 500) {
        const batch = db.batch();

        users.docs.slice(start, start + 500).forEach(doc => {
          const old = doc.data().fcmTokens || [];
          const next = old.filter(t => !invalid.includes(t));

          if (next.length !== old.length) {
            batch.update(doc.ref, { fcmTokens: next });
          }
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
  const snap = await db.collection('kampung')
    .doc(kampungId)
    .collection('sensus')
    .get();

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

  await db.collection('kampung')
    .doc(kampungId)
    .collection('statistik')
    .doc('penduduk')
    .set({
      totalPenduduk: snap.size,
      lakiLaki,
      perempuan,
      totalKK: kk.size,
      diperbaruiPada: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
}

exports.updatePopulationStats = onDocumentWritten(
  'kampung/{kampungId}/sensus/{residentId}',
  async event => {
    await rebuildPopulationStats(event.params.kampungId);
  }
);

exports.refreshPopulationStatsDaily = onSchedule(
  {
    schedule: 'every 24 hours',
    timeZone: 'Asia/Jakarta'
  },
  async () => {
    await rebuildPopulationStats('kiarajangkung');
  }
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

    if (before && JSON.stringify(before) === JSON.stringify(after)) {
      return;
    }

    const area = `RT ${after.rt || '-'} / RW ${after.rw || '-'}`;

    await sendScheduleMessage(
      after,
      'Perubahan Jadwal Ronda',
      `${after.hari || ''} • ${area} • ${after.jamMulai || '21.00'}–${after.jamSelesai || '04.00'}. Silakan periksa jadwal di aplikasi.`
    );
  }
);

exports.rondaReminders = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: 'Asia/Jakarta'
  },
  async () => {
    const now = new Date();
    const nowJakarta = new Date(now.getTime() + 7 * 60 * 60 * 1000);

    const snap = await db.collection('kampung')
      .doc('kiarajangkung')
      .collection('ronda')
      .get();

    for (const doc of snap.docs) {
      const d = doc.data();
      const weekday = DAY[String(d.hari || '').toLowerCase()];

      const match = String(d.jamMulai || '21:00')
        .match(/^(\d{1,2})[:.](\d{2})$/);

      if (!weekday || !match) continue;

      const [_, hour, minute] = match;

      for (let offset = 0; offset <= 7; offset++) {
        const date = new Date(
          nowJakarta.getTime() + offset * 86400000
        );

        if (date.getUTCDay() === weekday % 7) {
          const targetWallClock = Date.UTC(
            date.getUTCFullYear(),
            date.getUTCMonth(),
            date.getUTCDate(),
            Number(hour),
            Number(minute),
            0
          );

          const target = new Date(
            targetWallClock - 7 * 60 * 60 * 1000
          );

          const diff = target.getTime() - now.getTime();

          const kind =
            diff >= 23.9 * 3600000 && diff <= 24.1 * 3600000
              ? 'h1d'
              : diff >= 55 * 60000 && diff <= 65 * 60000
                ? 'h1'
                : null;

          if (!kind) continue;

          const dateKey =
            `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')}`;

          const marker = db.collection('kampung')
            .doc('kiarajangkung')
            .collection('ronda_notifikasi')
            .doc(`${doc.id}_${dateKey}_${kind}`);

          if ((await marker.get()).exists) continue;

          await sendScheduleMessage(
            d,
            kind === 'h1d'
              ? 'Pengingat Ronda Besok'
              : 'Pengingat Ronda 1 Jam Lagi',
            `${d.hari || ''}, ${dateKey} pukul ${d.jamMulai || '21.00'} • RT ${d.rt || '-'} / RW ${d.rw || '-'}. Jangan lupa hadir.`
          );

          await marker.set({
            scheduleId: doc.id,
            tanggal: dateKey,
            jenis: kind,
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

    const targetLevel = String(
      data.targetLevel || 'kampung'
    ).toLowerCase();

    const fieldByLevel = {
      kawil: 'kawilId',
      rw: 'rwId',
      rt: 'rtId'
    };

    let users = db.collection('users');

    if (fieldByLevel[targetLevel]) {
      const field = fieldByLevel[targetLevel];
      const value = String(data[field] || '');

      if (!value) {
        await event.data.ref.update({
          status: 'gagal',
          error: `Target ${field} kosong`
        });
        return;
      }

      users = users.where(field, '==', value);
    }

    const userSnap = await users.get();
    const tokenSet = new Set();

    userSnap.docs.forEach(doc => {
      const user = doc.data() || {};

      if (
        String(user.status || 'Aktif').toLowerCase() !== 'aktif' ||
        user.pushEnabled === false
      ) {
        return;
      }

      (Array.isArray(user.fcmTokens) ? user.fcmTokens : [])
        .forEach(token => {
          if (typeof token === 'string' && token.trim()) {
            tokenSet.add(token.trim());
          }
        });
    });

    const tokens = [...tokenSet];

    if (!tokens.length) {
      await event.data.ref.update({
        status: 'tanpa_token',
        jumlahToken: 0
      });
      return;
    }

    let sent = 0;
    let failed = 0;

    for (let i = 0; i < tokens.length; i += 500) {
      const chunk = tokens.slice(i, i + 500);

      const result = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: {
          title: String(
            data.judul || 'Informasi Kampung Kiarajangkung'
          ),
          body: String(
            data.pesan || 'Ada informasi baru dari pengurus wilayah.'
          )
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
"""

path = Path("/mnt/data/index-kampung-digital-baru.js")
path.write_text(code, encoding="utf-8")

print(f"File berhasil dibuat: {path.name}")
print(f"Ukuran: {path.stat().st_size:,} byte")
print(f"Jumlah baris: {len(code.splitlines())}")
