import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationService {
  static const _ua = {
    'User-Agent': 'FlutterWeatherApp/1.0 (github.com/iana8754/flutter-codespace)'
  };

  static Future<Position> getPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'Включите геолокацию (GPS) на телефоне';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw 'Нет доступа к геолокации. Разрешите его в настройках приложения';
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      throw 'Не удалось определить местоположение. Выйдите на открытое место и повторите';
    }
  }

  /// Название города по координатам (два сервиса на случай блокировки одного).
  static Future<String> getCity(double lat, double lon) async {
    try {
      final uri = Uri.https('api.bigdatacloud.net', '/data/reverse-geocode-client', {
        'latitude': '$lat',
        'longitude': '$lon',
        'localityLanguage': 'ru',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        for (final key in ['city', 'locality', 'principalSubdivision']) {
          final v = j[key];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    } catch (_) {}
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '$lat',
        'lon': '$lon',
        'zoom': '10',
        'accept-language': 'ru',
      });
      final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final a = (jsonDecode(res.body)['address'] ?? {}) as Map<String, dynamic>;
        for (final key in ['city', 'town', 'village', 'municipality', 'state']) {
          final v = a[key];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    } catch (_) {}
    return 'Ваше местоположение';
  }
}