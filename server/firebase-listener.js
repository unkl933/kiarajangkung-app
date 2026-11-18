'use strict';

const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const serviceAccount = require('./service-account.json');

if (!getApps().length) initializeApp({ credential: cert(serviceAccount) });

const db = getFirestore();
const messaging = getMessaging();
const NOTIFICATION_QUEUE = db.collection('kampung').doc('kiarajangkung').collection('notifikasi');
const ACTIVE_STATUS = 'aktif';
const PENDING_STATUS = ['baru', 'menunggu'];
const CLAIM_TIMEOUT_MS = 5 * 60 * 1000;

function normalizeRole(value) {
  const role = String(value || '').trim().toLowerCase();
  const aliases = { owner: 'owner', admin: 'admin', kawil: 'perangkat_kawil', perangkat_kawil: 'perangkat_kawil', rw: 'ketua_rw', ketua_rw: 'ketua_rw', rt: 'ketua_rt', ketua_rt: 'ketua_rt' };
  return aliases[role] || role;
}
function getRoles(profile) {
  return [...new Set([profile.role, ...(Array.isArray(profile.roles) ? profile.roles : [])].map(normalizeRole).filter(Boolean))];
}
function normalizeLevel(value) {
  const level = String(value || 'kampung').trim().toLowerCase();
  if (['kawil', 'perangkat_kawil'].includes(level)) return 'kawil';
  if (['rw', 'ketua_rw'].includes(level)) return 'rw';
  if (['rt', 'ketua_rt'].includes(level)) return 'rt';
  if (['kampung', 'semua', 'warga_kampung'].includes(level)) return 'kampung';
  throw new Error(`Target notifikasi tidak dikenal: ${level}`);
}
function isActiveProfile(profile) {
  return String(profile.status || '').trim().toLowerCase() === ACTIVE_STATUS;
}
function matchesArea(notification, profile, level) {
  if (level === 'kampung') return true;
  const keys = level === 'kawil' ? ['kawilId'] : level === 'rw' ? ['kawilId', 'rwId'] : ['kawilId', 'rwId', 'rtId'];
  return keys.every(key => {
    const targetId = String(notification[key] || '').trim();
    const userId = String(profile[key] || '').trim();
    return targetId.length > 0 && userId === targetId;
  });
}
function matchesTargetRoles(notification, profile) {
  const targetRoles = Array.isArray(notification.targetRoles) ? notification.targetRoles.map(normalizeRole).filter(Boolean) : [];
  return targetRoles.length === 0 || targetRoles.some(role => getRoles(profile).includes(role));
}
function collectTokens(profile) {
  const values = Array.isArray(profile.fcmTokens) ? profile.fcmTokens : [];
  return values.map(value => typeof value === 'string' ? value.trim() : value && typeof value === 'object' ? String(value.token || value.value || '').trim() : '').filter(Boolean);
}
async function claimNotification(ref) {
  return db.runTransaction(async transaction => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;
    const current = snapshot.data() || {};
    const status = String(current.status || '').trim().toLowerCase();
    if (!PENDING_STATUS.includes(status) || current.jenis === 'sos' || current.pushStatus === 'terkirim') return null;
    const lastAttempt = current.pushAttemptAt && typeof current.pushAttemptAt.toMillis === 'function' ? current.pushAttemptAt.toMillis() : 0;
    if (['memproses', 'gagal'].includes(current.pushStatus) && Date.now() - lastAttempt < CLAIM_TIMEOUT_MS) return null;
    transaction.update(ref, { pushStatus: 'memproses', pushAttemptAt: FieldValue.serverTimestamp(), pushError: FieldValue.delete() });
    return current;
  });
}
async function sendPush(tokens, title, body, jenis, notificationId) {
  let success = 0;
  let failure = 0;
  for (let index = 0; index < tokens.length; index += 500) {
    const result = await messaging.sendEachForMulticast({
      tokens: tokens.slice(index, index + 500),
      notification: { title, body },
      data: { type: String(jenis || 'informasi'), screen: 'notifikasi', notificationId: String(notificationId) },
      android: { priority: 'high', notification: { channelId: 'kampung_high', sound: 'default' } }
    });
    success += result.successCount;
    failure += result.failureCount;
  }
  return { success, failure };
}
async function processNotification(documentSnapshot) {
  const ref = documentSnapshot.ref;
  const data = await claimNotification(ref);
  if (!data) return;
  try {
    const jenis = String(data.jenis || 'informasi').trim().toLowerCase();
    if (jenis === 'sos') return;
    const level = normalizeLevel(data.targetLevel);
    const usersSnapshot = await db.collection('users').get();
    const recipients = [];
    const tokens = new Set();
    for (const userDocument of usersSnapshot.docs) {
      const profile = userDocument.data() || {};
      if (!isActiveProfile(profile) || !matchesArea(data, profile, level) || !matchesTargetRoles(data, profile)) continue;
      recipients.push(userDocument);
      collectTokens(profile).forEach(token => tokens.add(token));
    }
    const title = String(data.judul || 'Informasi Kampung Kiarajangkung');
    const body = String(data.pesan || 'Ada informasi baru di Kampung Digital Kiarajangkung.');
    const inboxId = `info_${documentSnapshot.id}`;
    for (let index = 0; index < recipients.length; index += 400) {
      const batch = db.batch();
      for (const recipient of recipients.slice(index, index + 400)) {
        batch.set(recipient.ref.collection('notifikasi').doc(inboxId), {
          kategori: jenis === 'agenda' ? 'pengumuman' : jenis, jenis, judul: title, pesan: body,
          targetLevel: level, referensiId: documentSnapshot.id, isRead: false,
          createdAt: data.createdAt || FieldValue.serverTimestamp()
        }, { merge: true });
      }
      await batch.commit();
    }
    const tokenList = [...tokens];
    const pushResult = await sendPush(tokenList, title, body, jenis, documentSnapshot.id);
    await ref.update({
      pushStatus: 'terkirim', pushTargetLevel: level, pushJumlahPenerima: recipients.length,
      pushJumlahToken: tokenList.length, pushBerhasil: pushResult.success, pushGagal: pushResult.failure,
      pushSentAt: FieldValue.serverTimestamp()
    });
    console.log('NOTIFIKASI SELESAI:', title, '| Target:', level, '| Penerima aktif:', recipients.length, '| Token:', tokenList.length, '| Berhasil:', pushResult.success, '| Gagal:', pushResult.failure);
  } catch (error) {
    console.error('GAGAL MEMPROSES:', documentSnapshot.id, error);
    await ref.update({ pushStatus: 'gagal', pushError: String(error && error.message ? error.message : error).slice(0, 500), pushFailedAt: FieldValue.serverTimestamp() });
  }
}
async function processPendingSnapshot(snapshot) {
  for (const documentSnapshot of snapshot.docs) await processNotification(documentSnapshot);
}
function startListener() {
  console.log('Memulai pemantau notifikasi Firebase Mi5...');
  const pendingQuery = NOTIFICATION_QUEUE.where('status', 'in', PENDING_STATUS);
  let retryRunning = false;
  pendingQuery.onSnapshot(snapshot => {
    snapshot.docChanges().forEach(change => {
      if (change.type === 'added' || change.type === 'modified') {
        processNotification(change.doc).catch(error => console.error('Kesalahan event notifikasi:', change.doc.id, error));
      }
    });
  }, error => console.error('Koneksi Firestore terputus:', error.message));
  setInterval(async () => {
    if (retryRunning) return;
    retryRunning = true;
    try {
      await processPendingSnapshot(await pendingQuery.get());
    } catch (error) {
      console.error('Gagal memeriksa antrean:', error.message);
    } finally {
      retryRunning = false;
    }
  }, 60 * 1000);
  console.log('Pemantau aktif. Pemeriksaan ulang antrean setiap 60 detik.');
}
startListener();
