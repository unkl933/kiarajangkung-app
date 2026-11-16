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
  collection, doc, getDoc, getDocs, query, where, setDoc,
} from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rules = fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8');
const projectId = process.env.GCLOUD_PROJECT || 'demo-no-project';
const root = 'kampung/kiarajangkung';
let env;

const profiles = {
  wargaA: { role: 'warga', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  wargaB: { role: 'warga', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  wargaLain: { role: 'warga', kawilId: 'kw-2', rwId: 'rw-2', rtId: 'rt-2' },
  rt: { role: 'ketua_rt', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  admin: { role: 'admin', kawilId: '', rwId: '', rtId: '' },
  owner: { role: 'owner', kawilId: '', rwId: '', rtId: '' },
};

async function seed() {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    for (const [uid, profile] of Object.entries(profiles)) {
      await setDoc(doc(db, 'users', uid), profile);
    }

    await setDoc(doc(db, root, 'kegiatan_rt', 'agenda-terbit'), {
      judul: 'Kerja bakti', status: 'terbit', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1',
    });
    await setDoc(doc(db, root, 'kegiatan_rt', 'agenda-aktif'), {
      judul: 'Posyandu', status: 'aktif', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1',
    });
    await setDoc(doc(db, root, 'kegiatan_rt', 'agenda-draf'), {
      judul: 'Rapat internal', status: 'draf', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1',
    });

    await setDoc(doc(db, root, 'ronda', 'ronda-1'), {
      hari: 'Senin', rt: '01', rw: '01', anggotaUid: ['wargaA', 'wargaB'],
    });
    await setDoc(doc(db, root, 'ronda', 'ronda-2'), {
      hari: 'Selasa', rt: '02', rw: '02', anggotaUid: ['wargaLain'],
    });
    await setDoc(doc(db, root, 'ronda_absensi', 'absensi-a'), {
      uid: 'wargaA', nama: 'Warga A', scheduleId: 'ronda-1', tanggal: '2026-11-16',
      statusKesediaan: 'Berhalangan', alasan: 'Sakit',
    });
    await setDoc(doc(db, root, 'ronda_absensi', 'absensi-b'), {
      uid: 'wargaB', nama: 'Warga B', scheduleId: 'ronda-1', tanggal: '2026-11-16',
      statusKesediaan: 'Bersedia',
    });
    await setDoc(doc(db, root, 'ronda_absensi', 'absensi-lain'), {
      uid: 'wargaLain', nama: 'Warga Lain', scheduleId: 'ronda-2', tanggal: '2026-11-16',
      statusKesediaan: 'Berhalangan', alasan: 'Keperluan keluarga',
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

test('warga dapat membaca agenda yang sudah diterbitkan dengan query status', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  const q = query(collection(db, root, 'kegiatan_rt'), where('status', 'in', ['terbit', 'aktif']));
  const result = await assertSucceeds(getDocs(q));
  assert.equal(result.size, 2);
});

test('warga tidak dapat mengambil seluruh agenda termasuk draf', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(getDocs(collection(db, root, 'kegiatan_rt')));
  await assertFails(getDoc(doc(db, root, 'kegiatan_rt', 'agenda-draf')));
});

test('Admin dapat membaca agenda termasuk draf', async () => {
  const db = env.authenticatedContext('admin').firestore();
  const result = await assertSucceeds(getDocs(collection(db, root, 'kegiatan_rt')));
  assert.equal(result.size, 3);
});

test('warga dapat membaca laporan absensi miliknya sendiri', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  const q = query(collection(db, root, 'ronda_absensi'), where('uid', '==', 'wargaA'));
  const result = await assertSucceeds(getDocs(q));
  assert.equal(result.size, 1);
});

test('anggota regu dapat membaca absensi anggota lain dalam regu yang sama', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertSucceeds(getDoc(doc(db, root, 'ronda_absensi', 'absensi-b')));
});

test('warga tidak dapat membaca absensi regu lain', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(getDoc(doc(db, root, 'ronda_absensi', 'absensi-lain')));
});

test('warga tidak dapat mengambil seluruh laporan absensi lintas regu', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(getDocs(collection(db, root, 'ronda_absensi')));
});

test('Admin dapat membaca seluruh laporan absensi ronda', async () => {
  const db = env.authenticatedContext('admin').firestore();
  const result = await assertSucceeds(getDocs(collection(db, root, 'ronda_absensi')));
  assert.equal(result.size, 3);
});
