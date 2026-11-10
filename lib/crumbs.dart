import 'dart:io';

/// Журнал шагов: пишется сразу на диск, поэтому переживает вылет приложения.
/// При следующем запуске приложение покажет последние строки.
class Crumbs {
  static File? _file;
  static File get _f =>
      _file ??= File('${Directory.systemTemp.path}/nav_steps.log');

  static void mark(String text) {
    try {
      final t = DateTime.now().toIso8601String().substring(11, 23);
      _f.writeAsStringSync('$t $text\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Читает журнал прошлого запуска и очищает его.
  static String? takePrevious() {
    try {
      final f = _f;
      if (!f.existsSync()) return null;
      final text = f.readAsStringSync();
      f.deleteSync();
      if (text.trim().isEmpty) return null;
      final lines = text.trim().split('\n');
      final tail = lines.length > 45 ? lines.sublist(lines.length - 45) : lines;
      return tail.join('\n');
    } catch (_) {
      return null;
    }
  }
}
