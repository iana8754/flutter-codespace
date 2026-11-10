import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_maps_mapkit/image.dart' as ymimg;
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import 'config.dart';
import 'crumbs.dart';
import 'map_icons.dart';
import 'models.dart';
import 'routing.dart';
import 'search.dart';
import 'widgets.dart';

enum _Field { from, to }

const _blue = Color(0xFF2F80ED);
const _red = Color(0xFFE53935);

final class _MapInput implements ymk.MapInputListener {
  _MapInput({required this.onTap, required this.onLongTap});
  final void Function(ymk.Point) onTap;
  final void Function(ymk.Point) onLongTap;

  @override
  void onMapTap(ymk.Map map, ymk.Point point) => onTap(point);

  @override
  void onMapLongTap(ymk.Map map, ymk.Point point) => onLongTap(point);
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const _meLabel = 'Моё местоположение';

  // ---- карта (MapKit держит слабые ссылки, поэтому всё храним в полях) ----
  ymk.MapWindow? _window;
  ymk.TrafficLayer? _traffic;
  ymk.UserLocationLayer? _userLayer;
  ymk.MapObjectCollection? _routeLayer;
  ymk.MapObjectCollection? _markerLayer;
  _MapInput? _mapInput;
  ymimg.ImageProvider? _iconFrom;
  ymimg.ImageProvider? _iconTo;
  ymimg.ImageProvider? _iconStop;
  String _iconFromText = '';
  String _iconToText = '';
  bool _trafficOn = true;

  // ---- геолокация ----
  ymk.Point? _me;
  StreamSubscription<Position>? _posSub;

  // ---- сервисы ----
  final _search = SearchService();
  final _routing = RoutingService();

  // ---- точки и поиск ----
  final _fromCtrl = TextEditingController(text: _meLabel);
  final _toCtrl = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();
  Timer? _debounce;
  AppPlace? _from; // null = «моё местоположение»
  AppPlace? _to;
  bool _searchOpen = false;
  _Field _active = _Field.to;
  _Field? _picking;
  List<Suggestion> _suggestions = [];
  int _geoToken = 0;

  // ---- маршруты ----
  TravelMode _mode = TravelMode.drive;
  final Map<TravelMode, List<RouteResult>> _results = {};
  final Map<TravelMode, String> _errors = {};
  final Set<TravelMode> _loading = {};
  int _selected = 0;
  int _gen = 0;
  bool _expanded = false;
  bool _navigating = false;

  RouteResult? get _current {
    final list = _results[_mode];
    if (list == null || list.isEmpty) return null;
    return list[math.min(_selected, list.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kMapkitKey.isNotEmpty) mapkit.onStart();
    _fromFocus.addListener(() => _onFocus(_Field.from));
    _toFocus.addListener(() => _onFocus(_Field.to));
    final previous = Crumbs.takePrevious();
    Crumbs.mark('=== запуск ===');
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPreviousLog(previous));
    }
  }

  void _showPreviousLog(String text) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Журнал прошлого запуска'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (kMapkitKey.isNotEmpty) mapkit.onStop();
    _debounce?.cancel();
    _posSub?.cancel();
    _search.dispose();
    _routing.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
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

  // ======================= Карта =======================

  Future<void> _onMapCreated(ymk.MapWindow window) async {
    _window = window;
    _traffic = mapkit.createTrafficLayer(window)..setTrafficVisible(_trafficOn);
    _routeLayer = window.map.mapObjects.addCollection();
    _markerLayer = window.map.mapObjects.addCollection();

    _mapInput = _MapInput(onTap: _onMapTap, onLongTap: _onMapTap);
    window.map.addInputListener(_mapInput!);

    _iconStop = ymimg.ImageProvider.fromImageProvider(
      MemoryImage(await makeDotIcon(fill: const Color(0xFF455A64), size: 44, ring: 8)),
    );

    final granted = await _ensureLocation(move: true);
    _userLayer = mapkit.createUserLocationLayer(window)..setVisible(granted);
  }

  Future<bool> _ensureLocation({bool move = false}) async {
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
      final pos = await Geolocator.getCurrentPosition();
      _me = ymk.Point(latitude: pos.latitude, longitude: pos.longitude);
      _userLayer?.setVisible(true);
      if (move) {
        _window?.map.move(ymk.CameraPosition(_me!, zoom: 15.0, azimuth: 0.0, tilt: 0.0));
      }
      return true;
    } catch (_) {
      _toast('Не удалось определить местоположение');
      return false;
    }
  }

  void _toggleTraffic() {
    setState(() => _trafficOn = !_trafficOn);
    _traffic?.setTrafficVisible(_trafficOn);
  }

  /// Нажатие на карту: ставит точку с подписью адреса.
  void _onMapTap(ymk.Point p) {
    if (!mounted || _navigating || _searchOpen) return;
    Crumbs.mark('нажатие на карту');
    _setPlaceFromMap(_picking ?? _Field.to, p);
  }

  bool _samePoint(ymk.Point a, ymk.Point b) =>
      (a.latitude - b.latitude).abs() < 1e-9 &&
      (a.longitude - b.longitude).abs() < 1e-9;

  void _setPlaceFromMap(_Field f, ymk.Point p) {
    final coords =
        '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
    _setPlace(f, AppPlace(name: 'Определяем адрес…', address: coords, point: p));
    final token = ++_geoToken;

    void apply(String? name) {
      if (!mounted || token != _geoToken) return;
      final current = f == _Field.from ? _from : _to;
      if (current == null || !_samePoint(current.point, p)) return;
      final place = AppPlace(
        name: name ?? 'Точка на карте',
        address: name == null ? coords : '',
        point: p,
      );
      setState(() {
        if (f == _Field.from) {
          _from = place;
          _fromCtrl.text = place.name;
        } else {
          _to = place;
          _toCtrl.text = place.name;
        }
      });
      _refreshIcons();
    }

    _search.reverse(p, onResult: apply, onError: (_) => apply(null));
  }

  // ---- отрисовка маршрутов и маркеров ----

  Future<void> _refreshIcons() async {
    Crumbs.mark('значки: создание');
    try {
      final to = _to;
      if (to != null && _iconToText != to.name) {
        final bytes = await makeLabelIcon(text: to.name, color: _red);
        _iconTo = ymimg.ImageProvider.fromImageProvider(MemoryImage(bytes));
        _iconToText = to.name;
      }
      final from = _from;
      if (from != null && _iconFromText != from.name) {
        final bytes = await makeLabelIcon(text: from.name, color: _blue);
        _iconFrom = ymimg.ImageProvider.fromImageProvider(MemoryImage(bytes));
        _iconFromText = from.name;
      }
    } catch (_) {}
    Crumbs.mark('значки: готовы');
    if (mounted) _redraw();
  }

  void _redraw({bool fit = false}) {
    final layer = _routeLayer;
    final markers = _markerLayer;
    if (layer == null || markers == null) return;
    try {
      Crumbs.mark('перерисовка: ${_mode.name}, fit=$fit');
      layer.clear();
      markers.clear();

      final list = _results[_mode] ?? const <RouteResult>[];
      final cur = _current;
      if (_to != null && list.isNotEmpty && cur != null) {
        for (var i = 0; i < list.length; i++) {
          if (identical(list[i], cur)) continue;
          final n = list[i].full.points.length;
          Crumbs.mark('перерисовка: запасной $i, точек $n');
          if (n < 2) continue;
          layer.addPolylineWithGeometry(list[i].full)
            ..strokeWidth = 6.0
            ..setStrokeColor(Colors.grey.shade600)
            ..outlineWidth = 1.5
            ..outlineColor = Colors.white;
        }
        var k = 0;
        for (final seg in cur.segments) {
          final n = seg.polyline.points.length;
          Crumbs.mark('перерисовка: участок $k, точек $n');
          k++;
          if (n < 2) continue;
          layer.addPolylineWithGeometry(seg.polyline)
            ..strokeWidth = seg.width
            ..setStrokeColor(seg.color)
            ..outlineWidth = 2.5
            ..outlineColor = Colors.white;
        }
        if (_mode == TravelMode.transit && _iconStop != null) {
          Crumbs.mark('перерисовка: остановок ${cur.stops.length}');
          for (final s in cur.stops) {
            markers.addPlacemark()
              ..geometry = s.point
              ..setIcon(_iconStop!);
          }
        }
      }

      final from = _from;
      if (from != null && _iconFrom != null) {
        Crumbs.mark('перерисовка: маркер «откуда»');
        markers.addPlacemark()
          ..geometry = from.point
          ..setIcon(_iconFrom!);
      }
      final to = _to;
      if (to != null && _iconTo != null) {
        Crumbs.mark('перерисовка: маркер «куда»');
        markers.addPlacemark()
          ..geometry = to.point
          ..setIcon(_iconTo!);
      }
      Crumbs.mark('перерисовка: готово');
      if (fit && cur != null) _fit(cur.points);
    } catch (e) {
      Crumbs.mark('перерисовка: ОШИБКА $e');
    }
  }

  double _log2(double x) => math.log(x) / math.ln2;

  /// Подбирает масштаб так, чтобы маршрут был виден над нижней панелью.
  void _fit(List<ymk.Point> pts) {
    final w = _window;
    if (w == null || pts.isEmpty) return;
    var minLat = pts.first.latitude, maxLat = minLat;
    var minLon = pts.first.longitude, maxLon = minLon;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    final size = MediaQuery.sizeOf(context);
    final midLat = (minLat + maxLat) / 2;
    final midLon = (minLon + maxLon) / 2;
    final latSpan = math.max(maxLat - minLat, 0.0015);
    final lonSpan = math.max(maxLon - minLon, 0.0015);
    final cosLat = math.cos(midLat * math.pi / 180).abs().clamp(0.2, 1.0).toDouble();
    final zLon = _log2(360 * size.width / (256 * lonSpan * 1.6));
    final zLat = _log2(360 * size.height * 0.4 * cosLat / (256 * latSpan * 1.6));
    final zoom = math.min(zLon, zLat).clamp(3.0, 17.0).toDouble();
    final latVisible = 360 * size.height * cosLat / (256 * math.pow(2, zoom));
    final centerLat = midLat - latVisible * 0.2;
    Crumbs.mark('камера: zoom=$zoom lat=$centerLat lon=$midLon');
    if (zoom.isNaN || centerLat.isNaN || midLon.isNaN) return;
    w.map.move(ymk.CameraPosition(
      ymk.Point(latitude: centerLat, longitude: midLon),
      zoom: zoom,
      azimuth: 0.0,
      tilt: 0.0,
    ));
  }

  // ======================= Поиск адресов =======================

  void _onFocus(_Field f) {
    final node = f == _Field.from ? _fromFocus : _toFocus;
    if (!node.hasFocus) return;
    final ctrl = f == _Field.from ? _fromCtrl : _toCtrl;
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    if (mounted) {
      setState(() {
        _active = f;
        _suggestions = [];
      });
    }
  }

  void _openSearch(_Field f) {
    setState(() {
      _searchOpen = true;
      _active = f;
      _suggestions = [];
      _picking = null;
    });
    _focusField(f);
  }

  void _focusField(_Field f) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (f == _Field.from ? _fromFocus : _toFocus).requestFocus();
    });
  }

  void _closeSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searchOpen = false;
      _suggestions = [];
    });
  }

  void _onQuery(String text) {
    setState(() {});
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final w = _window;
      if (w == null) return;
      final r = w.map.visibleRegion;
      _search.suggest(
        text,
        ymk.BoundingBox(r.bottomLeft, r.topRight),
        onResult: (list) {
          if (mounted) setState(() => _suggestions = list);
        },
        onError: _toast,
      );
    });
  }

  void _pickSuggestion(_Field f, Suggestion s) {
    _debounce?.cancel();
    final center = s.center;
    if (center != null) {
      _setPlace(f, AppPlace(name: s.title, address: s.subtitle, point: center));
      return;
    }
    final near = _me ?? ymk.Point(latitude: 52.2297, longitude: 21.0122);
    _search.resolve(
      s.searchText,
      near,
      onResult: (p) {
        if (!mounted) return;
        if (p == null) {
          _toast('Не удалось найти «${s.title}»');
        } else {
          _setPlace(f, AppPlace(name: s.title, address: s.subtitle, point: p.point));
        }
      },
      onError: _toast,
    );
  }

  Future<void> _useMyLocation(_Field f) async {
    if (_me == null) await _ensureLocation();
    if (!mounted) return;
    if (f == _Field.from) {
      setState(() {
        _from = null;
        _fromCtrl.text = _meLabel;
      });
      _afterPlaceChanged();
    } else {
      final me = _me;
      if (me == null) return;
      _setPlace(_Field.to, AppPlace(name: _meLabel, address: '', point: me));
    }
  }

  void _startPick(_Field f) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _picking = f;
      _searchOpen = false;
      _suggestions = [];
    });
  }

  void _cancelPick() => setState(() => _picking = null);

  void _setPlace(_Field f, AppPlace p) {
    setState(() {
      if (f == _Field.from) {
        _from = p;
        _fromCtrl.text = p.name;
      } else {
        _to = p;
        _toCtrl.text = p.name;
      }
    });
    _afterPlaceChanged();
  }

  /// Общая часть после смены точки: закрыть поиск или перейти к «Куда».
  void _afterPlaceChanged() {
    final needDestination = _to == null;
    setState(() {
      _picking = null;
      _suggestions = [];
      _searchOpen = needDestination && _searchOpen;
      if (_searchOpen) _active = _Field.to;
    });
    if (_searchOpen) {
      _focusField(_Field.to);
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _refreshIcons();
    if (_to != null) _calculate();
  }

  void _swap() {
    final to = _to;
    if (to == null) return;
    final me = _me;
    final newTo = _from ??
        (me != null ? AppPlace(name: _meLabel, address: '', point: me) : null);
    setState(() {
      _from = to;
      _fromCtrl.text = to.name;
      _to = newTo;
      _toCtrl.text = newTo?.name ?? '';
    });
    _refreshIcons();
    _calculate();
  }

  // ======================= Маршруты =======================

  Future<void> _calculate() async {
    final to = _to;
    if (to == null) return;
    var from = _from?.point ?? _me;
    if (from == null) {
      await _ensureLocation();
      from = _me;
    }
    if (from == null) {
      _toast('Не удалось определить, откуда ехать. Укажите точку «Откуда».');
      return;
    }
    final gen = ++_gen;
    Crumbs.mark('расчёт маршрутов: старт');
    setState(() {
      _results.clear();
      _errors.clear();
      _loading
        ..clear()
        ..addAll(TravelMode.values);
      _selected = 0;
    });
    _redraw();
    _run(gen, TravelMode.drive, _routing.drive(from, to.point));
    _run(gen, TravelMode.walk, _routing.walk(from, to.point));
    _run(gen, TravelMode.transit, _routing.transit(from, to.point));
  }

  void _run(int gen, TravelMode m, Future<List<RouteResult>> f) {
    f.then((list) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _results[m] = list;
        _loading.remove(m);
      });
      if (m == _mode) _redraw(fit: true);
    }).catchError((Object e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _errors[m] = e is TimeoutException ? 'Нет ответа от сервиса' : e.toString();
        _loading.remove(m);
      });
      if (m == _mode) _redraw();
    });
  }

  void _setMode(TravelMode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _selected = 0;
    });
    _redraw(fit: true);
  }

  void _selectRoute(int i) {
    setState(() => _selected = i);
    _redraw(fit: true);
  }

  void _clearAll() {
    _posSub?.cancel();
    _posSub = null;
    _gen++;
    _geoToken++;
    setState(() {
      _from = null;
      _to = null;
      _fromCtrl.text = _meLabel;
      _toCtrl.clear();
      _results.clear();
      _errors.clear();
      _loading.clear();
      _navigating = false;
      _expanded = false;
    });
    _redraw();
  }

  // ======================= «В путь» =======================

  void _startNav() {
    if (_current == null) return;
    Crumbs.mark('в путь: старт');
    _posSub?.cancel();
    setState(() => _navigating = true);
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((p) {
      _me = ymk.Point(latitude: p.latitude, longitude: p.longitude);
      final h = p.heading;
      final azimuth = (h.isNaN || h < 0) ? 0.0 : h % 360;
      _window?.map.move(ymk.CameraPosition(
        _me!,
        zoom: 17.0,
        azimuth: azimuth,
        tilt: _mode == TravelMode.drive ? 45.0 : 0.0,
      ));
    });
  }

  void _stopNav() {
    _posSub?.cancel();
    _posSub = null;
    setState(() => _navigating = false);
    _redraw(fit: true);
  }

  // ======================= Интерфейс =======================

  @override
  Widget build(BuildContext context) {
    if (kMapkitKey.isEmpty) return const _NoKey();
    final top = MediaQuery.of(context).padding.top;
    final scheme = Theme.of(context).colorScheme;
    final idle = _to == null && !_searchOpen && _picking == null && !_navigating;
    final showPanel = _to != null && !_searchOpen && _picking == null && !_navigating;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          YandexMap(onMapCreated: _onMapCreated),
          if (idle)
            Positioned(top: top + 12, left: 12, right: 12, child: _idleBar(scheme)),
          if (_picking != null)
            Positioned(top: top + 12, left: 12, right: 72, child: _pickBanner(scheme)),
          Positioned(
            right: 12,
            top: top + (idle ? 76 : 12),
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
                  onPressed: () => _ensureLocation(move: true),
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          if (_navigating)
            Align(alignment: Alignment.bottomCenter, child: _navBar(scheme)),
          if (showPanel)
            Align(alignment: Alignment.bottomCenter, child: _routePanel(scheme)),
          if (_searchOpen) Positioned.fill(child: _searchOverlay(scheme)),
        ],
      ),
    );
  }

  // ---- Главный экран: строка поиска ----

  Widget _idleBar(ColorScheme scheme) {
    return Material(
      elevation: 6,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => _openSearch(_Field.to),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            children: [
              Icon(Icons.search, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Куда едем?',
                  style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
                ),
              ),
              const Icon(Icons.directions, color: _blue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickBanner(ColorScheme scheme) {
    final what = _picking == _Field.from ? 'откуда' : 'куда';
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(
          children: [
            Expanded(child: Text('Нажмите на карту: $what')),
            TextButton(onPressed: _cancelPick, child: const Text('Отмена')),
          ],
        ),
      ),
    );
  }

  // ---- Экран поиска адресов ----

  Widget _searchOverlay(ColorScheme scheme) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: 'Назад',
                    onPressed: _closeSearch,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _textField(_fromCtrl, _fromFocus, 'Откуда',
                            Icons.trip_origin, _blue, _Field.from),
                        const SizedBox(height: 8),
                        _textField(_toCtrl, _toFocus, 'Куда', Icons.location_on,
                            _red, _Field.to),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Поменять местами',
                    onPressed: _swap,
                    icon: const Icon(Icons.swap_vert),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(bottom: 16 + keyboard),
                children: [
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: _blue,
                      child: Icon(Icons.my_location, color: Colors.white, size: 20),
                    ),
                    title: const Text(_meLabel),
                    onTap: () => _useMyLocation(_active),
                  ),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.secondaryContainer,
                      child: Icon(Icons.pin_drop_outlined,
                          color: scheme.onSecondaryContainer, size: 20),
                    ),
                    title: const Text('Выбрать на карте'),
                    onTap: () => _startPick(_active),
                  ),
                  const Divider(height: 1),
                  for (final s in _suggestions)
                    ListTile(
                      leading: Icon(Icons.place_outlined, color: scheme.onSurfaceVariant),
                      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: s.subtitle.isEmpty
                          ? null
                          : Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _pickSuggestion(_active, s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController ctrl,
    FocusNode node,
    String hint,
    IconData icon,
    Color color,
    _Field f,
  ) {
    return TextField(
      controller: ctrl,
      focusNode: node,
      onChanged: _onQuery,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        prefixIcon: Icon(icon, color: color, size: 20),
        suffixIcon: ctrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  ctrl.clear();
                  setState(() => _suggestions = []);
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  // ---- Нижняя панель маршрута ----

  Widget _routePanel(ColorScheme scheme) {
    final cur = _current;
    final maxH = MediaQuery.sizeOf(context).height * 0.72;
    return GestureDetector(
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -250 && !_expanded) setState(() => _expanded = true);
        if (v > 250 && _expanded) setState(() => _expanded = false);
      },
      child: Material(
        elevation: 14,
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _handle(scheme),
                  _addressBlock(scheme),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 6, 13, 0),
                    child: Row(
                      children: [
                        for (final m in TravelMode.values)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: _modeTile(m, scheme),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _summaryRow(scheme, cur),
                  if (_expanded && cur != null)
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _details(scheme, cur),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle(ColorScheme scheme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: SizedBox(
        height: 24,
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  /// Откуда → куда: всегда на виду, и в свёрнутой, и в развёрнутой панели.
  Widget _addressBlock(ColorScheme scheme) {
    final to = _to!;
    final fromText = _from?.name ?? _meLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openSearch(_Field.from),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.trip_origin, size: 18, color: _blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            fromText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, indent: 30, color: scheme.outlineVariant),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openSearch(_Field.to),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, size: 18, color: _red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                to.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (to.address.isNotEmpty)
                                Text(
                                  to.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Поменять местами',
                onPressed: _swap,
                icon: const Icon(Icons.swap_vert),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Закрыть маршрут',
                onPressed: _clearAll,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeTile(TravelMode m, ColorScheme scheme) {
    final selected = m == _mode;
    final list = _results[m];
    Widget trailing;
    if (_loading.contains(m)) {
      trailing = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (list != null && list.isNotEmpty) {
      trailing = Text(
        formatDuration(list.first.seconds),
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
    } else {
      trailing = const Text('—');
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _setMode(m),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        ),
        child: Column(
          children: [
            Icon(m.icon, size: 22),
            const SizedBox(height: 2),
            Text(m.label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(ColorScheme scheme, RouteResult? cur) {
    Widget left;
    if (_loading.contains(_mode)) {
      left = const LinearProgressIndicator();
    } else if (_errors[_mode] != null) {
      left = Text(_errors[_mode]!, style: TextStyle(color: scheme.error));
    } else if (cur != null) {
      final big = _mode == TravelMode.transit
          ? formatDuration(cur.seconds)
          : '${formatDuration(cur.seconds)} · ${formatDistance(cur.meters)}';
      left = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(big, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text(
            _summaryText(cur),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      );
    } else {
      left = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
      child: Row(
        children: [
          Expanded(child: left),
          IconButton(
            tooltip: _expanded ? 'Свернуть' : 'Подробнее',
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_more : Icons.expand_less),
          ),
          FilledButton.icon(
            onPressed: cur == null ? null : _startNav,
            icon: const Icon(Icons.navigation),
            label: const Text('В путь'),
          ),
        ],
      ),
    );
  }

  String _summaryText(RouteResult r) {
    switch (r.mode) {
      case TravelMode.drive:
        return 'С учётом текущих пробок';
      case TravelMode.walk:
        return 'Пешеходный маршрут';
      case TravelMode.transit:
        final transfers =
            r.transfers == 0 ? 'без пересадок' : 'пересадок: ${r.transfers}';
        return 'Пешком ${formatDistance(r.walkMeters)} · $transfers';
    }
  }

  Widget _details(ColorScheme scheme, RouteResult cur) {
    final list = _results[_mode] ?? const <RouteResult>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (list.length > 1) ...[
          const Text('Варианты', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) => RouteCard(
                route: list[i],
                selected: identical(list[i], cur),
                onTap: () => _selectRoute(i),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (cur.steps.isNotEmpty) ...[
          const Text('Как ехать', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final s in cur.steps) StepTile(step: s),
        ] else if (list.length <= 1)
          Text(
            'Для этого способа других вариантов нет.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }

  // ---- Панель во время поездки ----

  Widget _navBar(ColorScheme scheme) {
    final r = _current;
    final detail = r == null
        ? ''
        : _mode == TravelMode.transit
            ? '${formatDuration(r.seconds)} · пешком ${formatDistance(r.walkMeters)}'
            : '${formatDuration(r.seconds)} · ${formatDistance(r.meters)}';
    return Material(
      elevation: 12,
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(_mode.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _to?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(detail),
                  ],
                ),
              ),
              FilledButton.tonal(onPressed: _stopNav, child: const Text('Завершить')),
            ],
          ),
        ),
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
