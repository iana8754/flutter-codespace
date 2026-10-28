import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';

enum Kind { photo, video, other }

const _photoExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};
const _videoExt = {'mp4', 'mov', 'mkv', 'avi', '3gp', 'webm'};

class CloudFile {
  final String path, name, ext;
  final int size;
  final DateTime date;
  final Kind kind;
  String? url;
  CloudFile(this.path, this.name, this.ext, this.size, this.date, this.kind);

  static CloudFile? parse(String uid, dynamic f) {
    final key = f.name as String;
    if (key.startsWith('.')) return null;
    final i = key.indexOf('_');
    final dot = key.lastIndexOf('.');
    var name = key, ext = '';
    if (i > 0) {
      final end = dot > i ? dot : key.length;
      ext = dot > i ? key.substring(dot + 1) : '';
      try {
        name = utf8.decode(base64Url.decode(base64Url.normalize(key.substring(i + 1, end)))) +
            (ext.isEmpty ? '' : '.$ext');
      } catch (_) {}
    }
    final kind = _photoExt.contains(ext)
        ? Kind.photo
        : _videoExt.contains(ext)
            ? Kind.video
            : Kind.other;
    final size = ((f.metadata?['size']) as num?)?.toInt() ?? 0;
    final date = DateTime.tryParse(f.createdAt ?? '')?.toLocal() ?? DateTime.now();
    return CloudFile('$uid/$key', name, ext, size, date, kind);
  }
}

String _makeKey(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  final ext = dot > 0
      ? fileName.substring(dot + 1).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')
      : '';
  final enc = base64Url.encode(utf8.encode(base)).replaceAll('=', '');
  return '${DateTime.now().microsecondsSinceEpoch}_$enc${ext.isEmpty ? '' : '.$ext'}';
}

String _size(int b) {
  if (b < 1024) return '$b Б';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} КБ';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _stamp() {
  final n = DateTime.now();
  String t(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${t(n.month)}-${t(n.day)} ${t(n.hour)}.${t(n.minute)}.${t(n.second)}';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  int _busy = 0;
  bool _loading = true;
  String _query = '';
  List<CloudFile> _files = [];
  final _picker = ImagePicker();

  String get _uid => supa.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _load() async {
    try {
      final list = await supa.storage
          .from('files')
          .list(path: _uid, searchOptions: const SearchOptions(limit: 1000));
      final files = list
          .map((f) => CloudFile.parse(_uid, f))
          .whereType<CloudFile>()
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (files.isNotEmpty) {
        final urls = await supa.storage
            .from('files')
            .createSignedUrls(files.map((f) => f.path).toList(), 3600);
        final map = {for (final u in urls) u.path: u.signedUrl};
        for (final f in files) {
          f.url = map[f.path];
        }
      }
      if (mounted) setState(() => _files = files);
    } catch (e) {
      _snack('Не удалось загрузить список: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _upload(List<(File, String)> items) async {
    if (items.isEmpty) return;
    setState(() => _busy += items.length);
    for (final (file, name) in items) {
      try {
        await supa.storage.from('files').upload('$_uid/${_makeKey(name)}', file);
      } catch (e) {
        _snack('Ошибка загрузки "$name": $e');
      }
      if (mounted) setState(() => _busy--);
    }
    await _load();
    _snack('Готово');
  }

  Future<void> _takePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (x != null) await _upload([(File(x.path), 'Фото ${_stamp()}.jpg')]);
  }

  Future<void> _takeVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.camera);
    if (x != null) await _upload([(File(x.path), 'Видео ${_stamp()}.mp4')]);
  }

  Future<void> _pickGallery() async {
    final xs = await _picker.pickMultipleMedia();
    await _upload([for (final x in xs) (File(x.path), x.name)]);
  }

  Future<void> _pickFiles() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null) return;
    await _upload([
      for (final f in r.files)
        if (f.path != null) (File(f.path!), f.name)
    ]);
  }

  void _addMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetItem(Icons.photo_camera_rounded, 'Снять фото', _takePhoto),
          _sheetItem(Icons.videocam_rounded, 'Снять видео', _takeVideo),
          _sheetItem(Icons.photo_library_rounded, 'Из галереи', _pickGallery),
          _sheetItem(Icons.upload_file_rounded, 'Выбрать файлы', _pickFiles),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _sheetItem(IconData i, String t, Future<void> Function() fn) => ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(i, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(t),
        onTap: () {
          Navigator.pop(context);
          fn();
        },
      );

  Future<void> _open(CloudFile f) async {
    if (f.url == null) return;
    if (f.kind == Kind.photo) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(f.name, style: const TextStyle(fontSize: 15)),
            ),
            body: Center(
              child: InteractiveViewer(child: Image.network(f.url!)),
            ),
          ),
        ),
      );
    } else {
      await launchUrl(Uri.parse(f.url!), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _delete(CloudFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: Text(f.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supa.storage.from('files').remove([f.path]);
      await _load();
    } catch (e) {
      _snack('Не удалось удалить: $e');
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final titles = ['Файлы', 'Фото', 'Видео', 'Профиль'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab], style: const TextStyle(fontWeight: FontWeight.w700)),
        bottom: _busy > 0
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3), child: LinearProgressIndicator())
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body()),
      floatingActionButton: _tab == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: _addMenu,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Файлы'),
          NavigationDestination(icon: Icon(Icons.image_outlined), selectedIcon: Icon(Icons.image), label: 'Фото'),
          NavigationDestination(icon: Icon(Icons.movie_outlined), selectedIcon: Icon(Icons.movie), label: 'Видео'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Профиль'),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 0:
        return _filesTab();
      case 1:
        return _photosTab();
      case 2:
        return _list(_files.where((f) => f.kind == Kind.video).toList(), 'Видео пока нет');
      default:
        return _profileTab();
    }
  }

  Widget _empty(String t) => ListView(children: [
        SizedBox(
          height: 360,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.cloud_upload_outlined, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(t, style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Нажмите «Добавить»', style: TextStyle(color: Colors.grey.shade500)),
          ]),
        )
      ]);

  Widget _filesTab() {
    final q = _query.toLowerCase();
    final shown = _files.where((f) => f.name.toLowerCase().contains(q)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Поиск по файлам',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(child: _list(shown, 'Файлов пока нет')),
    ]);
  }

  Widget _list(List<CloudFile> files, String emptyText) {
    if (files.isEmpty) return _empty(emptyText);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
      itemCount: files.length,
      itemBuilder: (_, i) {
        final f = files[i];
        return Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            onTap: () => _open(f),
            leading: _thumb(f, 48),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${_size(f.size)} · ${_date(f.date)}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) => v == 'del' ? _delete(f) : _open(f),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Открыть')),
                PopupMenuItem(value: 'del', child: Text('Удалить')),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _thumb(CloudFile f, double s) {
    final c = Theme.of(context).colorScheme;
    if (f.kind == Kind.photo && f.url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(f.url!, width: s, height: s, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(Icons.image, size: s * .6)),
      );
    }
    final icon = f.kind == Kind.video ? Icons.play_circle_fill_rounded : Icons.insert_drive_file_rounded;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
          color: c.primaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: c.primary),
    );
  }

  Widget _photosTab() {
    final photos = _files.where((f) => f.kind == Kind.photo).toList();
    if (photos.isEmpty) return _empty('Фото пока нет');
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
      itemCount: photos.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => _open(photos[i]),
        onLongPress: () => _delete(photos[i]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(photos[i].url ?? '', fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300)),
        ),
      ),
    );
  }

  Widget _profileTab() {
    final total = _files.fold<int>(0, (s, f) => s + f.size);
    final c = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Center(
        child: CircleAvatar(
          radius: 44,
          backgroundColor: c.primary,
          child: Text(
            (supa.auth.currentUser?.email ?? '?')[0].toUpperCase(),
            style: const TextStyle(fontSize: 36, color: Colors.white),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Center(child: Text(supa.auth.currentUser?.email ?? '', style: const TextStyle(fontSize: 17))),
      const SizedBox(height: 28),
      _stat(Icons.folder, 'Всего файлов', '${_files.length}'),
      _stat(Icons.image, 'Фото', '${_files.where((f) => f.kind == Kind.photo).length}'),
      _stat(Icons.movie, 'Видео', '${_files.where((f) => f.kind == Kind.video).length}'),
      _stat(Icons.storage_rounded, 'Занято', _size(total)),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => supa.auth.signOut(),
        icon: const Icon(Icons.logout),
        label: const Text('Выйти из аккаунта'),
      ),
    ]);
  }

  Widget _stat(IconData i, String t, String v) => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(leading: Icon(i), title: Text(t), trailing: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
      );
}
