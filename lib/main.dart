import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FontFeature;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

String normalizeNik(String value) => value.replaceAll(RegExp(r'\D'), '');

String _wilayahSlug(String value) => value.trim().toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String _wilayahId(String level, String parentId, String label, {String? oldLabel, String? oldId}) {
  if (label.trim().isEmpty) return '';
  if ((oldId ?? '').trim().isNotEmpty && (oldLabel ?? '').trim().toLowerCase() == label.trim().toLowerCase()) return oldId!;
  final parent = parentId.trim().isEmpty ? '' : '${parentId.trim()}-';
  return '${level.toUpperCase()}-$parent${_wilayahSlug(label)}';
}

bool isArchivedResident(Map<String, dynamic> data) {
  final status = (data['statusWarga'] ?? 'Aktif').toString().trim().toLowerCase();
  return status == 'arsip' || status == 'nonaktif' || status == 'pindah' || status == 'meninggal';
}

Future<List<Map<String, dynamic>>> loadActiveResidents() async {
  final snapshot = await Db.module('sensus').get();
  final residents = snapshot.docs
      .map((doc) => <String, dynamic>{...doc.data(), 'wargaId': doc.id})
      .where((data) => !isArchivedResident(data) &&
          (data['nama'] ?? '').toString().trim().isNotEmpty)
      .toList();
  residents.sort((a, b) => (a['nama'] ?? '').toString().toLowerCase()
      .compareTo((b['nama'] ?? '').toString().toLowerCase()));
  return residents;
}

Map<String, dynamic>? resolveResident(
  List<Map<String, dynamic>> residents, String? wargaId, String? legacyName) {
  if (wargaId != null && wargaId.trim().isNotEmpty) {
    for (final resident in residents) {
      if ((resident['wargaId'] ?? '').toString() == wargaId) return resident;
    }
  }
  final name = (legacyName ?? '').trim().toLowerCase();
  if (name.isEmpty) return null;
  final matches = residents.where((r) =>
      (r['nama'] ?? '').toString().trim().toLowerCase() == name).toList();
  return matches.length == 1 ? matches.first : null;
}

Future<Map<String, dynamic>?> showResidentPicker(
  BuildContext context,
  List<Map<String, dynamic>> residents, {
  String? selectedWargaId,
  String title = 'Pilih warga dari Sensus',
}) async {
  final search = TextEditingController();
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setStateSheet) {
      final query = search.text.trim().toLowerCase();
      final filtered = residents.where((r) {
        final name = (r['nama'] ?? '').toString().toLowerCase();
        final nik = (r['nik'] ?? '').toString();
        final rt = (r['rt'] ?? '').toString();
        final rw = (r['rw'] ?? '').toString();
        return query.isEmpty || name.contains(query) || nik.contains(query) ||
            rt.toLowerCase().contains(query) || rw.toLowerCase().contains(query);
      }).toList();
      return SafeArea(child: SizedBox(
        height: MediaQuery.of(ctx).size.height * .78,
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Column(
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: search, autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Cari nama, NIK, RT atau RW'),
              onChanged: (_) => setStateSheet(() {})),
            const SizedBox(height: 8),
            Expanded(child: filtered.isEmpty
              ? const Center(child: Text('Warga aktif tidak ditemukan.'))
              : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
                  final r = filtered[i];
                  final id = (r['wargaId'] ?? '').toString();
                  final selected = id == selectedWargaId;
                  return ListTile(
                    leading: CircleAvatar(child: Text((r['nama'] ?? '?').toString().isNotEmpty ? (r['nama'] ?? '?').toString().substring(0, 1).toUpperCase() : '?')),
                    title: Text((r['nama'] ?? 'Tanpa nama').toString()),
                    subtitle: Text('NIK ${r['nik'] ?? '-'} • RT ${r['rt'] ?? '-'} / RW ${r['rw'] ?? '-'}'),
                    trailing: selected ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, r),
                  );
                })),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal'))),
          ],
        )),
      ));
    }),
  );
  search.dispose();
  return result;
}

Future<List<Map<String, dynamic>>?> showResidentMultiPicker(
  BuildContext context,
  List<Map<String, dynamic>> residents, {
  List<String> selectedWargaIds = const [],
  String title = 'Pilih beberapa warga',
}) async {
  final search = TextEditingController();
  final selected = <String>{...selectedWargaIds};
  final result = await showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setStateSheet) {
      final query = search.text.trim().toLowerCase();
      final filtered = residents.where((r) {
        final name = (r['nama'] ?? '').toString().toLowerCase();
        final nik = (r['nik'] ?? '').toString();
        return query.isEmpty || name.contains(query) || nik.contains(query);
      }).toList();
      return SafeArea(child: SizedBox(
        height: MediaQuery.of(ctx).size.height * .82,
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Column(children: [
          Text(title, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Cari nama atau NIK'), onChanged: (_) => setStateSheet(() {})),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: Text('Dipilih: ${selected.length} warga')),
          Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
            final r = filtered[i];
            final id = (r['wargaId'] ?? '').toString();
            return CheckboxListTile(
              value: selected.contains(id),
              title: Text((r['nama'] ?? 'Tanpa nama').toString()),
              subtitle: Text('RT ${r['rt'] ?? '-'} / RW ${r['rw'] ?? '-'}'),
              onChanged: (v) => setStateSheet(() { if (v == true) { selected.add(id); } else { selected.remove(id); } }),
            );
          })),
          Row(children: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')), const Spacer(), FilledButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, residents.where((r) => selected.contains((r['wargaId'] ?? '').toString())).toList()), child: const Text('Gunakan pilihan'))]),
        ])),
      ));
    }),
  );
  search.dispose();
  return result;
}

bool isResidentReferenceField(String moduleKey, String fieldKey) {
  if (moduleKey == 'umkm') return fieldKey == 'pemilik';
  if (moduleKey == 'perangkat') return false; // Nama perangkat dipilih pada judul formulir.
  if (moduleKey == 'sarana') return fieldKey == 'pengelola';
  if (moduleKey == 'kesenian') return fieldKey == 'ketua';
  if (moduleKey == 'kebersihan') return fieldKey == 'petugas';
  if (moduleKey == 'fasilitas_kesehatan') return fieldKey == 'penanggungJawab';
  if (moduleKey == 'organisasi') return ['ketua', 'wakil', 'sekretaris', 'bendahara'].contains(fieldKey);
  return false;
}

Future<void> writeWargaAudit({
  required String wargaId,
  required String modul,
  required String aksi,
  required String peran,
  required String namaWarga,
  String? recordId,
}) async {
  if (wargaId.trim().isEmpty) return;
  await Db.module('riwayat_perubahan').add({
    'wargaId': wargaId,
    'modul': modul,
    'recordId': recordId ?? '',
    'aksi': aksi,
    'peran': peran,
    'namaWarga': namaWarga,
    'uid': Db.auth.currentUser?.uid ?? '',
    'waktu': FieldValue.serverTimestamp(),
  });
}

Future<void> syncAccountProfileFromSensus(String wargaId, Map<String, dynamic> data, {bool selfEdit = false}) async {
  final uid = (data['accountUid'] ?? '').toString();
  if (uid.isEmpty) return;
  final updates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
  if (data.containsKey('telepon')) updates['telepon'] = data['telepon'];
  if (data.containsKey('alamat')) updates['alamat'] = data['alamat'];
  if (!selfEdit) {
    if (data.containsKey('nama')) updates['nama'] = data['nama'];
    if (data.containsKey('rt')) updates['rt'] = data['rt'];
    if (data.containsKey('rw')) updates['rw'] = data['rw'];
    if (data.containsKey('kawil')) updates['kawil'] = data['kawil'];
    if (data.containsKey('kawilId')) updates['kawilId'] = data['kawilId'];
    if (data.containsKey('rwId')) updates['rwId'] = data['rwId'];
    if (data.containsKey('rtId')) updates['rtId'] = data['rtId'];
  }
  await Db.user(uid).update(updates);
}

class PushService {
  static final Set<String> _registered = <String>{};
  static Future<void> register(User user) async {
    if (_registered.contains(user.uid)) return;
    _registered.add(user.uid);
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await Db.user(user.uid).set({'fcmTokens': FieldValue.arrayUnion([token]), 'pushEnabled': true, 'pushUpdatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
      messaging.onTokenRefresh.listen((newToken) async {
        await Db.user(user.uid).set({'fcmTokens': FieldValue.arrayUnion([newToken]), 'pushEnabled': true, 'pushUpdatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      });
    } catch (_) {
      _registered.remove(user.uid);
    }
  }
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
    String alamat = '',
    String rt = '',
    String rw = '',
    String kawil = '',
    String kawilId = '',
    String rwId = '',
    String rtId = '',
    String wargaId = '',
    List<String> roles = const ['warga'],
  }) async {
    return _request({
      'action': 'provisionResident',
      'nik': nik,
      'nama': nama,
      'tanggalLahir': tanggalLahir,
      'telepon': telepon,
      'alamat': alamat,
      'rt': rt,
      'rw': rw,
      'kawil': kawil,
      'kawilId': kawilId,
      'rwId': rwId,
      'rtId': rtId,
      'wargaId': wargaId,
      'roles': roles,
    });
  }

  static Future<Map<String, dynamic>> restoreOwnerNikAccount() async {
    return _request({'action': 'restoreOwnerNikAccount'});
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
        PushService.register(snapshot.data!);
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
  ModuleInfo('informasi_diri', 'Informasi Diri', 'Data pribadi sesuai Sensus Penduduk', Icons.person_pin_outlined),
  ModuleInfo('sensus', 'Sensus Penduduk', 'Data keluarga dan demografi', Icons.groups_outlined, privateData: true),
  ModuleInfo('arsip_warga', 'Arsip Warga', 'Warga pindah atau meninggal; riwayat tetap tersimpan', Icons.archive_outlined, privateData: true),
  ModuleInfo('migrasi_satu_data', 'Migrasi Satu Data Warga', 'Hubungkan data modul lama dengan Data Sensus', Icons.hub_outlined, privateData: true),
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
  DateTime clockNow = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() { super.initState(); _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => clockNow = DateTime.now()); }); }
  @override
  void dispose() { _clockTimer?.cancel(); super.dispose(); }
  bool get isAdmin {
    final roles = (widget.profile['roles'] is List)
        ? (widget.profile['roles'] as List).map((e) => e.toString().toLowerCase()).toSet()
        : <String>{};
    return widget.role.toLowerCase() == 'admin' || widget.role.toLowerCase() == 'owner' ||
        roles.contains('admin') || roles.contains('owner');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      dashboard(),
      ModulesPage(isAdmin: isAdmin),
      ProfilePage(user: widget.user, profile: widget.profile, isAdmin: isAdmin),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kampung Kiarajangkung'),
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

  void openModule(String key) {
    final module = modules.firstWhere((m) => m.keyName == key);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ModulePage(module: module, isAdmin: isAdmin),
    ));
  }

  void _showPrayerInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SingleChildScrollView(child: DashboardPrayerSchedule()),
        ),
      ),
    );
  }

  Widget dashboard() {
    final name = (widget.profile['nama'] ?? 'Warga').toString();
    final roles = (widget.profile['roles'] is List)
        ? (widget.profile['roles'] as List).map((e) => e.toString().toLowerCase()).toSet()
        : <String>{(widget.profile['role'] ?? 'warga').toString().toLowerCase()};
    roles.add('warga');
    const roleLabels = <String, String>{
      'perangkat_kawil':'Perangkat Kawil','ketua_rw':'Ketua RW','ketua_rt':'Ketua RT',
      'petugas_sampah':'Petugas Sampah','pemilik_umkm':'Pemilik UMKM',
      'pemilik_fasilitas':'Pemilik Fasilitas','ketua_organisasi':'Ketua Organisasi',
      'ketua_dkm':'Ketua DKM','admin':'Admin','owner':'Owner'
    };
    final jabatan = roles.where((r) => roleLabels.containsKey(r) && r != 'pemilik_umkm')
        .map((r) => roleLabels[r]!).toList();
    final now = clockNow.toUtc().add(const Duration(hours: 7));
    final dayNames = const ['Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'];
    final monthNames = const ['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'];
    final dateText = '${now.day} ${monthNames[now.month-1]} ${now.year}';
    final timeText = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF105B3E), Color(0xFF239B70)]),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: const Color(0xFF167C55).withOpacity(.18), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('👋 Wilujeng Sumping,', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                const Text('Selamat datang di kampung kami', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(dayNames[now.weekday-1], style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(dateText, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(timeText, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
                const Text('WIB', style: TextStyle(color: Colors.white70, fontSize: 10)),
              ]),
            ]),
            if (jabatan.isNotEmpty || roles.contains('pemilik_umkm')) ...[
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Colors.white30, height: 1)),
              if (jabatan.isNotEmpty) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.badge_outlined, color: Colors.white, size: 18), const SizedBox(width: 9),
                  Expanded(child: Text(jabatan.join(' • '), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12))),
                ]),
              ],
              if (roles.contains('pemilik_umkm')) ...[
                if (jabatan.isNotEmpty) const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
                  stream: Db.module('umkm').where('pemilikUid', isEqualTo: widget.user.uid).snapshots(),
                  builder: (context, snap) {
                    final usaha = snap.data?.docs.map((d) => (d.data()['nama'] ?? d.data()['nama_usaha'] ?? d.data()['judul'] ?? 'UMKM warga').toString()).toList() ?? <String>[];
                    final label = usaha.isNotEmpty ? usaha.join(', ') : (widget.profile['namaUsaha'] ?? 'Pemilik UMKM').toString();
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.storefront_outlined, color: Colors.white, size: 18), const SizedBox(width: 9),
                      Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12))),
                    ]);
                  },
                ),
              ],
            ],
          ]),
        ),
        const SizedBox(height: 12),
        const DashboardAnnouncements(),
        const SizedBox(height: 18),
        DashboardPopulationStats(isAdmin: isAdmin),
        const SizedBox(height: 16),
        const DashboardGallery(),
        const SizedBox(height: 16),
        _DashboardSectionTitle(title: 'Layanan Cepat', action: 'Semua layanan', onAction: () => setState(() => tab = 1)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: .98,
          children: [
            _DashboardService(icon: Icons.emergency_rounded, title: 'Kontak Darurat', color: const Color(0xFFD94B45), onTap: () => openModule('kontak_darurat')),
            _DashboardService(icon: Icons.health_and_safety_rounded, title: 'Fasilitas Kesehatan', color: const Color(0xFF26966C), onTap: () => openModule('fasilitas_kesehatan')),
            _DashboardService(icon: Icons.account_balance_rounded, title: 'Profil Kampung', color: const Color(0xFF3979B9), onTap: () => openModule('profil_kampung')),
            _DashboardService(icon: Icons.mosque_rounded, title: 'Jadwal Sholat', color: const Color(0xFF9A7A32), onTap: () => _showPrayerInfo(context)),
            _DashboardService(icon: Icons.shield_moon_rounded, title: 'Jadwal Ronda', color: const Color(0xFF586B9B), onTap: () => openModule('ronda')),
            _DashboardService(icon: Icons.event_note_rounded, title: 'Agenda Desa', color: const Color(0xFFB36A38), onTap: () => openModule('pengumuman')),
          ],
        ),
        const SizedBox(height: 20),
        const DashboardPrayerSchedule(),
        const SizedBox(height: 18),
        const DashboardEmergencyPreview(),
        const SizedBox(height: 18),
        const DashboardHealthPreview(),
        const SizedBox(height: 18),
        DashboardRondaPreview(profile: widget.profile),
        const SizedBox(height: 20),
        _DashboardSectionTitle(title: 'Jelajahi Kampung', action: 'Lihat semua', onAction: () => setState(() => tab = 1)),
        const SizedBox(height: 8),
        ...modules.where((m) => !['sensus'].contains(m.keyName)).take(9).map((m) => Card(
          margin: const EdgeInsets.only(bottom: 7),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(m.icon)),
            title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(m.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right), onTap: () => openModule(m.keyName),
          ),
        )),
      ],
    );
  }

}


class _DashboardSectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _DashboardSectionTitle({required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
      if (action != null)
        TextButton(onPressed: onAction, child: Text(action!)),
    ],
  );
}

class _DashboardService extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  const _DashboardService({required this.icon, required this.title,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE8EFEA)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 43, height: 43,
            decoration: BoxDecoration(color: color.withOpacity(.11), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24)),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    ),
  );
}

Future<Map<String, String>> _fetchPrayerTimes() async {
  final now = DateTime.now();
  final date = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
  final uri = Uri.parse('https://api.aladhan.com/v1/timings/$date?latitude=-7.2007&longitude=108.1290&method=20&school=0');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode != 200) throw Exception('Server jadwal sholat (${response.statusCode})');
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final timings = (json['data'] as Map<String, dynamic>)['timings'] as Map<String, dynamic>;
    String clean(String key) => (timings[key] ?? '--:--').toString().split(' ').first;
    return {'Subuh': clean('Fajr'), 'Dzuhur': clean('Dhuhr'), 'Asar': clean('Asr'), 'Maghrib': clean('Maghrib'), 'Isya': clean('Isha')};
  } finally { client.close(force: true); }
}

class DashboardPrayerSchedule extends StatefulWidget {
  const DashboardPrayerSchedule({super.key});
  @override
  State<DashboardPrayerSchedule> createState() => _DashboardPrayerScheduleState();
}

class _DashboardPrayerScheduleState extends State<DashboardPrayerSchedule> {
  late Future<Map<String, String>> _times;
  @override
  void initState() { super.initState(); _times = _fetchPrayerTimes(); }
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFFF0F6F2), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFDCEAE1))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: const [Icon(Icons.mosque_rounded, color: Color(0xFF167C55)), SizedBox(width: 8), Expanded(child: Text('Jadwal Sholat Kiarajangkung', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)))]),
      const SizedBox(height: 4),
      Text('Koordinat -7.2007, 108.1290 • ${DateTime.now().day.toString().padLeft(2,'0')}-${DateTime.now().month.toString().padLeft(2,'0')}-${DateTime.now().year}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
      const SizedBox(height: 12),
      FutureBuilder<Map<String, String>>(future: _times, builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
        if (snap.hasError) return Row(children: [const Expanded(child: Text('Jadwal otomatis gagal dimuat. Periksa koneksi internet.', style: TextStyle(fontSize: 12))), IconButton(onPressed: () => setState(() => _times = _fetchPrayerTimes()), icon: const Icon(Icons.refresh))]);
        final times = snap.data!;
        return Row(children: times.entries.map((e) => Expanded(child: Container(margin: EdgeInsets.only(right: e.key == 'Isya' ? 0 : 5), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 1), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Column(children: [Text(e.key, style: const TextStyle(fontSize: 9, color: Colors.black54)), const SizedBox(height: 4), Text(e.value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))])))).toList());
      }),
      const SizedBox(height: 6),
      const Text('Sumber perhitungan: AlAdhan • metode Singapura (20°/18°), mazhab Syafi’i. Waktu dapat berbeda beberapa menit dari ketetapan DKM setempat.', style: TextStyle(fontSize: 10, color: Colors.black54)),
    ]),
  );
}


String _cleanPhone(String value) => value.replaceAll(RegExp(r'[^0-9+]'), '');

String _whatsappNumber(String value) {
  var number = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (number.startsWith('0')) number = '62${number.substring(1)}';
  if (number.startsWith('8')) number = '62$number';
  return number;
}

Future<void> _openPhone(BuildContext context, String phone) async {
  if (phone.trim().isEmpty) return;
  final number = _cleanPhone(phone);
  if (number.isEmpty) {
    showMessage(context, 'Nomor telepon belum valid.');
    return;
  }
  final uri = Uri(scheme: 'tel', path: number);
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    showMessage(context, 'Tidak dapat membuka aplikasi telepon.');
  }
}

Future<void> _openWhatsApp(BuildContext context, String phone) async {
  // Samakan dengan handler WhatsApp pada modul: jangan memakai canLaunchUrl,
  // karena Android dapat menolak pemeriksaan tersebut walaupun URL bisa dibuka.
  final number = _whatsappNumber(phone);
  if (number.isEmpty) {
    if (context.mounted) showMessage(context, 'Nomor WhatsApp belum diisi.');
    return;
  }
  final uri = Uri.parse('https://wa.me/$number');
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showMessage(context, 'Tidak dapat membuka WhatsApp. Pastikan WhatsApp atau browser tersedia.');
    }
  } catch (e) {
    if (context.mounted) {
      showMessage(context, 'Gagal membuka WhatsApp. Periksa aplikasi WhatsApp atau browser.');
    }
  }
}

Future<void> _openHealthMap(BuildContext context, Map<String, dynamic> data) async {
  final link = (data['lokasiMaps'] ?? data['googleMaps'] ?? '').toString().trim();
  final address = (data['alamat'] ?? '').toString().trim();
  final query = address.isNotEmpty ? address : (data['judul'] ?? data['nama'] ?? '').toString();
  final uri = Uri.tryParse(link.isNotEmpty
      ? link
      : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
  if (uri != null && await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    showMessage(context, 'Lokasi belum tersedia atau Google Maps tidak dapat dibuka.');
  }
}

class DashboardEmergencyPreview extends StatelessWidget {
  const DashboardEmergencyPreview({super.key});
  Future<void> _showDetail(BuildContext context, Map<String, dynamic> data) async {
    final title = (data['judul'] ?? data['nama'] ?? data['kategori'] ?? 'Layanan darurat').toString();
    final phone = (data['telepon'] ?? '').toString().trim();
    final address = (data['alamat'] ?? '').toString().trim();
    final description = (data['catatan'] ?? data['keterangan'] ?? data['deskripsi'] ?? '').toString().trim();
    final maps = (data['lokasiMaps'] ?? data['googleMaps'] ?? '').toString().trim();
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ((data['kategori'] ?? '').toString().trim().isNotEmpty) _DetailLine(label: 'Jenis layanan', value: data['kategori'].toString()),
        if (phone.isNotEmpty) _DetailLine(label: 'Nomor telepon', value: phone),
        if (address.isNotEmpty) _DetailLine(label: 'Alamat', value: address),
        if (description.isNotEmpty) _DetailLine(label: 'Keterangan', value: description),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup')),
        if (phone.isNotEmpty) TextButton.icon(onPressed: () => _openPhone(context, phone), icon: const Icon(Icons.call), label: const Text('Telepon')),
        if (phone.isNotEmpty) TextButton.icon(onPressed: () => _openWhatsApp(context, phone), icon: const Icon(Icons.chat), label: const Text('WhatsApp')),
        if (address.isNotEmpty || maps.isNotEmpty) FilledButton.icon(onPressed: () => _openHealthMap(context, data), icon: const Icon(Icons.location_on_outlined), label: const Text('Buka Lokasi')),
      ],
    ));
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: Db.module('kontak_darurat').snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
      final docs = snapshot.data!.docs;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _DashboardSectionTitle(title: 'Kontak Darurat'),
        SizedBox(height: 154, child: ListView.separated(
          scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
          itemCount: docs.length, separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final title = (d['judul'] ?? d['nama'] ?? d['kategori'] ?? 'Layanan darurat').toString();
            final phone = (d['telepon'] ?? '').toString().trim();
            return SizedBox(width: 248, child: Card(child: InkWell(
              borderRadius: BorderRadius.circular(18), onTap: () => _showDetail(context, d),
              child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const CircleAvatar(backgroundColor: Color(0xFFFFE8E6), child: Icon(Icons.emergency, color: Color(0xFFD94B45))), const SizedBox(width: 9), Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)))]),
                const Spacer(), Text(phone.isEmpty ? 'Nomor belum tersedia' : phone, style: const TextStyle(fontSize: 12)), const SizedBox(height: 4),
                Row(children: [
                  if (phone.isNotEmpty) IconButton(visualDensity: VisualDensity.compact, tooltip: 'Telepon', onPressed: () => _openPhone(context, phone), icon: const Icon(Icons.call, color: Color(0xFF21865D))),
                  if (phone.isNotEmpty) IconButton(visualDensity: VisualDensity.compact, tooltip: 'WhatsApp', onPressed: () => _openWhatsApp(context, phone), icon: const Icon(Icons.chat, color: Color(0xFF21865D))),
                  const Spacer(), const Text('Detail', style: TextStyle(fontSize: 11, color: Color(0xFF21865D))),
                ]),
              ])),
            )));
          },
        )),
      ]);
    },
  );
}

class DashboardHealthPreview extends StatelessWidget {
  const DashboardHealthPreview({super.key});
  Future<void> _showDetail(BuildContext context, Map<String, dynamic> data) async {
    final title = (data['judul'] ?? data['nama'] ?? data['jenisFasilitas'] ?? 'Fasilitas kesehatan').toString();
    final phone = (data['telepon'] ?? '').toString().trim();
    final address = (data['alamat'] ?? '').toString().trim();
    final hours = (data['jamBuka'] ?? '').toString().trim();
    final services = (data['layanan'] ?? '').toString().trim();
    final description = (data['catatan'] ?? data['deskripsi'] ?? '').toString().trim();
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ((data['jenisFasilitas'] ?? '').toString().trim().isNotEmpty) _DetailLine(label: 'Jenis fasilitas', value: data['jenisFasilitas'].toString()),
        if (address.isNotEmpty) _DetailLine(label: 'Alamat', value: address),
        if (phone.isNotEmpty) _DetailLine(label: 'Telepon / WhatsApp', value: phone),
        if (hours.isNotEmpty) _DetailLine(label: 'Jam pelayanan', value: hours),
        if (services.isNotEmpty) _DetailLine(label: 'Jenis layanan', value: services),
        if (description.isNotEmpty) _DetailLine(label: 'Keterangan', value: description),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup')),
        if (phone.isNotEmpty) TextButton.icon(onPressed: () => _openPhone(context, phone), icon: const Icon(Icons.call), label: const Text('Telepon')),
        if (phone.isNotEmpty) TextButton.icon(onPressed: () => _openWhatsApp(context, phone), icon: const Icon(Icons.chat), label: const Text('WhatsApp')),
        FilledButton.icon(onPressed: () => _openHealthMap(context, data), icon: const Icon(Icons.map_outlined), label: const Text('Google Maps')),
      ],
    ));
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: Db.module('fasilitas_kesehatan').snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
      final docs = snapshot.data!.docs;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _DashboardSectionTitle(title: 'Fasilitas Kesehatan'),
        SizedBox(height: 166, child: ListView.separated(
          scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
          itemCount: docs.length, separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final title = (d['judul'] ?? d['nama'] ?? d['jenisFasilitas'] ?? 'Fasilitas kesehatan').toString();
            final address = (d['alamat'] ?? '').toString();
            final phone = (d['telepon'] ?? '').toString().trim();
            return SizedBox(width: 258, child: Card(child: InkWell(
              borderRadius: BorderRadius.circular(18), onTap: () => _showDetail(context, d),
              child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const CircleAvatar(backgroundColor: Color(0xFFE4F3EB), child: Icon(Icons.health_and_safety, color: Color(0xFF21865D))), const SizedBox(width: 9), Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)))]),
                const SizedBox(height: 8), Expanded(child: Text(address.isEmpty ? 'Alamat belum tersedia' : address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
                Row(children: [
                  if (phone.isNotEmpty) IconButton(visualDensity: VisualDensity.compact, tooltip: 'Telepon', onPressed: () => _openPhone(context, phone), icon: const Icon(Icons.call, color: Color(0xFF21865D))),
                  if (phone.isNotEmpty) IconButton(visualDensity: VisualDensity.compact, tooltip: 'WhatsApp', onPressed: () => _openWhatsApp(context, phone), icon: const Icon(Icons.chat, color: Color(0xFF21865D))),
                  const Spacer(), const Text('Detail', style: TextStyle(fontSize: 11, color: Color(0xFF21865D))),
                ]),
              ])),
            )));
          },
        )),
      ]);
    },
  );
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 2),
      SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w500)),
    ]),
  );
}

class RondaSchedulePage extends StatefulWidget {
  final bool isAdmin;
  const RondaSchedulePage({super.key, required this.isAdmin});
  @override
  State<RondaSchedulePage> createState() => _RondaSchedulePageState();
}

class _RondaSchedulePageState extends State<RondaSchedulePage> {
  static const days = ['Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'];
  DateTime weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
  int selectedDay = DateTime.now().weekday - 1;
  String dateKeyFor(int index) {
    final d = weekStart.add(Duration(days:index));
    return '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }
  String dateLabel(DateTime d) => '${d.day.toString().padLeft(2,'0')}-${d.month.toString().padLeft(2,'0')}-${d.year}';

  @override
  Widget build(BuildContext context) {
    final uid = Db.auth.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Jadwal Ronda'), actions: [
        IconButton(tooltip:'Laporan ronda', icon: const Icon(Icons.summarize_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RondaReportsPage(isAdmin: widget.isAdmin)))),
      ]),
      floatingActionButton: widget.isAdmin ? FloatingActionButton.extended(
        onPressed: () => showRondaScheduleForm(context), icon: const Icon(Icons.edit_calendar), label: const Text('Atur jadwal')) : null,
      body: StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
        stream: uid == null ? null : Db.user(uid).snapshots(),
        builder: (context, profileSnap) {
          final profile = profileSnap.data?.data() ?? <String,dynamic>{};
          final wargaId = (profile['wargaId'] ?? '').toString();
          return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
            stream: Db.module('ronda').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Gagal memuat jadwal: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final all = snap.data!.docs;
              return ListView(padding: const EdgeInsets.all(16), children: [
                Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFFEAF4ED), borderRadius: BorderRadius.circular(18)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Jadwal Piket Keamanan Lingkungan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  SizedBox(height: 5), Text('Warga dapat melihat jadwal seluruh hari. Absensi dan status berhalangan hanya dapat diisi untuk diri sendiri.'),
                ])),
                const SizedBox(height: 12),
                Row(children: [
                  IconButton(onPressed: () => setState(() { weekStart = weekStart.subtract(const Duration(days:7)); }), icon: const Icon(Icons.chevron_left)),
                  Expanded(child: Center(child: Text('${dateLabel(weekStart)} – ${dateLabel(weekStart.add(const Duration(days:6)))}', style: const TextStyle(fontWeight: FontWeight.bold)))),
                  IconButton(onPressed: () => setState(() { weekStart = weekStart.add(const Duration(days:7)); }), icon: const Icon(Icons.chevron_right)),
                ]),
                GridView.count(shrinkWrap:true, physics:const NeverScrollableScrollPhysics(), crossAxisCount:4, childAspectRatio:1.45, mainAxisSpacing:8, crossAxisSpacing:8,
                  children: List.generate(7, (i) {
                    final selected = selectedDay == i;
                    return InkWell(onTap:() => setState(() => selectedDay=i), borderRadius:BorderRadius.circular(12), child: Container(
                      alignment:Alignment.center, decoration:BoxDecoration(color:selected?const Color(0xFF167C55):Colors.white, borderRadius:BorderRadius.circular(12), border:Border.all(color:selected?const Color(0xFF167C55):const Color(0xFFDCE5DE))),
                      child: Column(mainAxisAlignment:MainAxisAlignment.center, children:[Text(days[i], style:TextStyle(fontWeight:FontWeight.w700,color:selected?Colors.white:Colors.black87)), Text(dateLabel(weekStart.add(Duration(days:i))).substring(0,5), style:TextStyle(fontSize:10,color:selected?Colors.white70:Colors.black54))]),
                    ));
                  }),
                ),
                const SizedBox(height:14),
                Row(children:[Expanded(child:Text('${days[selectedDay]}, ${dateLabel(weekStart.add(Duration(days:selectedDay)))}',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold))), IconButton(tooltip:'Kirim daftar hari ini ke WhatsApp', onPressed:() => shareRondaDay(context, all.where((d)=>(d.data()['hari']??'').toString().toLowerCase()==days[selectedDay].toLowerCase()).toList(), days[selectedDay], dateLabel(weekStart.add(Duration(days:selectedDay))), dateKeyFor(selectedDay), profile), icon:const Icon(Icons.share,color:Colors.green))]),
                ...all.where((d)=>(d.data()['hari']??'').toString().toLowerCase()==days[selectedDay].toLowerCase()).map((doc) => _RondaDayCard(
                  doc:doc, isAdmin:widget.isAdmin, uid:uid??'', wargaId:wargaId, dateKey:dateKeyFor(selectedDay), day:days[selectedDay],
                  onEdit:() => showRondaScheduleForm(context, docId:doc.id, initial:doc.data()),
                  onDelete:() async { final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Hapus jadwal?'),content:const Text('Jadwal ronda ini akan dihapus.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Hapus'))])); if(ok==true){await Db.module('ronda').doc(doc.id).delete();} },
                )),
                if (all.where((d)=>(d.data()['hari']??'').toString().toLowerCase()==days[selectedDay].toLowerCase()).isEmpty)
                  const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Belum ada petugas yang dijadwalkan pada hari ini.'))),
                const SizedBox(height:12),
                OutlinedButton.icon(onPressed:() => Navigator.push(context,MaterialPageRoute(builder:(_)=>RondaReportsPage(isAdmin:widget.isAdmin))), icon:const Icon(Icons.summarize_outlined), label:const Text('Lihat Laporan Ronda')),
              ]);
            },
          );
        },
      ),
    );
  }
}

class _RondaDayCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String,dynamic>> doc;
  final bool isAdmin;
  final String uid,wargaId,dateKey,day;
  final VoidCallback onEdit,onDelete;
  const _RondaDayCard({required this.doc,required this.isAdmin,required this.uid,required this.wargaId,required this.dateKey,required this.day,required this.onEdit,required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final d=doc.data();
    final raw=d['petugas'];
    final members=raw is List ? raw.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList() : <Map<String,dynamic>>[];
    final names=members.isNotEmpty ? members : (d['anggota']??'').toString().split(RegExp(r'[,;\n]')).where((x)=>x.trim().isNotEmpty).map((n)=>{'nama':n.trim()}).toList();
    final my=names.cast<Map<String,dynamic>?>().firstWhere((m)=>(m?['uid']??'').toString()==uid || (wargaId.isNotEmpty && (m?['wargaId']??'').toString()==wargaId),orElse:()=>null);
    return Card(margin:const EdgeInsets.only(bottom:12), child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Text('RT ${d['rt']??'-'} / RW ${d['rw']??'-'}',style:const TextStyle(fontWeight:FontWeight.bold))), if(isAdmin) PopupMenuButton<String>(onSelected:(v){if(v=='edit')onEdit();if(v=='delete')onDelete();},itemBuilder:(_)=>const [PopupMenuItem(value:'edit',child:Text('Edit jadwal')),PopupMenuItem(value:'delete',child:Text('Hapus jadwal'))])]),
      Text('Waktu ronda: ${d['jamMulai']??'21.00'} – ${d['jamSelesai']??'04.00'}'),
      const Divider(),
      const Text('Daftar petugas',style:TextStyle(fontWeight:FontWeight.bold)),
      ...names.map((m){final n=(m['nama']??'Petugas').toString(); final memberUid=(m['uid']??'').toString(); final keyUid=memberUid.isNotEmpty?memberUid:(m['wargaId']??n).toString(); final statusId='${dateKey}_${keyUid}_${doc.id}';
        return _RondaMemberLine(name:n, uid:uid, isMe:my!=null && ((my['uid']??'').toString()==memberUid || (my['wargaId']??'').toString()==(m['wargaId']??'')), statusId:statusId, dateKey:dateKey, scheduleId:doc.id, day:day, canSelf:my!=null && (memberUid.isEmpty || memberUid==uid));
      }),
      if(my!=null) _RondaSelfActions(uid:uid,wargaId:wargaId,name:(my['nama']??'Warga').toString(),dateKey:dateKey,day:day,scheduleId:doc.id),
      if(my==null && !isAdmin) const Padding(padding:EdgeInsets.only(top:6),child:Text('Anda tidak bertugas pada regu ini.',style:TextStyle(color:Colors.black54,fontSize:12))),
    ])));
  }
}

class _RondaMemberLine extends StatelessWidget {
  final String name,uid,statusId,dateKey,scheduleId,day; final bool isMe,canSelf;
  const _RondaMemberLine({required this.name,required this.uid,required this.isMe,required this.statusId,required this.dateKey,required this.scheduleId,required this.day,required this.canSelf});
  @override
  Widget build(BuildContext context)=>StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
    stream:Db.module('ronda_absensi').doc(statusId).snapshots(),
    builder:(context,snap){final a=snap.data?.data()??{}; final hadir=a['waktuHadir']!=null || a['status']=='Hadir'; final pulang=a['waktuPulang']!=null; final status=(a['statusKesediaan']??'Belum mengisi').toString();
      return Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[Icon(hadir?Icons.check_circle:pulang?Icons.check_circle_outline:Icons.circle_outlined,color:hadir?Colors.green:Colors.grey,size:18),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(name,style:const TextStyle(fontWeight:FontWeight.w500)),Text('Kesediaan: $status • ${hadir?'Hadir ${_timeText(a['waktuHadir'])}': 'Belum hadir'}${pulang?' • Pulang ${_timeText(a['waktuPulang'])}':''}',style:const TextStyle(fontSize:10,color:Colors.black54))])),if(a['alasan']!=null && a['alasan'].toString().isNotEmpty) IconButton(tooltip:'Alasan: ${a['alasan']}',onPressed:()=>showMessage(context,'Alasan $name: ${a['alasan']}'),icon:const Icon(Icons.info_outline,size:18))]));
    });
}

class _RondaSelfActions extends StatelessWidget {
  final String uid,wargaId,name,dateKey,day,scheduleId;
  const _RondaSelfActions({required this.uid,required this.wargaId,required this.name,required this.dateKey,required this.day,required this.scheduleId});
  String get docKey=>'${dateKey}_${uid}_$scheduleId';
  Future<void> setAvailability(BuildContext context,String status) async {
    String reason='';
    if(status=='Berhalangan'){
      final c=TextEditingController();
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Alasan berhalangan'),content:TextField(controller:c,maxLines:3,decoration:const InputDecoration(hintText:'Contoh: sakit, bekerja, keperluan keluarga')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim().isNotEmpty),child:const Text('Simpan'))]));
      if(ok!=true){c.dispose();return;} reason=c.text.trim();c.dispose();
    }
    await Db.module('ronda_absensi').doc(docKey).set({'uid':uid,'wargaId':wargaId,'nama':name,'tanggal':dateKey,'hari':day,'scheduleId':scheduleId,'statusKesediaan':status,'alasan':reason,'diperbaruiPada':FieldValue.serverTimestamp()},SetOptions(merge:true));
    if(context.mounted)showMessage(context,status=='Berhalangan'?'Alasan berhalangan dicatat.':'Status bersedia dicatat.');
  }
  Future<void> attendance(BuildContext context,String field) async {
    final now=DateTime.now().toUtc().add(const Duration(hours:7));
    await Db.module('ronda_absensi').doc(docKey).set({'uid':uid,'wargaId':wargaId,'nama':name,'tanggal':dateKey,'hari':day,'scheduleId':scheduleId,field:FieldValue.serverTimestamp(),'${field}Text':'${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}','updatedAt':FieldValue.serverTimestamp(),if(field=='waktuHadir')'status':'Hadir',if(field=='waktuPulang')'status':'Selesai Ronda'},SetOptions(merge:true));
    if(context.mounted)showMessage(context,field=='waktuHadir'?'Waktu hadir berhasil dicatat.':'Waktu pulang berhasil dicatat.');
  }
  @override
  Widget build(BuildContext context)=>StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:Db.module('ronda_absensi').doc(docKey).snapshots(),builder:(context,snap){final d=snap.data?.data()??{};final avail=(d['statusKesediaan']??'').toString();final hadir=d['waktuHadir']!=null;final pulang=d['waktuPulang']!=null;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Divider(),const Text('Status dan absensi Anda',style:TextStyle(fontWeight:FontWeight.bold)),Wrap(spacing:8,runSpacing:6,children:[OutlinedButton.icon(onPressed:()=>setAvailability(context,'Bersedia'),icon:const Icon(Icons.check_circle_outline),label:const Text('Bersedia')),OutlinedButton.icon(onPressed:()=>setAvailability(context,'Berhalangan'),icon:const Icon(Icons.event_busy),label:const Text('Berhalangan'))]),if(avail.isNotEmpty)Text('Status: $avail${(d['alasan']??'').toString().isNotEmpty?' • ${d['alasan']}':''}',style:const TextStyle(fontSize:12)),const SizedBox(height:8),Row(children:[Expanded(child:FilledButton.icon(onPressed:hadir?null:()=>attendance(context,'waktuHadir'),icon:const Icon(Icons.login),label:Text(hadir?'Hadir ${_timeText(d['waktuHadir'])}':'HADIR'))),const SizedBox(width:8),Expanded(child:FilledButton.tonalIcon(onPressed:(!hadir||pulang)?null:()=>attendance(context,'waktuPulang'),icon:const Icon(Icons.logout),label:Text(pulang?'Pulang ${_timeText(d['waktuPulang'])}':'PULANG')))]),]);});
}

String _timeText(dynamic value) {
  if(value is Timestamp){final d=value.toDate().toUtc().add(const Duration(hours:7));return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';}
  return (value??'--:--').toString();
}

Future<void> showRondaScheduleForm(BuildContext context,{String? docId,Map<String,dynamic>? initial}) async {
  final allSnap=await Db.module('sensus').get();
  if(!context.mounted)return;
  final residents=allSnap.docs.map((d){final m=d.data();return <String,dynamic>{...m,'wargaId':d.id};}).where((m){final gender=(m['jenisKelamin']??m['jenis_kelamin']??'').toString().toLowerCase();return gender.contains('laki') || gender=='l' || gender=='male';}).toList();
  final search=TextEditingController(); final rt=TextEditingController(text:(initial?['rt']??'').toString()); final rw=TextEditingController(text:(initial?['rw']??'').toString()); final start=TextEditingController(text:(initial?['jamMulai']??'21.00').toString()); final finish=TextEditingController(text:(initial?['jamSelesai']??'04.00').toString());
  final days=['Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu']; String day=(initial?['hari']??days[DateTime.now().weekday-1]).toString();
  final selected=<String>{}; final existing=initial?['petugas']; if(existing is List){for(final e in existing){if(e is Map && e['wargaId']!=null)selected.add(e['wargaId'].toString());}}
  await showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(ctx)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx).viewInsets.bottom),child:Container(height:MediaQuery.of(ctx).size.height*.88,padding:const EdgeInsets.all(16),decoration:const BoxDecoration(color:Color(0xFFF5F8F6),borderRadius:BorderRadius.vertical(top:Radius.circular(24))),child:StatefulBuilder(builder:(ctx,setStateSheet){final filtered=residents.where((r){final q=search.text.toLowerCase();final n=(r['nama']??'').toString().toLowerCase();final residentRt=(r['rt']??'').toString().toLowerCase();return (q.isEmpty||n.contains(q))&&(rt.text.trim().isEmpty||residentRt==rt.text.trim().toLowerCase());}).toList();return Column(children:[Text(docId==null?'Buat Jadwal Ronda':'Edit Jadwal Ronda',style:Theme.of(ctx).textTheme.titleLarge),const SizedBox(height:10),DropdownButtonFormField<String>(value:day,decoration:const InputDecoration(labelText:'Hari ronda'),items:days.map((d)=>DropdownMenuItem(value:d,child:Text(d))).toList(),onChanged:(v){if(v!=null)setStateSheet(()=>day=v);}),const SizedBox(height:8),Row(children:[Expanded(child:TextField(controller:rt,decoration:const InputDecoration(labelText:'RT'),onChanged:(_)=>setStateSheet((){}))),const SizedBox(width:8),Expanded(child:TextField(controller:rw,decoration:const InputDecoration(labelText:'RW')))]),const SizedBox(height:8),Row(children:[Expanded(child:TextField(controller:start,decoration:const InputDecoration(labelText:'Jam mulai'))),const SizedBox(width:8),Expanded(child:TextField(controller:finish,decoration:const InputDecoration(labelText:'Jam selesai')))]),const SizedBox(height:8),TextField(controller:search,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Cari nama warga laki-laki'),onChanged:(_)=>setStateSheet((){})),const SizedBox(height:8),Align(alignment:Alignment.centerLeft,child:Text('Pilih petugas (${selected.length})',style:const TextStyle(fontWeight:FontWeight.bold))),Expanded(child:filtered.isEmpty?const Center(child:Text('Tidak ada warga laki-laki pada RT ini.')):ListView.builder(itemCount:filtered.length,itemBuilder:(_,i){final r=filtered[i];final id=(r['wargaId']??'').toString();return CheckboxListTile(value:selected.contains(id),title:Text((r['nama']??'Tanpa nama').toString()),subtitle:Text('RT ${r['rt']??'-'} / RW ${r['rw']??'-'}'),onChanged:(v)=>setStateSheet((){if(v==true)selected.add(id);else selected.remove(id);}));})),Row(children:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),const Spacer(),FilledButton(onPressed:selected.isEmpty?null:()async{final picked=residents.where((r)=>selected.contains((r['wargaId']??'').toString())).toList();final petugas=picked.map((r)=>{'wargaId':r['wargaId'],'uid':r['accountUid']??'','nama':r['nama']??'','rt':r['rt']??'','rw':r['rw']??''}).toList();final payload={'hari':day,'rt':rt.text.trim(),'rw':rw.text.trim(),'jamMulai':start.text.trim(),'jamSelesai':finish.text.trim(),'petugas':petugas,'anggotaUid':petugas.map((e)=>e['uid']).where((e)=>e.toString().isNotEmpty).toList(),'anggota':petugas.map((e)=>e['nama']).join(', '),'updatedAt':FieldValue.serverTimestamp(),'updatedBy':Db.auth.currentUser?.uid};if(docId==null){payload['createdAt']=FieldValue.serverTimestamp();await Db.module('ronda').add(payload);}else{await Db.module('ronda').doc(docId).update(payload);}if(ctx.mounted)Navigator.pop(ctx);if(context.mounted)showMessage(context,'Jadwal ronda berhasil disimpan.');},child:const Text('Simpan Jadwal'))])]);})))); 
  search.dispose();rt.dispose();rw.dispose();start.dispose();finish.dispose();
}

Future<void> shareRondaDay(BuildContext context,List<QueryDocumentSnapshot<Map<String,dynamic>>> docs,String day,String date,String dateKey,Map<String,dynamic> profile) async {
  final b=StringBuffer('LAPORAN RONDA KAMPUNG KIARAJANGKUNG\n$day, $date\n\n');
  for(final doc in docs){
    final d=doc.data();
    b.writeln('RT ${d['rt']??'-'} / RW ${d['rw']??'-'} | ${d['jamMulai']??'21.00'}-${d['jamSelesai']??'04.00'}');
    final members=d['petugas'];
    if(members is List){
      final attendance=await Db.module('ronda_absensi').where('tanggal',isEqualTo:dateKey).where('scheduleId',isEqualTo:doc.id).get();
      final byUid={for(final a in attendance.docs)(a.data()['uid']??'').toString():a.data()};
      for(final member in members){
        if(member is! Map)continue;
        final uid=(member['uid']??'').toString(); final a=byUid[uid]??<String,dynamic>{};
        final reason=(a['alasan']??'').toString();
        b.writeln('- ${member['nama']??'Petugas'} | ${a['statusKesediaan']??'Belum mengisi'} | ${a['waktuHadir']!=null?'Hadir ${_timeText(a['waktuHadir'])}':'Belum hadir'} | ${a['waktuPulang']!=null?'Pulang ${_timeText(a['waktuPulang'])}':'Belum pulang'}${reason.isEmpty?'':' | Alasan: $reason'}');
      }
    } else { b.writeln((d['anggota']??'').toString()); }
    b.writeln();
  }
  try { await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(b.toString())}'),mode:LaunchMode.externalApplication); }
  catch(e){if(context.mounted)showMessage(context,'Tidak dapat membuka WhatsApp: $e');}
}

class RondaReportsPage extends StatelessWidget {
  final bool isAdmin;
  const RondaReportsPage({super.key, required this.isAdmin});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Laporan Ronda')),
    body: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream: Db.module('ronda_absensi').orderBy('tanggal', descending: true).limit(150).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Gagal memuat laporan: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('Belum ada data laporan ronda.'));
        final uid = Db.auth.currentUser?.uid ?? '';
        return ListView(padding: const EdgeInsets.all(16), children: [
          ...docs.map((doc) {
            final d = doc.data();
            final hadir = d['waktuHadir'] != null;
            final pulang = d['waktuPulang'] != null;
            final reason = (d['alasan'] ?? '').toString();
            final text = '${d['hari'] ?? ''}, ${d['tanggal'] ?? ''}\n${d['nama'] ?? 'Warga'}\nKesediaan: ${d['statusKesediaan'] ?? 'Belum mengisi'}${reason.isEmpty ? '' : '\nAlasan: $reason'}\nKehadiran: ${hadir ? 'Hadir ${_timeText(d['waktuHadir'])}' : 'Belum hadir'}\nPulang: ${pulang ? _timeText(d['waktuPulang']) : 'Belum pulang'}';
            final canShare = isAdmin || (d['uid'] ?? '').toString() == uid;
            return Card(child: ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: Text((d['nama'] ?? 'Laporan ronda').toString()),
              subtitle: Text('${d['hari'] ?? ''} • ${d['tanggal'] ?? ''}\n${hadir ? 'Hadir ${_timeText(d['waktuHadir'])}' : 'Belum hadir'}${pulang ? ' • Pulang ${_timeText(d['waktuPulang'])}' : ''}${reason.isNotEmpty ? ' • $reason' : ''}'),
              isThreeLine: true,
              trailing: canShare ? IconButton(
                tooltip: 'Kirim laporan WhatsApp', icon: const Icon(Icons.share, color: Colors.green),
                onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent('LAPORAN RONDA\n$text')}'), mode: LaunchMode.externalApplication),
              ) : null,
            ));
          }),
          if (isAdmin) FilledButton.icon(
            onPressed: () async {
              final b = StringBuffer('REKAP LAPORAN RONDA KAMPUNG KIARAJANGKUNG\n');
              for (final doc in docs) {
                final x = doc.data();
                b.writeln('${x['tanggal']} ${x['nama']} | ${x['statusKesediaan'] ?? '-'} | ${x['waktuHadir'] != null ? 'Hadir ${_timeText(x['waktuHadir'])}' : 'Tidak hadir'} | ${x['waktuPulang'] != null ? 'Pulang ${_timeText(x['waktuPulang'])}' : 'Belum pulang'}${(x['alasan'] ?? '').toString().isEmpty ? '' : ' | Alasan: ${x['alasan']}'}');
              }
              await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(b.toString())}'), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.share), label: const Text('Kirim rekap laporan WhatsApp'),
          ),
        ]);
      },
    ),
  );
}

class DashboardRondaPreview extends StatelessWidget {
  final Map<String,dynamic> profile;
  const DashboardRondaPreview({super.key,required this.profile});
  @override Widget build(BuildContext context){
    final uid=Db.auth.currentUser?.uid??''; final wargaId=(profile['wargaId']??'').toString();
    return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
      stream:wargaId.isEmpty?null:Db.module('sensus').doc(wargaId).snapshots(),
      builder:(context,residentSnap){
      final gender=((residentSnap.data?.data()?['jenisKelamin'])??profile['jenisKelamin']??'').toString().toLowerCase();
      if(gender.contains('perempuan') || gender=='p')return const SizedBox.shrink();
      return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:Db.module('ronda').snapshots(),builder:(context,snap){
      if(!snap.hasData)return const SizedBox.shrink();
      final now=DateTime.now(); final today=DateTime(now.year,now.month,now.day);
      final dayNames=['Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'];
      final matches=<Map<String,dynamic>>[];
      for(final doc in snap.data!.docs){final d=doc.data();final petugas=d['petugas'];bool mine=false;
        if(petugas is List){mine=petugas.any((m)=>m is Map && (((m['uid']??'').toString()==uid && uid.isNotEmpty)||(wargaId.isNotEmpty && (m['wargaId']??'').toString()==wargaId)));}
        if(!mine){final ids=(d['anggotaUid'] is List)?(d['anggotaUid'] as List).map((e)=>e.toString()).toList():<String>[];mine=ids.contains(uid);}
        if(mine){final day=dayNames.indexWhere((x)=>x.toLowerCase()==(d['hari']??'').toString().toLowerCase());if(day>=0){var delta=(day+1)-today.weekday;if(delta<0)delta+=7;final date=today.add(Duration(days:delta));matches.add({'data':d,'date':date,'day':dayNames[day]});}}
      }
      if(matches.isEmpty)return const SizedBox.shrink();
      matches.sort((a,b)=>(a['date'] as DateTime).compareTo(b['date'] as DateTime));
      return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const _DashboardSectionTitle(title:'Jadwal Ronda Anda'),...matches.map((m){final d=m['data'] as Map<String,dynamic>;final date=m['date'] as DateTime;return Card(child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xFFE9EDF7),child:Icon(Icons.shield_moon,color:Color(0xFF586B9B))),title:Text('${m['day']}, ${date.day}-${date.month}-${date.year}',style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('RT ${d['rt']??'-'} / RW ${d['rw']??'-'} • ${d['jamMulai']??'21.00'}–${d['jamSelesai']??'04.00'}'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const ModulePage(module:ModuleInfo('ronda','Jadwal Ronda','Jadwal ronda',Icons.nightlight_outlined),isAdmin:false)))));})]);
    });
      },
    );
  }
}

class DashboardPopulationStats extends StatefulWidget {
  final bool isAdmin;
  const DashboardPopulationStats({super.key, required this.isAdmin});
  @override
  State<DashboardPopulationStats> createState() => _DashboardPopulationStatsState();
}

class _DashboardPopulationStatsState extends State<DashboardPopulationStats> {
  String? _lastPublished;
  DocumentReference<Map<String, dynamic>> get _summaryRef => Db.module('statistik_penduduk').doc('ringkasan');

  Widget _renderStats(BuildContext context, int total, int male, int female, int kk) {
    final malePct = total == 0 ? 0.0 : male / total;
    final femalePct = total == 0 ? 0.0 : female / total;
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Statistik Penduduk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      const SizedBox(height: 4), const Text('Diperbarui otomatis dari Data Sensus Penduduk', style: TextStyle(fontSize: 10, color: Colors.black54)),
      const SizedBox(height: 12), Row(children: [
        Expanded(child: _populationRing('Laki-laki', male, malePct, const Color(0xFF3979B9))),
        Expanded(child: _populationRing('Perempuan', female, femalePct, const Color(0xFFD66A91))),
      ]),
      const Divider(height: 20), Row(children: [
        Expanded(child: _populationNumber('Total penduduk', total, Icons.groups_outlined)),
        Expanded(child: _populationNumber('Total KK', kk, Icons.home_work_outlined)),
      ]),
      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Rincian Penduduk'), content: Text('Total penduduk: $total jiwa\nLaki-laki: $male jiwa (${(malePct * 100).toStringAsFixed(1)}%)\nPerempuan: $female jiwa (${(femalePct * 100).toStringAsFixed(1)}%)\nTotal kepala keluarga: $kk KK'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))])), child: const Text('Lihat rincian'))),
    ])));
  }

  Map<String, int> _count(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final list = docs.where((d) => !isArchivedResident(d.data())).toList();
    final male = list.where((d) => ['laki-laki','laki laki','l','pria'].contains((d.data()['jenisKelamin'] ?? '').toString().trim().toLowerCase())).length;
    final female = list.where((d) => ['perempuan','wanita','p'].contains((d.data()['jenisKelamin'] ?? '').toString().trim().toLowerCase())).length;
    final kk = list.map((d) => (d.data()['noKK'] ?? '').toString().trim()).where((v) => v.isNotEmpty).toSet().length;
    return {'total': list.length, 'male': male, 'female': female, 'kk': kk};
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAdmin) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.module('sensus').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const SizedBox.shrink();
          if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()));
          final counts = _count(snapshot.data!.docs);
          final signature = '${counts['total']}:${counts['male']}:${counts['female']}:${counts['kk']}';
          if (_lastPublished != signature) {
            _lastPublished = signature;
            Future.microtask(() => _summaryRef.set({...counts, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)));
          }
          return _renderStats(context, counts['total']!, counts['male']!, counts['female']!, counts['kk']!);
        },
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _summaryRef.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
        final d = snapshot.data!.data()!;
        return _renderStats(context, (d['total'] as num?)?.toInt() ?? 0, (d['male'] as num?)?.toInt() ?? 0, (d['female'] as num?)?.toInt() ?? 0, (d['kk'] as num?)?.toInt() ?? 0);
      },
    );
  }
}
Widget _genderCircle(String title, int count, double percent) => Column(children: [
  SizedBox(width: 76, height: 76, child: Stack(alignment: Alignment.center, children: [
    SizedBox.expand(child: CircularProgressIndicator(value: percent, strokeWidth: 7, backgroundColor: const Color(0xFFE6EEE8), color: const Color(0xFF167C55))),
    Text('${(percent*100).round()}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
  ])),
  const SizedBox(height: 5), Text('$title ($count)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
]);
Widget _statItem(String title,String value,IconData icon)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Column(children:[Icon(icon,color:const Color(0xFF167C55)),const SizedBox(height:4),Text(value,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)),Text(title,style:const TextStyle(fontSize:11,color:Colors.black54))]));


Widget _populationRing(String label, int count, double pct, Color color) => Column(children: [
  SizedBox(width: 82, height: 82, child: Stack(alignment: Alignment.center, children: [
    SizedBox.expand(child: CircularProgressIndicator(value: pct, strokeWidth: 8, backgroundColor: color.withOpacity(.13), valueColor: AlwaysStoppedAnimation<Color>(color))),
    Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${(pct * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text('$count jiwa', style: const TextStyle(fontSize: 9))]),
  ])), const SizedBox(height: 6), Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
]);


Widget _populationNumber(String label, int count, IconData icon) => Row(children: [Icon(icon, color: const Color(0xFF21865D)), const SizedBox(width: 7), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)), Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54))]))]);

class DashboardAnnouncements extends StatelessWidget {
  const DashboardAnnouncements({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream: Db.module('pengumuman').snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const SizedBox.shrink();
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
      return Material(
        color: Colors.white,
        elevation: 5,
        shadowColor: const Color(0x33167547),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => showModalBottomSheet<void>(
            context: context, isScrollControlled: true, showDragHandle: true,
            builder: (ctx) => SafeArea(child: Padding(
              padding: const EdgeInsets.all(18),
              child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items.map((d) => ListTile(
                  title: Text((d['judul'] ?? d['nama'] ?? 'Pengumuman').toString()),
                  subtitle: Text((d['deskripsi'] ?? d['keterangan'] ?? '').toString()),
                )).toList(),
              )),
            )),
          ),
          child: Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE5EEE8))),
            child: Row(children: [
              Container(width: 38, height: 38, decoration: const BoxDecoration(color: Color(0xFF167C55), shape: BoxShape.circle), child: const Icon(Icons.campaign_rounded, color: Colors.white)),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('PENGUMUMAN KAMPUNG', style: TextStyle(color: Color(0xFF167C55), fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: .5)),
                const SizedBox(height: 4),
                Expanded(child: Align(alignment: Alignment.centerLeft, child: _MarqueeText(text: message))),
              ])),
              const SizedBox(width: 5), const Icon(Icons.chevron_right, color: Colors.black45),
            ]),
          ),
        ),
      );
    },
  );
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
  final bool isAdmin;
  const ModulesPage({super.key, this.isAdmin = false});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Informasi & Layanan', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...modules.where((m) => isAdmin || !['arsip_warga', 'migrasi_satu_data'].contains(m.keyName)).map((m) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(m.icon),
                  ),
                  title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(m.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ModulePage(module: m, isAdmin: isAdmin),
                  )),
                ),
              )),
        ],
      );
}


class ProfileKampungSection {
  final String keyName;
  final String title;
  final String subtitle;
  final IconData icon;
  const ProfileKampungSection(this.keyName, this.title, this.subtitle, this.icon);
}

const profileKampungSections = <ProfileKampungSection>[
  ProfileKampungSection('sejarah', 'Sejarah Desa', 'Asal-usul dan perkembangan Kiarajangkung', Icons.history_edu_outlined),
  ProfileKampungSection('geografis', 'Geografis & Wilayah', 'Letak, luas wilayah, batas dan kondisi alam', Icons.map_outlined),
  ProfileKampungSection('kependudukan', 'Kependudukan', 'Data penduduk dan keluarga', Icons.groups_outlined),
  ProfileKampungSection('pemerintahan', 'Pemerintahan Desa', 'Identitas dan struktur pemerintahan', Icons.account_balance_outlined),
  ProfileKampungSection('infrastruktur', 'Infrastruktur', 'Jalan, jembatan, irigasi dan bangunan', Icons.construction_outlined),
  ProfileKampungSection('sarana_prasarana', 'Sarana & Prasarana', 'Air bersih, pendidikan, kesehatan dan fasilitas umum', Icons.domain_outlined),
  ProfileKampungSection('pendidikan_ekonomi', 'Pendidikan & Ekonomi', 'Pendidikan, mata pencaharian dan kegiatan ekonomi', Icons.school_outlined),
  ProfileKampungSection('potensi', 'Potensi Desa', 'Pertanian, perkebunan, wisata, seni dan UMKM', Icons.eco_outlined),
];

class ProfileKampungPage extends StatelessWidget {
  final bool isAdmin;
  const ProfileKampungPage({super.key, required this.isAdmin});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profil Kampung')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFEAF4ED), borderRadius: BorderRadius.circular(16)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Profil Kampung Kiarajangkung', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Text('Informasi kampung disajikan dalam 8 bagian. Data historis diberi penanda tahun agar tidak dianggap sebagai data terbaru.'),
            SizedBox(height: 8),
            Text('Data historis: Tahun 2022', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF39724F))),
          ]),
        ),
        const SizedBox(height: 14),
        if (isAdmin) Padding(padding: const EdgeInsets.only(bottom: 12), child: OutlinedButton.icon(
          onPressed: () => _seedProfile2022(context),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Masukkan arsip profil desa Tahun 2022'),
        )),
        ...profileKampungSections.map((section) => Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            leading: CircleAvatar(backgroundColor: const Color(0xFFEAF4ED), child: Icon(section.icon, color: const Color(0xFF39724F))),
            title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(section.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileKampungSectionPage(section: section, isAdmin: isAdmin))),
          ),
        )),
      ],
    ),
  );
}

Future<void> _seedProfile2022(BuildContext context) async {
  final ref = Db.module('profil_kampung');
  final existing = await ref.where('tahunData', isEqualTo: 2022).limit(1).get();
  if (existing.docs.isNotEmpty) {
    if (context.mounted) showMessage(context, 'Arsip Tahun 2022 sudah pernah dimasukkan.');
    return;
  }
  const kepala = '1. KATAR | 1820–1830 | Panyindangan\n2. EJOB ATMANATADIWANGSA | 1830–1870 | Cijoho\n3. SACA DIWANGSA | 1870–1890 | Cijoho\n4. SALYA DIWANGSA | 1890–1912 | Cijoho\n5. MARHASAN | 1912–1924 | Buniruum\n6. ABDUL ROJAK SURAWIKARTA | 1924–1936 | Celeput\n7. DAHLAN | 1936–1937 | Cijoho\n8. WIRANATA | 1937–1954 | Cijoho\n9. ADIWISASTRA | 1954–1965 | Buniruum\n10. E. RUSLI | 1965–1973 | Cijoho\n11. MAMAT SUDARYAT | 1973–1977 | Kiarajangkung\n12. E. KOSWARA (Kartiker) | 1977–1978 | Cisayong\n13. A. SUKANDA (H. Nurjaman) | 1978–1988 | Cilangen\n14. NANA SUPRIATNA (H. Nursofa) | 1988–1995 | Cilangen\n15. AGUS WIHARYA (PJS) | 1995–1998 | Sirnamanah\n16. OYON SUDAYAT (PJS) | 1998–2000 | Sirnamanah\n17. H. EMPON SURYANA | 2000–2005 | Kiarajangkung\n18. ENDANG SAMBAS (PJS) | 2005–2005 | Kiarajangkung\n19. H. NURSOFA | 2005–2006 | Cilangen\n20. LILI B. HADIAMAN (PJS) | 2006–2007 | Kiarajangkung\n21. ENDANG SAMBAS (PLT) | 2007–2007 | Kiarajangkung\n22. ASEP WAWAN, S.Sos | 2007–2013 | Cimulya\n23. ASEP WAWAN, S.Sos. | 2013–2019 | Cimulya\n24. TUHAEDAH (PJS) | 2019–2019 | Cisayong\n25. ASEP WAWAN, S.Sos | 2019–2025 | Cimulya';
  final data = <String, Map<String, dynamic>>{
    'sejarah': {'judul':'Sejarah Desa Kiarajangkung','ringkasan':'Menurut keterangan sesepuh, Kiarajangkung berdiri sekitar tahun 1820 M. Dahulu termasuk wilayah Kecamatan Cisayong. Pada tahun 1996 wilayah dimekarkan menjadi Desa Kiarajangkung dan Desa Sundakerta pada masa pemerintahan A. Sukanda (H. Nurjaman).','asalNama':'Kiara berarti pohon tinggi/besar. Jangkung dalam bahasa Sunda berarti tinggi atau menjulang. Menurut cerita karuhun, sisa pohon Kiara yang menjulang sekitar 23 meter berada di RT 02 RW 04 dan disebut sebagai tunas/sirung.','tahunBerdiri':'Sekitar 1820 M (menurut keterangan sesepuh)','pemekaran':'Tahun 1996 menjadi Desa Kiarajangkung dan Desa Sundakerta.','daftarKepalaDesa':kepala,'catatan':'Sumber: Profil Desa Kiarajangkung Februari 2022. Riwayat berdasarkan keterangan sesepuh/tokoh desa; ejaan dan periode perlu validasi arsip.'},
    'geografis': {'judul':'Geografis dan Wilayah (Arsip 2022)','alamatWilayah':'Desa Kiarajangkung, Kecamatan Sukahening, Kabupaten Tasikmalaya, Jawa Barat. Berada di lereng Gunung Talagabodas dan berbatasan dengan kawasan hutan lindung menuju Kabupaten Garut.','luasWilayah':'331,54 ha. Rincian sumber: pesawahan 120 ha; kolam 2,5 ha; kehutanan/hutan lindung 180 ha; tanah darat 211,54 ha; hutan rakyat/kebun 166 ha; jalan, irigasi, pemakaman dan lainnya 6 ha. Rincian kategori dapat tumpang tindih dan perlu verifikasi.','batasUtara':'Desa Kertamukti, Kecamatan Ciawi','batasSelatan':'Desa Sundakerta','batasTimur':'Desa Sukahening','batasBarat':'Kehutanan / Kabupaten Garut','dusun':'Cimulya; Cilangen; Kiarajangkung; Sirnamanah; Cipalegor.','koordinat':'-7.2007, 108.1290 (7°12′02.5″ LS, 108°07′44.4″ BT) — koordinat yang dikonfirmasi pengguna.','ketinggian':'Dokumen mencatat ±780 mdpl pada sejarah dan 853 mdpl pada kondisi geologis. Perlu verifikasi.','iklimTopografi':'Suhu rata-rata 18–21°C; curah hujan 2.994 mm/tahun; sumber air dari pegunungan dinyatakan cukup. Topografi: pegunungan 65%; lembah/dataran 35%.','catatanVerifikasi':'Luas rincian tidak boleh dijumlahkan tanpa pengecekan karena berpotensi tumpang tindih. Ketinggian berbeda antara 780 dan 853 mdpl.'},
    'kependudukan': {'judul':'Kependudukan (Arsip 2022)','jumlahPenduduk':'3.895 jiwa','jumlahKk':'1.383 KK','lakiLaki':'1.911 jiwa','perempuan':'1.984 jiwa','perDusun':'Cimulya: 321 KK, 923 jiwa (452 laki-laki; 471 perempuan)\nCilangen: 293 KK, 785 jiwa (364; 421)\nKiarajangkung: 231 KK, 651 jiwa (326; 325)\nSirnamanah: 209 KK, 628 jiwa (302; 326)\nCipalegor: 329 KK, 908 jiwa (467; 441)','agama':'Cimulya: Islam 923\nCilangen: Islam 785\nKiarajangkung: Islam 651\nSirnamanah: Islam 614, Katolik 14\nCipalegor: Islam 898, Katolik 6, Kepercayaan terhadap Tuhan YME 4. Total tabel sumber: Islam 3.895, Katolik 20, Kepercayaan 4; tidak selaras dengan total jiwa 3.895.','catatanVerifikasi':'Data penduduk per dusun menjumlah 3.895 jiwa. Tabel agama jika dijumlahkan melebihi total; pertahankan sesuai sumber sampai diverifikasi.'},
    'pemerintahan': {'judul':'Pemerintahan Desa (Arsip 2022)','identitas':'Pemerintah Desa Kiarajangkung, Kecamatan Sukahening, Kabupaten Tasikmalaya. Dokumen sumber bertanggal Februari 2022.','kepalaDesa':'Asep Wawan, S.Sos. (periode yang dicantumkan dalam dokumen 2019–2025; bukan konfirmasi jabatan saat ini).','periode':'Data historis Februari 2022.','perangkat':'Struktur perangkat desa tidak dirinci dalam dokumen sumber yang diberikan. Perlu dilengkapi dari data pemerintah desa terbaru.','lembaga':'Perlu dilengkapi dengan data lembaga desa terkini.'},
    'infrastruktur': {'judul':'Infrastruktur Desa (Arsip 2022)','jalan':'Panjang jalan beraspal 2.300 m; jalan berbatu 1.700 m; jalan bertanah 2.500 m. Bagian lain dokumen menyebut total jalan desa 2,5 km dan 1,5 km beraspal rusak berat/berlubang. Perlu rekonsiliasi.','jembatan':'Disebut 2 buah pada satu bagian dan 5 buah pada bagian lain; bagian kondisi menyebut 5 buah kurang baik tetapi masih dapat digunakan. Perlu verifikasi.','irigasi':'Disebut 6 saluran irigasi; bagian lain menyebut 20.000 m² irigasi rusak berat/tidak berfungsi.','kantor':'Kantor desa 80,5 m² (disebut rusak ringan); bangunan kantor dusun 120 m².','perumahan':'Rumah layak huni 782; tidak layak huni 200; rusak berat 15; berada di lokasi rawan longsor 95.','catatanVerifikasi':'Angka jalan, jembatan, dan irigasi berbeda/berpotensi salah satuan di dokumen sumber. Jangan dianggap kondisi terkini.'},
    'sarana_prasarana': {'judul':'Sarana dan Prasarana (Arsip 2022)','airBersih':'KK mendapat air bersih 1.206; KK kesulitan air bersih 202. Bak penampungan 5 buah; pipanisasi 2.500 m.','peribadatan':'Masjid jami representatif (kapasitas 600 jamaah) 5 buah; masjid jami tidak memadai 20 buah. Bagian lain menyebut masjid 7 buah; perlu verifikasi.','pendidikan':'Gedung sekolah: SD 3; SMP 1; SMA 1.','kesehatan':'Poskesdes/Pustu 1; Posyandu 5. Tidak tercatat rumah sakit atau puskesmas.','pasar':'Pasar desa 1; pertokoan 2; warung 6.','keamanan':'Pos kamling 7.','lainnya':'Mobil 11; pikap 6; truk 3; lapangan 1; balai desa 1.'},
    'pendidikan_ekonomi': {'judul':'Pendidikan dan Ekonomi Warga (Arsip 2022)','pendidikanFormal':'TK 105 orang; SD 2.340; SLTP/sederajat 653; SLTA/sederajat 390; D1 1; D2 2; D3 7; S1 121; S2 3.','mataPencaharian':'PNS 19; TNI/Polri 2; petani 159; buruh tani 57; buruh harian lepas 638; pedagang 69; peternak 7.','pertanianEkonomi':'Dokumen mencatat pertanian, buruh tani, peternakan, perdagangan dan pekerjaan harian sebagai mata pencaharian warga.','umkm':'Data jumlah dan jenis UMKM belum dirinci dalam dokumen sumber.'},
    'potensi': {'judul':'Potensi Desa (Arsip 2022)','pertanian':'Lahan pesawahan tercatat 120 ha; sumber air berasal dari kawasan pegunungan. Potensi pertanian perlu diperbarui dengan komoditas dan produksi terkini.','perkebunan':'Hutan rakyat/kebun tercatat 166 ha pada dokumen; perlu pemeriksaan apakah kategori ini tumpang tindih dengan luas lainnya.','peternakan':'Dokumen mencatat 7 orang peternak; jenis dan skala peternakan belum dirinci.','wisata':'Wilayah berada di lereng Gunung Talagabodas dengan lanskap pegunungan dan sumber air. Potensi wisata belum dijelaskan rinci dalam dokumen.','seniBudaya':'Belum dirinci dalam dokumen sumber; dapat dilengkapi oleh pemerintah desa dan warga.','umkm':'Potensi usaha lokal perlu dihimpun melalui pendataan UMKM warga.'}
  };
  final batch = FirebaseFirestore.instance.batch();
  for (final entry in data.entries) {
    final doc = ref.doc('arsip_2022_${entry.key}');
    batch.set(doc, {'bagian':entry.key, 'judul':entry.value['judul'], 'tahunData':2022, 'updatedAt':FieldValue.serverTimestamp(), ...entry.value});
  }
  await batch.commit();
  if (context.mounted) showMessage(context, '8 bagian arsip profil desa Tahun 2022 berhasil dimasukkan.');
}

class ProfileKampungSectionPage extends StatelessWidget {
  final ProfileKampungSection section;
  final bool isAdmin;
  const ProfileKampungSectionPage({super.key, required this.section, required this.isAdmin});

  List<ModuleField> get fields {
    switch (section.keyName) {
      case 'sejarah': return const [
        ModuleField('ringkasan', 'Sejarah dan asal-usul', lines: 6),
        ModuleField('asalNama', 'Asal-usul nama Kiarajangkung', lines: 3),
        ModuleField('tahunBerdiri', 'Tahun berdiri / mulai berkembang', hint: 'Perkiraan sesuai dokumen sumber'),
        ModuleField('pemekaran', 'Riwayat pemekaran', lines: 3),
        ModuleField('daftarKepalaDesa', 'Daftar kepala desa', lines: 6),
        ModuleField('catatan', 'Sumber / catatan verifikasi', lines: 3),
      ];
      case 'geografis': return const [
        ModuleField('alamatWilayah', 'Lokasi / alamat wilayah', lines: 2),
        ModuleField('luasWilayah', 'Luas wilayah', hint: 'Cantumkan satuan ha; verifikasi rincian kategori'),
        ModuleField('ketinggian', 'Ketinggian wilayah', hint: 'mdpl; perlu verifikasi bila berbeda sumber'),
        ModuleField('batasUtara', 'Batas utara'), ModuleField('batasSelatan', 'Batas selatan'),
        ModuleField('batasTimur', 'Batas timur'), ModuleField('batasBarat', 'Batas barat'),
        ModuleField('dusun', 'Daftar dusun / wilayah', lines: 4),
        ModuleField('koordinat', 'Koordinat', hint: '-7.2007, 108.1290 (7°12′02.5″ LS, 108°07′44.4″ BT)'),
        ModuleField('iklimTopografi', 'Iklim dan topografi', lines: 3),
        ModuleField('catatanVerifikasi', 'Catatan verifikasi data wilayah', lines: 3),
      ];
      case 'kependudukan': return const [
        ModuleField('jumlahPenduduk', 'Jumlah penduduk', keyboard: TextInputType.number),
        ModuleField('jumlahKk', 'Jumlah kepala keluarga', keyboard: TextInputType.number),
        ModuleField('lakiLaki', 'Laki-laki', keyboard: TextInputType.number),
        ModuleField('perempuan', 'Perempuan', keyboard: TextInputType.number),
        ModuleField('perDusun', 'Data penduduk per dusun', lines: 5),
        ModuleField('agama', 'Data penduduk berdasarkan agama', lines: 5),
        ModuleField('pendidikan', 'Data tingkat pendidikan', lines: 4),
        ModuleField('pekerjaan', 'Data mata pencaharian', lines: 4),
        ModuleField('catatanVerifikasi', 'Catatan verifikasi / sumber data', lines: 3),
      ];
      case 'pemerintahan': return const [
        ModuleField('identitas', 'Identitas pemerintahan desa', lines: 3),
        ModuleField('kepalaDesa', 'Kepala desa'), ModuleField('sekretarisDesa', 'Sekretaris desa'),
        ModuleField('perangkat', 'Struktur perangkat desa', lines: 6),
        ModuleField('lembaga', 'Lembaga pemerintahan dan kemasyarakatan', lines: 4),
        ModuleField('periode', 'Periode / masa jabatan'),
      ];
      case 'infrastruktur': return const [
        ModuleField('jalan', 'Jalan', lines: 3), ModuleField('jembatan', 'Jembatan', hint: 'Jumlah dan kondisi; verifikasi bila ada perbedaan sumber'),
        ModuleField('irigasi', 'Irigasi dan saluran air', lines: 3),
        ModuleField('kantor', 'Kantor desa / dusun', lines: 3),
        ModuleField('perumahan', 'Perumahan dan permukiman', lines: 3),
        ModuleField('catatanVerifikasi', 'Catatan verifikasi / sumber data', lines: 3),
      ];
      case 'sarana_prasarana': return const [
        ModuleField('airBersih', 'Sarana air bersih', lines: 3), ModuleField('peribadatan', 'Tempat ibadah', lines: 3),
        ModuleField('pendidikan', 'Sarana pendidikan', lines: 3), ModuleField('kesehatan', 'Sarana kesehatan', lines: 3),
        ModuleField('pasar', 'Pasar / sarana perdagangan', lines: 3), ModuleField('keamanan', 'Poskamling / keamanan', lines: 3),
        ModuleField('lainnya', 'Sarana lainnya', lines: 3),
      ];
      case 'pendidikan_ekonomi': return const [
        ModuleField('pendidikanFormal', 'Pendidikan formal', lines: 4),
        ModuleField('pendidikanNonFormal', 'Pendidikan nonformal', lines: 3),
        ModuleField('mataPencaharian', 'Mata pencaharian warga', lines: 4),
        ModuleField('pertanianEkonomi', 'Kegiatan ekonomi utama', lines: 4),
        ModuleField('umkm', 'UMKM dan perdagangan', lines: 4),
      ];
      default: return const [
        ModuleField('pertanian', 'Pertanian', lines: 4), ModuleField('perkebunan', 'Perkebunan / kehutanan', lines: 4),
        ModuleField('peternakan', 'Peternakan / perikanan', lines: 3), ModuleField('wisata', 'Wisata dan alam', lines: 4),
        ModuleField('seniBudaya', 'Seni dan budaya', lines: 4), ModuleField('umkm', 'Potensi UMKM / produk lokal', lines: 4),
        ModuleField('potensiLain', 'Potensi lainnya', lines: 3),
      ];
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(section.title)),
    floatingActionButton: isAdmin ? FloatingActionButton.extended(
      onPressed: () => _edit(context), icon: const Icon(Icons.edit_note), label: const Text('Kelola data')) : null,
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Db.module('profil_kampung').where('bagian', isEqualTo: section.keyName).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Gagal memuat data: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs.toList()..sort((a, b) { final av = a.data()['updatedAt']; final bv = b.data()['updatedAt']; if (av is Timestamp && bv is Timestamp) return bv.compareTo(av); return 0; });
        if (docs.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(isAdmin ? 'Belum ada data ${section.title}. Tekan Kelola data untuk mengisi.' : 'Data ${section.title} belum tersedia.')));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF4DB), borderRadius: BorderRadius.circular(12)), child: const Text('Data historis dari dokumen lama diberi label Tahun 2022. Angka yang belum diverifikasi harus tetap sesuai sumber dan tidak boleh dikoreksi tanpa konfirmasi.')),
          const SizedBox(height: 12),
          ...docs.map((doc) {
            final d = doc.data();
            final entries = fields.where((f) => (d[f.key] ?? '').toString().trim().isNotEmpty).toList();
            return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text((d['judul'] ?? section.title).toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), if (isAdmin) PopupMenuButton<String>(onSelected: (v) async { if (v == 'edit') { await _edit(context, docId: doc.id, initial: d); } else if (v == 'delete' && await confirmDelete(context) == true) { await doc.reference.delete(); } }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Hapus'))])]),
              Text('Data Tahun ${d['tahunData'] ?? 2022}', style: const TextStyle(color: Color(0xFF39724F), fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 8),
              ...entries.map((f) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 3), SelectableText(d[f.key].toString())]))),
              if ((d['catatanVerifikasi'] ?? '').toString().trim().isNotEmpty) Text('Catatan: ${d['catatanVerifikasi']}', style: const TextStyle(fontStyle: FontStyle.italic)),
            ])));
          }),
        ]);
      },
    ),
  );

  Future<void> _edit(BuildContext context, {String? docId, Map<String, dynamic>? initial}) async {
    final title = TextEditingController(text: (initial?['judul'] ?? section.title).toString());
    final year = TextEditingController(text: (initial?['tahunData'] ?? 2022).toString());
    final ctrls = {for (final f in fields) f.key: TextEditingController(text: (initial?[f.key] ?? '').toString())};
    final formKey = GlobalKey<FormState>();
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(child: SizedBox(height: MediaQuery.of(ctx).size.height * .85, child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(docId == null ? 'Tambah ${section.title}' : 'Edit ${section.title}', style: Theme.of(ctx).textTheme.titleLarge)),
        Expanded(child: Form(key: formKey, child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Judul data'), validator: (v) => v == null || v.trim().isEmpty ? 'Judul wajib diisi' : null),
          const SizedBox(height: 10),
          TextFormField(controller: year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tahun data', hintText: 'Contoh: 2022'), validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Masukkan tahun yang valid' : null),
          const SizedBox(height: 10),
          ...fields.map((f) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TextFormField(controller: ctrls[f.key], maxLines: f.lines, keyboardType: f.keyboard, decoration: InputDecoration(labelText: f.label, hintText: f.hint.isEmpty ? null : f.hint)))),
          const Text('Data lama akan diberi label Tahun 2022. Pastikan angka yang belum diverifikasi tidak diubah.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
        ]))),
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal'))), const SizedBox(width: 10), Expanded(child: FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Simpan')))])),
      ]))),
    ));
    if (ok == true) {
      final data = <String, dynamic>{'bagian': section.keyName, 'judul': title.text.trim(), 'tahunData': int.tryParse(year.text.trim()) ?? 2022, 'updatedAt': FieldValue.serverTimestamp()};
      for (final f in fields) { data[f.key] = ctrls[f.key]!.text.trim(); }
      final ref = docId == null ? Db.module('profil_kampung').doc() : Db.module('profil_kampung').doc(docId);
      await ref.set(data, SetOptions(merge: true));
      if (context.mounted) showMessage(context, 'Data ${section.title} berhasil disimpan.');
    }
    title.dispose(); year.dispose(); for (final c in ctrls.values) { c.dispose(); }
  }
}

class ModulePage extends StatelessWidget {
  final ModuleInfo module;
  final bool isAdmin;
  const ModulePage({super.key, required this.module, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    if (module.keyName == 'profil_kampung') {
      return ProfileKampungPage(isAdmin: isAdmin);
    }
    if (module.keyName == 'ronda') {
      return RondaSchedulePage(isAdmin: isAdmin);
    }
    if (module.keyName == 'informasi_diri') {
      return const InformasiDiriPage();
    }
    if (module.keyName == 'arsip_warga') return ArchivedResidentsPage(isAdmin: isAdmin);
    if (module.keyName == 'migrasi_satu_data') return MigrasiSatuDataPage(isAdmin: isAdmin);
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
          final visibleDocs = module.keyName == 'sensus'
              ? snapshot.data!.docs.where((d) => !isArchivedResident(d.data())).toList()
              : snapshot.data!.docs;
          if (visibleDocs.isEmpty) return const Center(child: Text('Belum ada data aktif. Data yang diarsipkan dapat dilihat di menu Arsip Warga.'));
          return ListView.builder(
            primary: true,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: visibleDocs.length,
            itemBuilder: (context, index) {
              final doc = visibleDocs[index];
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
                          if (module.keyName == 'sensus' && isArchivedResident(data))
                            Padding(padding: const EdgeInsets.only(top: 5), child: Text('ARSIP • ${data['statusArsip'] ?? 'Warga tidak aktif'}', style: const TextStyle(color: Colors.deepOrange, fontSize: 11, fontWeight: FontWeight.bold))),
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
                            } else if (v == 'delete' && canEdit && module.keyName != 'sensus') {
                              final yes = await confirmDelete(context);
                              if (yes == true) {
                                await PhotoService.deleteIfOwned(photo);
                                await doc.reference.delete();
                              }
                            }
                          },
                          itemBuilder: (_) => canEdit
                              ? (module.keyName == 'sensus'
                                  ? const [PopupMenuItem(value: 'edit', child: Text('Edit / Arsipkan'))]
                                  : const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(value: 'delete', child: Text('Hapus')),
                                    ])
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
        ModuleField('alamat', 'Alamat lengkap'),
        ModuleField('agama', 'Agama'),
        ModuleField('kewarganegaraan', 'Kewarganegaraan'),
        ModuleField('golonganDarah', 'Golongan darah'),
        ModuleField('kodePos', 'Kode pos', keyboard: TextInputType.number),
        ModuleField('namaAyah', 'Nama ayah'),
        ModuleField('namaIbu', 'Nama ibu'),
        ModuleField('statusDalamKeluarga', 'Status dalam keluarga'),
        ModuleField('statusPerkawinan', 'Status perkawinan'),
        ModuleField('pendidikan', 'Pendidikan'),
        ModuleField('pekerjaan', 'Pekerjaan'),
        ModuleField('hubunganKeluarga', 'Hubungan dalam keluarga'),
        ModuleField('kawil', 'Kawil / Dusun'),
        ModuleField('rw', 'RW'),
        ModuleField('rt', 'RT'),
        ModuleField('statusWarga', 'Status warga', hint: 'Aktif / Arsip'),
        ModuleField('statusArsip', 'Alasan arsip', hint: 'Pindah / Meninggal'),
        ModuleField('tanggalArsip', 'Tanggal arsip', hint: 'DD-MM-YYYY'),
        ModuleField('alamatTujuan', 'Alamat tujuan jika pindah'),
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
        ModuleField('penanggungJawab', 'Penanggung jawab'),
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

List<String> definitionsForResidentPicker(String moduleKey) {
  switch (moduleKey) {
    case 'umkm': return ['pemilik'];
    case 'sarana': return ['pengelola'];
    case 'kesenian': return ['ketua'];
    case 'kebersihan': return ['petugas'];
    case 'fasilitas_kesehatan': return ['penanggungJawab'];
    case 'organisasi': return ['ketua', 'wakil', 'sekretaris', 'bendahara'];
    default: return const [];
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
  final currentUid = Db.auth.currentUser?.uid;
  final currentProfile = currentUid == null ? null : await Db.user(currentUid).get();
  final currentData = currentProfile?.data() ?? <String, dynamic>{};
  final currentRoles = (currentData['roles'] is List)
      ? List<String>.from(currentData['roles'].map((e) => e.toString()))
      : <String>[(currentData['role'] ?? 'warga').toString()];
  final isOwner = currentRoles.map((e) => e.toLowerCase()).contains('owner');
  final initialRoles = (initial?['roles'] is List)
      ? List<String>.from((initial!['roles'] as List).map((e) => e.toString()))
      : <String>['warga'];
  final selectedRoles = <String>{...initialRoles, 'warga'};
  final usesResidentPicker = isAdmin && (module.keyName == 'perangkat' ||
      definitionsForResidentPicker(module.keyName).isNotEmpty);
  List<Map<String, dynamic>> residentOptions = <Map<String, dynamic>>[];
  if (usesResidentPicker) {
    try {
      residentOptions = await loadActiveResidents();
    } catch (e) {
      if (context.mounted) showMessage(context, 'Gagal mengambil Data Sensus: $e');
      return;
    }
  }
  final selectedResidents = <String, Map<String, dynamic>>{};
  for (final fieldKey in definitionsForResidentPicker(module.keyName)) {
    final id = (initial?['${fieldKey}WargaId'] ?? '').toString();
    final name = (initial?[fieldKey] ?? '').toString();
    final found = resolveResident(residentOptions, id, name);
    if (found != null) selectedResidents[fieldKey] = found;
  }
  Map<String, dynamic>? selectedTitleResident;
  if (module.keyName == 'perangkat') {
    selectedTitleResident = resolveResident(residentOptions,
      (initial?['pemegangJabatanWargaId'] ?? initial?['wargaId'] ?? '').toString(),
      (initial?['nama'] ?? initial?['judul'] ?? '').toString());
  }
  List<Map<String, dynamic>> selectedOrganizationMembers = <Map<String, dynamic>>[];
  bool organizationMembersTouched = false;
  final existingMembers = initial?['anggotaWarga'];
  if (existingMembers is List) {
    for (final item in existingMembers) {
      if (item is Map) {
        final found = resolveResident(residentOptions,
          (item['wargaId'] ?? '').toString(), (item['nama'] ?? '').toString());
        if (found != null) selectedOrganizationMembers.add(found);
      }
    }
  }
  final title = TextEditingController(
    text: (initial?['judul'] ?? initial?['nama'] ?? initial?['nama_usaha'] ?? '').toString(),
  );
  final definitions = fieldsForModule(module.keyName);
  final controllers = <String, TextEditingController>{
    for (final field in definitions)
      field.key: TextEditingController(text: (initial?[field.key] ?? '').toString()),
  };
  if (module.keyName == 'sensus' && (controllers['statusWarga']?.text ?? '').trim().isEmpty) {
    controllers['statusWarga']?.text = 'Aktif';
  }
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
                  if (module.keyName == 'perangkat')
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_search_outlined),
                      onPressed: () async {
                        final picked = await showResidentPicker(sheetContext, residentOptions,
                          selectedWargaId: (selectedTitleResident?['wargaId'] ?? '').toString(),
                          title: 'Pilih perangkat dari Sensus');
                        if (picked != null) setSheetState(() {
                          selectedTitleResident = picked;
                          title.text = (picked['nama'] ?? '').toString();
                        });
                      },
                      label: Text(selectedTitleResident == null ? 'Pilih nama perangkat dari Sensus' : 'Nama: ${selectedTitleResident!['nama']}'),
                    ))
                  else
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
                  ...definitions.where((field) => field.key != 'fotoUrl' && field.key != 'ketuaUid' &&
                      !(module.keyName == 'sensus' && ['statusArsip','tanggalArsip','alamatTujuan'].contains(field.key) && (controllers['statusWarga']?.text ?? 'Aktif') != 'Arsip')).map((field) {
                    if (isAdmin && module.keyName == 'organisasi' && field.key == 'anggota') {
                      return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(field.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.group_add_outlined),
                          onPressed: () async {
                            final picked = await showResidentMultiPicker(sheetContext, residentOptions,
                              selectedWargaIds: selectedOrganizationMembers.map((e) => (e['wargaId'] ?? '').toString()).toList());
                            if (picked != null) setSheetState(() { selectedOrganizationMembers = picked; organizationMembersTouched = true; });
                          },
                          label: Text('Pilih anggota dari Sensus (${selectedOrganizationMembers.length})'),
                        ),
                      ]));
                    }
                    if (isAdmin && isResidentReferenceField(module.keyName, field.key)) {
                      final selected = selectedResidents[field.key];
                      return Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton.icon(
                        icon: const Icon(Icons.person_search_outlined),
                        onPressed: () async {
                          final picked = await showResidentPicker(sheetContext, residentOptions,
                            selectedWargaId: (selected?['wargaId'] ?? '').toString(),
                            title: 'Pilih ${field.label.toLowerCase()} dari Sensus');
                          if (picked != null) setSheetState(() {
                            selectedResidents[field.key] = picked;
                            controllers[field.key]?.text = (picked['nama'] ?? '').toString();
                            if (['umkm', 'kebersihan', 'perangkat', 'organisasi'].contains(module.keyName) &&
                                (controllers['telepon']?.text ?? '').trim().isEmpty) {
                              controllers['telepon']?.text = (picked['telepon'] ?? '').toString();
                            }
                          });
                        },
                        label: Text(selected != null ? '${field.label}: ${selected['nama']}' : ((initial?['${field.key}WargaId'] ?? '').toString().isNotEmpty ? '${field.label} tersimpan: ${initial?[field.key]} (pilih pengganti bila perlu)' : 'Pilih ${field.label} dari Sensus')),
                      ));
                    }
                    if (module.keyName == 'sensus' && field.key == 'statusWarga') {
                      final current = (controllers[field.key]?.text ?? '').trim();
                      final value = ['arsip','nonaktif','pindah','meninggal'].contains(current.toLowerCase()) ? 'Arsip' : 'Aktif';
                      return Padding(padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<String>(
                        value: value,
                        decoration: InputDecoration(labelText: field.label),
                        items: const [DropdownMenuItem(value: 'Aktif', child: Text('Aktif')), DropdownMenuItem(value: 'Arsip', child: Text('Arsip'))],
                        onChanged: (v) => setSheetState(() { controllers[field.key]!.text = v ?? 'Aktif'; }),
                      ));
                    }
                    if (module.keyName == 'sensus' && field.key == 'statusArsip') {
                      final current = (controllers[field.key]?.text ?? '').trim();
                      final legacyStatus = (initial?['statusWarga'] ?? '').toString().trim();
                      final archiveReason = current.isNotEmpty ? current : (['Pindah','Meninggal'].contains(legacyStatus) ? legacyStatus : null);
                      return Padding(padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<String>(
                        value: ['Pindah', 'Meninggal'].contains(archiveReason) ? archiveReason : null,
                        decoration: InputDecoration(labelText: field.label),
                        items: const [DropdownMenuItem(value: 'Pindah', child: Text('Pindah')), DropdownMenuItem(value: 'Meninggal', child: Text('Meninggal'))],
                        onChanged: (v) => setSheetState(() { controllers[field.key]!.text = v ?? ''; }),
                      ));
                    }
                    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextFormField(
                      controller: controllers[field.key], keyboardType: field.keyboard, maxLines: field.lines,
                      readOnly: module.keyName == 'sensus' && field.key == 'nik' && docId != null,
                      validator: field.required ? (v) => v == null || v.trim().isEmpty ? '${field.label} wajib diisi' : null : null,
                      decoration: InputDecoration(labelText: field.label, hintText: field.hint.isEmpty ? null : field.hint, alignLabelWithHint: field.lines > 1, suffixIcon: module.keyName == 'sensus' && field.key == 'nik' && docId != null ? const Icon(Icons.lock_outline, size: 18) : null),
                    ));
                  }),
                  if (module.keyName == 'sensus' && isOwner && docId == null) ...[
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: StatefulBuilder(
                          builder: (roleContext, setRoleState) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Role warga (khusus Owner)', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              const Text('Warga selalu memiliki role dasar Warga. Pilih jabatan tambahan bila diperlukan.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                              ...const <MapEntry<String, String>>[
                                MapEntry('owner', 'Owner'),
                                MapEntry('admin', 'Admin'),
                                MapEntry('perangkat_kawil', 'Perangkat Kawil'),
                                MapEntry('ketua_rw', 'Ketua RW'),
                                MapEntry('ketua_rt', 'Ketua RT'),
                                MapEntry('petugas_sampah', 'Petugas Sampah'),
                                MapEntry('pemilik_umkm', 'Pemilik UMKM'),
                                MapEntry('pemilik_fasilitas', 'Pemilik Fasilitas'),
                                MapEntry('ketua_organisasi', 'Ketua Organisasi'),
                                MapEntry('ketua_dkm', 'Ketua DKM'),
                              ].map((entry) => CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: selectedRoles.contains(entry.key),
                                title: Text(entry.value),
                                onChanged: (value) => setRoleState(() {
                                  if (value == true) {
                                    selectedRoles.add(entry.key);
                                  } else {
                                    selectedRoles.remove(entry.key);
                                  }
                                  selectedRoles.add('warga');
                                }),
                              )),
                              const Divider(),
                              const Text('Wilayah penugasan', style: TextStyle(fontWeight: FontWeight.bold)),
                              const Text('Isi Kawil, RW, dan RT sesuai jabatan. Ketua RT dibatasi pada RT yang dipilih; Ketua RW mencakup seluruh RT di RW tersebut.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (module.keyName == 'sensus' && !isOwner)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text('Role ditetapkan oleh Owner. Admin hanya dapat memasukkan data warga dan membuat akun login.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ),
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
                      if (module.keyName == 'perangkat' && selectedTitleResident == null &&
                          (initial?['pemegangJabatanWargaId'] ?? initial?['wargaId'] ?? '').toString().isEmpty) {
                        showMessage(sheetContext, 'Pilih nama perangkat dari Data Sensus.');
                        return;
                      }
                      for (final field in definitions.where((f) => isAdmin && isResidentReferenceField(module.keyName, f.key))) {
                        final existingLink = (initial?['${field.key}WargaId'] ?? '').toString();
                        final hasLegacyName = (controllers[field.key]?.text ?? '').trim().isNotEmpty;
                        if (selectedResidents[field.key] == null && (field.required || (existingLink.isEmpty && hasLegacyName))) {
                          showMessage(sheetContext, 'Pilih ${field.label} dari Data Sensus agar nama tidak tersimpan tanpa wargaId.');
                          return;
                        }
                      }
                      if (module.keyName == 'sensus') {
                        final nik = normalizeNik(controllers['nik']?.text ?? '');
                        if (!RegExp(r'^\d{16}$').hasMatch(nik)) {
                          showMessage(sheetContext, 'NIK harus tepat 16 digit angka.');
                          return;
                        }
                        controllers['nik']!.text = nik;
                        if ((controllers['statusWarga']?.text ?? 'Aktif') == 'Arsip' &&
                            (controllers['statusArsip']?.text ?? '').trim().isEmpty) {
                          showMessage(sheetContext, 'Pilih alasan arsip: Pindah atau Meninggal.');
                          return;
                        }
                        if ((controllers['statusWarga']?.text ?? 'Aktif') == 'Arsip' &&
                            (controllers['statusArsip']?.text ?? '') == 'Pindah' &&
                            (controllers['alamatTujuan']?.text ?? '').trim().isEmpty) {
                          showMessage(sheetContext, 'Isi alamat tujuan warga yang pindah.');
                          return;
                        }
                        if (docId == null && (controllers['statusWarga']?.text ?? 'Aktif') == 'Arsip') {
                          showMessage(sheetContext, 'Tambahkan warga sebagai Aktif terlebih dahulu, lalu arsipkan setelah data tersimpan.');
                          return;
                        }
                      }
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
                      if (module.keyName == 'sensus') {
                        payload['nik'] = normalizeNik((payload['nik'] ?? '').toString());
                        payload['statusWarga'] = (payload['statusWarga'] ?? 'Aktif').toString().trim().isEmpty ? 'Aktif' : payload['statusWarga'];
                        final kawilLabel = (payload['kawil'] ?? '').toString();
                        final rwLabel = (payload['rw'] ?? '').toString();
                        final rtLabel = (payload['rt'] ?? '').toString();
                        final kawilId = _wilayahId('KAWIL', '', kawilLabel, oldLabel: (initial?['kawil'] ?? '').toString(), oldId: (initial?['kawilId'] ?? '').toString());
                        final rwId = _wilayahId('RW', kawilId, rwLabel, oldLabel: (initial?['rw'] ?? '').toString(), oldId: (initial?['rwId'] ?? '').toString());
                        final rtId = _wilayahId('RT', rwId, rtLabel, oldLabel: (initial?['rt'] ?? '').toString(), oldId: (initial?['rtId'] ?? '').toString());
                        payload['kawilId'] = kawilId;
                        payload['rwId'] = rwId;
                        payload['rtId'] = rtId;
                        if (payload['statusWarga'] == 'Arsip' && (payload['tanggalArsip'] ?? '').toString().trim().isEmpty) {
                          final now = DateTime.now();
                          payload['tanggalArsip'] = '${now.day.toString().padLeft(2,'0')}-${now.month.toString().padLeft(2,'0')}-${now.year}';
                        }
                      }
                      if (module.keyName == 'perangkat' && selectedTitleResident != null) {
                        final resident = selectedTitleResident!;
                        payload['nama'] = (resident['nama'] ?? '').toString();
                        payload['judul'] = (resident['nama'] ?? '').toString();
                        payload['wargaId'] = resident['wargaId'];
                        payload['pemegangJabatanWargaId'] = resident['wargaId'];
                      }
                      for (final entry in selectedResidents.entries) {
                        final resident = entry.value;
                        payload[entry.key] = (resident['nama'] ?? '').toString();
                        payload['${entry.key}WargaId'] = resident['wargaId'];
                        if (module.keyName == 'organisasi' && entry.key == 'ketua') {
                          payload['ketuaUid'] = (resident['accountUid'] ?? '').toString();
                        }
                        if (module.keyName == 'umkm' && entry.key == 'pemilik') {
                          // UID dipertahankan untuk kompatibilitas ringkasan UMKM di dashboard;
                          // wargaId tetap menjadi penghubung identitas utama.
                          payload['pemilikUid'] = (resident['accountUid'] ?? '').toString();
                        }
                      }
                      if (isAdmin && module.keyName == 'organisasi' && organizationMembersTouched) {
                        payload['anggotaWarga'] = selectedOrganizationMembers.map((r) => {
                          'wargaId': r['wargaId'], 'nama': r['nama'],
                        }).toList();
                        payload['anggotaWargaIds'] = selectedOrganizationMembers.map((r) => r['wargaId']).toList();
                        payload['anggota'] = selectedOrganizationMembers.map((r) => r['nama']).join(', ');
                        final ketua = selectedResidents['ketua'];
                        if (ketua != null) payload['ketuaUid'] = (ketua['accountUid'] ?? '').toString();
                      }
                      if (module.keyName == 'umkm') {
                        payload['pemilikNamaSnapshot'] = payload['pemilik'];
                        final newOwner = selectedResidents['pemilik'];
                        if (newOwner != null) {
                          final newOwnerId = (newOwner['wargaId'] ?? '').toString();
                          final oldOwnerResolved = resolveResident(residentOptions,
                            (initial?['pemilikWargaId'] ?? '').toString(), (initial?['pemilik'] ?? '').toString());
                          final oldOwnerId = (oldOwnerResolved?['wargaId'] ?? initial?['pemilikWargaId'] ?? '').toString();
                          final history = <Map<String, dynamic>>[];
                          final oldHistory = initial?['riwayatPemilik'];
                          if (oldHistory is List) {
                            for (final item in oldHistory) { if (item is Map) history.add(Map<String, dynamic>.from(item)); }
                          }
                          if (docId == null) {
                            final now = Timestamp.now();
                            history.add({'wargaId': newOwnerId, 'nama': newOwner['nama'] ?? '', 'mulaiPada': now, 'selesaiPada': null, 'status': 'Pemilik saat ini'});
                            payload['pemilikMulaiPada'] = now;
                          } else if (oldOwnerId.isNotEmpty && oldOwnerId != newOwnerId) {
                            final oldName = (oldOwnerResolved?['nama'] ?? initial?['pemilik'] ?? initial?['pemilikNamaSnapshot'] ?? '').toString();
                            final now = Timestamp.now();
                            history.add({'wargaId': oldOwnerId, 'nama': oldName, 'mulaiPada': initial?['pemilikMulaiPada'], 'selesaiPada': now, 'status': 'Pemilik sebelumnya'});
                            history.add({'wargaId': newOwnerId, 'nama': newOwner['nama'] ?? '', 'mulaiPada': now, 'selesaiPada': null, 'status': 'Pemilik saat ini'});
                            payload['pemilikMulaiPada'] = now;
                          } else if (history.isEmpty) {
                            final now = Timestamp.now();
                            history.add({'wargaId': newOwnerId, 'nama': newOwner['nama'] ?? '', 'mulaiPada': now, 'selesaiPada': null, 'status': 'Pemilik saat ini'});
                            payload['pemilikMulaiPada'] = now;
                          }
                          payload['riwayatPemilik'] = history;
                        }
                      }
                      // Field lama tetap dipertahankan agar daftar dan dashboard yang
                      // sudah ada tetap dapat membaca data dengan format sebelumnya.
                      payload['deskripsi'] ??= '';
                      payload['keterangan'] ??= payload['deskripsi'];
                        if (docId == null) {
                          payload['createdAt'] = FieldValue.serverTimestamp();
                          payload['createdBy'] = Db.auth.currentUser?.uid;
                          DocumentReference<Map<String, dynamic>> savedDoc;
                          if (module.keyName == 'sensus') {
                            savedDoc = Db.module('sensus').doc();
                            final nik = (payload['nik'] ?? '').toString();
                            final allSensus = await Db.module('sensus').get();
                            final duplicateDocs = allSensus.docs.where((d) => normalizeNik((d.data()['nik'] ?? '').toString()) == nik).toList();
                            if (duplicateDocs.isNotEmpty) throw Exception('NIK sudah terdaftar atas nama ${(duplicateDocs.first.data()['nama'] ?? 'warga lain')}. Gunakan data Sensus yang sudah ada.');
                            final indexRef = Db.firestore.collection('kampung').doc('kiarajangkung').collection('sensus_nik_index').doc(nik);
                            await Db.firestore.runTransaction((tx) async {
                              final indexSnap = await tx.get(indexRef);
                              if (indexSnap.exists) throw Exception('NIK sudah digunakan oleh data warga lain.');
                              payload['wargaId'] = savedDoc.id;
                              payload['roles'] = isOwner ? <String>{'warga', ...selectedRoles}.toList() : <String>['warga'];
                              tx.set(savedDoc, payload);
                              tx.set(indexRef, {'nik': nik, 'wargaId': savedDoc.id, 'createdAt': FieldValue.serverTimestamp()});
                            });
                          } else {
                            savedDoc = await Db.module(module.keyName).add(payload);
                          }
                          if (module.keyName == 'sensus') {
                            final assignedRoles = isOwner ? <String>{'warga', ...selectedRoles}.toList() : <String>['warga'];
                            try {
                              final account = await PhotoService.provisionResident(
                                nik: (payload['nik'] ?? '').toString().trim(), nama: title.text.trim(),
                                tanggalLahir: (payload['tanggalLahir'] ?? '').toString().trim(),
                                telepon: (payload['telepon'] ?? '').toString(), alamat: (payload['alamat'] ?? '').toString(), rt: (payload['rt'] ?? '').toString(),
                                rw: (payload['rw'] ?? '').toString(), kawil: (payload['kawil'] ?? '').toString(),
                                kawilId: (payload['kawilId'] ?? '').toString(), rwId: (payload['rwId'] ?? '').toString(), rtId: (payload['rtId'] ?? '').toString(),
                                wargaId: savedDoc.id, roles: assignedRoles,
                              );
                              await savedDoc.update({'accountUid': (account['uid'] ?? '').toString(), 'akunStatus': 'Aktif'});
                              if (context.mounted) showMessage(context, 'Data Sensus tersimpan dan akun warga berhasil dibuat.');
                            } catch (accountError) {
                              await savedDoc.update({'akunStatus': 'Gagal dibuat'});
                              if (context.mounted) showMessage(context, 'Data Sensus tersimpan, tetapi akun belum berhasil dibuat: $accountError');
                            }
                            await writeWargaAudit(wargaId: savedDoc.id, modul: 'sensus', aksi: 'data warga ditambahkan', peran: 'identitas', namaWarga: title.text.trim(), recordId: savedDoc.id);
                          }
                          if (module.keyName == 'perangkat' && selectedTitleResident != null) {
                            await writeWargaAudit(wargaId: (selectedTitleResident!['wargaId'] ?? '').toString(), modul: module.keyName, aksi: 'ditambahkan', peran: (payload['jabatan'] ?? '').toString(), namaWarga: (selectedTitleResident!['nama'] ?? '').toString(), recordId: savedDoc.id);
                          }
                          for (final entry in selectedResidents.entries) {
                            await writeWargaAudit(wargaId: (entry.value['wargaId'] ?? '').toString(), modul: module.keyName, aksi: 'ditambahkan', peran: entry.key, namaWarga: (entry.value['nama'] ?? '').toString(), recordId: savedDoc.id);
                          }
                          for (final resident in selectedOrganizationMembers) {
                            await writeWargaAudit(wargaId: (resident['wargaId'] ?? '').toString(), modul: module.keyName, aksi: 'ditambahkan sebagai anggota', peran: 'anggota', namaWarga: (resident['nama'] ?? '').toString(), recordId: savedDoc.id);
                          }
                        } else {
                          final recordRef = Db.module(module.keyName).doc(docId);
                          if (module.keyName == 'sensus') {
                            final nik = (payload['nik'] ?? '').toString();
                            final oldNik = normalizeNik((initial?['nik'] ?? '').toString());
                            final allSensus = await Db.module('sensus').get();
                            if (allSensus.docs.any((d) => d.id != docId && normalizeNik((d.data()['nik'] ?? '').toString()) == nik)) throw Exception('NIK sudah dipakai oleh warga lain.');
                            final newIndexRef = Db.firestore.collection('kampung').doc('kiarajangkung').collection('sensus_nik_index').doc(nik);
                            final oldIndexRef = oldNik.isEmpty ? null : Db.firestore.collection('kampung').doc('kiarajangkung').collection('sensus_nik_index').doc(oldNik);
                            await Db.firestore.runTransaction((tx) async {
                              final newIndex = await tx.get(newIndexRef);
                              final oldIndex = oldIndexRef != null && oldNik != nik ? await tx.get(oldIndexRef) : null;
                              if (newIndex.exists && (newIndex.data()?['wargaId'] ?? '') != docId) throw Exception('NIK sudah digunakan oleh warga lain.');
                              tx.update(recordRef, payload);
                              tx.set(newIndexRef, {'nik': nik, 'wargaId': docId, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                              if (oldIndexRef != null && oldNik != nik && oldIndex != null && oldIndex.exists && (oldIndex.data()?['wargaId'] ?? '') == docId) tx.delete(oldIndexRef);
                            });
                            final syncedData = <String, dynamic>{...?initial, ...payload, 'accountUid': initial?['accountUid'] ?? ''};
                            await syncAccountProfileFromSensus(docId, syncedData);
                            final accountUid = (initial?['accountUid'] ?? '').toString();
                            if (payload['statusWarga'] == 'Arsip' && accountUid.isNotEmpty) {
                              final accountSnap = await Db.user(accountUid).get();
                              final accountData = accountSnap.data() ?? <String, dynamic>{};
                              if ((accountData['status'] ?? 'Aktif') == 'Aktif') {
                                await recordRef.update({'statusAkunSebelumArsip': 'Aktif'});
                                await Db.user(accountUid).update({'status': 'Nonaktif', 'updatedAt': FieldValue.serverTimestamp()});
                              }
                            } else if (payload['statusWarga'] == 'Aktif' && initial?['statusWarga'] == 'Arsip' && accountUid.isNotEmpty && initial?['statusAkunSebelumArsip'] == 'Aktif') {
                              await Db.user(accountUid).update({'status': 'Aktif', 'updatedAt': FieldValue.serverTimestamp()});
                            }
                            await writeWargaAudit(wargaId: docId, modul: 'sensus', aksi: payload['statusWarga'] == 'Arsip' && initial?['statusWarga'] != 'Arsip' ? 'warga diarsipkan' : 'data identitas diperbarui', peran: 'identitas', namaWarga: (payload['nama'] ?? '').toString(), recordId: docId);
                          } else {
                            await recordRef.update(payload);
                          }
                          final oldPhoto = (initial?['fotoUrl'] ?? initial?['foto'] ?? initial?['imageUrl'] ?? '').toString();
                          if (oldPhoto.isNotEmpty && oldPhoto != finalPhotoUrl) await PhotoService.deleteIfOwned(oldPhoto);
                          if (module.keyName == 'perangkat' && selectedTitleResident != null) {
                            await writeWargaAudit(wargaId: (selectedTitleResident!['wargaId'] ?? '').toString(), modul: module.keyName, aksi: 'diperbarui', peran: (payload['jabatan'] ?? '').toString(), namaWarga: (selectedTitleResident!['nama'] ?? '').toString(), recordId: docId);
                          }
                          if (module.keyName == 'umkm') {
                            final oldOwnerId = (initial?['pemilikWargaId'] ?? '').toString();
                            final oldOwnerName = (initial?['pemilik'] ?? '').toString();
                            final newOwner = selectedResidents['pemilik'];
                            if (oldOwnerId.isNotEmpty && newOwner != null && oldOwnerId != (newOwner['wargaId'] ?? '').toString()) {
                              await writeWargaAudit(wargaId: oldOwnerId, modul: 'umkm', aksi: 'kepemilikan berakhir', peran: 'pemilik lama', namaWarga: oldOwnerName, recordId: docId);
                              await writeWargaAudit(wargaId: (newOwner['wargaId'] ?? '').toString(), modul: 'umkm', aksi: 'menjadi pemilik', peran: 'pemilik baru', namaWarga: (newOwner['nama'] ?? '').toString(), recordId: docId);
                            }
                          }
                          for (final entry in selectedResidents.entries) {
                            await writeWargaAudit(wargaId: (entry.value['wargaId'] ?? '').toString(), modul: module.keyName, aksi: 'diperbarui', peran: entry.key, namaWarga: (entry.value['nama'] ?? '').toString(), recordId: docId);
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

class ArchivedResidentsPage extends StatelessWidget {
  final bool isAdmin;
  const ArchivedResidentsPage({super.key, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) return const Scaffold(body: Center(child: Text('Akses hanya untuk Admin/Owner.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Arsip Warga')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.module('sensus').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Gagal memuat arsip: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs.where((d) => isArchivedResident(d.data())).toList();
          if (docs.isEmpty) return const Center(child: Text('Belum ada warga yang diarsipkan.'));
          return ListView.builder(
            padding: const EdgeInsets.all(12), itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i]; final d = doc.data();
              return Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.archive_outlined)),
                title: Text((d['nama'] ?? 'Tanpa nama').toString()),
                subtitle: Text('${d['statusArsip'] ?? 'Alasan tidak dicatat'} • NIK ${d['nik'] ?? '-'}\nTanggal arsip: ${d['tanggalArsip'] ?? '-'}'),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(onSelected: (v) async {
                  if (v == 'restore') {
                    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                      title: const Text('Aktifkan kembali warga?'),
                      content: Text('Data ${(d['nama'] ?? '').toString()} akan kembali ke daftar warga aktif. Riwayat arsip tetap disimpan.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aktifkan'))],
                    ));
                    if (yes == true) {
                      await doc.reference.update({'statusWarga': 'Aktif', 'diaktifkanKembaliPada': FieldValue.serverTimestamp(), 'diaktifkanKembaliOleh': Db.auth.currentUser?.uid, 'updatedAt': FieldValue.serverTimestamp()});
                      final accountUid = (d['accountUid'] ?? '').toString();
                      if (accountUid.isNotEmpty && d['statusAkunSebelumArsip'] == 'Aktif') {
                        await Db.user(accountUid).update({'status': 'Aktif', 'updatedAt': FieldValue.serverTimestamp()});
                      }
                      await writeWargaAudit(wargaId: doc.id, modul: 'sensus', aksi: 'diaktifkan kembali dari arsip', peran: 'status warga', namaWarga: (d['nama'] ?? '').toString());
                      if (context.mounted) showMessage(context, 'Warga berhasil diaktifkan kembali.');
                    }
                  }
                }, itemBuilder: (_) => const [PopupMenuItem(value: 'restore', child: Text('Aktifkan kembali'))]),
              ));
            },
          );
        },
      ),
    );
  }
}

Future<Map<String, int>> runLegacyWargaMigration() async {
  final census = await Db.module('sensus').get();
  final residents = census.docs.map((d) => <String, dynamic>{...d.data(), 'wargaId': d.id}).toList();
  final byName = <String, List<Map<String, dynamic>>>{};
  for (final r in residents) {
    final key = (r['nama'] ?? '').toString().trim().toLowerCase();
    if (key.isNotEmpty) (byName[key] ??= <Map<String, dynamic>>[]).add(r);
  }
  Map<String, dynamic>? unique(String name) {
    final matches = byName[name.trim().toLowerCase()] ?? const <Map<String, dynamic>>[];
    return matches.length == 1 ? matches.first : null;
  }

  final report = <String, int>{'diperiksa': 0, 'diperbarui': 0, 'ambiguAtauTidakCocok': 0, 'indeksNIKDibuat': 0, 'NIKGanda': 0, 'statusAktifDiisi': 0};
  WriteBatch? censusBatch; var censusBatchCount = 0;
  for (final doc in census.docs) {
    final data = doc.data();
    final patch = <String, dynamic>{};
    if ((data['wargaId'] ?? '').toString().isEmpty) patch['wargaId'] = doc.id;
    if ((data['statusWarga'] ?? '').toString().trim().isEmpty) { patch['statusWarga'] = 'Aktif'; report['statusAktifDiisi'] = report['statusAktifDiisi']! + 1; }
    final kawilId = _wilayahId('KAWIL', '', (data['kawil'] ?? '').toString(), oldLabel: (data['kawil'] ?? '').toString(), oldId: (data['kawilId'] ?? '').toString());
    final rwId = _wilayahId('RW', kawilId, (data['rw'] ?? '').toString(), oldLabel: (data['rw'] ?? '').toString(), oldId: (data['rwId'] ?? '').toString());
    final rtId = _wilayahId('RT', rwId, (data['rt'] ?? '').toString(), oldLabel: (data['rt'] ?? '').toString(), oldId: (data['rtId'] ?? '').toString());
    if ((data['kawilId'] ?? '').toString() != kawilId) patch['kawilId'] = kawilId;
    if ((data['rwId'] ?? '').toString() != rwId) patch['rwId'] = rwId;
    if ((data['rtId'] ?? '').toString() != rtId) patch['rtId'] = rtId;
    final accountUid = (data['accountUid'] ?? '').toString();
    if (accountUid.isNotEmpty) {
      final userRef = Db.user(accountUid);
      final userSnap = await userRef.get();
      if (userSnap.exists) {
        final userData = userSnap.data() ?? <String, dynamic>{};
        final userPatch = <String, dynamic>{};
        if ((userData['kawilId'] ?? '').toString().isEmpty) userPatch['kawilId'] = kawilId;
        if ((userData['rwId'] ?? '').toString().isEmpty) userPatch['rwId'] = rwId;
        if ((userData['rtId'] ?? '').toString().isEmpty) userPatch['rtId'] = rtId;
        if (userPatch.isNotEmpty) await userRef.update(userPatch);
      }
    }
    if (patch.isNotEmpty) {
      censusBatch ??= Db.firestore.batch();
      censusBatch.update(doc.reference, patch); censusBatchCount++;
      if (censusBatchCount >= 400) { await censusBatch.commit(); censusBatch = null; censusBatchCount = 0; }
    }
  }
  if (censusBatch != null && censusBatchCount > 0) await censusBatch.commit();
  final nikGroups = <String, List<Map<String, dynamic>>>{};
  for (final resident in residents) {
    final nik = normalizeNik((resident['nik'] ?? '').toString());
    if (RegExp(r'^\d{16}$').hasMatch(nik)) (nikGroups[nik] ??= <Map<String, dynamic>>[]).add(resident);
  }
  WriteBatch? nikBatch; var nikBatchCount = 0;
  for (final entry in nikGroups.entries) {
    if (entry.value.length != 1) { report['NIKGanda'] = report['NIKGanda']! + entry.value.length; continue; }
    final resident = entry.value.single;
    final indexRef = Db.module('sensus_nik_index').doc(entry.key);
    final indexSnap = await indexRef.get();
    if (indexSnap.exists && (indexSnap.data()?['wargaId'] ?? '') != (resident['wargaId'] ?? '')) {
      report['NIKGanda'] = report['NIKGanda']! + 1;
      continue;
    }
    if (!indexSnap.exists) {
      nikBatch ??= Db.firestore.batch();
      nikBatch.set(indexRef, {'nik': entry.key, 'wargaId': resident['wargaId'], 'createdAt': FieldValue.serverTimestamp(), 'migrated': true});
      nikBatchCount++; report['indeksNIKDibuat'] = report['indeksNIKDibuat']! + 1;
      if (nikBatchCount >= 400) { await nikBatch.commit(); nikBatch = null; nikBatchCount = 0; }
    }
  }
  if (nikBatch != null && nikBatchCount > 0) await nikBatch.commit();
  final configs = <String, List<String>>{
    'umkm': ['pemilik'],
    'sarana': ['pengelola'],
    'kesenian': ['ketua'],
    'kebersihan': ['petugas'],
    'fasilitas_kesehatan': ['penanggungJawab'],
    'organisasi': ['ketua', 'wakil', 'sekretaris', 'bendahara'],
  };
  for (final entry in configs.entries) {
    final docs = await Db.module(entry.key).get();
    WriteBatch? batch;
    var batchCount = 0;
    for (final doc in docs.docs) {
      report['diperiksa'] = report['diperiksa']! + 1;
      final data = doc.data();
      final updates = <String, dynamic>{};
      for (final field in entry.value) {
        final existingId = (data['${field}WargaId'] ?? '').toString();
        final name = (data[field] ?? '').toString().trim();
        if (existingId.isNotEmpty || name.isEmpty) continue;
        final resident = unique(name);
        if (resident == null) { report['ambiguAtauTidakCocok'] = report['ambiguAtauTidakCocok']! + 1; continue; }
        updates['${field}WargaId'] = resident['wargaId'];
        if (entry.key == 'organisasi' && field == 'ketua') updates['ketuaUid'] = resident['accountUid'] ?? '';
        if (entry.key == 'umkm' && field == 'pemilik') updates['pemilikUid'] = resident['accountUid'] ?? '';
      }
      if (entry.key == 'organisasi' && data['anggotaWarga'] == null) {
        final names = (data['anggota'] ?? '').toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (names.isNotEmpty) {
          final members = <Map<String, dynamic>>[]; var allMatched = true;
          for (final name in names) {
            final resident = unique(name);
            if (resident == null) { allMatched = false; report['ambiguAtauTidakCocok'] = report['ambiguAtauTidakCocok']! + 1; break; }
            members.add({'wargaId': resident['wargaId'], 'nama': resident['nama']});
          }
          if (allMatched) { updates['anggotaWarga'] = members; updates['anggotaWargaIds'] = members.map((m) => m['wargaId']).toList(); }
        }
      }
      if (updates.isNotEmpty) {
        batch ??= Db.firestore.batch();
        batch.update(doc.reference, updates); batchCount++; report['diperbarui'] = report['diperbarui']! + 1;
        if (batchCount >= 400) { await batch.commit(); batch = null; batchCount = 0; }
      }
    }
    if (batch != null && batchCount > 0) await batch.commit();
  }

  // Perangkat menyimpan nama pemegang jabatan pada judul/nama.
  final perangkatDocs = await Db.module('perangkat').get();
  WriteBatch? perangkatBatch; var perangkatCount = 0;
  for (final doc in perangkatDocs.docs) {
    report['diperiksa'] = report['diperiksa']! + 1;
    final d = doc.data();
    if ((d['pemegangJabatanWargaId'] ?? d['wargaId'] ?? '').toString().isNotEmpty) continue;
    final name = (d['nama'] ?? d['judul'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final resident = unique(name);
    if (resident == null) { report['ambiguAtauTidakCocok'] = report['ambiguAtauTidakCocok']! + 1; continue; }
    perangkatBatch ??= Db.firestore.batch();
    perangkatBatch.update(doc.reference, {'wargaId': resident['wargaId'], 'pemegangJabatanWargaId': resident['wargaId']});
    perangkatCount++; report['diperbarui'] = report['diperbarui']! + 1;
    if (perangkatCount >= 400) { await perangkatBatch.commit(); perangkatBatch = null; perangkatCount = 0; }
  }
  if (perangkatBatch != null && perangkatCount > 0) await perangkatBatch.commit();

  await Db.module('riwayat_perubahan').add({
    'modul': 'migrasi_satu_data', 'aksi': 'migrasi data lama', 'ringkasan': report,
    'uid': Db.auth.currentUser?.uid ?? '', 'waktu': FieldValue.serverTimestamp(),
  });
  return report;
}

class MigrasiSatuDataPage extends StatefulWidget {
  final bool isAdmin;
  const MigrasiSatuDataPage({super.key, required this.isAdmin});
  @override State<MigrasiSatuDataPage> createState() => _MigrasiSatuDataPageState();
}

class _ImportRow {
  final int rowNumber;
  final Map<String, dynamic> data;
  String status;
  String message;
  String? matchedId;
  _ImportRow(this.rowNumber, this.data, this.status, this.message, {this.matchedId});
  bool get ready => status == 'COCOK' || status == 'BARU';
}

class _MigrasiSatuDataPageState extends State<MigrasiSatuDataPage> {
  final _config = Db.firestore.collection('system_config').doc('sensus_migration');
  final List<_ImportRow> _rows = [];
  bool _busy = false;
  String _fileName = '';
  String _filter = 'SEMUA';
  Map<String, int>? _legacyReport;
  int get _readyCount => _rows.where((e) => e.ready).length;
  int get _errorCount => _rows.length - _readyCount;

  static const _headers = <String>[
    'wargaId','NIK','No_KK','Nama_Lengkap','Nama_Panggilan','Jenis_Kelamin','Tempat_Lahir','Tanggal_Lahir','Agama','Status_Perkawinan','Hubungan_Dalam_KK','Pendidikan','Pekerjaan','No_HP','Kawil','RW','RT','Alamat','Status_Warga','Keterangan'
  ];
  static const _map = <String,String>{
    'wargaId':'wargaId','NIK':'nik','No_KK':'noKK','Nama_Lengkap':'nama','Nama_Panggilan':'namaPanggilan','Jenis_Kelamin':'jenisKelamin','Tempat_Lahir':'tempatLahir','Tanggal_Lahir':'tanggalLahir','Agama':'agama','Status_Perkawinan':'statusPerkawinan','Hubungan_Dalam_KK':'hubunganKeluarga','Pendidikan':'pendidikan','Pekerjaan':'pekerjaan','No_HP':'telepon','Kawil':'kawil','RW':'rw','RT':'rt','Alamat':'alamat','Status_Warga':'statusWarga','Keterangan':'keterangan'
  };

  String _cellText(xls.Data? cell) => cell?.value?.toString().trim() ?? '';
  String _norm(String value) => value.replaceAll(RegExp(r'\D'), '');

  Future<void> _pickAndCheckExcel() async {
    if (!widget.isAdmin || _busy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
      if (picked == null || picked.files.single.bytes == null) return;
      setState(() { _busy = true; _rows.clear(); _fileName = picked.files.single.name; });
      final excel = xls.Excel.decodeBytes(picked.files.single.bytes!);
      if (excel.tables.isEmpty) throw Exception('File Excel tidak memiliki sheet.');
      final sheet = excel.tables['DATA_WARGA'] ?? excel.tables.values.first;
      if (sheet.rows.isEmpty) throw Exception('Sheet DATA_WARGA kosong.');
      final headerRow = sheet.rows.first.map(_cellText).toList();
      final indexes = <String,int>{for (var i=0;i<headerRow.length;i++) headerRow[i]:i};
      for (final required in ['NIK','Nama_Lengkap']) { if (!indexes.containsKey(required)) throw Exception('Kolom wajib $required tidak ditemukan. Gunakan template Sensus.'); }
      final existingSnap = await Db.module('sensus').get();
      final byNik = <String,List<QueryDocumentSnapshot<Map<String,dynamic>>>>{};
      for (final doc in existingSnap.docs) {
        final nik = _norm((doc.data()['nik'] ?? '').toString());
        if (nik.isNotEmpty) (byNik[nik] ??= []).add(doc);
      }
      final seenNik = <String,int>{};
      final parsed = <_ImportRow>[];
      for (var i=1;i<sheet.rows.length;i++) {
        final cells = sheet.rows[i];
        if (cells.every((c) => _cellText(c).isEmpty)) continue;
        final rowData = <String,dynamic>{};
        for (final h in _headers) {
          final idx = indexes[h];
          final value = idx == null || idx >= cells.length ? '' : _cellText(cells[idx]);
          final key = _map[h]!;
          if (value.isNotEmpty) rowData[key] = value;
        }
        final nik = _norm((rowData['nik'] ?? '').toString());
        final name = (rowData['nama'] ?? '').toString().trim();
        String status, message; String? matchedId;
        if (nik.isEmpty || nik.length != 16 || name.isEmpty) {
          status='TIDAK VALID'; message=nik.isEmpty ? 'NIK kosong; tidak dapat dicocokkan otomatis.' : (nik.length != 16 ? 'NIK harus 16 digit.' : 'Nama lengkap wajib diisi.');
        } else if (seenNik.containsKey(nik)) {
          status='DATA GANDA'; message='NIK juga muncul pada baris ${seenNik[nik]}. Periksa data xls.Excel.';
        } else {
          seenNik[nik]=i+1;
          final explicitId=(rowData['wargaId'] ?? '').toString();
          final candidates = explicitId.isNotEmpty
              ? existingSnap.docs.where((d)=>d.id==explicitId).toList()
              : (byNik[nik] ?? []);
          if (candidates.length > 1) { status='AMBIGU'; message='Ditemukan lebih dari satu warga dengan NIK ini.'; }
          else if (candidates.length == 1) {
            final existingNik = _norm((candidates.first.data()['nik'] ?? '').toString());
            final oldName=(candidates.first.data()['nama'] ?? '').toString().trim().toLowerCase();
            if (explicitId.isNotEmpty && existingNik != nik) {
              status='TIDAK COCOK'; message='wargaId ditemukan, tetapi NIK pada Excel berbeda dari NIK Sensus. NIK warga tidak boleh diganti melalui impor.';
            } else if (oldName.isNotEmpty && oldName != name.toLowerCase()) { status='PERLU VERIFIKASI'; message='NIK cocok tetapi nama berbeda: "$oldName".'; matchedId=candidates.first.id; }
            else { status='COCOK'; message='Warga lama ditemukan; pembaruan akan mempertahankan wargaId.'; matchedId=candidates.first.id; }
          } else if (explicitId.isNotEmpty) { status='TIDAK COCOK'; message='wargaId pada Excel tidak ditemukan. Tidak akan membuat warga baru otomatis.'; }
          else { status='BARU'; message='NIK belum ditemukan; siap ditambahkan sebagai warga baru.'; }
        }
        parsed.add(_ImportRow(i+1,rowData,status,message,matchedId:matchedId));
      }
      if (mounted) {
        setState(() => _rows.addAll(parsed));
        await _config.set({
          'lockResidentEdits': true,
          'lockMessage': 'Pembaruan Data Sensus sedang berlangsung. Perubahan data pribadi sementara dikunci. Silakan coba kembali setelah proses selesai.',
          'lockUpdatedAt': FieldValue.serverTimestamp(),
          'lockUpdatedBy': Db.auth.currentUser?.uid ?? '',
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Gagal membaca Excel: $e');
    } finally { if (mounted) setState(() => _busy=false); }
  }

  Future<void> _exportExcel({bool templateOnly=false, bool errorsOnly=false, String kawil='', String rw='', String rt=''}) async {
    if (!widget.isAdmin || _busy) return;
    setState(()=>_busy=true);
    try {
      final excel=xls.Excel.createExcel();
      final sheet=excel['DATA_WARGA'];
      sheet.appendRow(_headers.map((e)=>xls.TextCellValue(e)).toList());
      if (!templateOnly && !errorsOnly) {
        final snap=await Db.module('sensus').get();
        for (final doc in snap.docs) {
          final d=doc.data();
          if(kawil.isNotEmpty && (d['kawil']??'').toString()!=kawil) continue;
          if(rw.isNotEmpty && (d['rw']??'').toString()!=rw) continue;
          if(rt.isNotEmpty && (d['rt']??'').toString()!=rt) continue;
          final values=<String,dynamic>{'wargaId':doc.id,...d};
          sheet.appendRow(_headers.map((h)=>xls.TextCellValue((values[_map[h]] ?? '').toString())).toList());
        }
      }
      if (errorsOnly) {
        final report=excel['HASIL_PEMERIKSAAN'];
        report.appendRow(['Baris Excel','Nama','NIK','Status','Keterangan'].map((e)=>xls.TextCellValue(e)).toList());
        for(final row in _rows.where((e)=>!e.ready)) {
          report.appendRow([xls.TextCellValue(row.rowNumber.toString()),xls.TextCellValue((row.data['nama']??'').toString()),xls.TextCellValue((row.data['nik']??'').toString()),xls.TextCellValue(row.status),xls.TextCellValue(row.message)]);
        }
      }
      final ref=excel['REFERENSI'];
      ref.appendRow([xls.TextCellValue('Petunjuk'),xls.TextCellValue('Isi NIK sebagai teks 16 digit. Jangan mengubah wargaId pada data hasil ekspor.')]);
      final bytes=excel.encode();
      if (bytes==null) throw Exception('Gagal membuat file xls.Excel.');
      final path=await FilePicker.platform.saveFile(fileName:templateOnly?'Template_Sensus_Warga.xlsx':(errorsOnly?'Laporan_Pemeriksaan_Sensus.xlsx':'Ekspor_Sensus_Warga.xlsx'),bytes:Uint8List.fromList(bytes));
      if (path!=null && mounted) showMessage(context,'File Excel berhasil disiapkan.');
    } catch(e) { if(mounted) showMessage(context,'Gagal ekspor Excel: $e'); }
    finally { if(mounted) setState(()=>_busy=false); }
  }

  Future<void> _chooseExportScope() async {
    final kawil=TextEditingController(); final rw=TextEditingController(); final rt=TextEditingController();
    final result=await showDialog<List<String>?>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Pilih wilayah ekspor'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:kawil,decoration:const InputDecoration(labelText:'Kawil / Dusun (kosong = semua)')),
        const SizedBox(height:8),TextField(controller:rw,decoration:const InputDecoration(labelText:'RW (kosong = semua)')),
        const SizedBox(height:8),TextField(controller:rt,decoration:const InputDecoration(labelText:'RT (kosong = semua)')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,[kawil.text.trim(),rw.text.trim(),rt.text.trim()]),child:const Text('Ekspor'))],
    ));
    kawil.dispose();rw.dispose();rt.dispose();
    if(result!=null) await _exportExcel(kawil:result[0],rw:result[1],rt:result[2]);
  }

  Future<void> _resolveRow(_ImportRow row) async {
    final nik=TextEditingController(text:(row.data['nik']??'').toString());
    final name=TextEditingController(text:(row.data['nama']??'').toString());
    final existing=await Db.module('sensus').get();
    final candidates=existing.docs.where((d)=>_norm((d.data()['nik']??'').toString())==_norm(nik.text)).toList();
    String? selected=row.matchedId;
    if(selected==null && candidates.length==1) selected=candidates.first.id;
    final result=await showDialog<Map<String,String>?>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:Text('Periksa baris ${row.rowNumber}'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:nik,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'NIK (16 digit)')),
        const SizedBox(height:10),TextField(controller:name,decoration:const InputDecoration(labelText:'Nama lengkap')),
        if(candidates.isNotEmpty) ...[
          const SizedBox(height:12),const Align(alignment:Alignment.centerLeft,child:Text('Pilih data Sensus yang dimaksud:')),
          DropdownButtonFormField<String>(value:selected,items:candidates.map((d)=>DropdownMenuItem(value:d.id,child:Text('${d.data()['nama']??'Tanpa nama'} • ${d.id}',overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setDialog(()=>selected=v)),
        ],
        const SizedBox(height:8),const Text('Jika NIK cocok tetapi nama berbeda, pastikan identitas benar sebelum mengonfirmasi.',style:TextStyle(fontSize:12)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,{'nik':nik.text.trim(),'nama':name.text.trim(),'selected':selected??''}),child:const Text('Perbarui pemeriksaan'))],
    )));
    nik.dispose();name.dispose();
    if(result==null)return;
    final newNik=_norm(result['nik']??'');final newName=(result['nama']??'').trim();
    if(newNik.length!=16||newName.isEmpty){setState(() { row.status='TIDAK VALID'; row.message='NIK harus 16 digit dan nama wajib diisi.'; row.matchedId=null; });return;}
    final duplicate=_rows.any((r)=>!identical(r,row)&&_norm((r.data['nik']??'').toString())==newNik);
    if(duplicate){setState(() { row.data['nik']=result['nik']; row.data['nama']=newName; row.status='DATA GANDA'; row.message='NIK sama dengan baris lain dalam file xls.Excel.'; row.matchedId=null; });return;}
    final chosen=result['selected']??'';
    final matched=chosen.isNotEmpty?existing.docs.where((d)=>d.id==chosen).toList():existing.docs.where((d)=>_norm((d.data()['nik']??'').toString())==newNik).toList();
    setState(() {
      row.data['nik']=result['nik'];
      row.data['nama']=newName;
      if(matched.length>1){ row.status='AMBIGU'; row.message='Masih ada lebih dari satu data yang cocok.'; row.matchedId=null; }
      else if(matched.length==1){ row.status='COCOK'; row.message='Dikonfirmasi Admin cocok dengan data Sensus ${matched.first.id}.'; row.matchedId=matched.first.id; }
      else if(chosen.isNotEmpty){ row.status='TIDAK COCOK'; row.message='Data Sensus yang dipilih tidak ditemukan.'; row.matchedId=null; }
      else if((row.data['wargaId']??'').toString().isNotEmpty){ row.status='TIDAK COCOK'; row.message='wargaId pada Excel tidak ditemukan dengan NIK tersebut. Hapus/periksa wargaId hanya jika memang membuat warga baru.'; row.matchedId=null; }
      else { row.status='BARU'; row.message='Tidak ditemukan NIK yang sama; siap menjadi warga baru setelah verifikasi.'; row.matchedId=null; }
    });
  }

  Future<void> _applyReady() async {
    final ready = _rows.where((e) => e.ready).toList();
    if (ready.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terapkan data cocok?'),
        content: Text('${ready.length} baris akan diterapkan ke Sensus. Data bermasalah tidak akan diubah. wargaId, akun, dan role yang sudah ada akan dipertahankan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terapkan')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    var count = 0;
    try {
      final censusRef = Db.module('sensus');
      final indexRef = Db.module('sensus_nik_index');
      for (final row in ready) {
        final nik = _norm((row.data['nik'] ?? '').toString());
        if (nik.length != 16) throw Exception('NIK pada baris ${row.rowNumber} tidak valid.');
        final id = row.matchedId ?? ((row.data['wargaId'] ?? '').toString().isNotEmpty
            ? row.data['wargaId'].toString()
            : censusRef.doc().id);
        final residentRef = censusRef.doc(id);
        final newIndexRef = indexRef.doc(nik);
        await Db.firestore.runTransaction((tx) async {
          final residentSnap = await tx.get(residentRef);
          final newIndexSnap = await tx.get(newIndexRef);
          final oldData = residentSnap.data() ?? <String, dynamic>{};
          final oldNik = _norm((oldData['nik'] ?? '').toString());
          final oldIndexRef = oldNik.isNotEmpty && oldNik != nik ? indexRef.doc(oldNik) : null;
          final oldIndexSnap = oldIndexRef == null ? null : await tx.get(oldIndexRef);
          if (newIndexSnap.exists && (newIndexSnap.data()?['wargaId'] ?? '') != id) {
            throw Exception('NIK ${row.data['nik']} sudah terdaftar pada warga lain.');
          }
          if (row.status == 'BARU' && residentSnap.exists) {
            throw Exception('Data baru baris ${row.rowNumber} ternyata memiliki wargaId yang sudah ada. Periksa ulang.');
          }
          final safeData = Map<String, dynamic>.from(row.data)
            ..remove('role')
            ..remove('roles')
            ..remove('accountUid')
            ..remove('akunStatus')
            ..remove('wargaId');
          safeData['nik'] = nik;
          safeData['wargaId'] = id;
          safeData['updatedAt'] = FieldValue.serverTimestamp();
          safeData['updatedBy'] = Db.auth.currentUser?.uid ?? '';
          if (!residentSnap.exists) {
            safeData['createdAt'] = FieldValue.serverTimestamp();
            safeData['createdBy'] = Db.auth.currentUser?.uid ?? '';
            safeData['roles'] = <String>['warga'];
            safeData['akunStatus'] = 'Belum dibuat';
          }
          tx.set(residentRef, safeData, SetOptions(merge: true));
          tx.set(newIndexRef, {
            'nik': nik,
            'wargaId': id,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': Db.auth.currentUser?.uid ?? '',
          }, SetOptions(merge: true));
          if (oldIndexRef != null && oldIndexSnap != null && oldIndexSnap.exists &&
              (oldIndexSnap.data()?['wargaId'] ?? '') == id) {
            tx.delete(oldIndexRef);
          }
        });
        count++;
      }
      var auditOk = true;
      try {
        await Db.module('riwayat_perubahan').add({
          'jenis': 'impor_sensus',
          'jumlah': count,
          'file': _fileName,
          'actorUid': Db.auth.currentUser?.uid ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) { auditOk = false; }
      if (mounted) {
        setState(() => _rows.removeWhere((e) => e.ready));
        showMessage(context, auditOk
            ? 'Berhasil menerapkan $count data cocok/baru.'
            : 'Data diterapkan, tetapi pencatatan riwayat gagal. Periksa izin Firestore.');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Penerapan dihentikan setelah $count data: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setLock(bool value) async {
    try {
      await _config.set({'lockResidentEdits':value,'lockMessage':'Pembaruan Data Sensus sedang berlangsung. Perubahan data pribadi sementara dikunci. Silakan coba kembali setelah proses selesai.','lockUpdatedAt':FieldValue.serverTimestamp(),'lockUpdatedBy':Db.auth.currentUser?.uid ?? ''},SetOptions(merge:true));
      if(mounted)showMessage(context,value?'Penguncian Informasi Diri diaktifkan.':'Penguncian Informasi Diri dinonaktifkan.');
    } catch(e){if(mounted)showMessage(context,'Gagal mengubah penguncian: $e');}
  }

  Future<void> _runLegacyMigration() async {
    if (!widget.isAdmin || _busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Migrasi data modul lama?'),
        content: const Text('Sistem akan menghubungkan data modul lama dengan Sensus jika pasangan warga ditemukan secara unik. Data ambigu atau tidak cocok dilewati dan data lama tidak dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mulai migrasi')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() { _busy = true; _legacyReport = null; });
    try {
      final result = await runLegacyWargaMigration();
      if (mounted) setState(() => _legacyReport = result);
      if (mounted) showMessage(context, 'Migrasi data modul lama selesai.');
    } catch (e) {
      if (mounted) showMessage(context, 'Migrasi data lama gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible=_filter=='SEMUA'?_rows:_rows.where((r)=>r.status==_filter).toList();
    return Scaffold(appBar:AppBar(title:const Text('Migrasi Satu Data Warga')),body:ListView(padding:const EdgeInsets.all(16),children:[
      if (widget.isAdmin) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Migrasi hubungan modul lama', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        const Text('Menghubungkan data UMKM, perangkat, sarana, kesenian, kebersihan, fasilitas kesehatan, dan organisasi ke wargaId Sensus yang cocok.'),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _busy ? null : _runLegacyMigration, icon: const Icon(Icons.hub_outlined), label: const Text('Jalankan migrasi modul lama')),
        if (_legacyReport != null) ...[
          const SizedBox(height: 8),
          Text('Diperiksa: ${_legacyReport!['diperiksa'] ?? 0} • Diperbarui: ${_legacyReport!['diperbarui'] ?? 0}'),
          Text('NIK ganda: ${_legacyReport!['NIKGanda'] ?? 0} • Nama ambigu/tidak cocok: ${_legacyReport!['ambiguAtauTidakCocok'] ?? 0}'),
        ],
      ]))),
      StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:_config.snapshots(),builder:(context,snap){final locked=snap.data?.data()?['lockResidentEdits']==true;return Card(child:SwitchListTile(value:locked,onChanged:_busy?null:_setLock,title:const Text('Kunci perubahan Informasi Diri warga'),subtitle:Text(locked?'Aktif — warga hanya dapat melihat data.':'Nonaktif — warga dapat mengajukan perubahan data.'),secondary:Icon(locked?Icons.lock:Icons.lock_open,color:locked?Colors.orange:Colors.green)));}),
      Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Impor dan ekspor Excel (.xlsx)',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),const SizedBox(height:6),const Text('Gunakan sheet DATA_WARGA. NIK harus 16 digit. wargaId dari hasil ekspor jangan diubah.'),const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:_busy?null:_pickAndCheckExcel,icon:const Icon(Icons.file_upload_outlined),label:const Text('Impor Excel')),OutlinedButton.icon(onPressed:_busy?null:()=>_exportExcel(templateOnly:true),icon:const Icon(Icons.file_download_outlined),label:const Text('Template')),OutlinedButton.icon(onPressed:_busy?null:_chooseExportScope,icon:const Icon(Icons.download),label:const Text('Ekspor Sensus'))])]))),
      if(_busy) const LinearProgressIndicator(),
      if(_fileName.isNotEmpty) Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text('File: $_fileName')),
      if(_rows.isNotEmpty) ...[
        Wrap(spacing:8,runSpacing:8,children:[_summaryChip('Total',_rows.length,Colors.blue),_summaryChip('Siap diterapkan',_readyCount,Colors.green),_summaryChip('Perlu perbaikan',_errorCount,Colors.orange)]),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(value:_filter,decoration:const InputDecoration(labelText:'Filter hasil pemeriksaan'),items:['SEMUA','COCOK','BARU','DATA GANDA','AMBIGU','PERLU VERIFIKASI','TIDAK VALID','TIDAK COCOK'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>_filter=v??'SEMUA')),
        const SizedBox(height:8),
        ...visible.map((r)=>Card(child:ListTile(isThreeLine:true,onTap:()=>_resolveRow(r),title:Text('${r.rowNumber}. ${r.data['nama']??'(tanpa nama)'}'),subtitle:Text('NIK: ${r.data['nik']??'-'}\n${r.message}'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Chip(label:Text(r.status),backgroundColor:r.ready?Colors.green.shade100:Colors.orange.shade100),const Icon(Icons.edit_outlined,size:16)])))),
        const SizedBox(height:10),
        FilledButton.icon(onPressed:_busy||_readyCount==0?null:_applyReady,icon:const Icon(Icons.check_circle_outline),label:Text('Terapkan Semua Data Cocok ($_readyCount)')),
        OutlinedButton.icon(onPressed:_busy?null:()=>_exportExcel(errorsOnly:true),icon:const Icon(Icons.report_outlined),label:const Text('Ekspor laporan kesalahan')),
      ],
      const SizedBox(height:12),
      const Text('Catatan: data dengan NIK kosong, ganda, ambigu, atau nama berbeda tidak diterapkan otomatis. Penerapan mempertahankan ID dokumen warga yang sudah ada.',style:TextStyle(fontSize:12,color:Colors.black54)),
    ]),);
  }
  Widget _summaryChip(String label,int value,Color color)=>Chip(avatar:CircleAvatar(backgroundColor:color,radius:5),label:Text('$label: $value'));
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
            title: const Text('Informasi Diri dari Sensus'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InformasiDiriPage())),
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

class InformasiDiriPage extends StatefulWidget {
  const InformasiDiriPage({super.key});
  @override State<InformasiDiriPage> createState()=>_InformasiDiriPageState();
}
class _InformasiDiriPageState extends State<InformasiDiriPage>{
  DocumentReference<Map<String, dynamic>> get _migrationConfig => Db.firestore.collection('system_config').doc('sensus_migration');
  Future<bool> _isLocked() async {
    final snap = await _migrationConfig.get();
    return snap.data()?['lockResidentEdits'] == true;
  }
  static const locked={'nama','nik','noKK','role','roles','wargaId','accountUid','createdAt','createdBy','updatedAt','updatedBy','akunStatus','kawil','rw','rt','kawilId','rwId','rtId','statusWarga','statusArsip','tanggalArsip','alamatTujuan','statusAkunSebelumArsip'};
  Future<void> edit(Map<String, dynamic> data, String wargaId) async {
    if (await _isLocked()) {
      if (mounted) showMessage(context, 'Pembaruan Data Sensus sedang berlangsung. Perubahan data pribadi sementara dikunci. Silakan coba kembali setelah selesai.');
      return;
    }
    final editable = data.entries
        .where((e) => !locked.contains(e.key) && e.value is String)
        .toList();

    final controllers = <String, TextEditingController>{
      for (final e in editable)
        e.key: TextEditingController(text: e.value.toString()),
    };

    final labels = <String, String>{
      'jenisKelamin': 'Jenis kelamin',
      'tempatLahir': 'Tempat lahir',
      'tanggalLahir': 'Tanggal lahir',
      'telepon': 'Nomor HP / WhatsApp',
      'agama': 'Agama',
      'statusPerkawinan': 'Status perkawinan',
      'pendidikan': 'Pendidikan',
      'pekerjaan': 'Pekerjaan',
      'hubunganKeluarga': 'Hubungan keluarga',
      'kawil': 'Kawil / Dusun',
      'rw': 'RW',
      'rt': 'RT',
      'alamat': 'Alamat',
    };

    bool busy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Perbarui Informasi Diri',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(16),
                      children: editable.map<Widget>((e) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: controllers[e.key],
                            maxLines: 1,
                            decoration: InputDecoration(
                              labelText: labels[e.key] ?? e.key,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setSheet(() => busy = true);
                              try {
                                if (await _isLocked()) {
                                  throw Exception('Pembaruan Data Sensus sedang berlangsung. Perubahan data pribadi sementara dikunci.');
                                }
                                final changes = <String, dynamic>{
                                  for (final e in controllers.entries)
                                    e.key: e.value.text.trim(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                };
                                await Db.module('sensus')
                                    .doc(wargaId)
                                    .update(changes);
                                final selfProfileUpdates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
                                if (changes.containsKey('telepon')) selfProfileUpdates['telepon'] = changes['telepon'];
                                if (changes.containsKey('alamat')) selfProfileUpdates['alamat'] = changes['alamat'];
                                await Db.user(Db.auth.currentUser!.uid).update(selfProfileUpdates);
                                await writeWargaAudit(
                                  wargaId: wargaId,
                                  modul: 'informasi_diri',
                                  aksi: 'memperbarui identitas',
                                  peran: 'data pribadi',
                                  namaWarga: (data['nama'] ?? '').toString(),
                                );
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                }
                                if (context.mounted) {
                                  showMessage(
                                    context,
                                    'Informasi diri berhasil diperbarui.',
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  showMessage(
                                    context,
                                    'Gagal memperbarui data: $e',
                                  );
                                }
                              } finally {
                                if (ctx.mounted) {
                                  setSheet(() => busy = false);
                                }
                              }
                            },
                      child: busy
                          ? const CircularProgressIndicator()
                          : const Text('Simpan Perubahan'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  @override Widget build(BuildContext context){final user=Db.auth.currentUser; if(user==null)return const Scaffold(body:Center(child:Text('Silakan login kembali.')));return Scaffold(appBar:AppBar(title:const Text('Informasi Diri')),body:StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:Db.user(user.uid).snapshots(),builder:(context,userSnap){if(!userSnap.hasData)return const Center(child:CircularProgressIndicator());final profile=userSnap.data!.data()??{};final wargaId=(profile['wargaId']??'').toString();if(wargaId.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Akun ini belum terhubung dengan data Sensus. Silakan hubungi Admin/Owner.')));return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:Db.module('sensus').doc(wargaId).snapshots(),builder:(context,snap){if(snap.hasError)return Center(child:Text('Gagal memuat Sensus: ${snap.error}'));if(!snap.hasData)return const Center(child:CircularProgressIndicator());final data=snap.data!.data();if(data==null)return const Center(child:Text('Data Sensus milik akun ini tidak ditemukan.'));final entries=data.entries.where((e)=>!{'roles','role','accountUid','wargaId','createdAt','createdBy','updatedAt','updatedBy'}.contains(e.key));final roles=(profile['roles'] is List)?(profile['roles'] as List).join(', '):(profile['role']??'warga').toString();return ListView(padding:const EdgeInsets.all(16),children:[Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFEAF4ED),borderRadius:BorderRadius.circular(16)),child:const Text('Data ini terhubung langsung dengan Sensus Penduduk. Nama asli, NIK, Nomor KK, dan Role dikunci untuk menjaga keakuratan identitas.')),const SizedBox(height:12),Card(child:ListTile(title:const Text('Role / Hak Akses'),subtitle:Text(roles),trailing:const Icon(Icons.lock_outline))),...entries.map((e){final isLocked={'nama','nik','noKK'}.contains(e.key);final labels={'nama':'Nama Asli','nik':'NIK','noKK':'Nomor KK','jenisKelamin':'Jenis kelamin','tempatLahir':'Tempat lahir','tanggalLahir':'Tanggal lahir','telepon':'Nomor HP / WhatsApp','agama':'Agama','statusPerkawinan':'Status perkawinan','pendidikan':'Pendidikan','pekerjaan':'Pekerjaan','hubunganKeluarga':'Hubungan keluarga','kawil':'Kawil / Dusun','rw':'RW','rt':'RT','alamat':'Alamat'};return Card(child:ListTile(title:Text(labels[e.key]??e.key),subtitle:Text(e.value.toString().isEmpty?'Belum diisi':e.value.toString()),trailing:isLocked?const Icon(Icons.lock_outline,size:18):null));}),const SizedBox(height:12),StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:_migrationConfig.snapshots(),builder:(context,lockSnap){final lockedForUpdate=lockSnap.data?.data()?['lockResidentEdits']==true;return Column(children:[if(lockedForUpdate)Container(width:double.infinity,padding:const EdgeInsets.all(14),margin:const EdgeInsets.only(bottom:10),decoration:BoxDecoration(color:Colors.orange.shade50,borderRadius:BorderRadius.circular(12),border:Border.all(color:Colors.orange.shade200)),child:const Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(Icons.warning_amber_rounded,color:Colors.orange),SizedBox(width:8),Expanded(child:Text('Pembaruan Data Sensus sedang berlangsung. Untuk sementara Anda hanya dapat melihat data. Perubahan data pribadi akan dibuka kembali setelah proses selesai.'))])),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:lockedForUpdate?null:()=>edit(data,wargaId),icon:Icon(lockedForUpdate?Icons.lock_outline:Icons.edit_outlined),label:Text(lockedForUpdate?'Perubahan Data Dikunci':'Edit / Perbarui Data')))]);})]);});}));}
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
          TextFormField(initialValue: (widget.profile['nama'] ?? '').toString(), readOnly: true, decoration: const InputDecoration(labelText: 'Nama asli (terkunci)')),
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
            final meData = me.data!.data() ?? <String, dynamic>{};
            final meRoles = (meData['roles'] is List)
                ? (meData['roles'] as List).map((e) => e.toString().toLowerCase()).toSet()
                : <String>{(meData['role'] ?? '').toString().toLowerCase()};
            final isOwner = meRoles.contains('owner') ||
                (meData['role'] ?? '').toString().toLowerCase() == 'owner';
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: Db.firestore.collection('users').orderBy('nama').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Gagal memuat akun: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (isOwner)
                      Card(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: ListTile(
                          leading: const Icon(Icons.replay_circle_filled_outlined),
                          title: const Text('Pulihkan login Owner dengan NIK'),
                          subtitle: const Text('Membuat ulang akun NIK dari data Sensus milik Owner yang sedang login. Data Sensus tidak dibuat ulang.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Pulihkan akun NIK Owner?'),
                                content: const Text('Sistem akan membuat akun login NIK berdasarkan data Sensus Owner yang sedang login. Password awal adalah tanggal lahir (DDMMYYYY) dan wajib diganti setelah login.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pulihkan akun')),
                                ],
                              ),
                            );
                            if (confirmed != true || !context.mounted) return;
                            try {
                              final result = await PhotoService.restoreOwnerNikAccount();
                              if (context.mounted) {
                                showMessage(context, (result['message'] ?? 'Akun NIK Owner berhasil dipulihkan.').toString());
                              }
                            } catch (e) {
                              if (context.mounted) showMessage(context, 'Pemulihan akun gagal: $e');
                            }
                          },
                        ),
                      ),
                    ...snapshot.data!.docs.map((doc) {
                    final d = doc.data();
                    final role = (d['role'] ?? 'warga').toString();
                    final roleList = (d['roles'] is List)
                        ? (d['roles'] as List).map((e) => e.toString()).join(', ')
                        : role;
                    final nik = (d['nik'] ?? '').toString();
                    final maskedNik = nik.length == 16
                        ? '${nik.substring(0, 4)}********${nik.substring(12)}'
                        : 'NIK tidak tersedia';
                    return Card(
                      child: ListTile(
                        title: Text((d['nama'] ?? 'Tanpa nama').toString()),
                        subtitle: Text('$maskedNik\nRole: $roleList • Status: ${(d['status'] ?? 'Aktif')}'),
                        isThreeLine: true,
                        trailing: isOwner && role != 'owner'
                            ? PopupMenuButton<String>(
                                onSelected: (value) async {
                                  try {
                                    await doc.reference.update({
                                      'role': value,
                                      'roles': value == 'warga' ? ['warga'] : ['warga', value],
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
                  ],
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

String _formatHistoryDate(dynamic value) {
  if (value == null) return '—';
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (date != null) return '${date.day.toString().padLeft(2,'0')}-${date.month.toString().padLeft(2,'0')}-${date.year}';
  return value.toString();
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
            if (phone.isNotEmpty) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.call, color: Colors.green),
                title: const Text('Telepon kontak ini'),
                subtitle: Text(phone),
                onTap: () async {
                  final dialNumber = phone.replaceAll(RegExp(r'[^0-9+]'), '');
                  if (dialNumber.isEmpty) {
                    showMessage(sheetContext, 'Nomor telepon belum valid.');
                    return;
                  }
                  final dialUri = Uri(scheme: 'tel', path: dialNumber);
                  final opened = await launchUrl(dialUri, mode: LaunchMode.externalApplication);
                  if (!opened && sheetContext.mounted) {
                    showMessage(sheetContext, 'Tidak dapat membuka aplikasi telepon.');
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.chat, color: Colors.green),
                title: const Text('Hubungi melalui WhatsApp'),
                subtitle: Text(phone),
                onTap: () => openWhatsApp(sheetContext, phone),
              ),
            ],
            if (maps.isNotEmpty || address.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined, color: Colors.red),
                title: const Text('Buka lokasi di Google Maps'),
                subtitle: Text(maps.isNotEmpty ? maps : address, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => openGoogleMaps(sheetContext, maps.isNotEmpty ? maps : address),
              ),
            if (data['riwayatPemilik'] is List && (data['riwayatPemilik'] as List).isNotEmpty) ...[
              const Divider(),
              const Text('Riwayat Kepemilikan UMKM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ...(data['riwayatPemilik'] as List).whereType<Map>().map((item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text((item['nama'] ?? 'Pemilik').toString()),
                subtitle: Text('${item['status'] ?? ''} • Mulai: ${_formatHistoryDate(item['mulaiPada'])} • Selesai: ${_formatHistoryDate(item['selesaiPada'])}'),
              )),
            ],
            const Divider(),
            ...data.entries.where((e) => !excluded.contains(e.key) &&
                !{'telepon', 'whatsapp', 'lokasiMaps', 'googleMaps', 'fotoUrl', 'foto', 'imageUrl', 'riwayatPemilik', 'wargaId', 'accountUid', 'roles', 'role', 'ketuaUid', 'anggotaWarga', 'anggotaWargaIds', 'kawilId', 'rwId', 'rtId', 'pemilikNamaSnapshot', 'pemilikMulaiPada', 'statusAkunSebelumArsip'}.contains(e.key) &&
                !e.key.endsWith('WargaId') && !e.key.endsWith('Nik') && !e.key.endsWith('Uid')).map((e) => Padding(
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
