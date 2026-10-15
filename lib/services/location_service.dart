import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

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
      final p = (await placemarkFromCoordinates(lat, lon)).first;
      return p.locality?.isNotEmpty == true
          ? p.locality!
          : (p.administrativeArea ?? 'Ваше местоположение');
    } catch (_) {
      return 'Ваше местоположение';
    }
  }
}