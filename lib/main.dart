import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const KampungDigitalApp());
}

class KampungDigitalApp extends StatelessWidget {
  const KampungDigitalApp({super.key});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF167C55);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kampung Digital Kiarajangkung',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: green),
        scaffoldBackgroundColor: const Color(0xFFF5F8F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F8F6),
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class Db {
  static final auth = FirebaseAuth.instance;
  static final firestore = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> module(String key) =>
      firestore.collection('kampung').doc('kiarajangkung').collection(key);
  static DocumentReference<Map<String, dynamic>> user(String uid) =>
      firestore.collection('users').doc(uid);
}

class PhotoService {
  static const int maxBytes = 1024 * 1024; // maksimal 1 MB
  // Ganti setelah Web App Google Apps Script selesai di-deploy.
  static const String driveApiUrl =
      'https://script.google.com/macros/s/AKfycbwUtml4Yb4wsKePvzZNmk4ifyCxjb88hcOdhwfjfZqqddevgqUWs_3B0oX5MLmLt8w/exec';
  static final picker = ImagePicker();

  static Future<Uint8List> pickAndCompress() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 78,
    );
    if (picked == null) throw Exception('Pemilihan foto dibatalkan.');
    final original = await picked.readAsBytes();
    Uint8List result = original;
    for (final quality in [78, 68, 58, 48, 38, 28]) {
      result = await FlutterImageCompress.compressWithList(
        original,
        minWidth: 1280,
        minHeight: 1280,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (result.lengthInBytes <= maxBytes) break;
    }
    if (result.lengthInBytes > maxBytes) {
      throw Exception('Ukuran foto masih lebih dari 1 MB. Pilih foto lain.');
    }
    return result;
  }

  static Future<Map<String, dynamic>> _request(Map<String, dynamic> body) async {
    if (driveApiUrl.contains('ISI_DEPLOYMENT_ID')) {
      throw Exception('URL Google Drive belum dipasang di main.dart.');
    }
    final user = Db.auth.currentUser;
    if (user == null) throw Exception('Silakan login kembali.');
    final token = await user.getIdToken(true);
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(driveApiUrl));
      request.headers.contentType = ContentType.json;
      request.followRedirects = false;
      request.write(jsonEncode({
        ...body,
        'idToken': token,
        'apiKey': Firebase.app().options.apiKey,
        'projectId': Firebase.app().options.projectId,
      }));

      var response = await request.close();

      // Apps Script ContentService sering mengembalikan 302 ke
      // script.googleusercontent.com setelah POST berhasil diproses.
      // Ambil isi respons dari URL pengalihan tersebut dengan GET.
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          throw Exception('Google Apps Script mengirim pengalihan tanpa alamat tujuan.');
        }
        final redirectUri = Uri.parse(driveApiUrl).resolve(location);
        if (!['script.google.com', 'script.googleusercontent.com']
            .contains(redirectUri.host)) {
          throw Exception(
            'Pengalihan Google Apps Script tidak dikenali (${redirectUri.host}). '
            'Pastikan akses Web App disetel Anyone.',
          );
        }
        final redirectedRequest = await client.getUrl(redirectUri);
        response = await redirectedRequest.close();
      }

      final responseText = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Server Google Drive (${response.statusCode}): $responseText');
      }
      final decoded = jsonDecode(responseText);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        throw Exception(decoded is Map
            ? (decoded['error'] ?? 'Gagal memproses foto')
            : 'Respons Google Drive tidak valid.');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> upload(Uint8List bytes, String moduleKey, {String? docId}) async {
    if (bytes.lengthInBytes > maxBytes) throw Exception('Foto melebihi batas 1 MB.');
    final result = await _request({
      'action': 'upload',
      'module': moduleKey,
      if (docId != null) 'docId': docId,
      'fileName': '${DateTime.now().millisecondsSinceEpoch}.jpg',
      'mimeType': 'image/jpeg',
      'base64': base64Encode(bytes),
    });
    return (result['imageUrl'] ?? '').toString();
  }

  static Future<Map<String, dynamic>> provisionResident({
    required String nik,
    required String nama,
    required String tanggalLahir,
    String telepon = '',
    String rt = '',
    String rw = '',
  }) async {
    return _request({
      'action': 'provisionResident',
      'nik': nik,
      'nama': nama,
      'tanggalLahir': tanggalLahir,
      'telepon': telepon,
      'rt': rt,
      'rw': rw,
    });
  }

  static Future<void> deleteIfOwned(String? url) async {
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final fileId = uri.queryParameters['id'];
    if (fileId == null || fileId.isEmpty || !uri.host.contains('drive.google.com')) return;
    try {
      await _request({'action': 'delete', 'fileId': fileId});
    } catch (_) {
      // Kegagalan menghapus foto lama tidak membatalkan penghapusan data utama.
    }
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: Db.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage();
        }
        if (snapshot.data == null) return const LoginPage();
        return UserProfileGate(user: snapshot.data!);
      },
    );
  }
}

class UserProfileGate extends StatelessWidget {
  final User user;
  const UserProfileGate({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: Db.user(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage();
        }
        if (snapshot.hasError) {
          return ErrorPage(message: 'Gagal membaca profil: ${snapshot.error}');
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const PendingAccountPage();
        }
        final accountStatus = (snapshot.data!.data()?['status'] ?? 'Aktif').toString().toLowerCase();
        if (accountStatus == 'nonaktif' || accountStatus == 'pending') {
          return const PendingAccountPage(inactive: true);
        }
        final data = snapshot.data!.data() ?? {};
        if (data['mustChangePassword'] == true) return const ChangePasswordPage(force: true);
        return HomePage(
          user: user,
          profile: data,
          role: (data['role'] ?? 'warga').toString(),
        );
      },
    );
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}

class ErrorPage extends StatelessWidget {
  final String message;
  const ErrorPage({super.key, required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool obscure = true;

  Future<void> submit() async {
    final identity = email.text.trim();
    final isNik = RegExp(r'^\d{16}$').hasMatch(identity);
    if (!isNik && !identity.contains('@')) {
      showMessage(context, 'Masukkan NIK 16 digit. Akun pengurus lama masih dapat masuk menggunakan email.');
      return;
    }
    if (password.text.isEmpty) {
      showMessage(context, 'Password wajib diisi.');
      return;
    }
    setState(() => busy = true);
    try {
      // Akun warga memakai alias email internal berbasis NIK.
      // Akun Owner/Admin lama tetap dapat memakai email Firebase yang sudah ada.
      final loginEmail = isNik ? '$identity@login.kiarajangkung.id' : identity;
      await Db.auth.signInWithEmailAndPassword(
        email: loginEmail,
        password: password.text,
      );
    } on FirebaseAuthException catch (e) {
      showMessage(context, authError(e));
    } catch (e) {
      showMessage(context, 'Terjadi kesalahan: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 86,
                    width: 86,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Icon(Icons.location_city_rounded, size: 42),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Kampung Digital',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text('Kiarajangkung • Informasi dan layanan warga',
                      style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 32),
                  Text('Masuk ke akun warga',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 18),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'NIK (16 digit) / Email pengurus',
                      hintText: 'Masukkan NIK. Akun Owner/Admin lama dapat memakai email.',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password (awal: tanggal lahir DDMMYYYY)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Masuk'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: busy ? null : () => showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Lupa password?'),
                        content: const Text('Silakan hubungi Admin atau Owner Kampung untuk verifikasi data dan reset password.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mengerti'))],
                      ),
                    ),
                    child: const Text('Lupa password? Hubungi Admin / Owner'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PendingAccountPage extends StatelessWidget {
  final bool inactive;
  const PendingAccountPage({super.key, this.inactive = false});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.verified_user_outlined, size: 54),
              const SizedBox(height: 16),
              Text(
                inactive ? 'Akun belum aktif' : 'Profil akun belum tersedia',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Silakan hubungi Admin/Owner Kampung Kiarajangkung. Akun warga dibuat melalui data Sensus Penduduk.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Db.auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Keluar'),
              ),
            ]),
          ),
        ),
      );
}

class CompleteProfilePage extends StatefulWidget {
  final User user;
  const CompleteProfilePage({super.key, required this.user});
  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  bool busy = false;

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      showMessage(context, 'Nama lengkap wajib diisi.');
      return;
    }
    setState(() => busy = true);
    try {
      await Db.user(widget.user.uid).set({
        'nama': name.text.trim(),
        'email': widget.user.email ?? '',
        'telepon': phone.text.trim(),
        'alamat': address.text.trim(),
        'role': 'warga',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      showMessage(context, 'Gagal menyimpan profil: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Lengkapi akun')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Lengkapi data diri agar layanan kampung dapat digunakan.'),
            const SizedBox(height: 20),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama lengkap')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Nomor WhatsApp')),
            const SizedBox(height: 12),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Alamat / RT / RW')),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: busy ? null : save,
              child: busy ? const CircularProgressIndicator() : const Text('Simpan profil'),
            ),
          ],
        ),
      );
}

class ModuleInfo {
  final String keyName;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool privateData;
  const ModuleInfo(this.keyName, this.title, this.subtitle, this.icon,
      {this.privateData = false});
}

const modules = <ModuleInfo>[
  ModuleInfo('profil_kampung', 'Profil Kampung', 'Sejarah, visi, misi dan batas wilayah', Icons.account_balance_outlined),
  ModuleInfo('pengumuman', 'Pengumuman & Agenda', 'Informasi dan kegiatan warga', Icons.campaign_outlined),
  ModuleInfo('galeri', 'Galeri Kampung', 'Dokumentasi kegiatan kampung', Icons.photo_library_outlined),
  ModuleInfo('sensus', 'Sensus Penduduk', 'Data keluarga dan demografi', Icons.groups_outlined, privateData: true),
  ModuleInfo('perangkat', 'Perangkat Kampung', 'Kadus, RW, RT, kader dan DKM', Icons.badge_outlined),
  ModuleInfo('ronda', 'Jadwal Ronda', 'Jadwal dan informasi siskamling', Icons.nightlight_outlined),
  ModuleInfo('kontak_darurat', 'Kontak Darurat', 'Babinsa, Bhabinkamtibmas dan layanan', Icons.emergency_outlined),
  ModuleInfo('umkm', 'UMKM Warga', 'Direktori usaha dan produk lokal', Icons.storefront_outlined),
  ModuleInfo('sarana', 'Sarana & Prasarana', 'Fasilitas umum kampung', Icons.domain_outlined),
  ModuleInfo('wisata', 'Wisata Kampung', 'Destinasi dan potensi wisata', Icons.park_outlined),
  ModuleInfo('kesenian', 'Kesenian & Budaya', 'Sanggar, paguron dan seni tradisi', Icons.theater_comedy_outlined),
  ModuleInfo('kebersihan', 'Kebersihan', 'Jadwal pengangkutan sampah setiap Jumat pagi', Icons.cleaning_services_outlined),
  ModuleInfo('fasilitas_kesehatan', 'Fasilitas Kesehatan', 'Klinik, puskesmas dan apotek', Icons.local_hospital_outlined),
  ModuleInfo('organisasi', 'Organisasi & Lembaga Kampung', 'Karang Taruna, PKK, Posyandu, kelompok tani dan lainnya', Icons.groups_2_outlined),
];

class HomePage extends StatefulWidget {
  final User user;
  final Map<String, dynamic> profile;
  final String role;
  const HomePage({super.key, required this.user, required this.profile, required this.role});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool get isAdmin => widget.role.toLowerCase() == 'admin' || widget.role.toLowerCase() == 'owner';

  @override
  Widget build(BuildContext context) {
    final pages = [
      dashboard(),
      const ModulesPage(),
      ProfilePage(user: widget.user, profile: widget.profile, isAdmin: isAdmin),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kampung Digital'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Panel Admin',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPage())),
            ),
          IconButton(
            tooltip: 'Pengaturan akun',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ProfilePage(user: widget.user, profile: widget.profile, isAdmin: isAdmin),
            )),
          ),
        ],
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Beranda'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Layanan'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Akun'),
        ],
      ),
    );
  }

  Widget dashboard() {
    final name = (widget.profile['nama'] ?? 'Warga').toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF167C55), Color(0xFF239B70)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Wilujeng sumping 👋', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Kampung Digital Kiarajangkung', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const DashboardAnnouncements(),
        const SizedBox(height: 18),
        const DashboardGallery(),
        const SizedBox(height: 22),
        Text('Ringkasan Kampung', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: StatCard(
              icon: Icons.people_alt_outlined,
              title: 'Data warga',
              value: isAdmin ? 'Kelola sensus' : 'Informasi warga',
            )),
            const SizedBox(width: 10),
            const Expanded(child: StatCard(
              icon: Icons.store_outlined,
              title: 'UMKM',
              value: 'Lihat data',
            )),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Akses cepat', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            TextButton(onPressed: () => setState(() => tab = 1), child: const Text('Lihat semua')),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: modules.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.55,
          ),
          itemBuilder: (_, i) => InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ModulePage(module: modules[i], isAdmin: isAdmin),
            )),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(modules[i].icon, color: Theme.of(context).colorScheme.primary, size: 27),
                  const SizedBox(height: 9),
                  Text(modules[i].title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(modules[i].subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DashboardAnnouncements extends StatelessWidget {
  const DashboardAnnouncements({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Db.module('pengumuman').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final items = snapshot.data!.docs.map((d) => d.data()).where((d) {
          final status = (d['status'] ?? 'aktif').toString().toLowerCase();
          return status != 'nonaktif' && status != 'arsip';
        }).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        final message = items.map((d) {
          final title = (d['judul'] ?? d['nama'] ?? 'Pengumuman').toString();
          final detail = (d['deskripsi'] ?? d['keterangan'] ?? '').toString();
          return detail.trim().isEmpty ? title : '$title: $detail';
        }).join('     •     ');
        return Container(
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1CC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD778)),
          ),
          child: Row(children: [
            Container(
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFD778),
                borderRadius: BorderRadius.horizontal(left: Radius.circular(13)),
              ),
              child: const Icon(Icons.campaign_rounded, color: Color(0xFF704900)),
            ),
            const SizedBox(width: 10),
            Expanded(child: _MarqueeText(text: message)),
          ]),
        );
      },
    );
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  const _MarqueeText({required this.text});
  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: Duration(seconds: (widget.text.length ~/ 8).clamp(12, 35).toInt()))..repeat();
  }
  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) controller.duration = Duration(seconds: (widget.text.length ~/ 8).clamp(12, 35).toInt());
  }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ClipRect(
    child: LayoutBuilder(builder: (context, constraints) => AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Transform.translate(
        offset: Offset(constraints.maxWidth - (constraints.maxWidth + widget.text.length * 7.0) * controller.value, 0),
        child: Align(alignment: Alignment.centerLeft, child: Text(widget.text, maxLines: 1, softWrap: false, style: const TextStyle(color: Color(0xFF704900), fontWeight: FontWeight.w600))),
      ),
    )),
  );
}

class DashboardGallery extends StatefulWidget {
  const DashboardGallery({super.key});
  @override
  State<DashboardGallery> createState() => _DashboardGalleryState();
}

class _DashboardGalleryState extends State<DashboardGallery> {
  final PageController pageController = PageController(viewportFraction: 1);
  Timer? timer;
  int current = 0;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> photos = [];

  void startSlide() {
    timer?.cancel();
    if (photos.length < 2) return;
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !pageController.hasClients || photos.isEmpty) return;
      current = (current + 1) % photos.length;
      pageController.animateToPage(current, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() { timer?.cancel(); pageController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Db.module('galeri').orderBy('updatedAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) return const SizedBox.shrink();
        photos = snapshot.data!.docs.where((doc) {
          final d = doc.data();
          final url = (d['fotoUrl'] ?? d['foto'] ?? d['imageUrl'] ?? '').toString().trim();
          return url.startsWith('https://') || url.startsWith('http://');
        }).toList();
        if (photos.isEmpty) return const SizedBox.shrink();
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) startSlide(); });
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Kegiatan Warga', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 190,
              child: PageView.builder(
                controller: pageController,
                itemCount: photos.length,
                onPageChanged: (v) => setState(() => current = v),
                itemBuilder: (context, index) {
                  final data = photos[index].data();
                  final url = (data['fotoUrl'] ?? data['foto'] ?? data['imageUrl']).toString();
                  final title = (data['judul'] ?? data['nama'] ?? 'Kegiatan warga').toString();
                  return Stack(fit: StackFit.expand, children: [
                    Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300, child: const Icon(Icons.broken_image_outlined, size: 42))),
                    Positioned(left: 0, right: 0, bottom: 0, child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 22, 14, 12),
                      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])),
                      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    )),
                  ]);
                },
              ),
            ),
          ),
          if (photos.length > 1) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(photos.length, (i) => Container(
              width: current == i ? 18 : 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(color: current == i ? Theme.of(context).colorScheme.primary : Colors.grey.shade400, borderRadius: BorderRadius.circular(8)),
            ))),
          ],
        ]);
      },
    );
  }
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  const StatCard({super.key, required this.icon, required this.title, required this.value});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ]),
        ),
      );
}

class ModulesPage extends StatelessWidget {
  const ModulesPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Informasi & Layanan', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...modules.map((m) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(m.icon),
                  ),
                  title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(m.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ModulePage(module: m, isAdmin: false),
                  )),
                ),
              )),
        ],
      );
}

class ModulePage extends StatelessWidget {
  final ModuleInfo module;
  final bool isAdmin;
  const ModulePage({super.key, required this.module, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final canEdit = isAdmin;
    if (module.privateData && !canEdit) {
      return Scaffold(
        appBar: AppBar(title: Text(module.title)),
        body: const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Data sensus lengkap hanya dapat diakses oleh pengurus yang berwenang.',
              textAlign: TextAlign.center),
        )),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(module.title)),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => showRecordForm(context, module, isAdmin: canEdit),
              icon: const Icon(Icons.add),
              label: const Text('Tambah data'),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.module(module.keyName).orderBy('updatedAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Gagal memuat data: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Belum ada data. Informasi akan ditampilkan di sini.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data();
              final title = (data['judul'] ?? data['nama'] ?? data['nama_usaha'] ?? data['nama_lengkap'] ?? 'Data kampung').toString();
              final desc = (data['deskripsi'] ?? data['keterangan'] ?? data['alamat'] ?? '').toString();
              final photo = (data['fotoUrl'] ?? data['foto'] ?? data['imageUrl'] ?? '').toString().trim();
              final isChairForRecord = module.keyName == 'organisasi' &&
                  (data['ketuaUid'] ?? '').toString() == Db.auth.currentUser?.uid;
              final canEditThisRecord = canEdit || isChairForRecord;
              return Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 14),
                child: InkWell(
                  onTap: () => showRecordDetail(context, title, data),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (module.keyName != 'sensus')
                      SizedBox(
                        height: 174,
                        width: double.infinity,
                        child: photo.isEmpty
                            ? _photoPlaceholder()
                            : Image.network(photo, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _photoPlaceholder()),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 12, 8, 14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          if ((data['kategori'] ?? data['jenisFasilitas'] ?? data['jenisUsaha'] ?? '').toString().trim().isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 4), child: Text(
                              (data['kategori'] ?? data['jenisFasilitas'] ?? data['jenisUsaha']).toString(),
                              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600))),
                          if (desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(
                            desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade700, height: 1.3))),
                          const SizedBox(height: 7),
                          Text('Lihat detail  ›', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                        ])),
                        if (module.keyName == 'pengumuman')
                          IconButton(
                            tooltip: 'Bagikan ke WhatsApp',
                            icon: const Icon(Icons.share_outlined, color: Colors.green),
                            onPressed: () => shareAnnouncementToWhatsApp(context, data),
                          ),
                        if (canEditThisRecord) PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              showRecordForm(context, module, isAdmin: canEdit, isChair: isChairForRecord && !canEdit, docId: doc.id, initial: data);
                            } else if (v == 'delete' && canEdit) {
                              final yes = await confirmDelete(context);
                              if (yes == true) {
                                await PhotoService.deleteIfOwned(photo);
                                await doc.reference.delete();
                              }
                            }
                          },
                          itemBuilder: (_) => canEdit
                              ? const [
                                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'delete', child: Text('Hapus')),
                                ]
                              : const [PopupMenuItem(value: 'edit', child: Text('Edit organisasi'))],
                        ) else const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.arrow_forward_ios, size: 16)),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}


Widget _photoPlaceholder() => Container(
  color: const Color(0xFFE8F1EC),
  alignment: Alignment.center,
  child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.image_outlined, size: 42, color: Color(0xFF6B9B82)),
    SizedBox(height: 6),
    Text('Belum ada foto', style: TextStyle(color: Color(0xFF6B9B82))),
  ]),
);

class ModuleField {
  final String key;
  final String label;
  final String hint;
  final int lines;
  final TextInputType keyboard;
  final bool required;
  const ModuleField(this.key, this.label, {
    this.hint = '',
    this.lines = 1,
    this.keyboard = TextInputType.text,
    this.required = false,
  });
}

List<ModuleField> fieldsForModule(String key) {
  switch (key) {
    case 'profil_kampung':
      return const [
        ModuleField('sejarah', 'Sejarah kampung', lines: 4),
        ModuleField('visi', 'Visi', lines: 2),
        ModuleField('misi', 'Misi', lines: 4),
        ModuleField('batasWilayah', 'Batas wilayah', lines: 3),
        ModuleField('luasWilayah', 'Luas wilayah'),
        ModuleField('jumlahPenduduk', 'Jumlah penduduk', keyboard: TextInputType.number),
        ModuleField('fotoUrl', 'URL foto profil', hint: 'https://...'),
      ];
    case 'pengumuman':
      return const [
        ModuleField('kategori', 'Kategori', hint: 'Umum / Kegiatan / Penting'),
        ModuleField('deskripsi', 'Isi pengumuman', lines: 5, required: true),
        ModuleField('tanggal', 'Tanggal kegiatan', hint: 'Contoh: 20-11-2026'),
        ModuleField('waktu', 'Waktu', hint: 'Contoh: 08.00 WIB'),
        ModuleField('lokasi', 'Lokasi kegiatan'),
        ModuleField('prioritas', 'Prioritas', hint: 'Normal / Penting / Mendesak'),
        ModuleField('status', 'Status', hint: 'aktif / nonaktif / arsip'),
        ModuleField('fotoUrl', 'URL foto/lampiran', hint: 'https://...'),
      ];
    case 'galeri':
      return const [
        ModuleField('kategori', 'Kategori foto', hint: 'Kegiatan / Pembangunan / Budaya'),
        ModuleField('tanggal', 'Tanggal kegiatan'),
        ModuleField('deskripsi', 'Keterangan foto', lines: 3),
        ModuleField('fotoUrl', 'URL foto', hint: 'https://...', required: true),
        ModuleField('videoUrl', 'URL video (opsional)', hint: 'https://...'),
      ];
    case 'sensus':
      return const [
        ModuleField('noKK', 'Nomor Kartu Keluarga', keyboard: TextInputType.number),
        ModuleField('nik', 'NIK', keyboard: TextInputType.number, required: true),
        ModuleField('jenisKelamin', 'Jenis kelamin', hint: 'Laki-laki / Perempuan'),
        ModuleField('tempatLahir', 'Tempat lahir'),
        ModuleField('tanggalLahir', 'Tanggal lahir', hint: 'DD-MM-YYYY (wajib untuk akun awal)', required: true),
        ModuleField('telepon', 'Nomor WhatsApp', keyboard: TextInputType.phone),
        ModuleField('statusPerkawinan', 'Status perkawinan'),
        ModuleField('pendidikan', 'Pendidikan'),
        ModuleField('pekerjaan', 'Pekerjaan'),
        ModuleField('hubunganKeluarga', 'Hubungan dalam keluarga'),
        ModuleField('rt', 'RT'),
        ModuleField('rw', 'RW'),
      ];
    case 'perangkat':
      return const [
        ModuleField('jabatan', 'Jabatan', required: true),
        ModuleField('wilayah', 'Wilayah tugas', hint: 'Dusun / RW / RT'),
        ModuleField('telepon', 'Nomor WhatsApp', keyboard: TextInputType.phone),
        ModuleField('alamat', 'Alamat'),
        ModuleField('periode', 'Periode jabatan'),
        ModuleField('fotoUrl', 'URL foto', hint: 'https://...'),
      ];
    case 'ronda':
      return const [
        ModuleField('rt', 'RT'),
        ModuleField('rw', 'RW'),
        ModuleField('hari', 'Hari ronda', required: true),
        ModuleField('jamMulai', 'Jam mulai', hint: '21.00'),
        ModuleField('jamSelesai', 'Jam selesai', hint: '04.00'),
        ModuleField('anggota', 'Nama anggota / petugas', lines: 4),
        ModuleField('catatan', 'Catatan', lines: 2),
      ];
    case 'kontak_darurat':
      return const [
        ModuleField('kategori', 'Jenis layanan', hint: 'Babinsa / Bhabinkamtibmas / Ambulans'),
        ModuleField('telepon', 'Nomor WhatsApp/telepon', keyboard: TextInputType.phone, required: true),
        ModuleField('alamat', 'Alamat'),
        ModuleField('lokasiMaps', 'Link Google Maps', hint: 'https://maps.google.com/...'),
        ModuleField('catatan', 'Keterangan layanan', lines: 3),
      ];
    case 'umkm':
      return const [
        ModuleField('pemilik', 'Nama pemilik', required: true),
        ModuleField('jenisUsaha', 'Jenis usaha'),
        ModuleField('produk', 'Produk / jasa', lines: 3),
        ModuleField('alamat', 'Alamat usaha'),
        ModuleField('telepon', 'WhatsApp pemilik', keyboard: TextInputType.phone),
        ModuleField('jamBuka', 'Jam operasional'),
        ModuleField('lokasiMaps', 'Link Google Maps', hint: 'https://maps.google.com/...'),
        ModuleField('fotoUrl', 'URL foto usaha', hint: 'https://...'),
      ];
    case 'sarana':
      return const [
        ModuleField('jenisFasilitas', 'Jenis fasilitas'),
        ModuleField('alamat', 'Alamat / lokasi'),
        ModuleField('lokasiMaps', 'Link Google Maps', hint: 'https://maps.google.com/...'),
        ModuleField('kondisi', 'Kondisi', hint: 'Baik / Perlu perbaikan / Rusak'),
        ModuleField('pengelola', 'Pengelola'),
        ModuleField('tahunDibangun', 'Tahun dibangun', keyboard: TextInputType.number),
        ModuleField('telepon', 'Nomor pengelola', keyboard: TextInputType.phone),
        ModuleField('fotoUrl', 'URL foto', hint: 'https://...'),
      ];
    case 'wisata':
      return const [
        ModuleField('jenisWisata', 'Jenis wisata'),
        ModuleField('deskripsi', 'Deskripsi daya tarik', lines: 4),
        ModuleField('alamat', 'Alamat'),
        ModuleField('lokasiMaps', 'Link Google Maps', hint: 'https://maps.google.com/...'),
        ModuleField('jamBuka', 'Jam operasional'),
        ModuleField('hargaTiket', 'Harga tiket', hint: 'Contoh: Gratis / Rp5.000'),
        ModuleField('telepon', 'Kontak pengelola', keyboard: TextInputType.phone),
        ModuleField('fotoUrl', 'URL foto', hint: 'https://...'),
      ];
    case 'kesenian':
      return const [
        ModuleField('jenisKesenian', 'Jenis kesenian'),
        ModuleField('namaKelompok', 'Nama kelompok / sanggar'),
        ModuleField('ketua', 'Ketua / pimpinan'),
        ModuleField('telepon', 'WhatsApp', keyboard: TextInputType.phone),
        ModuleField('alamat', 'Alamat sanggar'),
        ModuleField('lokasiMaps', 'Link Google Maps', hint: 'https://maps.google.com/...'),
        ModuleField('sejarah', 'Sejarah / keterangan', lines: 4),
        ModuleField('fotoUrl', 'URL foto', hint: 'https://...'),
        ModuleField('videoUrl', 'URL video (opsional)', hint: 'https://...'),
      ];
    case 'kebersihan':
      return const [
        ModuleField('jadwal', 'Jadwal pengangkutan', hint: 'Setiap Jumat pagi', required: true),
        ModuleField('cakupan', 'Cakupan layanan', hint: 'Diambil langsung dari setiap rumah'),
        ModuleField('biaya', 'Biaya per rumah per pengambilan', hint: 'Rp3.000', required: true),
        ModuleField('petugas', 'Nama petugas'),
        ModuleField('telepon', 'WhatsApp petugas', keyboard: TextInputType.phone),
        ModuleField('catatan', 'Catatan layanan', lines: 3),
      ];
    case 'fasilitas_kesehatan':
      return const [
        ModuleField('jenisFasilitas', 'Jenis fasilitas', hint: 'Klinik / Puskesmas Desa / Puskesmas Kecamatan / Apotek', required: true),
        ModuleField('alamat', 'Alamat'),
        ModuleField('lokasiMaps', 'Link Google Maps', hint: 'https://maps.google.com/...'),
        ModuleField('telepon', 'Nomor telepon / WhatsApp', keyboard: TextInputType.phone),
        ModuleField('jamBuka', 'Jam pelayanan'),
        ModuleField('layanan', 'Jenis layanan', lines: 3),
        ModuleField('catatan', 'Catatan tambahan', lines: 2),
      ];
    case 'organisasi':
      return const [
        ModuleField('kategori', 'Jenis organisasi', hint: 'Karang Taruna / PKK / Posyandu / Kelompok Tani / DKM / Linmas / LPM / Lainnya', required: true),
        ModuleField('deskripsi', 'Profil dan tujuan organisasi', lines: 4),
        ModuleField('ketua', 'Nama ketua'),
        ModuleField('ketuaUid', 'UID akun Ketua organisasi (diisi Owner/Admin)'),
        ModuleField('wakil', 'Nama wakil ketua'),
        ModuleField('sekretaris', 'Nama sekretaris'),
        ModuleField('bendahara', 'Nama bendahara'),
        ModuleField('anggota', 'Daftar anggota / jumlah anggota', lines: 3),
        ModuleField('programKerja', 'Program kerja', lines: 4),
        ModuleField('alamat', 'Alamat sekretariat'),
        ModuleField('telepon', 'WhatsApp pengurus', keyboard: TextInputType.phone),
        ModuleField('lokasiMaps', 'Link Google Maps sekretariat', hint: 'https://maps.google.com/...'),
        ModuleField('periode', 'Periode kepengurusan'),
        ModuleField('fotoUrl', 'URL foto/logo organisasi', hint: 'https://...'),
      ];
    default:
      return const [
        ModuleField('deskripsi', 'Keterangan', lines: 3),
        ModuleField('alamat', 'Alamat / lokasi'),
        ModuleField('telepon', 'Nomor WhatsApp', keyboard: TextInputType.phone),
        ModuleField('catatan', 'Catatan tambahan', lines: 2),
      ];
  }
}

Future<void> showRecordForm(
  BuildContext context,
  ModuleInfo module, {
  required bool isAdmin,
  bool isChair = false,
  String? docId,
  Map<String, dynamic>? initial,
}) async {
  if (!isAdmin && !isChair) return;
  final title = TextEditingController(
    text: (initial?['judul'] ?? initial?['nama'] ?? initial?['nama_usaha'] ?? '').toString(),
  );
  final definitions = fieldsForModule(module.keyName);
  final controllers = <String, TextEditingController>{
    for (final field in definitions)
      field.key: TextEditingController(text: (initial?[field.key] ?? '').toString()),
  };
  final formKey = GlobalKey<FormState>();
  final photoController = TextEditingController(
    text: (initial?['fotoUrl'] ?? initial?['foto'] ?? initial?['imageUrl'] ?? '').toString(),
  );
  Uint8List? selectedPhoto;
  bool uploadingPhoto = false;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * .88),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFFF5F8F6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(height: 18),
                  Text(docId == null ? 'Tambah ${module.title}' : 'Edit ${module.title}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: title,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Nama/judul wajib diisi' : null,
                    decoration: InputDecoration(
                      labelText: module.keyName == 'sensus' ? 'Nama lengkap warga' :
                        module.keyName == 'umkm' ? 'Nama usaha' :
                        module.keyName == 'kebersihan' ? 'Nama layanan' :
                        module.keyName == 'fasilitas_kesehatan' ? 'Nama fasilitas kesehatan' : 'Nama / Judul',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...definitions.where((field) => field.key != 'fotoUrl' && !(isChair && field.key == 'ketuaUid')).map((field) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextFormField(
                      controller: controllers[field.key],
                      keyboardType: field.keyboard,
                      maxLines: field.lines,
                      validator: field.required
                          ? (v) => v == null || v.trim().isEmpty ? '${field.label} wajib diisi' : null
                          : null,
                      decoration: InputDecoration(
                        labelText: field.label,
                        hintText: field.hint.isEmpty ? null : field.hint,
                        alignLabelWithHint: field.lines > 1,
                      ),
                    ),
                  )),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Foto / Gambar', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Maksimal 1 MB. Foto akan dikompres otomatis.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 10),
                        if (selectedPhoto != null)
                          ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(selectedPhoto!, height: 150, width: double.infinity, fit: BoxFit.cover))
                        else if (photoController.text.trim().isNotEmpty)
                          ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(photoController.text.trim(), height: 150, width: double.infinity, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => SizedBox(height: 90, child: _photoPlaceholder())))
                        else
                          SizedBox(height: 90, child: _photoPlaceholder()),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: uploadingPhoto ? null : () async {
                            try {
                              final bytes = await PhotoService.pickAndCompress();
                              setSheetState(() { selectedPhoto = bytes; });
                              if (sheetContext.mounted) showMessage(sheetContext, 'Foto siap diunggah (${(bytes.lengthInBytes / 1024).toStringAsFixed(0)} KB).');
                            } catch (e) {
                              if (sheetContext.mounted && !e.toString().contains('dibatalkan')) showMessage(sheetContext, '$e');
                            }
                          },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Pilih foto dari galeri'),
                        ),
                        TextFormField(
                          controller: photoController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Atau URL foto (opsional)',
                            hintText: 'https://alamat-gambar.jpg',
                            prefixIcon: Icon(Icons.link),
                          ),
                          onChanged: (_) => setSheetState(() { selectedPhoto = null; }),
                        ),
                        if (selectedPhoto != null || photoController.text.trim().isNotEmpty)
                          Align(alignment: Alignment.centerRight, child: TextButton.icon(
                            onPressed: () => setSheetState(() { selectedPhoto = null; photoController.clear(); }),
                            icon: const Icon(Icons.delete_outline), label: const Text('Hapus pilihan foto')),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (module.keyName == 'pengumuman')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tampilkan di pengumuman berjalan'),
                      value: (controllers['status']?.text ?? 'aktif').toLowerCase() != 'nonaktif',
                      onChanged: (v) => setSheetState(() {
                        controllers['status']!.text = v ? 'aktif' : 'nonaktif';
                      }),
                    ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: uploadingPhoto ? null : () async {
                      if (!formKey.currentState!.validate()) return;
                      setSheetState(() { uploadingPhoto = true; });
                      String? newlyUploadedPhotoUrl;
                      try {
                        String finalPhotoUrl = photoController.text.trim();
                        if (selectedPhoto != null) {
                          finalPhotoUrl = await PhotoService.upload(selectedPhoto!, module.keyName, docId: docId);
                          newlyUploadedPhotoUrl = finalPhotoUrl;
                        }
                      final payload = <String, dynamic>{
                        'judul': title.text.trim(),
                        'nama': title.text.trim(),
                        ...{
                          for (final field in definitions.where((field) => field.key != 'fotoUrl'))
                            field.key: controllers[field.key]!.text.trim(),
                        },
                        'fotoUrl': finalPhotoUrl,
                        'updatedAt': FieldValue.serverTimestamp(),
                        'updatedBy': Db.auth.currentUser?.uid,
                      };
                      // Field lama tetap dipertahankan agar daftar dan dashboard yang
                      // sudah ada tetap dapat membaca data dengan format sebelumnya.
                      payload['deskripsi'] ??= '';
                      payload['keterangan'] ??= payload['deskripsi'];
                        if (docId == null) {
                          payload['createdAt'] = FieldValue.serverTimestamp();
                          payload['createdBy'] = Db.auth.currentUser?.uid;
                          await Db.module(module.keyName).add(payload);
                          if (module.keyName == 'sensus') {
                            try {
                              await PhotoService.provisionResident(
                                nik: (payload['nik'] ?? '').toString().trim(),
                                nama: title.text.trim(),
                                tanggalLahir: (payload['tanggalLahir'] ?? '').toString().trim(),
                                telepon: (payload['telepon'] ?? '').toString(),
                                rt: (payload['rt'] ?? '').toString(),
                                rw: (payload['rw'] ?? '').toString(),
                              );
                              if (context.mounted) showMessage(context, 'Data sensus tersimpan dan akun warga berhasil dibuat. Password awal adalah tanggal lahir DDMMYYYY; warga wajib menggantinya saat masuk pertama kali.');
                            } catch (accountError) {
                              if (context.mounted) showMessage(context, 'Data sensus tersimpan, tetapi akun belum berhasil dibuat: $accountError');
                            }
                          }
                        } else {
                          await Db.module(module.keyName).doc(docId).update(payload);
                          final oldPhoto = (initial?['fotoUrl'] ?? initial?['foto'] ?? initial?['imageUrl'] ?? '').toString();
                          if (oldPhoto.isNotEmpty && oldPhoto != finalPhotoUrl) {
                            await PhotoService.deleteIfOwned(oldPhoto);
                          }
                        }
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        if (context.mounted && module.keyName != 'sensus') showMessage(context, 'Data berhasil disimpan.');
                      } catch (e) {
                        if (newlyUploadedPhotoUrl != null) {
                          await PhotoService.deleteIfOwned(newlyUploadedPhotoUrl);
                        }
                        if (context.mounted) showMessage(context, 'Gagal menyimpan: $e');
                      } finally {
                        if (sheetContext.mounted) setSheetState(() { uploadingPhoto = false; });
                      }
                    },
                    child: const Text('Simpan data'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  title.dispose();
  photoController.dispose();
  for (final controller in controllers.values) {
    controller.dispose();
  }
}

class ProfilePage extends StatefulWidget {
  final User user;
  final Map<String, dynamic> profile;
  final bool isAdmin;
  const ProfilePage({super.key, required this.user, required this.profile, required this.isAdmin});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Map<String, dynamic> profile = Map<String, dynamic>.from(widget.profile);
  bool uploading = false;

  Future<void> changePhoto() async {
    setState(() => uploading = true);
    try {
      final bytes = await PhotoService.pickAndCompress();
      final url = await PhotoService.upload(bytes, 'profil');
      final old = (profile['fotoProfilUrl'] ?? '').toString();
      await Db.user(widget.user.uid).update({
        'fotoProfilUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (old.isNotEmpty && old != url) await PhotoService.deleteIfOwned(old);
      if (mounted) {
        setState(() => profile['fotoProfilUrl'] = url);
        showMessage(context, 'Foto profil berhasil diperbarui.');
      }
    } catch (e) {
      if (mounted && !e.toString().contains('dibatalkan')) showMessage(context, 'Gagal mengganti foto profil: $e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = (profile['fotoProfilUrl'] ?? '').toString();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Center(child: Stack(alignment: Alignment.bottomRight, children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo.isEmpty ? const Icon(Icons.person, size: 48) : null,
          ),
          Material(
            color: Theme.of(context).colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: uploading ? null : changePhoto,
              child: Padding(padding: const EdgeInsets.all(8), child: uploading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.camera_alt, color: Colors.white, size: 18)),
            ),
          ),
        ])),
        const SizedBox(height: 12),
        Center(child: Text((profile['nama'] ?? 'Pengguna').toString(), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
        Center(child: Text(_maskNik((profile['nik'] ?? '').toString()), style: TextStyle(color: Colors.grey.shade600))),
        const SizedBox(height: 8),
        Center(child: Chip(label: Text((profile['role'] ?? 'warga').toString().toUpperCase()))),
        const SizedBox(height: 22),
        Card(child: Column(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Ganti foto profil'),
            subtitle: const Text('Pilih foto dari galeri HP (maksimal 1 MB setelah kompresi)'),
            onTap: uploading ? null : changePhoto,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit data diri'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(user: widget.user, profile: profile))),
          ),
          const Divider(height: 1),
          if (widget.isAdmin)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Panel Admin'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPage())),
            ),
          if (widget.isAdmin) const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('Ubah password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordPage())),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Keluar akun', style: TextStyle(color: Colors.red)),
            onTap: () async => Db.auth.signOut(),
          ),
        ])),
      ],
    );
  }
}

class EditProfilePage extends StatefulWidget {
  final User user;
  final Map<String, dynamic> profile;
  const EditProfilePage({super.key, required this.user, required this.profile});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final name = TextEditingController(text: (widget.profile['nama'] ?? '').toString());
  late final phone = TextEditingController(text: (widget.profile['telepon'] ?? '').toString());
  late final address = TextEditingController(text: (widget.profile['alamat'] ?? '').toString());
  bool busy = false;

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await Db.user(widget.user.uid).update({
        'nama': name.text.trim(),
        'telepon': phone.text.trim(),
        'alamat': address.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        showMessage(context, 'Profil berhasil diperbarui.');
        Navigator.pop(context);
      }
    } catch (e) {
      showMessage(context, 'Gagal memperbarui profil: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit data diri')),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama lengkap')),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Nomor WhatsApp')),
          const SizedBox(height: 12),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Alamat / RT / RW')),
          const SizedBox(height: 12),
          TextFormField(initialValue: widget.user.email ?? '', readOnly: true, decoration: const InputDecoration(labelText: 'Email akun')),
          const SizedBox(height: 22),
          FilledButton(onPressed: busy ? null : save, child: busy ? const CircularProgressIndicator() : const Text('Simpan perubahan')),
        ]),
      );
}

class ChangePasswordPage extends StatefulWidget {
  final bool force;
  const ChangePasswordPage({super.key, this.force = false});
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final password = TextEditingController();
  bool busy = false;
  Future<void> change() async {
    if (password.text.length < 6) {
      showMessage(context, 'Password minimal 6 karakter.');
      return;
    }
    setState(() => busy = true);
    try {
      await Db.auth.currentUser!.updatePassword(password.text);
      await Db.user(Db.auth.currentUser!.uid).set({
        'mustChangePassword': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        showMessage(context, 'Password berhasil diubah.');
        if (widget.force) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthGate()),
            (route) => false,
          );
        } else {
          Navigator.pop(context);
        }
      }
    } on FirebaseAuthException catch (e) {
      showMessage(context, e.code == 'requires-recent-login'
          ? 'Demi keamanan, silakan keluar dan masuk kembali sebelum mengubah password.'
          : authError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ubah password')),
        body: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password baru')),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : change, child: const Text('Simpan password'))),
          ]),
        ),
      );
}

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Panel Pengelola')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
              child: const Text('Kelola informasi Kampung Digital. Data yang ditambahkan di sini akan tampil dinamis pada menu warga.'),
            ),
            const SizedBox(height: 14),
            ...modules.map((m) => Card(
                  child: ListTile(
                    leading: Icon(m.icon),
                    title: Text(m.title),
                    subtitle: const Text('Tambah, edit, dan hapus data'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ModulePage(module: m, isAdmin: true))),
                  ),
                )),
            Card(
              child: ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Manajemen akun warga'),
                subtitle: const Text('Lihat akun dan tetapkan admin'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementPage())),
              ),
            ),
          ],
        ),
      );
}

class UserManagementPage extends StatelessWidget {
  const UserManagementPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Manajemen akun')),
        body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: Db.user(Db.auth.currentUser!.uid).get(),
          builder: (context, me) {
            if (!me.hasData) return const Center(child: CircularProgressIndicator());
            final isOwner = (me.data!.data()?['role'] ?? '').toString() == 'owner';
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: Db.firestore.collection('users').orderBy('nama').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Gagal memuat akun: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: snapshot.data!.docs.map((doc) {
                    final d = doc.data();
                    final role = (d['role'] ?? 'warga').toString();
                    final nik = (d['nik'] ?? '').toString();
                    final maskedNik = nik.length == 16
                        ? '${nik.substring(0, 4)}********${nik.substring(12)}'
                        : 'NIK tidak tersedia';
                    return Card(
                      child: ListTile(
                        title: Text((d['nama'] ?? 'Tanpa nama').toString()),
                        subtitle: Text('$maskedNik\nPeran: $role • Status: ${(d['status'] ?? 'Aktif')}'),
                        isThreeLine: true,
                        trailing: isOwner && role != 'owner'
                            ? PopupMenuButton<String>(
                                onSelected: (value) async {
                                  try {
                                    await doc.reference.update({
                                      'role': value,
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    });
                                    if (context.mounted) showMessage(context, 'Peran akun diperbarui menjadi $value.');
                                  } catch (e) {
                                    if (context.mounted) showMessage(context, 'Gagal mengubah peran: $e');
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'warga', child: Text('Jadikan Warga')),
                                  PopupMenuItem(value: 'admin', child: Text('Jadikan Admin')),
                                ],
                              )
                            : Chip(label: Text(role.toUpperCase())),
                      ),
                    );
                  }).toList(),
                );
              },
            );
          },
        ),
      );
}

Future<bool?> confirmDelete(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus data?'),
        content: const Text('Data yang dihapus tidak dapat dikembalikan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );


Future<void> shareAnnouncementToWhatsApp(BuildContext context, Map<String, dynamic> data) async {
  final title = (data['judul'] ?? data['nama'] ?? 'Pengumuman Kampung').toString();
  final description = (data['deskripsi'] ?? data['keterangan'] ?? '').toString();
  final date = (data['tanggal'] ?? '').toString();
  final time = (data['waktu'] ?? '').toString();
  final location = (data['lokasi'] ?? data['alamat'] ?? '').toString();
  final category = (data['kategori'] ?? 'Pengumuman & Agenda').toString();
  final buffer = StringBuffer()
    ..writeln('📢 *$category*')
    ..writeln('*$title*');
  if (date.isNotEmpty) buffer.writeln('📅 Tanggal: $date');
  if (time.isNotEmpty) buffer.writeln('⏰ Waktu: $time');
  if (location.isNotEmpty) buffer.writeln('📍 Lokasi: $location');
  if (description.isNotEmpty) buffer.writeln('\n$description');
  buffer.writeln('\n_Pemerintah Kampung Kiarajangkung_');
  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(buffer.toString())}');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) showMessage(context, 'Tidak dapat membuka WhatsApp.');
  }
}

Future<void> openWhatsApp(BuildContext context, String rawNumber) async {
  var number = rawNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (number.startsWith('0')) number = '62${number.substring(1)}';
  if (number.startsWith('8')) number = '62$number';
  if (number.isEmpty) {
    showMessage(context, 'Nomor WhatsApp belum diisi.');
    return;
  }
  final uri = Uri.parse('https://wa.me/$number');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) showMessage(context, 'Tidak dapat membuka WhatsApp.');
  }
}

Future<void> openGoogleMaps(BuildContext context, String rawLocation) async {
  final value = rawLocation.trim();
  if (value.isEmpty) {
    showMessage(context, 'Link atau lokasi Google Maps belum diisi.');
    return;
  }
  final uri = Uri.tryParse(value);
  final target = (uri != null && (uri.scheme == 'https' || uri.scheme == 'http'))
      ? uri
      : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(value)}');
  if (!await launchUrl(target, mode: LaunchMode.externalApplication)) {
    if (context.mounted) showMessage(context, 'Tidak dapat membuka Google Maps.');
  }
}

void showRecordDetail(BuildContext context, String title, Map<String, dynamic> data) {
  final excluded = {'createdAt', 'updatedAt', 'createdBy', 'updatedBy'};
  final phone = (data['telepon'] ?? data['whatsapp'] ?? '').toString().trim();
  final maps = (data['lokasiMaps'] ?? data['googleMaps'] ?? '').toString().trim();
  final address = (data['alamat'] ?? data['lokasi'] ?? '').toString().trim();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Builder(builder: (context) {
              final photo = (data['fotoUrl'] ?? data['foto'] ?? data['imageUrl'] ?? '').toString().trim();
              if (photo.isEmpty) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(bottom: 16), child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(photo, width: double.infinity, height: 220, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => SizedBox(height: 120, child: _photoPlaceholder())),
              ));
            }),
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            if ((data['kategori'] ?? '').toString().toLowerCase().contains('pengumuman') || data.containsKey('prioritas') || data.containsKey('tanggal'))
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: () => shareAnnouncementToWhatsApp(sheetContext, data),
                  icon: const Icon(Icons.chat, color: Colors.green),
                  label: const Text('Bagikan ke WhatsApp Group'),
                )),
              ),
            const SizedBox(height: 14),
            if (phone.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.chat, color: Colors.green),
                title: const Text('Hubungi melalui WhatsApp'),
                subtitle: Text(phone),
                onTap: () => openWhatsApp(sheetContext, phone),
              ),
            if (maps.isNotEmpty || address.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined, color: Colors.red),
                title: const Text('Buka lokasi di Google Maps'),
                subtitle: Text(maps.isNotEmpty ? maps : address, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => openGoogleMaps(sheetContext, maps.isNotEmpty ? maps : address),
              ),
            const Divider(),
            ...data.entries.where((e) => !excluded.contains(e.key) &&
                !{'telepon', 'whatsapp', 'lokasiMaps', 'googleMaps', 'fotoUrl', 'foto', 'imageUrl'}.contains(e.key)).map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.key.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 3),
                    Text(e.value?.toString() ?? '-'),
                  ]),
                )),
          ]),
        ),
      ),
    ),
  );
}

String _maskNik(String nik) => nik.length == 16 ? '${nik.substring(0, 4)}********${nik.substring(12)}' : '';

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String authError(FirebaseAuthException e) {
  switch (e.code) {
    case 'email-already-in-use':
      return 'Email sudah terdaftar.';
    case 'invalid-email':
      return 'Format email tidak valid.';
    case 'weak-password':
      return 'Password terlalu lemah. Gunakan minimal 6 karakter.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'NIK/email atau password salah. Pastikan akun sudah dibuat oleh Admin.';
    case 'network-request-failed':
      return 'Koneksi internet bermasalah.';
    case 'too-many-requests':
      return 'Terlalu banyak percobaan. Coba lagi nanti.';
    default:
      return e.message ?? 'Autentikasi gagal (${e.code}).';
  }
}
