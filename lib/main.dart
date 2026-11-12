import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

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
          return CompleteProfilePage(user: user);
        }
        final data = snapshot.data!.data() ?? {};
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
  bool isLogin = true;
  bool busy = false;
  bool obscure = true;

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.length < 6) {
      showMessage(context, 'Masukkan email dan password minimal 6 karakter.');
      return;
    }
    setState(() => busy = true);
    try {
      UserCredential result;
      if (isLogin) {
        result = await Db.auth.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      } else {
        result = await Db.auth.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
        await Db.user(result.user!.uid).set({
          'nama': result.user!.displayName ?? '',
          'email': email.text.trim(),
          'telepon': '',
          'alamat': '',
          'role': 'warga',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
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
                  Text(isLogin ? 'Selamat datang kembali' : 'Buat akun warga',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 18),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
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
                        : Text(isLogin ? 'Masuk' : 'Daftar akun'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: busy ? null : () => setState(() => isLogin = !isLogin),
                    child: Text(isLogin
                        ? 'Belum punya akun? Daftar warga'
                        : 'Sudah punya akun? Masuk'),
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
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: desc.isEmpty ? null : Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(desc, maxLines: 3, overflow: TextOverflow.ellipsis),
                  ),
                  trailing: canEdit ? PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        showRecordForm(context, module, isAdmin: canEdit, docId: doc.id, initial: data);
                      } else if (v == 'delete') {
                        final yes = await confirmDelete(context);
                        if (yes == true) await doc.reference.delete();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus')),
                    ],
                  ) : const Icon(Icons.chevron_right),
                  onTap: () => showRecordDetail(context, title, data),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> showRecordForm(
  BuildContext context,
  ModuleInfo module, {
  required bool isAdmin,
  String? docId,
  Map<String, dynamic>? initial,
}) async {
  if (!isAdmin) return;
  final title = TextEditingController(text: (initial?['judul'] ?? initial?['nama'] ?? '').toString());
  final desc = TextEditingController(text: (initial?['deskripsi'] ?? initial?['keterangan'] ?? '').toString());
  final address = TextEditingController(text: (initial?['alamat'] ?? '').toString());
  final contact = TextEditingController(text: (initial?['telepon'] ?? initial?['whatsapp'] ?? '').toString());
  final extra = TextEditingController(text: (initial?['catatan'] ?? '').toString());
  final formKey = GlobalKey<FormState>();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: Container(
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
                    validator: (v) => v == null || v.trim().isEmpty ? 'Bagian ini wajib diisi' : null,
                    decoration: const InputDecoration(labelText: 'Nama / Judul'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Deskripsi / Keterangan')),
                  const SizedBox(height: 10),
                  TextField(controller: address, decoration: const InputDecoration(labelText: 'Alamat / Lokasi')),
                  const SizedBox(height: 10),
                  TextField(controller: contact, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telepon / WhatsApp')),
                  const SizedBox(height: 10),
                  TextField(controller: extra, maxLines: 2, decoration: const InputDecoration(labelText: 'Catatan tambahan')),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final payload = <String, dynamic>{
                        'judul': title.text.trim(),
                        'nama': title.text.trim(),
                        'deskripsi': desc.text.trim(),
                        'keterangan': desc.text.trim(),
                        'alamat': address.text.trim(),
                        'telepon': contact.text.trim(),
                        'catatan': extra.text.trim(),
                        'updatedAt': FieldValue.serverTimestamp(),
                        'updatedBy': Db.auth.currentUser?.uid,
                      };
                      try {
                        if (docId == null) {
                          payload['createdAt'] = FieldValue.serverTimestamp();
                          payload['createdBy'] = Db.auth.currentUser?.uid;
                          await Db.module(module.keyName).add(payload);
                        } else {
                          await Db.module(module.keyName).doc(docId).update(payload);
                        }
                        if (context.mounted) Navigator.pop(context);
                        showMessage(sheetContext, 'Data berhasil disimpan.');
                      } catch (e) {
                        showMessage(sheetContext, 'Gagal menyimpan: $e');
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
}

class ProfilePage extends StatelessWidget {
  final User user;
  final Map<String, dynamic> profile;
  final bool isAdmin;
  const ProfilePage({super.key, required this.user, required this.profile, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.person, size: 44),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text((profile['nama'] ?? 'Pengguna').toString(), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
        Center(child: Text(user.email ?? '', style: TextStyle(color: Colors.grey.shade600))),
        const SizedBox(height: 8),
        Center(child: Chip(label: Text((profile['role'] ?? 'warga').toString().toUpperCase()))),
        const SizedBox(height: 22),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit data diri'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(user: user, profile: profile))),
            ),
            const Divider(height: 1),
            if (isAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Panel Admin'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPage())),
              ),
            if (isAdmin) const Divider(height: 1),
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
          ]),
        ),
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
  const ChangePasswordPage({super.key});
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
      if (mounted) {
        showMessage(context, 'Password berhasil diubah.');
        Navigator.pop(context);
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
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: Db.firestore.collection('users').orderBy('nama').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('Gagal memuat akun: ${snapshot.error}'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            return ListView(
              padding: const EdgeInsets.all(12),
              children: snapshot.data!.docs.map((doc) {
                final d = doc.data();
                final role = (d['role'] ?? 'warga').toString();
                return Card(
                  child: ListTile(
                    title: Text((d['nama'] ?? 'Tanpa nama').toString()),
                    subtitle: Text('${d['email'] ?? ''}\nPeran: $role'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        await doc.reference.update({'role': value, 'updatedAt': FieldValue.serverTimestamp()});
                        showMessage(context, 'Peran akun diperbarui menjadi $value.');
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'warga', child: Text('Jadikan Warga')),
                        PopupMenuItem(value: 'admin', child: Text('Jadikan Admin')),
                      ],
                    ),
                  ),
                );
              }).toList(),
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

void showRecordDetail(BuildContext context, String title, Map<String, dynamic> data) {
  final excluded = {'createdAt', 'updatedAt', 'createdBy', 'updatedBy'};
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            ...data.entries.where((e) => !excluded.contains(e.key)).map((e) => Padding(
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
      return 'Email atau password salah.';
    case 'network-request-failed':
      return 'Koneksi internet bermasalah.';
    case 'too-many-requests':
      return 'Terlalu banyak percobaan. Coba lagi nanti.';
    default:
      return e.message ?? 'Autentikasi gagal (${e.code}).';
  }
}
