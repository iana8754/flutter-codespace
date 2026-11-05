import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class TaxiGps {
  static Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Включите геолокацию (GPS) на телефоне.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Разрешение на геолокацию не предоставлено.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Доступ к геолокации запрещён. Разрешите его в настройках Android.');
    }
  }

  static Future<LatLng> currentPosition() async {
    await ensurePermission();
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return LatLng(p.latitude, p.longitude);
  }

  static Stream<Position> watch() async* {
    await ensurePermission();
    yield* Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 3),
      ),
    );
  }
}
