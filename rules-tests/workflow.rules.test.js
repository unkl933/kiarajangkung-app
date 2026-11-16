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
import { collection, doc, getDoc, getDocs, setDoc, updateDoc } from 'firebase/firestore';

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
  rw: { role: 'ketua_rw', kawilId: 'kw-1', rwId: 'rw-1', rtId: 'rt-1' },
  kawil: { role: 'perangkat_kawil', kawilId: 'kw-1', rwId: '', rtId: '' },
  admin: { role: 'admin', kawilId: '', rwId: '', rtId: '' },
  owner: { role: 'owner', kawilId: '', rwId: '', rtId: '' },
};

const scoped = (uid, extra = {}) => ({
  pemohonUid: uid,
  kawilId: profiles[uid].kawilId,
  rwId: profiles[uid].rwId,
  rtId: profiles[uid].rtId,
  ...extra,
});

async function seed() {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    for (const [uid, profile] of Object.entries(profiles)) {
      await setDoc(doc(db, 'users', uid), profile);
    }
    await setDoc(doc(db, root, 'pelayanan_surat', 'surat-warga-a'), {
      ...scoped('wargaA'),
      jenisSurat: 'Surat Pengantar',
      keperluan: 'Administrasi',
      status: 'diajukan',
    });
    await setDoc(doc(db, root, 'pelayanan_surat', 'surat-warga-b'), {
      ...scoped('wargaB'),
      jenisSurat: 'Surat Pengantar',
      keperluan: 'Administrasi',
      status: 'diajukan',
    });
    await setDoc(doc(db, root, 'pelayanan_surat', 'surat-perbaikan'), {
      ...scoped('wargaA'),
      jenisSurat: 'Surat Keterangan',
      keperluan: 'Administrasi',
      status: 'perlu_perbaikan',
    });
    await setDoc(doc(db, root, 'pengaduan', 'aduan-warga-a'), {
      ...scoped('wargaA'),
      judul: 'Lampu jalan mati',
      uraian: 'Lampu jalan dekat balai mati',
      status: 'menunggu_validasi_rt',
    });
    await setDoc(doc(db, root, 'laporan_rt_bulanan', 'laporan-rt-1'), {
      kawilId: 'kw-1',
      rwId: 'rw-1',
      rtId: 'rt-1',
      dikirimOlehUid: 'rt',
      status: 'dikirim',
      bulan: '2026-11',
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

test('warga dapat mengajukan surat untuk dirinya dengan wilayah profil yang sama', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertSucceeds(setDoc(doc(db, root, 'pelayanan_surat', 'surat-baru'), {
    ...scoped('wargaA'),
    jenisSurat: 'Surat Pengantar',
    keperluan: 'Administrasi',
    status: 'diajukan',
  }));
});

test('warga tidak dapat mengajukan surat atas nama orang lain atau wilayah lain', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(setDoc(doc(db, root, 'pelayanan_surat', 'surat-spoof'), {
    ...scoped('wargaB'),
    jenisSurat: 'Surat Pengantar',
    status: 'diajukan',
  }));
  await assertFails(setDoc(doc(db, root, 'pelayanan_surat', 'surat-salah-wilayah'), {
    ...scoped('wargaA', { rtId: 'rt-99' }),
    jenisSurat: 'Surat Pengantar',
    status: 'diajukan',
  }));
});

test('warga hanya dapat membaca surat miliknya sendiri', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertSucceeds(getDoc(doc(db, root, 'pelayanan_surat', 'surat-warga-a')));
  await assertSucceeds(getDoc(doc(db, root, 'pelayanan_surat', 'surat-perbaikan')));
  await assertFails(getDoc(doc(db, root, 'pelayanan_surat', 'surat-warga-b')));
});

test('warga dapat memperbaiki surat yang dikembalikan tanpa mengubah identitas dan wilayah', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertSucceeds(updateDoc(doc(db, root, 'pelayanan_surat', 'surat-perbaikan'), {
    keperluan: 'Administrasi kependudukan',
    status: 'diajukan',
  }));
  await assertFails(updateDoc(doc(db, root, 'pelayanan_surat', 'surat-perbaikan'), {
    pemohonUid: 'wargaB',
  }));
});

test('petugas wilayah dapat membaca surat di wilayahnya dan tidak dapat membaca wilayah lain', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertSucceeds(getDoc(doc(db, root, 'pelayanan_surat', 'surat-warga-a')));
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), root, 'pelayanan_surat', 'surat-warga-lain'), {
      ...scoped('wargaLain'), jenisSurat: 'Surat Pengantar', status: 'diajukan',
    });
  });
  await assertFails(getDoc(doc(db, root, 'pelayanan_surat', 'surat-warga-lain')));
});

test('warga dapat membuat pengaduan atas nama sendiri dan wilayahnya dengan status awal validasi RT', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertSucceeds(setDoc(doc(db, root, 'pengaduan', 'aduan-baru'), {
    ...scoped('wargaA'),
    judul: 'Jalan rusak',
    uraian: 'Jalan lingkungan berlubang',
    status: 'menunggu_validasi_rt',
  }));
  await assertFails(setDoc(doc(db, root, 'pengaduan', 'aduan-status-lama'), {
    ...scoped('wargaA'), judul: 'Jalan rusak', uraian: 'Uraian', status: 'baru',
  }));
});

test('warga tidak dapat membuat pengaduan atas nama orang lain atau membaca pengaduan orang lain', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(setDoc(doc(db, root, 'pengaduan', 'aduan-spoof'), {
    ...scoped('wargaB'), judul: 'Aduan palsu', status: 'baru',
  }));
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), root, 'pengaduan', 'aduan-warga-lain'), {
      ...scoped('wargaB'), judul: 'Aduan warga lain', status: 'baru',
    });
  });
  await assertFails(getDoc(doc(db, root, 'pengaduan', 'aduan-warga-lain')));
});

test('validasi pengaduan wajib berjenjang RT lalu RW lalu Kawil', async () => {
  const rtDb = env.authenticatedContext('rt').firestore();
  const rwDb = env.authenticatedContext('rw').firestore();
  const kawilDb = env.authenticatedContext('kawil').firestore();
  const ref = doc(rtDb, root, 'pengaduan', 'aduan-warga-a');
  await assertSucceeds(updateDoc(ref, { status: 'menunggu_validasi_rw', tanggapan: 'Diperiksa RT' }));
  await assertFails(updateDoc(doc(kawilDb, root, 'pengaduan', 'aduan-warga-a'), { status: 'terverifikasi' }));
  await assertSucceeds(updateDoc(doc(rwDb, root, 'pengaduan', 'aduan-warga-a'), { status: 'menunggu_validasi_kawil', tanggapan: 'Diperiksa RW' }));
  await assertSucceeds(updateDoc(doc(kawilDb, root, 'pengaduan', 'aduan-warga-a'), { status: 'terverifikasi', tanggapan: 'Validasi akhir Kawil' }));
  await assertSucceeds(updateDoc(doc(kawilDb, root, 'pengaduan', 'aduan-warga-a'), { status: 'ditindaklanjuti', tanggapan: 'Mulai ditangani' }));
  await assertFails(updateDoc(doc(kawilDb, root, 'pengaduan', 'aduan-warga-a'), { status: 'selesai' }));
  await assertSucceeds(updateDoc(doc(kawilDb, root, 'pengaduan', 'aduan-warga-a'), {
    status: 'selesai', catatanPenyelesaian: 'Lampu jalan sudah diperbaiki',
    diselesaikanOlehUid: 'kawil', diselesaikanOlehNama: 'Petugas Kawil',
  }));
  await assertFails(updateDoc(ref, { pemohonUid: 'rt' }));
});
test('RT tidak dapat melewati validasi RW atau Kawil', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertFails(updateDoc(doc(db, root, 'pengaduan', 'aduan-warga-a'), { status: 'menunggu_validasi_kawil' }));
  await assertFails(updateDoc(doc(db, root, 'pengaduan', 'aduan-warga-a'), { status: 'ditindaklanjuti' }));
});
test('Ketua RW tidak dapat memvalidasi sebelum RT', async () => {
  const db = env.authenticatedContext('rw').firestore();
  await assertFails(updateDoc(doc(db, root, 'pengaduan', 'aduan-warga-a'), { status: 'menunggu_validasi_kawil' }));
});
test('hanya Kawil yang dapat menandai selesai dan catatan wajib diisi', async () => {
  const db = env.authenticatedContext('kawil').firestore();
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), root, 'pengaduan', 'aduan-warga-a'), { status: 'ditindaklanjuti' });
  });
  await assertFails(updateDoc(doc(db, root, 'pengaduan', 'aduan-warga-a'), { status: 'selesai' }));
  await assertFails(updateDoc(doc(db, root, 'pengaduan', 'aduan-warga-a'), {
    status: 'selesai', catatanPenyelesaian: '', diselesaikanOlehUid: 'kawil',
  }));
  await assertSucceeds(updateDoc(doc(db, root, 'pengaduan', 'aduan-warga-a'), {
    status: 'selesai', catatanPenyelesaian: 'Sudah diperbaiki', diselesaikanOlehUid: 'kawil',
  }));
});

test('petugas dari wilayah lain tidak dapat mengubah pengaduan', async () => {
  const db = env.authenticatedContext('wargaLain').firestore();
  await assertFails(updateDoc(doc(db, root, 'pengaduan', 'aduan-warga-a'), {
    status: 'selesai',
  }));
});

test('Ketua RT dapat mengirim laporan bulanan untuk RT sendiri', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertSucceeds(setDoc(doc(db, root, 'laporan_rt_bulanan', 'laporan-baru'), {
    kawilId: 'kw-1',
    rwId: 'rw-1',
    rtId: 'rt-1',
    dikirimOlehUid: 'rt',
    status: 'dikirim',
    bulan: '2026-12',
  }));
});

test('Ketua RT tidak dapat mengirim laporan untuk RT lain', async () => {
  const db = env.authenticatedContext('rt').firestore();
  await assertFails(setDoc(doc(db, root, 'laporan_rt_bulanan', 'laporan-rt-lain'), {
    kawilId: 'kw-1',
    rwId: 'rw-1',
    rtId: 'rt-99',
    dikirimOlehUid: 'rt',
    status: 'dikirim',
    bulan: '2026-12',
  }));
});

test('Ketua RW dapat memverifikasi laporan RT dalam wilayah RW-nya', async () => {
  const db = env.authenticatedContext('rw').firestore();
  await assertSucceeds(updateDoc(doc(db, root, 'laporan_rt_bulanan', 'laporan-rt-1'), {
    status: 'diverifikasi_rw',
    catatanPetugas: 'Sudah diperiksa',
  }));
});

test('Kawil dapat menerima laporan yang sudah diverifikasi RW', async () => {
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), root, 'laporan_rt_bulanan', 'laporan-rt-1'), {
      status: 'diverifikasi_rw',
    });
  });
  const db = env.authenticatedContext('kawil').firestore();
  await assertSucceeds(updateDoc(doc(db, root, 'laporan_rt_bulanan', 'laporan-rt-1'), {
    status: 'diterima_kawil',
  }));
});

test('warga tidak dapat membaca laporan RT bulanan lintas wilayah', async () => {
  const db = env.authenticatedContext('wargaA').firestore();
  await assertFails(getDocs(collection(db, root, 'laporan_rt_bulanan')));
});
