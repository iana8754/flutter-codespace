import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationService {
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
    return Geolocator.getCurrentPosition();
  }

  static Future<String> getCity(double lat, double lon) async {
    try {
      final uri = Uri.https(
        'api.bigdatacloud.net',
        '/data/reverse-geocode-client',
        {
          'latitude': '$lat',
          'longitude': '$lon',
          'localityLanguage': 'ru',
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return 'Ваше местоположение';
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      for (final key in ['city', 'locality', 'principalSubdivision']) {
        final v = j[key];
        if (v is String && v.isNotEmpty) return v;
      }
    } catch (_) {}
    return 'Ваше местоположение';
  }
}