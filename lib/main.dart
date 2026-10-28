import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

// ====== ВСТАВЬТЕ СВОИ ДАННЫЕ ИЗ SUPABASE (Settings -> API) ======
const supabaseUrl = 'https://ljmpxywhmryovewazols.supabase.co/rest/v1/';
const supabaseKey = 'https://ljmpxywhmryovewazols.supabase.co/rest/v1/';
// ================================================================

const bucket = 'files';
SupabaseClient get sb => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5B6CFF);
    return MaterialApp(
      title: 'Моё облако',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        scaffoldBackgroundColor: const Color(0xFFF4F5FB),
        appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF4F5FB), elevation: 0, scrolledUnderElevation: 0),
      ),
      darkTheme: ThemeData(
          useMaterial3: true, colorSchemeSeed: seed, brightness: Brightness.dark),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (context, _) =>
          sb.auth.currentSession == null ? const LoginPage() : const HomePage(),
    );
  }
}

// ---------------------------------------------------------------- Вход
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false, _busy = false, _hide = true;

  void _msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final email = _email.text.trim(), pass = _pass.text;
      if (_register) {
        final r = await sb.auth.signUp(email: email, password: pass);
        if (r.session == null) _msg('Проверьте почту и подтвердите адрес, затем войдите');
      } else {
        await sb.auth.signInWithPassword(email: email, password: pass);
      }
    } on AuthException catch (e) {
      _msg(e.message);
    } catch (e) {
      _msg('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, cs.tertiary],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Icon(Icons.cloud_rounded, size: 84, color: Colors.white),
                const SizedBox(height: 8),
                const Text('Моё облако',
                    style: TextStyle(
                        fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Все файлы всегда с вами',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 28),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(children: [
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.mail_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _pass,
                        obscureText: _hide,
                        decoration: InputDecoration(
                          labelText: 'Пароль (от 6 символов)',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _hide = !_hide)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_register ? 'Создать аккаунт' : 'Войти'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _register = !_register),
                        child: Text(_register
                            ? 'Уже есть аккаунт? Войти'
                            : 'Нет аккаунта? Зарегистрироваться'),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Файлы
bool isImageName(String n) {
  final e = n.toLowerCase();
  return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.bmp'].any(e.endsWith);
}

bool isVideoName(String n) {
  final e = n.toLowerCase();
  return ['.mp4', '.mov', '.mkv', '.webm', '.avi', '.3gp'].any(e.endsWith);
}

String fmtSize(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b Б';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} КБ';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
}

class CloudFile {
  final String name;
  final String? thumbUrl;
  final int? size;
  CloudFile(this.name, this.thumbUrl, this.size);
  String get title =>
      name.contains('_') ? name.substring(name.indexOf('_') + 1) : name;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _picker = ImagePicker();
  List<CloudFile> _files = [];
  bool _loading = true, _uploading = false;
  String get _uid => sb.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final store = sb.storage.from(bucket);
      final list = await store.list(path: _uid);
      final objs = list.where((f) => !f.name.startsWith('.')).toList();
      objs.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

      final imgPaths =
          objs.where((f) => isImageName(f.name)).map((f) => '$_uid/${f.name}').toList();
      final urls = <String, String>{};
      if (imgPaths.isNotEmpty) {
        await Future.wait(imgPaths.map((p) async {
          try {
        urls[p] = await store.createSignedUrl(p, 3600);
      } catch (_) {}
    }));
    }
      _files = objs.map((f) {
        final sz = f.metadata?['size'];
        return CloudFile(f.name, urls['$_uid/${f.name}'], sz is int ? sz : null);
      }).toList();
    } catch (e) {
      _msg('Не удалось загрузить список: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _upload(List<(File, String)> items) async {
    if (items.isEmpty) return;
    setState(() => _uploading = true);
    try {
      for (final (file, name) in items) {
        final safe = name.replaceAll(RegExp(r'[^\w.\-]'), '_');
        final key = '$_uid/${DateTime.now().millisecondsSinceEpoch}_$safe';
        await sb.storage.from(bucket).upload(key, file);
      }
      _msg('Загружено: ${items.length}');
    } catch (e) {
      _msg('Ошибка загрузки: $e');
    }
    if (mounted) setState(() => _uploading = false);
    await _load();
  }

  Future<void> _takePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (x != null) await _upload([(File(x.path), x.name)]);
  }

  Future<void> _takeVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.camera);
    if (x != null) await _upload([(File(x.path), x.name)]);
  }

  Future<void> _pickGallery() async {
    final xs = await _picker.pickMultipleMedia();
    await _upload(xs.map((x) => (File(x.path), x.name)).toList());
  }

  Future<void> _pickFiles() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null) return;
    await _upload(r.files
        .where((f) => f.path != null)
        .map((f) => (File(f.path!), f.name))
        .toList());
  }

  Future<void> _open(CloudFile f) async {
    try {
      final url = await sb.storage.from(bucket).createSignedUrl('$_uid/${f.name}', 3600);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      _msg('Не удалось открыть: $e');
    }
  }

  Future<void> _delete(CloudFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: Text(f.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sb.storage.from(bucket).remove(['$_uid/${f.name}']);
      await _load();
    } catch (e) {
      _msg('Ошибка удаления: $e');
    }
  }

  void _showAddSheet() {
    Widget tile(IconData i, String t, Color c, VoidCallback onTap) => ListTile(
          leading: CircleAvatar(
              backgroundColor: c.withValues(alpha: .15), child: Icon(i, color: c)),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          tile(Icons.photo_camera_rounded, 'Снять фото', Colors.indigo, _takePhoto),
          tile(Icons.videocam_rounded, 'Снять видео', Colors.red, _takeVideo),
          tile(Icons.photo_library_rounded, 'Фото и видео из галереи', Colors.teal, _pickGallery),
          tile(Icons.insert_drive_file_rounded, 'Файлы с телефона', Colors.orange, _pickFiles),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моё облако', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Выйти',
            onPressed: () => sb.auth.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _showAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Добавить'),
      ),
      body: Column(children: [
        if (_uploading) const LinearProgressIndicator(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _files.isEmpty
                      ? ListView(children: [
                          SizedBox(height: MediaQuery.of(context).size.height * .25),
                          Icon(Icons.cloud_upload_outlined,
                              size: 96, color: cs.primary.withValues(alpha: .5)),
                          const SizedBox(height: 12),
                          const Center(
                              child: Text('Здесь пока пусто',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                          const SizedBox(height: 6),
                          const Center(child: Text('Нажмите «Добавить», чтобы загрузить файл')),
                        ])
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: .86),
                          itemCount: _files.length,
                          itemBuilder: (_, i) => _card(_files[i], cs),
                        ),
                ),
        ),
      ]),
    );
  }

  Widget _card(CloudFile f, ColorScheme cs) {
    IconData icon = Icons.insert_drive_file_rounded;
    Color color = cs.primary;
    if (isVideoName(f.name)) {
      icon = Icons.play_circle_fill_rounded;
      color = Colors.red;
    } else if (f.name.toLowerCase().endsWith('.pdf')) {
      icon = Icons.picture_as_pdf_rounded;
      color = Colors.deepOrange;
    }
    return Material(
      color: cs.surface,
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(f),
        onLongPress: () => _delete(f),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: f.thumbUrl != null
                  ? Image.network(f.thumbUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: color))
                  : Container(
                      color: color.withValues(alpha: .1),
                      child: Icon(icon, size: 56, color: color)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(fmtSize(f.size),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) => v == 'del' ? _delete(f) : _open(f),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Открыть')),
                  PopupMenuItem(value: 'del', child: Text('Удалить')),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
