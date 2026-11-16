import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rules = fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8');
const projectId = process.env.GCLOUD_PROJECT || 'demo-no-project';
const root = 'kampung/kiarajangkung';
let env;

const profiles = {
  warga: { role: 'warga', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  rt: { role: 'ketua_rt', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  rtLain: { role: 'ketua_rt', kawilId: 'kw-2', rwId: 'rw-2', rtId: 'rt-2' },
  rw: { role: 'ketua_rw', kawilId: 'kw-1', rwId: 'rw-1', rtId: '' },
  kawil: { role: 'perangkat_kawil', kawilId: 'kw-1', rwId: '', rtId: '' },
  admin: { role: 'admin', kawilId: '', rwId: '', rtId: '' },
  owner: { role: 'owner', kawilId: '', rwId: '', rtId: '' },
};

const ref = (db, collectionName, id) => doc(db, root, collectionName, id);
const scoped = (uid, extra = {}) => ({
  dibuatOlehUid: uid,
  kawilId: profiles[uid].kawilId,
  rwId: profiles[uid].rwId,
  rtId: profiles[uid].rtId,
  publik: false,
  ...extra,
});

async function seed() {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    for (const [uid, profile] of Object.entries(profiles)) {
      await setDoc(doc(db, 'users', uid), profile);
    }
    await setDoc(ref(db, 'wilayah_rw', 'rw-1'), { kawilId: 'kw-1' });
    await setDoc(ref(db, 'wilayah_rt', 'rt-1'), { rwId: 'rw-1' });
    await setDoc(ref(db, 'koordinasi_instruksi', 'instruksi-1'), {
      ...scoped('kawil', { targetLevel: 'rw', targetId: 'rw-1' }),
      judul: 'Instruksi kerja bakti',
    });
    await setDoc(ref(db, 'koordinasi_tugas', 'tugas-rt-1'), {
      ...scoped('rw', { targetLevel: 'rt', targetId: 'rt-1' }),
      judul: 'Pendataan warga',
    });
    await setDoc(ref(db, 'koordinasi_tugas', 'tugas-rt-lain'), {
      ...scoped('rw', { targetLevel: 'rt', targetId: 'rt-2' }),
      judul: 'Tugas wilayah lain',
    });
    await setDoc(ref(db, 'koordinasi_forum', 'forum-publik'), {
      ...scoped('rt', { publik: true }),
      pesan: 'Informasi umum',
    });
    await setDoc(ref(db, 'koordinasi_forum', 'forum-rw'), {
      ...scoped('rw', { publik: false }),
      pesan: 'Forum internal RW',
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

test('Kawil dapat membuat instruksi untuk RW di wilayahnya', async () => {
  const db = env.authenticatedContext('kawil').firestore();
  await assertSucceeds(setDoc(ref(db, 'koordinasi_instruksi', 'instruksi-baru'), {
    ...scoped('kawil', { targetLevel: 'rw', targetId: 'rw-1' }),
    judul: 'Arahan kegiatan',
  }));
});

test('Kawil tidak dapat membuat instruksi untuk RW di luar wilayahnya', async () => {
  const db = env.authenticatedContext('kawil').firestore();
  await assertFails(setDoc(ref(db, 'koordinasi_instruksi', 'instruksi-salah'), {
    ...scoped('kawil', { targetLevel: 'rw', targetId: 'rw-2', rwId: 'rw-2' }),
    judul: 'Arahan lintas wilayah',
  }));
});

test('Ketua RW dapat membuat tugas untuk RT di RW sendiri', async () => {
  const db = env.authenticatedContext('rw').firestore();
  await assertSucceeds(setDoc(ref(db, 'koordinasi_tugas', 'tugas-baru'), {
    ...scoped('rw', { targetLevel: 'rt', targetId: 'rt-1' }),
    judul: 'Pendataan',
  }));
});

test('Ketua RT tidak dapat membuat instruksi atau tugas hierarki', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertFails(setDoc(ref(db, 'koordinasi_tugas', 'tugas-tidak-sah'), {
    ...scoped('rt', { targetLevel: 'rt', targetId: 'rt-1' }),
    judul: 'Tugas buatan RT',
  }));
});

test('warga dapat membaca koordinasi yang ditandai publik tetapi bukan dokumen internal', async () => {
  const db = env.authenticatedContext('warga').firestore();
  await assertSucceeds(getDoc(ref(db, 'koordinasi_forum', 'forum-publik')));
  await assertFails(getDoc(ref(db, 'koordinasi_forum', 'forum-rw')));
});

test('Ketua RT dapat membaca forum RW sendiri', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertSucceeds(getDoc(ref(db, 'koordinasi_forum', 'forum-rw')));
});

test('Ketua RT tidak dapat membaca forum RW lain', async () => {
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(ref(context.firestore(), 'koordinasi_forum', 'forum-rw-lain'), {
      ...scoped('rw', { rwId: 'rw-2', kawilId: 'kw-2' }),
      pesan: 'Forum RW lain',
    });
  });
  const db = env.authenticatedContext('rt').firestore();
  await assertFails(getDoc(ref(db, 'koordinasi_forum', 'forum-rw-lain')));
});

test('Ketua RT dapat menambahkan progres pada tugas yang ditujukan ke RT sendiri', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertSucceeds(setDoc(ref(db, 'koordinasi_progres', 'progres-1'), {
    ...scoped('rt'),
    tugasId: 'tugas-rt-1',
    uraian: 'Pendataan dimulai',
  }));
});

test('Ketua RT tidak dapat menambahkan progres untuk tugas RT lain', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertFails(setDoc(ref(db, 'koordinasi_progres', 'progres-salah'), {
    ...scoped('rt'),
    tugasId: 'tugas-rt-lain',
    uraian: 'Progres tidak berhak',
  }));
});

test('dokumen koordinasi bersifat append-only dan tidak dapat diubah atau dihapus', async () => {
  const db = env.authenticatedContext('kawil').firestore();
  await assertFails(updateDoc(ref(db, 'koordinasi_instruksi', 'instruksi-1'), {
    judul: 'Diubah',
  }));
  await assertFails(deleteDoc(ref(db, 'koordinasi_instruksi', 'instruksi-1')));
});

test('warga tidak dapat membuat pesan rapat internal', async () => {
  const db = env.authenticatedContext('warga').firestore();
  await assertFails(setDoc(ref(db, 'koordinasi_rapat', 'rapat-warga'), {
    ...scoped('warga'),
    judul: 'Rapat warga',
  }));
});
