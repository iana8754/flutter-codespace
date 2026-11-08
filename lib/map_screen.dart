import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import 'config.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  ymk.MapWindow? _mapWindow;

  // MapKit хранит только слабые ссылки, поэтому слои держим в полях.
  ymk.TrafficLayer? _traffic;
  ymk.UserLocationLayer? _userLayer;

  bool _trafficOn = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kMapkitKey.isNotEmpty) mapkit.onStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (kMapkitKey.isNotEmpty) mapkit.onStop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kMapkitKey.isEmpty) return;
    if (state == AppLifecycleState.resumed) mapkit.onStart();
    if (state == AppLifecycleState.paused) mapkit.onStop();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onMapCreated(ymk.MapWindow window) async {
    _mapWindow = window;
    _traffic = mapkit.createTrafficLayer(window)..setTrafficVisible(_trafficOn);

    final granted = await _ensureLocationPermission();
    _userLayer = mapkit.createUserLocationLayer(window)..setVisible(granted);
    if (granted) await _goToMe();
  }

  Future<bool> _ensureLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Включите геолокацию на телефоне');
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Нет доступа к геолокации');
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _goToMe() async {
    final window = _mapWindow;
    if (window == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      window.map.move(
        ymk.CameraPosition(
          ymk.Point(latitude: pos.latitude, longitude: pos.longitude),
          zoom: 15.0,
          azimuth: 0.0,
          tilt: 0.0,
        ),
      );
    } catch (_) {
      _toast('Не удалось определить местоположение');
    }
  }

  Future<void> _onMyLocationPressed() async {
    final granted = await _ensureLocationPermission();
    _userLayer?.setVisible(granted);
    if (granted) await _goToMe();
  }

  void _toggleTraffic() {
    setState(() => _trafficOn = !_trafficOn);
    _traffic?.setTrafficVisible(_trafficOn);
  }

  @override
  Widget build(BuildContext context) {
    if (kMapkitKey.isEmpty) return const _NoKey();
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: Stack(
        children: [
          YandexMap(onMapCreated: _onMapCreated),
          Positioned(
            right: 12,
            bottom: bottom + 24,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'traffic',
                  tooltip: 'Пробки',
                  backgroundColor:
                      _trafficOn ? scheme.primaryContainer : scheme.surface,
                  onPressed: _toggleTraffic,
                  child: const Icon(Icons.traffic),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'me',
                  tooltip: 'Где я',
                  onPressed: _onMyLocationPressed,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoKey extends StatelessWidget {
  const _NoKey();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Не задан ключ MapKit.\n\n'
            'Соберите приложение с параметром\n--dart-define=MAPKIT_API_KEY=ВАШ_КЛЮЧ\n'
            '(в GitHub Actions он берётся из секрета MAPKIT_API_KEY).',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
