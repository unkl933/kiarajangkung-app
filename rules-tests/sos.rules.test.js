import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, query, where,
  setDoc, updateDoc, serverTimestamp,
} from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rules = fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8');
const projectId = process.env.GCLOUD_PROJECT || 'demo-no-project';
const dbPath = 'kampung/kiarajangkung';
let env;

const profiles = {
  wargaA: { role: 'warga', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  wargaB: { role: 'warga', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  wargaLain: { role: 'warga', kawilId: 'kw-2', rwId: 'rw-2', rtId: 'rt-2' },
  rt: { role: 'ketua_rt', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  rw: { role: 'ketua_rw', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-9' },
  kawil: { role: 'perangkat_kawil', kawilId: 'kw-1', rwId: 'rw-9', rtId: 'rt-9' },
  admin: { role: 'admin', kawilId: '', rwId: '', rtId: '' },
  owner: { role: 'owner', kawilId: '', rwId: '', rtId: '' },
};

function report(id, ownerUid = 'wargaA', area = {}) {
  return {
    jenis: 'Kesehatan / Medis',
    uraian: 'Membutuhkan bantuan segera',
    lokasiManual: 'Dekat balai kampung',
    latitude: null,
    longitude: null,
    akurasiLokasiMeter: null,
    lokasiMaps: '',
    pemohonUid: ownerUid,
    pemohonNama: ownerUid,
    pemohonTelepon: '',
    kawil: 'Kiarajangkung',
    kawilId: area.kawilId ?? 'kw-1',
    rw: 'RW 01',
    rwId: area.rwId ?? 'rw-1',
    rt: 'RT 01',
    rtId: area.rtId ?? 'rt-1',
    status: 'baru',
    petugasMerespons: [],
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

async function seedProfiles() {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [uid, profile] of Object.entries(profiles)) {
      await setDoc(doc(db, 'users', uid), profile);
    }
    await setDoc(doc(db, dbPath, 'laporan_sos', 'sos-seed'), report('sos-seed'));
    await setDoc(doc(db, dbPath, 'laporan_sos', 'sos-other-area'),
      report('sos-other-area', 'wargaLain', { kawilId: 'kw-2', rwId: 'rw-2', rtId: 'rt-2' }));
  });
}

function sosRef(db, id) { return doc(db, dbPath, 'laporan_sos', id); }

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await seedProfiles();
});

after(async () => {
  if (env) await env.cleanup();
});

test('warga dapat membuat SOS atas nama sendiri dengan wilayah profil yang sama', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  const payload = report('new-sos');
  await assertSucceeds(setDoc(sosRef(db, 'new-sos'), payload));
});

test('warga tidak dapat membuat SOS atas nama pengguna lain', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(setDoc(sosRef(db, 'spoofed-sos'), report('spoofed-sos', 'wargaB')));
});

test('warga tidak dapat membuat SOS dengan wilayah yang berbeda dari profil', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(setDoc(sosRef(db, 'wrong-area'), report('wrong-area', 'wargaA', {
    kawilId: 'kw-2', rwId: 'rw-2', rtId: 'rt-2',
  })));
});

test('warga hanya dapat membaca laporan SOS miliknya', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertSucceeds(getDoc(sosRef(db, 'sos-seed')));
  await assertFails(getDoc(sosRef(db, 'sos-other-area')));
});

test('Ketua RT dapat membaca laporan di RT sendiri, bukan RT lain', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertSucceeds(getDoc(sosRef(db, 'sos-seed')));
  await assertFails(getDoc(sosRef(db, 'sos-other-area')));
});

test('Ketua RW dapat membaca laporan di RW sendiri', async () => {
  const db = env.authenticatedContext('rw').firestore();
  await assertSucceeds(getDoc(sosRef(db, 'sos-seed')));
  await assertFails(getDoc(sosRef(db, 'sos-other-area')));
});

test('Kawil dapat membaca laporan di wilayah Kawil sendiri', async () => {
  const db = env.authenticatedContext('kawil').firestore();
  await assertSucceeds(getDoc(sosRef(db, 'sos-seed')));
  await assertFails(getDoc(sosRef(db, 'sos-other-area')));
});

test('Admin dan Owner dapat membaca laporan SOS lintas wilayah', async () => {
  for (const uid of ['admin', 'owner']) {
    const db = env.authenticatedContext(uid).firestore();
    await assertSucceeds(getDoc(sosRef(db, 'sos-other-area')));
  }
});

test('petugas wilayah dapat mengubah status penanganan SOS', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertSucceeds(updateDoc(sosRef(db, 'sos-seed'), {
    status: 'diproses',
    catatanPetugas: 'Petugas menuju lokasi',
    updatedAt: serverTimestamp(),
  }));
});

test('petugas tidak dapat mengubah identitas pelapor atau wilayah laporan', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertFails(updateDoc(sosRef(db, 'sos-seed'), {
    pemohonUid: 'rt',
  }));
  await assertFails(updateDoc(sosRef(db, 'sos-seed'), {
    rtId: 'rt-99',
  }));
});

test('petugas dari wilayah lain tidak dapat mengubah laporan', async () => {
  const db = env.authenticatedContext('wargaLain').firestore();
  await assertFails(updateDoc(sosRef(db, 'sos-seed'), { status: 'diproses' }));
});

test('warga dapat membuat notifikasi hanya untuk SOS miliknya yang sudah ada', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  const payload = {
    jenis: 'sos',
    referensiId: 'sos-seed',
    dibuatOlehUid: 'wargaA',
    judul: 'SOS DARURAT',
    pesan: 'Membutuhkan bantuan',
    kawil: 'Kiarajangkung', kawilId: 'kw-1',
    rw: 'RW 01', rwId: 'rw-1',
    rt: 'RT 01', rtId: 'rt-1',
    targetLevel: 'darurat',
    targetRoles: ['ketua_rt', 'ketua_rw', 'perangkat_kawil', 'admin', 'owner'],
    status: 'baru',
    createdAt: new Date(),
  };
  await assertSucceeds(setDoc(doc(db, dbPath, 'notifikasi', 'notif-sos'), payload));
});

test('warga tidak dapat membuat notifikasi SOS atas nama orang lain', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  const payload = {
    jenis: 'sos', referensiId: 'sos-seed', dibuatOlehUid: 'wargaB',
    judul: 'SOS', pesan: 'Bantuan', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1',
    kawil: 'Kiarajangkung', rw: 'RW 01', rt: 'RT 01',
    targetLevel: 'darurat', targetRoles: ['ketua_rt'], status: 'baru',
    createdAt: new Date(),
  };
  await assertFails(setDoc(doc(db, dbPath, 'notifikasi', 'notif-spoof'), payload));
});

test('warga tidak dapat membaca antrean notifikasi internal', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(getDocs(collection(db, dbPath, 'notifikasi')));
});

test('warga tidak dapat menambahkan field di luar daftar SOS yang diizinkan', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(setDoc(sosRef(db, 'extra-field'), {
    ...report('extra-field'),
    statusAdmin: true,
  }));
});
