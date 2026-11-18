# Kampung Digital Kiarajangkung

Aplikasi layanan dan informasi kampung berbasis **Flutter** untuk menghubungkan warga dengan pengurus wilayah serta membantu pengelolaan administrasi dan kegiatan Kampung Kiarajangkung.

Aplikasi dikembangkan untuk perangkat Android dengan antarmuka yang mudah digunakan oleh warga maupun pengurus kampung. Hak akses menu dan data disesuaikan dengan peran serta wilayah akun.

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/Firebase-Authentication%20%7C%20Firestore%20%7C%20FCM-FFCA28?logo=firebase&logoColor=black" alt="Firebase">
  <img src="https://img.shields.io/badge/Status-Development-orange" alt="Development">
</p>

---

## Tujuan Aplikasi

Kampung Digital Kiarajangkung dikembangkan untuk:

- Memudahkan warga memperoleh informasi dan layanan kampung.
- Mendukung komunikasi antara warga, RT, RW, perangkat Kawil, dan pengelola kampung.
- Membantu pengelolaan data penduduk secara terpusat dan bertanggung jawab.
- Mempercepat penyampaian laporan, pengaduan, dan keadaan darurat.
- Mendokumentasikan kegiatan, pelayanan, dan koordinasi wilayah.

## Fitur Aplikasi

### 1. Beranda dan Informasi Kampung

- Beranda dengan akses cepat ke layanan dan informasi.
- Pencarian menu atau layanan.
- Profil kampung, sejarah, visi, misi, dan informasi wilayah.
- Pengumuman dan agenda kegiatan.
- Galeri dokumentasi kegiatan kampung.

### 2. Data Warga

- Informasi diri warga yang terhubung dengan data Sensus Penduduk.
- Pengelolaan data Sensus Penduduk oleh petugas berwenang.
- Pencarian dan pengurutan data penduduk.
- Arsip warga pindah atau meninggal dengan riwayat yang tetap tersimpan.
- Fitur migrasi dan pencocokan data modul lama dengan data Sensus.
- Pengelolaan perangkat kampung, wilayah, dan akun sesuai kewenangan.

Data pribadi dan data kependudukan dibatasi berdasarkan hak akses. Tidak semua data dapat dilihat oleh seluruh pengguna.

### 3. Pelayanan Masyarakat

- Pengajuan dan pemantauan layanan masyarakat.
- Pengaduan atau laporan warga.
- Informasi kegiatan dan laporan lingkungan RT/RW.
- Pemantauan proses pelayanan sesuai kewenangan petugas.

### 4. Koordinasi Wilayah

- Koordinasi antara perangkat Kawil, Ketua RW, dan Ketua RT.
- Instruksi dan disposisi wilayah.
- Tugas dan tindak lanjut.
- Undangan rapat, forum, dan pengumuman pengurus.
- Riwayat koordinasi dan perkembangan tugas.

### 5. SOS dan Informasi Darurat

- Pengiriman laporan SOS oleh warga.
- Informasi kejadian, pelapor, keterangan, dan lokasi apabila tersedia.
- Notifikasi kepada petugas yang berwenang sesuai cakupan wilayah.
- Pemantauan laporan SOS oleh Owner/Admin, perangkat Kawil, Ketua RW, atau Ketua RT sesuai wilayahnya.
- Petugas dapat memberikan respons dan memperbarui status penanganan.
- Riwayat laporan dan respons tetap disimpan.
- Informasi kontak darurat seperti Bhabinkamtibmas, Babinsa, IGD, dan ambulans.

**Catatan:** Fitur SOS merupakan sarana pelaporan dan koordinasi. Untuk keadaan yang mengancam keselamatan, warga tetap perlu menghubungi layanan darurat terkait secara langsung.

### 6. Jadwal Ronda

- Informasi jadwal ronda dan siskamling.
- Daftar petugas ronda.
- Pencatatan kehadiran dan laporan ronda.
- Informasi jadwal yang dapat dibagikan kepada petugas.

### 7. Layanan dan Potensi Kampung

Aplikasi menyediakan bagian informasi untuk:

- UMKM warga dan produk lokal.
- Sarana dan prasarana kampung.
- Potensi dan destinasi wisata.
- Kesenian dan budaya.
- Jadwal kebersihan dan pengangkutan sampah.
- Fasilitas kesehatan.
- Organisasi dan lembaga kampung seperti Karang Taruna, PKK, Posyandu, kelompok tani, dan lainnya.

### 8. Panel Administrasi

- Pengelolaan akun dan status pengguna.
- Persetujuan permintaan akun warga.
- Pengelolaan wilayah dan perangkat.
- Pengaturan data sesuai hak akses.
- Reset akun warga oleh petugas yang berwenang.
- Dashboard Kepala Wilayah untuk pemantauan data dan pelayanan di wilayahnya.

## Hak Akses Pengguna

Aplikasi menggunakan pengaturan peran (*role-based access control*) dan cakupan wilayah.

| Peran | Cakupan umum |
|---|---|
| Warga | Informasi kampung, profil, layanan, pengaduan, ronda, dan pelaporan SOS |
| Ketua RT | Data dan pelayanan pada wilayah RT sesuai kewenangan |
| Ketua RW | Pemantauan dan koordinasi pada wilayah RW sesuai kewenangan |
| Perangkat Kawil | Pemantauan dan koordinasi wilayah Kawil |
| Admin | Pengelolaan operasional dan administrasi sesuai kewenangan |
| Owner | Akses pengelolaan tertinggi aplikasi |

Satu akun dapat memiliki lebih dari satu peran. Hak akses mengikuti gabungan kewenangan yang diberikan kepada akun tersebut. Pembatasan tetap diterapkan pada data dan wilayah yang menjadi tanggung jawab pengguna.

## Teknologi

| Bagian | Teknologi |
|---|---|
| Aplikasi | Flutter dan Dart |
| Autentikasi | Firebase Authentication |
| Database | Cloud Firestore |
| Push notification | Firebase Cloud Messaging (FCM) |
| Aturan keamanan data | Firestore Security Rules |
| Integrasi pendukung | Google Apps Script |
| Platform utama | Android |

Beberapa library Flutter yang digunakan antara lain:

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `firebase_messaging`
- `geolocator`
- `image_picker`
- `flutter_image_compress`
- `pdf` dan `printing`
- `share_plus`
- `url_launcher`
- `excel` dan `file_picker`

Firebase Authentication digunakan untuk autentikasi pengguna, Firestore untuk penyimpanan dan sinkronisasi data, sedangkan FCM digunakan untuk push notification. Lihat dokumentasi resmi [Firebase untuk Flutter](https://firebase.google.com/docs/flutter) untuk informasi lebih lanjut.

## Persyaratan Pengembangan

Siapkan:

- Flutter SDK yang sesuai dengan batas versi pada `pubspec.yaml`.
- Dart SDK yang disertakan dengan Flutter.
- Android SDK dan Android build tools.
- JDK yang kompatibel dengan konfigurasi Gradle proyek.
- Akses ke proyek Firebase yang digunakan aplikasi.

## Menjalankan Proyek

### 1. Clone repositori

```bash
git clone https://github.com/unkl933/kiarajangkung-app.git
cd kiarajangkung-app
```

Untuk berpindah ke branch pengembangan yang digunakan:

```bash
git checkout backup
```

### 2. Pasang dependensi

```bash
flutter pub get
```

### 3. Konfigurasi Firebase

Aplikasi Android menggunakan konfigurasi Firebase untuk package:

```text
com.unkl.kiarajangkung
```

Pastikan file konfigurasi Android `google-services.json` berasal dari proyek Firebase yang benar dan ditempatkan di:

```text
android/app/google-services.json
```

Pastikan Firebase Authentication dan Cloud Firestore sudah disiapkan. Periksa juga aturan keamanan Firestore pada file `firestore.rules` sebelum digunakan.

Jangan mengunggah file service account, private key, token, atau kredensial rahasia ke repositori publik.

### 4. Jalankan di perangkat atau emulator

```bash
flutter run
```

### 5. Build APK release secara lokal

```bash
flutter build apk --release
```

Hasil APK biasanya tersedia di:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Nama package Android:

```text
com.unkl.kiarajangkung
```

## Struktur Proyek

Gambaran folder dan file penting:

```text
kiarajangkung-app/
├── android/                  # Konfigurasi aplikasi Android
├── assets/                   # Aset gambar dan ikon
├── lib/
│   └── main.dart             # Kode utama aplikasi Flutter
├── google-apps-script/
│   └── Code.gs               # Integrasi Google Apps Script
├── firestore.rules           # Aturan keamanan Cloud Firestore
├── firebase.json             # Konfigurasi Firebase CLI
├── pubspec.yaml              # Dependensi dan konfigurasi Flutter
└── README.md                 # Dokumentasi proyek
```

## Keamanan dan Privasi

- Akses data harus mengikuti Firestore Security Rules.
- Data pribadi warga hanya boleh diakses oleh pengguna yang memiliki kewenangan.
- Jangan menonaktifkan aturan keamanan Firestore untuk mengatasi error aplikasi.
- Jangan menyimpan kredensial Firebase Admin atau service account di dalam aplikasi Flutter.
- Periksa kembali hak akses dan cakupan wilayah sebelum menerapkan perubahan ke lingkungan produksi.

## Status Pengembangan

Kampung Digital Kiarajangkung masih terus dikembangkan. Susunan menu, fitur, aturan akses, dan integrasi dapat berubah mengikuti kebutuhan operasional kampung serta hasil pengujian.

Sebelum menggunakan versi terbaru untuk operasional, lakukan pengujian login, hak akses setiap peran, data wilayah, pelayanan, notifikasi, dan laporan SOS.

---

**Kampung Digital Kiarajangkung**  
Digitalisasi informasi, pelayanan, dan koordinasi masyarakat kampung.
