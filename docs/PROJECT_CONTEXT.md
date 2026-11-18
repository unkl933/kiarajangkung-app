# Kampung Digital Kiarajangkung — Konteks Proyek & Keputusan

Dokumen ini menjadi catatan acuan pengembangan agar perubahan berikutnya melanjutkan aplikasi yang sudah ada, bukan membangun ulang dari nol. Perbarui dokumen ini setiap kali ada keputusan baru yang disepakati.

## Repository dan lingkungan
- Repository: https://github.com/unkl933/kiarajangkung-app
- Branch kerja yang diminta: `backup`
- Package Android: `com.unkl.kiarajangkung`
- Aplikasi: Flutter + Firebase Authentication + Cloud Firestore + FCM.
- Firebase project: `kiarajangkung-app`.
- Batas biaya: tetap Firebase Spark/free. Jangan meminta atau melakukan upgrade ke Blaze.
- Notifikasi server-side: gunakan server Node.js pada Mi5 melalui Termux, folder `~/my-server`, port 3000, IP LAN yang pernah digunakan `192.168.1.11`. Mi5 dipilih agar tidak perlu Cloud Functions berbayar.
- Build APK: lokal di perangkat/komputer pengguna. Jangan mengubah GitHub Actions/workflow build kecuali diminta secara eksplisit.
- Jangan meminta atau menampilkan `service-account.json`; file tersebut berisi kredensial rahasia.

## Prinsip pengembangan
1. Pertahankan arsitektur, koleksi, modul, dan alur yang sudah berjalan.
2. Sebelum mengubah kode, periksa implementasi aktual di branch `backup`; jangan menebak nama field, status, atau koleksi.
3. Hindari rewrite besar dan jangan menghapus kode lama tanpa memahami dependensinya.
4. Perubahan backend dan Flutter harus kompatibel dengan data lama.
5. Setiap fitur baru harus mempertahankan keterkaitan identitas melalui `wargaId` bila berkaitan dengan penduduk.
6. Uji/build lokal setelah perubahan kode yang relevan; jangan mengklaim sudah diuji bila belum.
7. Rencana dan keputusan baru pengguna perlu ditambahkan ke dokumen ini sebelum implementasi.

## Data warga / Sensus
- Koleksi utama Sensus: `kampung/kiarajangkung/sensus`.
- Sensus adalah sumber utama identitas warga.
- `wargaId` adalah penghubung identitas warga dengan modul lain.
- Indeks NIK berada pada `kampung/kiarajangkung/sensus_nik_index`; NIK harus unik.
- Data Sensus memuat antara lain `nama`, `nik`, `noKK`, `wargaId`, `accountUid`, `roles`, `statusWarga`, `kawilId`, `rwId`, `rtId`, serta data profil/wilayah.
- Status warga yang telah ada mencakup `Aktif` dan `Arsip`. Jangan memakai atau mengganti `statusWarga` sebagai status validasi.
- Pengarsipan dapat menonaktifkan akun terkait dan pemulihan arsip dapat mengaktifkannya kembali sesuai `statusAkunSebelumArsip`.
- Pengeditan Informasi Diri mengunci identitas utama seperti nama, NIK, No. KK, role, wargaId, accountUid, dan wilayah tertentu. Ada penguncian sementara melalui `system_config/sensus_migration.lockResidentEdits`.
- Riwayat/audit warga ditulis melalui `writeWargaAudit`.

### Keputusan validasi data warga (baru disepakati)
- Data warga baru yang ditambahkan otomatis masuk antrean validasi.
- Perubahan data warga lama juga otomatis masuk antrean validasi.
- Data warga lama yang belum pernah divalidasi dapat ditandai manual sebagai **Perlu Validasi** oleh petugas yang berwenang.
- Petugas memeriksa data sesuai kewenangan wilayah (RT/RW/Kawil/Admin/Owner berdasarkan aturan akses aplikasi).
- Hasil pemeriksaan harus mendukung persetujuan atau permintaan perbaikan; warga/pengaju diberi notifikasi hasilnya.
- Status validasi harus menjadi metadata/alur tersendiri, terpisah dari `statusWarga` Aktif/Arsip.
- Sebelum membuat nama field/status dan transisi final, telusuri kembali kode Sensus yang ada dan rancang kompatibilitas data lama. Jangan mengubah identitas utama secara otomatis.
- Notifikasi untuk antrean validasi harus mencakup petugas yang berwenang dan pengaju/warga sesuai peristiwa; jangan broadcast ke seluruh kampung.

## Autentikasi dan role
- Profil akun disimpan pada `users/{uid}`.
- Akun dapat memiliki beberapa role dalam array `roles` dan role utama `role`.
- Jika akun memiliki lebih dari satu role, fitur dari semua role harus digabung; jangan mewajibkan pengguna berpindah role secara manual.
- Hierarki/role wilayah yang tampak dalam kode mencakup Owner, Admin, `perangkat_kawil`, `ketua_rw`, `ketua_rt`, dan warga.
- Data wilayah pada profil dapat menggunakan `kawilId`, `rwId`, `rtId`.
- Kewenangan data mengikuti cakupan wilayah: RT pada wilayah RT-nya; RW pada wilayah RW dan RT di bawahnya; Kawil pada wilayah Kawil; Admin/Owner sesuai kewenangan penuh yang sudah ada.
- Owner berwenang menetapkan/mengubah role. Admin mengelola data operasional/akun sesuai pembatasan yang sudah diterapkan, tetapi tidak boleh diberi kewenangan menetapkan role jika aturan aplikasi saat ini melarangnya.
- Jangan mengubah alur reset akun yang telah diperbaiki tanpa memeriksa implementasi dan pengaman Sensus agar tidak terjadi akun/data warga ganda.

## Modul dan keterhubungan
Modul yang telah dibahas/dikembangkan dan perlu dipertahankan keterhubungannya dengan sumber data warga meliputi:
- Sensus / Data Warga dan Informasi Diri
- Perangkat dan struktur wilayah RT/RW/Kawil
- Ronda
- Pemerintahan
- Organisasi/Lembaga
- UMKM
- Agenda/Kegiatan RT
- Pengumuman
- Pengaduan
- Pelayanan Surat
- Kontak Darurat / SOS
- Sampah
- DKM
- Sarana/fasilitas kampung
- Arsip warga dan audit/riwayat warga

Daftar ini adalah konteks modul yang pernah disebut/dikerjakan; sebelum mengubah masing-masing modul, periksa kode aktual dan skema yang sedang digunakan.

## Notifikasi — target perilaku
- Notifikasi tampil di kotak masuk/lonceng aplikasi dan dikirim sebagai push FCM kepada akun yang memiliki token.
- FCM token berada di `users/{uid}.fcmTokens`.
- Inbox berada di `users/{uid}/notifikasi`; halaman aplikasi membaca koleksi ini.
- Notifikasi harus disaring menurut role dan wilayah penerima; sertakan pembuat/pemohon ketika relevan.
- Pengumuman menggunakan koleksi `koordinasi_pengumuman`; antrean notifikasi generik menggunakan `notifikasi`.
- Kegiatan RT berada pada `kegiatan_rt`; kode saat ini sudah membuat dokumen antrean notifikasi untuk kegiatan/agenda.
- Pelayanan Surat berada pada `pelayanan_surat`.
- Pengaduan berada pada `pengaduan`.
- SOS berada pada `laporan_sos` dan alurnya terpisah. Jangan mengubah atau mengirim ulang SOS melalui listener notifikasi umum; mekanisme SOS yang ada harus tetap bekerja.
- Jenis notifikasi yang perlu dicakup: Pengumuman, Pelayanan Surat, Pengaduan, Kegiatan/Agenda, serta validasi data warga.
- Pelayanan Surat: petugas pada tahap yang sedang membutuhkan tindakan mendapat notifikasi; pemohon mendapat konfirmasi dan pembaruan status.
- Pengaduan: petugas sesuai tahap/wilayah mendapat notifikasi; pelapor mendapat konfirmasi dan pembaruan status/tindak lanjut.
- Kegiatan/Agenda dan Pengumuman: warga pada target wilayah mendapat notifikasi; pembuat juga mendapat notifikasi bila relevan.
- Validasi Sensus: petugas berwenang mendapat tugas validasi; warga/pengaju mendapat pemberitahuan hasil/perbaikan.
- Status/transisi persis untuk Pelayanan Surat dan Pengaduan harus diambil dari kode yang berjalan, bukan ditebak.

## Server notifikasi Mi5 — kondisi yang diketahui
- File di `~/my-server`: `server.js`, `firebase-listener.js`, `listener-state.json`, log, `node_modules`, dan Firebase Admin service account.
- Firebase Admin SDK dan uji tulis Firestore pernah berhasil.
- Listener lama mengawasi `kampung/kiarajangkung/notifikasi`, mengabaikan jenis SOS, memilih antrean berstatus `baru`/`menunggu`, mencocokkan penerima dari data wilayah user, membuat inbox dan mengirim FCM.
- Listener lama memiliki retry/recheck; file yang pernah diperiksa memiliki definisi `startListener()` ganda sehingga perlu dirapikan dengan hati-hati.
- Implementasi lama berpotensi melewatkan antrean berdasarkan filter waktu sejak start, dan belum tentu memasukkan UID pembuat sebagai penerima.
- Sebuah perubahan Flutter sudah dibuat pada `_queuePush()` untuk menambahkan `dibuatOlehUid` dan `dibuatOlehNama` pada dokumen antrean. Commit: `8a2054c6e83b7ac9cfe4e173e1b9a61ac79f0626`.
- Listener pengganti yang aman belum dipasang di Mi5. Jangan mengklaim listener baru aktif sebelum file diganti dan diuji.
- Rencana teknis: pertahankan antrean generik; tambahkan pemantauan perubahan langsung untuk `pelayanan_surat`, `pengaduan`, dan Sensus; gunakan catatan pemrosesan terpisah/idempotensi agar snapshot/restart tidak mengirim berulang; retry kegagalan; hindari dua proses listener aktif bersamaan.
- Pengiriman FCM tidak dapat dijamin tepat satu kali jika proses mati di antara pengiriman dan pencatatan sukses; gunakan ID inbox deterministik untuk menekan duplikasi.
- Mi5 harus aktif/terjangkau untuk mengirim push. Inbox Firestore tetap menjadi sumber notifikasi yang bisa dibaca saat aplikasi dibuka.

## Firebase / biaya
- Pengguna memutuskan tetap di Spark gratis.
- Cloud Functions belum dideploy; percobaan deploy meminta upgrade Blaze karena Artifact Registry. Jangan mengulang deploy atau menyarankan upgrade sebagai syarat.
- Gunakan Mi5 untuk worker notifikasi. Firebase tetap untuk Auth, Firestore, dan FCM.
- Jangan menghapus kode Cloud Functions lama sebelum audit dependensi; boleh dibiarkan dormant sampai diputuskan.

## Status pengerjaan notifikasi terakhir
- Branch: `backup`.
- Commit Flutter terakhir: `8a2054c6e83b7ac9cfe4e173e1b9a61ac79f0626` (menambahkan metadata pembuat pada antrean push kegiatan/agenda).
- Belum ada listener pengganti yang dipasang pada Mi5.
- Belum ada build APK lokal setelah perubahan commit tersebut.
- Tugas lanjutan: audit transisi status aktual seluruh koleksi; implementasikan worker Mi5 yang aman; uji inbox/FCM untuk setiap modul; lalu build lokal bila diminta.

## Cara bekerja dengan pengguna
- Pengguna mengembangkan aplikasi ini bertahap dan memiliki banyak rencana fitur lanjutan.
- Gunakan repo dan branch yang sudah ada; jangan mulai proyek baru.
- Berikan langkah praktis, satu tahap yang jelas saat perlu tindakan manual di HP/Termux.
- Jelaskan dengan jujur apa yang sudah diubah, apa yang baru direncanakan, dan apa yang belum diuji.

## Audit teknis validasi Sensus (18 November 2026)

Pemeriksaan kode aktual pada branch `backup` menemukan jalur berikut:
- Formulir Admin/Owner membuat dokumen `sensus` dan `sensus_nik_index` dalam transaksi; metadata validasi harus dibuat dalam alur transaksi yang sama agar tidak ada data baru tanpa antrean.
- Formulir Admin/Owner mengubah dokumen Sensus dan indeks NIK dalam transaksi; perubahan data harus membuat antrean validasi tanpa merusak pengarsipan dan sinkronisasi profil akun.
- Halaman `InformasiDiriPage` milik warga mengubah field profil langsung pada dokumen Sensus dan memperbarui profil `users/{uid}`; aturan Firestore saat ini membatasi field perubahan warga. Alur ini perlu menghasilkan antrean validasi dan tetap mempertahankan batas field tersebut.
- Impor Excel pada `MigrasiSatuDataPage._applyReady()` membuat atau memperbarui dokumen Sensus beserta indeks NIK dalam transaksi. Jalur impor juga harus membuat antrean validasi untuk data baru maupun data yang berubah.
- Aturan baca koleksi Sensus saat ini hanya mengizinkan Owner/Admin atau pemilik dokumen (`ownsSensus`). Petugas RT/RW/Kawil belum diberi akses baca Sensus secara umum; akses pemeriksaan harus ditambahkan dengan pembatasan wilayah yang sama seperti helper `s2InArea`, bukan membuka seluruh koleksi.
- Aturan Firestore untuk `users/{uid}/notifikasi/{id}` melarang pembuatan inbox dari aplikasi. Worker Mi5 tetap menjadi pihak yang membuat inbox dan mengirim FCM.
- Status Pelayanan Surat yang terlihat di rules: `diajukan`, `diperiksa_rt`, `diverifikasi_rw`, `disetujui`, `perlu_perbaikan`, dan `ditolak`. Status Pengaduan menggunakan tahapan `menunggu_validasi_rt`, `menunggu_validasi_rw`, `menunggu_validasi_kawil`, `terverifikasi`, `ditindaklanjuti`, `selesai`, serta status pengembalian/perbaikan dan penolakan. Perlu audit Flutter untuk memastikan semua transisi aktual sebelum listener dibuat.

Belum ada kode validasi yang diubah pada audit ini. Implementasi harus dilakukan bertahap: (1) desain dokumen antrean dan aturan keamanan, (2) sambungkan ke empat jalur simpan Sensus, (3) buat UI antrean dan keputusan petugas sesuai wilayah, (4) integrasikan notifikasi Mi5. Jangan mengaktifkan perubahan rules sebelum uji emulator/akun per role tersedia.
