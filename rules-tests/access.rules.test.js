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
  collection, doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc,
} from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rules = fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8');
const projectId = process.env.GCLOUD_PROJECT || 'demo-no-project';
const root = 'kampung/kiarajangkung';
let env;

const profiles = {
  wargaA: { role: 'warga', wargaId: 'warga-a', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  wargaB: { role: 'warga', wargaId: 'warga-b', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  kawil: { role: 'perangkat_kawil', kawilId: 'kw-1', rwId: '', rtId: '' },
  admin: { role: 'admin', kawilId: '', rwId: '', rtId: '' },
  owner: { role: 'owner', kawilId: '', rwId: '', rtId: '' },
};

async function seed() {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    for (const [uid, profile] of Object.entries(profiles)) {
      await setDoc(doc(db, 'users', uid), profile);
    }
    await setDoc(doc(db, root, 'galeri', 'foto-1'), {
      judul: 'Kerja bakti', status: 'aktif',
    });
    await setDoc(doc(db, root, 'rahasia_internal', 'dokumen-1'), {
      isi: 'Data internal yang tidak boleh dibaca warga.',
    });
    await setDoc(doc(db, root, 'riwayat_perubahan', 'riwayat-1'), {
      uid: 'wargaA', wargaId: 'warga-a', aksi: 'perubahan data',
    });
    await setDoc(doc(db, root, 'sensus', 'warga-a'), {
      wargaId: 'warga-a', accountUid: 'wargaA', nama: 'Warga A', nik: '3200000000000001',
    });
    await setDoc(doc(db, root, 'sensus', 'warga-b'), {
      wargaId: 'warga-b', accountUid: 'wargaB', nama: 'Warga B', nik: '3200000000000002',
    });
    await setDoc(doc(db, root, 'wilayah_rw', 'rw-1'), {
      nama: '001', kawilId: 'kw-1',
    });
    await setDoc(doc(db, root, 'organisasi', 'karang-taruna'), {
      nama: 'Karang Taruna', judul: 'Karang Taruna', ketuaUid: 'wargaA',
    });
    await setDoc(doc(db, 'kampung', 'kampung-lain', 'pengumuman', 'umum-1'), {
      judul: 'Dokumen kampung lain',
    });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await seed();
});

after(async () => {
  if (env) await env.cleanup();
});

test('warga yang login dapat membaca koleksi informasi umum yang diizinkan', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  const result = await assertSucceeds(getDocs(collection(db, root, 'galeri')));
  assert.equal(result.size, 1);
});

test('pengguna tanpa login tidak dapat membaca koleksi informasi umum', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, root, 'galeri', 'foto-1')));
});

test('koleksi yang tidak dikenal ditolak untuk warga, Admin, dan Owner', async () => {
  for (const uid of ['wargaA', 'admin', 'owner']) {
    const db = env.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(db, root, 'rahasia_internal', 'dokumen-1')));
  }
});

test('Admin dan Owner tidak dapat menulis ke koleksi yang tidak dikenal', async () => {
  for (const uid of ['admin', 'owner']) {
    const db = env.authenticatedContext(uid).firestore();
    await assertFails(setDoc(doc(db, root, 'rahasia_internal', 'baru'), { isi: 'tidak boleh' }));
  }
});

test('path koleksi kampung lain tidak dapat dibaca melalui aturan kampung Kiarajangkung', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(getDoc(doc(db, 'kampung', 'kampung-lain', 'pengumuman', 'umum-1')));
});

test('warga hanya dapat membaca profil akunnya sendiri; Admin dapat membaca profil warga', async () => {
  const wargaDb = env.authenticatedContext('wargaA').firestore();
  await assertSucceeds(getDoc(doc(wargaDb, 'users', 'wargaA')));
  await assertFails(getDoc(doc(wargaDb, 'users', 'wargaB')));
  const adminDb = env.authenticatedContext('admin').firestore();
  await assertSucceeds(getDoc(doc(adminDb, 'users', 'wargaB')));
});

test('warga hanya dapat membaca data Sensus yang terhubung ke akunnya', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertSucceeds(getDoc(doc(db, root, 'sensus', 'warga-a')));
  await assertFails(getDoc(doc(db, root, 'sensus', 'warga-b')));
});

test('riwayat perubahan hanya dapat dibaca Admin atau Owner', async () => {
  const wargaDb = env.authenticatedContext('wargaA').firestore();
  await assertFails(getDoc(doc(wargaDb, root, 'riwayat_perubahan', 'riwayat-1')));
  const ownerDb = env.authenticatedContext('owner').firestore();
  await assertSucceeds(getDoc(doc(ownerDb, root, 'riwayat_perubahan', 'riwayat-1')));
});

test('akses wilayah RW dibatasi untuk Admin atau Kawil yang menaunginya', async () => {
  const wargaDb = env.authenticatedContext('wargaA').firestore();
  await assertFails(getDoc(doc(wargaDb, root, 'wilayah_rw', 'rw-1')));
  const kawilDb = env.authenticatedContext('kawil').firestore();
  await assertSucceeds(getDoc(doc(kawilDb, root, 'wilayah_rw', 'rw-1')));
});

test('Admin dapat mengelola koleksi informasi umum yang sudah dikenal', async () => {
  const db = env.authenticatedContext('admin').firestore();
  const ref = doc(db, root, 'galeri', 'admin-created');
  await assertSucceeds(setDoc(ref, { judul: 'Dokumentasi baru' }));
  await assertSucceeds(updateDoc(ref, { judul: 'Dokumentasi diperbarui' }));
  await assertSucceeds(deleteDoc(ref));
});

test('warga tidak dapat menambah, mengubah, atau menghapus koleksi informasi umum', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  const existing = doc(db, root, 'galeri', 'foto-1');
  await assertFails(setDoc(doc(db, root, 'galeri', 'foto-warga'), { judul: 'Tidak boleh' }));
  await assertFails(updateDoc(existing, { judul: 'Diubah warga' }));
  await assertFails(deleteDoc(existing));
});

test('ketua organisasi hanya dapat mengubah informasi yang diizinkan, bukan pemilik akses', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  const ref = doc(db, root, 'organisasi', 'karang-taruna');
  await assertSucceeds(updateDoc(ref, { judul: 'Karang Taruna Kiarajangkung' }));
  await assertFails(updateDoc(ref, { ketuaUid: 'wargaB' }));
});
