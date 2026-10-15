import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/city.dart';

class GeoService {
  static const _ua = {
    'User-Agent': 'FlutterWeatherApp/1.0 (github.com/iana8754/flutter-codespace)'
  };

  static String _norm(String s) => s.toLowerCase().replaceAll('ё', 'е');

  static String? _region(List<dynamic> parts) {
    final r = parts.whereType<String>().where((s) => s.isNotEmpty).join(', ');
    return r.isEmpty ? null : r;
  }

  /// Мгновенный поиск по встроенному списку: «о» → Омск, Оренбург, Орёл...
  static List<City> local(String q) {
    final k = _norm(q.trim());
    if (k.isEmpty) return [];
    final starts = <City>[];
    final inner = <City>[];
    for (final c in popularCities) {
      final n = _norm(c.$1);
      if (n.startsWith(k)) {
        starts.add(cityFromRecord(c));
      } else if (n.split(RegExp(r'[ \-]')).any((w) => w.startsWith(k))) {
        inner.add(cityFromRecord(c));
      }
    }
    return [...starts, ...inner].take(10).toList();
  }

  /// Онлайн-поиск (любой город мира). Два сервиса на случай блокировки.
  static Future<List<City>> remote(String q) async {
    try {
      final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': q,
        'count': '8',
        'language': 'ru',
        'format': 'json',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body)['results'] as List?) ?? [];
        return list
            .map<City>((e) => City(
                  name: e['name'] as String,
                  region: _region([e['admin1'], e['country']]),
                  lat: (e['latitude'] as num).toDouble(),
                  lon: (e['longitude'] as num).toDouble(),
                ))
            .toList();
      }
    } catch (_) {}
    try {
      final uri = Uri.https('photon.komoot.io', '/api/', {'q': q, 'limit': '12'});
      final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final feats = (jsonDecode(res.body)['features'] as List?) ?? [];
        final out = <City>[];
        for (final f in feats) {
          final p = f['properties'] as Map<String, dynamic>;
          if (p['osm_key'] != 'place' || p['name'] == null) continue;
          final c = f['geometry']['coordinates'] as List;
          out.add(City(
            name: p['name'] as String,
            region: _region([p['state'], p['country']]),
            lat: (c[1] as num).toDouble(),
            lon: (c[0] as num).toDouble(),
          ));
        }
        return out;
      }
    } catch (_) {}
    return [];
  }

  static List<City> merge(List<City> local, List<City> remote) {
    final out = [...local];
    for (final r in remote) {
      if (!out.any((c) => c.sameAs(r))) out.add(r);
    }
    return out.take(15).toList();
  }
}