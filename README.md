# 🛒 Warung Barokah Kiarajangkung - Flutter POS (Point of Sale)

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Google Sheets](https://img.shields.io/badge/Google%20Sheets-%2334A853.svg?style=for-the-badge&logo=Google-Sheets&logoColor=white)
![Apps Script](https://img.shields.io/badge/Apps%20Script-%234285F4.svg?style=for-the-badge&logo=Google&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)

Aplikasi Kasir (POS) ringan berbasis **Flutter** yang dirancang khusus untuk warung kelontong dan UMKM dengan optimalisasi perangkat RAM terbatas (3 GB). Menggunakan **Google Sheets & Google Apps Script** sebagai *backend* database yang fleksibel, gratis, dan mudah dikelola tanpa server terpusat yang mahal.

</div>

---

## ✨ Fitur Utama

- **Kasir & Transaksi Cepat:** Mendukung pemindaian *barcode*, perhitungan PPN, diskon, *Split Bill*, serta pembayaran non-tunai via QRIS.
- **Manajemen Produk Fleksibel:** Pengaturan harga bertingkat (Harga Utuh, 1/2, 1/4 bungkus, dan harga eceran/grosir).
- **Sistem Konsinyasi & Kunjungan Sales:** Fitur khusus untuk melacak barang titipan sales, pengecekan sisa stok fisik vs sistem, hingga estimasi uang setoran otomatis.
- **Kulakan & Belanja Ulang:** Pencatatan pengeluaran modal harian sekaligus penambahan stok barang secara langsung.
- **Manajemen Kasbon (Hutang Pelanggan):** Pencatatan rincian kasbon lengkap dengan riwayat pembayaran cicilan dan fitur cetak/bagikan ringkasan via WhatsApp berformat PDF.
- **Laporan Keuangan & Laba:** Rekapitulasi transaksi dan perhitungan laba bersih secara *real-time*.

---

## 🚀 Optimalisasi Performa (RAM 3 GB)
Aplikasi ini dioptimalkan khusus agar berjalan sangat ringan di perangkat Android kelas entry-level (RAM 3 GB) melalui:
- Kompresi dan pembatasan ukuran aset gambar (`logo.png`, `qris.png`).
- Penggunaan keyword `const` secara masif untuk efisiensi *widget tree*.
- Manajemen memori dan pemecahan komponen widget agar terhindar dari *lag* atau *force close*.

---

## 🛠️ Teknologi yang Digunakan
- **Frontend:** [Flutter](https://flutter.dev/) (Dart)
- **Backend / Database:** [Google Sheets](https://workspace.google.com/products/sheets/)
- **API & Serverless Middleware:** [Google Apps Script](https://developers.google.com/apps-script)

---

## ⚙️ Konfigurasi Backend (Google Apps Script)

Aplikasi ini terhubung ke Google Sheets menggunakan Google Apps Script sebagai API. Pastikan Google Sheets Anda memiliki 3 tab utama dengan struktur header berikut:

1. **`Products`**
   ```text
   id | name | category | buyPrice | price | halfPrice | quarterPrice | stock | retailName | retailConversion | retailPrice | barcode | isConsignment | salesName
   ```
2. **`Transactions`**
   ```text
   Transaction_ID | Date | Subtotal | Discount | Tax | Total | Net_Profit | Items_Summary | Staff_Name | Payment_Type
   ```
3. **`Debts`**
   ```text
   Debt_ID | Customer_Name | Staff_Name | Date | Total_Amount | Paid_Amount | Remaining_Amount | Status | Items_Summary | Settlement_History
   ```

---

## 📦 Cara Menjalankan Proyek (Development)

1. **Clone repository ini:**
   ```bash
   git clone https://github.com/username/warung-barokah-pos.git
   cd warung-barokah-pos
   ```

2. **Install dependencies Flutter:**
   ```bash
   flutter pub get
   ```

3. **Atur Endpoint API:**
   Buka file konfigurasi atau file utama (`lib/main.dart`) lalu masukkan URL Web App Google Apps Script Anda pada variabel `googleSheetUrl`.

4. **Jalankan Aplikasi:**
   ```bash
   flutter run
   ```

---

## 🤖 Otomatisasi Release APK (GitHub Actions)
Repositori ini dilengkapi dengan konfigurasi GitHub Actions (`.github/workflows/release-apk.yml`) untuk mem-build file APK *Release* secara otomatis setiap kali Anda membuat tag versi baru.

Cara membuat rilis baru:
```bash
git tag v1.0.0
git push origin v1.0.0
```
Cek tab **Actions** di GitHub Anda, dan file APK siap unduh akan otomatis tersedia di menu **Releases**.

---

## 📄 Lisensi
Proyek ini dilisensikan di bawah [MIT License](LICENSE). Silakan gunakan, modifikasi, dan kembangkan untuk mendukung kemajuan UMKM!