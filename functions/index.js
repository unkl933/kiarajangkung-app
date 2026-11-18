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
// Kirim push DAN buat inbox permanen untuk SOS kepada Owner serta pengurus
// wilayah yang sesuai. Admin SDK melewati Rules; penerima ditentukan dari profil
// users, bukan dari targetRoles yang dikirim aplikasi warga.
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
      const currentData = current.data() || {};
      if (currentData.pushStatus === 'terkirim') return false;
      const lastAttempt = currentData.pushAttemptAt?.toDate?.()?.getTime?.() || 0;
      if (currentData.pushStatus === 'memproses' && Date.now() - lastAttempt < 5 * 60 * 1000) return false;
      tx.update(ref, {
        pushStatus: 'memproses',
        pushAttemptAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return true;
    });
    if (!claimed) return;

    try {
      const targetRoles = ['perangkat_kawil', 'kawil', 'admin', 'owner'];
      const usersSnap = await db.collection('users').get();
      const recipients = [];
      const tokens = new Set();
      const targetArea = String(data.kawilId || '').trim();

      for (const userDoc of usersSnap.docs) {
        const user = userDoc.data() || {};
        const roles = new Set([
          String(user.role || '').toLowerCase(),
          ...(Array.isArray(user.roles) ? user.roles.map(x => String(x).toLowerCase()) : [])
        ].filter(Boolean));
        if (![...roles].some(role => targetRoles.includes(role))) continue;

        const isGlobalManager = roles.has('admin') || roles.has('owner');
        const isMatchingKawil = targetArea.length > 0 &&
          String(user.kawilId || '').trim() === targetArea &&
          (roles.has('perangkat_kawil') || roles.has('kawil'));
        if (!isGlobalManager && !isMatchingKawil) continue;

        recipients.push({ uid: userDoc.id, user });
        (Array.isArray(user.fcmTokens) ? user.fcmTokens : []).forEach(token => {
          if (typeof token === 'string' && token.trim()) tokens.add(token.trim());
        });
      }

      const title = String(data.judul || 'SOS DARURAT');
      const body = String(data.pesan || 'Ada warga yang membutuhkan bantuan segera.');
      // Inbox per penerima membuat SOS tetap terlihat meskipun push ditolak OS,
      // perangkat sedang offline, atau pengguna membuka aplikasi belakangan.
      for (let i = 0; i < recipients.length; i += 400) {
        const batch = db.batch();
        for (const recipient of recipients.slice(i, i + 400)) {
          const inboxRef = db.collection('users').doc(recipient.uid)
            .collection('notifikasi').doc('sos_' + event.params.notificationId);
          batch.set(inboxRef, {
            jenis: 'sos',
            kategori: 'darurat',
            judul: title,
            pesan: body,
            referensiId: String(data.referensiId || ''),
            screen: 'darurat',
            isRead: false,
            createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
        }
        await batch.commit();
      }

      const tokenList = [...tokens];
      let sent = 0;
      let failed = 0;
      for (let i = 0; i < tokenList.length; i += 500) {
        const batchTokens = tokenList.slice(i, i + 500);
        const result = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: { title, body },
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
        pushJumlahPenerima: recipients.length,
        pushJumlahToken: tokenList.length,
        pushBerhasil: sent,
        pushGagal: failed,
        pushJumlahAkun: recipients.length,
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

// Antrean notifikasi umum: pengumuman, instruksi, tugas, dan undangan rapat.
// Dokumen antrean dibuat oleh aplikasi; Cloud Function menentukan penerima dari
// profil users agar pengirim tidak dapat memilih akun/token secara sembarang.
exports.generalNotificationCreated = onDocumentCreated(
  'kampung/kiarajangkung/notifikasi/{notificationId}',
  async event => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() || {};
    const jenis = String(data.jenis || '').toLowerCase();
    if (jenis === 'sos' || !['menunggu', 'baru'].includes(String(data.status || '').toLowerCase())) return;

    const ref = snap.ref;
    const claimed = await db.runTransaction(async tx => {
      const current = await tx.get(ref);
      const value = current.data() || {};
      if (value.pushStatus === 'terkirim') return false;
      const attemptedAt = value.pushAttemptAt?.toDate?.()?.getTime?.() || 0;
      if (value.pushStatus === 'memproses' && Date.now() - attemptedAt < 5 * 60 * 1000) return false;
      tx.update(ref, {
        pushStatus: 'memproses',
        pushAttemptAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return true;
    });
    if (!claimed) return;

    try {
      const rawTargetLevel = String(data.targetLevel || 'kampung').toLowerCase();
      const targetLevel = ['kawil', 'perangkat_kawil'].includes(rawTargetLevel) ? 'kawil' :
        ['rw', 'ketua_rw'].includes(rawTargetLevel) ? 'rw' :
        ['rt', 'ketua_rt'].includes(rawTargetLevel) ? 'rt' : 'kampung';
      const areaKeys = targetLevel === 'kawil' ? ['kawilId'] :
        targetLevel === 'rw' ? ['kawilId', 'rwId'] :
        targetLevel === 'rt' ? ['kawilId', 'rwId', 'rtId'] : [];
      const usersSnap = await db.collection('users').get();
      const recipients = [];
      const tokens = new Set();
      for (const userDoc of usersSnap.docs) {
        const user = userDoc.data() || {};
        if (areaKeys.some(key => !String(data[key] || '').trim() ||
          String(user[key] || '').trim() !== String(data[key] || '').trim())) continue;
        recipients.push(userDoc);
        (Array.isArray(user.fcmTokens) ? user.fcmTokens : []).forEach(token => {
          if (typeof token === 'string' && token.trim()) tokens.add(token.trim());
        });
      }
      // Pastikan pembuat agenda/instruksi juga menerima salinan inbox,
      // meskipun ia tidak cocok dengan filter area penerima.
      const creatorUid = String(data.dibuatOlehUid || data.createdByUid || '');
      if (creatorUid && !recipients.some(doc => doc.id === creatorUid)) {
        const creator = await db.collection('users').doc(creatorUid).get();
        if (creator.exists) {
          recipients.push(creator);
          (Array.isArray(creator.data()?.fcmTokens) ? creator.data().fcmTokens : []).forEach(token => {
            if (typeof token === 'string' && token.trim()) tokens.add(token.trim());
          });
        }
      }

      const title = String(data.judul || 'Informasi Kampung');
      const body = String(data.pesan || 'Ada informasi baru di Kampung Digital Kiarajangkung.');
      const inboxId = 'info_' + event.params.notificationId;
      for (let i = 0; i < recipients.length; i += 400) {
        const batch = db.batch();
        for (const recipient of recipients.slice(i, i + 400)) {
          batch.set(recipient.ref.collection('notifikasi').doc(inboxId), {
            kategori: jenis === 'agenda' ? 'pengumuman' : jenis || 'informasi',
            jenis: jenis || 'informasi',
            judul: title,
            pesan: body,
            targetLevel,
            referensiId: event.params.notificationId,
            isRead: false,
            createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
        }
        await batch.commit();
      }

      const tokenList = [...tokens];
      let sent = 0;
      let failed = 0;
      for (let i = 0; i < tokenList.length; i += 500) {
        const group = tokenList.slice(i, i + 500);
        const result = await admin.messaging().sendEachForMulticast({
          tokens: group,
          notification: { title, body },
          data: {
            type: jenis || 'informasi',
            screen: 'notifikasi',
            notificationId: event.params.notificationId
          },
          android: { priority: 'high' }
        });
        sent += result.successCount;
        failed += result.failureCount;
      }
      await ref.update({
        pushStatus: 'terkirim',
        pushJumlahPenerima: recipients.length,
        pushJumlahToken: tokenList.length,
        pushBerhasil: sent,
        pushGagal: failed,
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
  // Pelapor menerima konfirmasi saat pengaduan pertama kali dikirim,
  // kemudian menerima setiap perubahan status berikutnya.
  if ((!previousStatus || nextStatus !== previousStatus) &&
      (nextStatus === 'menunggu_validasi_rt' ||
       ['menunggu_validasi_rw', 'menunggu_validasi_kawil', 'terverifikasi',
        'ditindaklanjuti', 'selesai', 'ditolak', 'perlu_perbaikan_rt',
        'perlu_perbaikan_rw', 'perlu_perbaikan_kawil'].includes(nextStatus))) {
    const authorUid = String(complaint.pemohonUid || '');
    const author = users.docs.find(doc => doc.id === authorUid);
    if (author) add(author, author.data() || {});
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



// Pengumuman kampung: kirim push dan salinan inbox saat diterbitkan atau
// diperbarui. Pengumuman tanpa target wilayah berlaku untuk seluruh kampung.
exports.announcementNotificationChanged = onDocumentWritten(
  'kampung/kiarajangkung/pengumuman/{announcementId}',
  async event => {
    const before = event.data?.before?.data() || null;
    const after = event.data?.after?.data() || null;
    if (!after) return;
    const status = String(after.status || 'aktif').toLowerCase();
    if (['draf', 'nonaktif', 'arsip'].includes(status)) return;
    if (before && JSON.stringify(before) === JSON.stringify(after)) return;

    const users = await db.collection('users').get();
    const targetLevelRaw = String(after.targetLevel || 'kampung').toLowerCase();
    const targetLevel = ['kawil', 'perangkat_kawil'].includes(targetLevelRaw) ? 'kawil' :
      ['rw', 'ketua_rw'].includes(targetLevelRaw) ? 'rw' :
      ['rt', 'ketua_rt'].includes(targetLevelRaw) ? 'rt' : 'kampung';
    const keys = targetLevel === 'kawil' ? ['kawilId'] :
      targetLevel === 'rw' ? ['kawilId', 'rwId'] :
      targetLevel === 'rt' ? ['kawilId', 'rwId', 'rtId'] : [];
    const recipients = new Map();
    for (const doc of users.docs) {
      const user = doc.data() || {};
      if (keys.some(key => !String(after[key] || '').trim() ||
        String(user[key] || '').trim() !== String(after[key] || '').trim())) continue;
      recipients.set(doc.id, { ref: doc.ref, user });
    }
    const creatorUid = String(after.dibuatOlehUid || after.createdByUid || '');
    if (creatorUid && !recipients.has(creatorUid)) {
      const creator = await db.collection('users').doc(creatorUid).get();
      if (creator.exists) recipients.set(creatorUid, { ref: creator.ref, user: creator.data() || {} });
    }
    const title = String(after.judul || after.nama || 'Pengumuman Kampung');
    const body = String(after.isi || after.deskripsi || after.keterangan || 'Ada pengumuman baru di Kampung Digital Kiarajangkung.');
    await deliverUserNotifications({
      recipients: [...recipients.entries()].map(([uid, value]) => ({ uid, ...value })),
      eventKey: 'pengumuman_' + event.id,
      jenis: 'pengumuman',
      title, body,
      referensiJenis: 'pengumuman',
      referensiId: event.params.announcementId,
      screen: 'notifikasi'
    });
  }
);

// Pelayanan surat: petugas pada tahap berikutnya menerima tugas baru,
// sedangkan pemohon selalu menerima konfirmasi dan setiap perubahan status.
exports.serviceLetterNotificationChanged = onDocumentWritten(
  'kampung/kiarajangkung/pelayanan_surat/{letterId}',
  async event => {
    const before = event.data?.before?.data() || null;
    const after = event.data?.after?.data() || null;
    if (!after) return;
    const nextStatus = String(after.status || '');
    const previousStatus = String(before?.status || '');
    if (before && nextStatus === previousStatus) return;

    const users = await db.collection('users').get();
    const recipients = new Map();
    const add = (doc, user) => recipients.set(doc.id, { uid: doc.id, ref: doc.ref, user });
    const same = key => String(after[key] || '').trim();
    const matches = (user, role, keys) => roleSet(user).has(role) &&
      keys.every(key => same(key) && String(user[key] || '').trim() === same(key));
    const stage = nextStatus === 'diajukan' ? 'rt' :
      nextStatus === 'diperiksa_rt' ? 'rw' :
      nextStatus === 'diverifikasi_rw' ? 'kawil' : '';
    for (const doc of users.docs) {
      const user = doc.data() || {};
      const match = stage === 'rt' ? matches(user, 'ketua_rt', ['kawilId', 'rwId', 'rtId']) :
        stage === 'rw' ? matches(user, 'ketua_rw', ['kawilId', 'rwId']) :
        stage === 'kawil' ? matches(user, 'perangkat_kawil', ['kawilId']) : false;
      if (match) add(doc, user);
    }
    const applicantUid = String(after.pemohonUid || '');
    if (applicantUid) {
      const applicant = users.docs.find(doc => doc.id === applicantUid);
      if (applicant) add(applicant, applicant.data() || {});
    }
    if (!recipients.size) return;

    const labels = {
      diajukan: ['Pengajuan Pelayanan Baru', 'Ada permohonan surat baru yang menunggu pemeriksaan Ketua RT.'],
      diperiksa_rt: ['Pengajuan Diperiksa RT', 'Permohonan surat diteruskan untuk verifikasi Ketua RW.'],
      diverifikasi_rw: ['Pengajuan Diverifikasi RW', 'Permohonan surat menunggu persetujuan Kawil.'],
      disetujui: ['Surat Disetujui', 'Permohonan surat Anda telah disetujui. Buka aplikasi untuk melihat dokumen.'],
      perlu_perbaikan: ['Pengajuan Perlu Diperbaiki', 'Petugas meminta perbaikan pada permohonan surat Anda. Buka aplikasi untuk melihat catatan.'],
      ditolak: ['Pengajuan Ditolak', 'Permohonan surat Anda tidak dapat dilanjutkan. Buka aplikasi untuk melihat keterangannya.']
    };
    const [title, body] = labels[nextStatus] || ['Pembaruan Pelayanan', 'Ada pembaruan pada permohonan pelayanan Anda.'];
    await deliverUserNotifications({
      recipients: [...recipients.values()],
      eventKey: 'pelayanan_' + event.id,
      jenis: 'pelayanan',
      title, body,
      referensiJenis: 'pelayanan_surat',
      referensiId: event.params.letterId,
      status: nextStatus,
      screen: 'pelayanan'
    });
  }
);

// Membuat inbox per akun lebih dahulu, lalu mengirim push ke seluruh token unik.
// ID berbasis event menjaga agar retry Cloud Functions tidak menggandakan pesan.
async function deliverUserNotifications({ recipients, eventKey, jenis, title, body,
  referensiJenis, referensiId, status, screen }) {
  const tokens = new Set();
  for (const recipient of recipients) {
    const inboxRef = recipient.ref.collection('notifikasi').doc(
      String(eventKey).replace(/[^a-zA-Z0-9_-]/g, '_')
    );
    const shouldSend = await db.runTransaction(async tx => {
      const existing = await tx.get(inboxRef);
      if (existing.exists) return false;
      tx.create(inboxRef, {
        categoria: jenis,
        kategori: jenis,
        jenis,
        judul: title,
        pesan: body,
        referensiJenis,
        referensiId,
        ...(status ? { status } : {}),
        ...(screen ? { screen } : {}),
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return true;
    });
    if (!shouldSend) continue;
    (Array.isArray(recipient.user.fcmTokens) ? recipient.user.fcmTokens : [])
      .forEach(token => {
        if (typeof token === 'string' && token.trim()) tokens.add(token.trim());
      });
  }
  const tokenList = [...tokens];
  for (let i = 0; i < tokenList.length; i += 500) {
    await admin.messaging().sendEachForMulticast({
      tokens: tokenList.slice(i, i + 500),
      notification: { title, body },
      data: {
        type: jenis,
        screen: screen || 'notifikasi',
        referensiJenis: referensiJenis || '',
        referensiId: referensiId || ''
      },
      android: { priority: 'high' }
    });
  }
}
