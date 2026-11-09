import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_maps_mapkit/image.dart' as ymimg;
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import 'config.dart';
import 'map_icons.dart';
import 'models.dart';
import 'routing.dart';
import 'search.dart';
import 'widgets.dart';

enum _Field { from, to }

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
  final _sheet = DraggableScrollableController();
  Timer? _debounce;
  AppPlace? _from; // null = «моё местоположение»
  AppPlace? _to;
  _Field? _active; // какое поле сейчас редактируется
  _Field? _picking; // ждём нажатия на карту для этого поля
  List<Suggestion> _suggestions = [];

  // ---- маршруты ----
  TravelMode _mode = TravelMode.drive;
  final Map<TravelMode, List<RouteResult>> _results = {};
  final Map<TravelMode, String> _errors = {};
  final Set<TravelMode> _loading = {};
  int _selected = 0;
  int _gen = 0;
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
    _sheet.dispose();
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

  void _sheetTo(double size) {
    if (_sheet.isAttached) {
      _sheet.animateTo(
        size,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  // ======================= Карта =======================

  Future<void> _onMapCreated(ymk.MapWindow window) async {
    _window = window;
    _traffic = mapkit.createTrafficLayer(window)..setTrafficVisible(_trafficOn);
    _routeLayer = window.map.mapObjects.addCollection();
    _markerLayer = window.map.mapObjects.addCollection();

    _mapInput = _MapInput(onTap: _onMapTap, onLongTap: _onMapLongTap);
    window.map.addInputListener(_mapInput!);

    _iconFrom = ymimg.ImageProvider.fromImageProvider(
      MemoryImage(await makeDotIcon(fill: const Color(0xFF2F80ED))),
    );
    _iconTo = ymimg.ImageProvider.fromImageProvider(
      MemoryImage(await makeDotIcon(fill: const Color(0xFFE53935), size: 84)),
    );
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

  // Нажатия на карту: выбор точки «Откуда/Куда».
  void _onMapTap(ymk.Point p) {
    if (!mounted || _picking == null) return;
    _applyPicked(p);
  }

  void _onMapLongTap(ymk.Point p) {
    if (!mounted) return;
    if (_picking != null) {
      _applyPicked(p);
    } else {
      _setPlace(_Field.to, _placeFromPoint(p));
    }
  }

  AppPlace _placeFromPoint(ymk.Point p) => AppPlace(
        name: 'Точка на карте',
        address:
            '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
        point: p,
      );

  void _applyPicked(ymk.Point p) {
    final f = _picking;
    if (f == null) return;
    _setPlace(f, _placeFromPoint(p));
  }

  // ---- отрисовка маршрутов и маркеров ----

  void _redraw({bool fit = false}) {
    final layer = _routeLayer;
    final markers = _markerLayer;
    if (layer == null || markers == null) return;
    layer.clear();
    markers.clear();

    final list = _results[_mode] ?? const <RouteResult>[];
    final cur = _current;
    if (list.isNotEmpty && cur != null) {
      for (var i = 0; i < list.length; i++) {
        if (identical(list[i], cur)) continue;
        layer.addPolylineWithGeometry(list[i].full)
          ..style = const ymk.LineStyle(
            strokeWidth: 6.0,
            outlineWidth: 1.5,
            outlineColor: Colors.white,
          )
          ..setStrokeColor(Colors.grey.shade600);
      }
      for (final seg in cur.segments) {
        layer.addPolylineWithGeometry(seg.polyline)
          ..style = ymk.LineStyle(
            strokeWidth: seg.width,
            outlineWidth: 2.5,
            outlineColor: Colors.white,
          )
          ..setStrokeColor(seg.color);
      }
      if (_mode == TravelMode.transit) {
        for (final s in cur.stops) {
          markers.addPlacemark()
            ..geometry = s.point
            ..setIcon(_iconStop!);
        }
      }
    }

    final to = _to;
    if (to != null && _iconTo != null) {
      markers.addPlacemark()
        ..geometry = to.point
        ..setIcon(_iconTo!);
    }
    final from = _from;
    if (from != null && _iconFrom != null) {
      markers.addPlacemark()
        ..geometry = from.point
        ..setIcon(_iconFrom!);
    }

    if (fit && cur != null) _fit(cur.points);
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
    setState(() {
      _active = f;
      _picking = null;
      _suggestions = [];
    });
    _sheetTo(0.92);
  }

  void _closeSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _active = null;
      _suggestions = [];
    });
    _sheetTo(_to == null ? 0.38 : 0.55);
  }

  void _onQuery(_Field f, String text) {
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
        _active = null;
        _suggestions = [];
      });
      FocusManager.instance.primaryFocus?.unfocus();
      _sheetTo(0.55);
      _calculate();
    } else {
      final me = _me;
      if (me == null) return;
      _setPlace(
        _Field.to,
        AppPlace(name: _meLabel, address: '', point: me),
      );
    }
  }

  void _startPick(_Field f) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _picking = f;
      _active = null;
      _suggestions = [];
    });
    _sheetTo(0.14);
  }

  void _cancelPick() {
    setState(() => _picking = null);
    _sheetTo(0.38);
  }

  void _setPlace(_Field f, AppPlace p) {
    setState(() {
      if (f == _Field.from) {
        _from = p;
        _fromCtrl.text = p.name;
      } else {
        _to = p;
        _toCtrl.text = p.name;
      }
      _active = null;
      _picking = null;
      _suggestions = [];
    });
    FocusManager.instance.primaryFocus?.unfocus();
    _sheetTo(0.55);
    _calculate();
  }

  void _swap() {
    final to = _to;
    if (to == null) return;
    final oldFrom = _from;
    final me = _me;
    final newTo = oldFrom ??
        (me != null ? AppPlace(name: _meLabel, address: '', point: me) : null);
    setState(() {
      _from = to;
      _fromCtrl.text = to.name;
      _to = newTo;
      _toCtrl.text = newTo?.name ?? '';
    });
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
    setState(() {
      _to = null;
      _toCtrl.clear();
      _results.clear();
      _errors.clear();
      _loading.clear();
      _navigating = false;
    });
    _redraw();
  }

  // ======================= «В путь» =======================

  void _startNav() {
    if (_current == null) return;
    _posSub?.cancel();
    setState(() => _navigating = true);
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((p) {
      _me = ymk.Point(latitude: p.latitude, longitude: p.longitude);
      _window?.map.move(ymk.CameraPosition(
        _me!,
        zoom: 17.0,
        azimuth: p.heading.isNaN ? 0.0 : p.heading,
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
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          YandexMap(onMapCreated: _onMapCreated),
          if (_picking != null)
            Positioned(top: top + 12, left: 12, right: 72, child: _pickBanner()),
          Positioned(
            right: 12,
            top: top + 12,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'traffic',
                  tooltip: 'Пробки',
                  backgroundColor: _trafficOn
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surface,
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
            Align(alignment: Alignment.bottomCenter, child: _navBar())
          else
            Positioned.fill(
              child: DraggableScrollableSheet(
                controller: _sheet,
                initialChildSize: 0.38,
                minChildSize: 0.14,
                maxChildSize: 0.92,
                snap: true,
                snapSizes: const [0.14, 0.38, 0.6, 0.92],
                builder: (context, scroll) => _sheetBody(context, scroll),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pickBanner() {
    final what = _picking == _Field.from ? 'откуда' : 'куда';
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).colorScheme.surface,
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

  Widget _navBar() {
    final r = _current;
    final scheme = Theme.of(context).colorScheme;
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

  Widget _sheetBody(BuildContext context, ScrollController scroll) {
    final scheme = Theme.of(context).colorScheme;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      elevation: 12,
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(16, 10, 16, 24 + keyboard),
        children: _sheetChildren(scheme),
      ),
    );
  }

  List<Widget> _sheetChildren(ColorScheme scheme) {
    final children = <Widget>[
      Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: scheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      _fieldsBlock(),
    ];

    if (_active != null) {
      children.addAll(_searchList());
      return children;
    }

    if (_to == null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          'Введите адрес или место в поле «Куда». Можно выбрать точку на карте '
          '(кнопка в списке) или поставить её долгим нажатием на карту.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ));
      return children;
    }

    children.add(const SizedBox(height: 12));
    children.add(Row(
      children: [
        for (final m in TravelMode.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _modeTile(m, scheme),
            ),
          ),
      ],
    ));

    final list = _results[_mode];
    final cur = _current;
    if (_loading.contains(_mode)) {
      children.add(const Padding(
        padding: EdgeInsets.only(top: 16),
        child: LinearProgressIndicator(),
      ));
    } else if (_errors[_mode] != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          _errors[_mode]!,
          style: TextStyle(color: scheme.error),
        ),
      ));
    } else if (list != null && list.isNotEmpty && cur != null) {
      children.add(const SizedBox(height: 12));
      children.add(SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => RouteCard(
            route: list[i],
            selected: identical(list[i], cur),
            onTap: () => _selectRoute(i),
          ),
        ),
      ));
      children.add(const SizedBox(height: 8));
      children.add(Text(
        _summaryText(cur),
        style: TextStyle(color: scheme.onSurfaceVariant),
      ));
      children.add(const SizedBox(height: 12));
      children.add(SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _startNav,
          icon: const Icon(Icons.navigation),
          label: Text(
            _mode == TravelMode.transit
                ? 'В путь · ${formatDuration(cur.seconds)}'
                : 'В путь · ${formatDuration(cur.seconds)} · ${formatDistance(cur.meters)}',
          ),
        ),
      ));
      if (cur.steps.isNotEmpty) {
        children.add(const Divider(height: 28));
        for (final s in cur.steps) {
          children.add(StepTile(step: s));
        }
      }
    }
    return children;
  }

  String _summaryText(RouteResult r) {
    switch (r.mode) {
      case TravelMode.drive:
        return 'Время указано с учётом текущих пробок';
      case TravelMode.walk:
        return 'Пешком ${formatDistance(r.meters)}';
      case TravelMode.transit:
        final transfers = r.transfers == 0
            ? 'без пересадок'
            : 'пересадок: ${r.transfers}';
        return 'Пешком ${formatDistance(r.walkMeters)} · $transfers';
    }
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
        style: const TextStyle(fontWeight: FontWeight.w600),
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

  Widget _fieldsBlock() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _input(_fromCtrl, _fromFocus, 'Откуда', Icons.trip_origin,
                  const Color(0xFF2F80ED), _Field.from),
              const SizedBox(height: 8),
              _input(_toCtrl, _toFocus, 'Куда', Icons.location_on,
                  const Color(0xFFE53935), _Field.to),
            ],
          ),
        ),
        Column(
          children: [
            IconButton(
              tooltip: 'Поменять местами',
              onPressed: _swap,
              icon: const Icon(Icons.swap_vert),
            ),
            if (_to != null)
              IconButton(
                tooltip: 'Сбросить',
                onPressed: _clearAll,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ],
    );
  }

  Widget _input(
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
      onChanged: (t) => _onQuery(f, t),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        prefixIcon: Icon(icon, color: color, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  List<Widget> _searchList() {
    final f = _active!;
    return [
      const SizedBox(height: 8),
      ListTile(
        leading: const Icon(Icons.my_location),
        title: const Text(_meLabel),
        onTap: () => _useMyLocation(f),
      ),
      ListTile(
        leading: const Icon(Icons.pin_drop_outlined),
        title: const Text('Выбрать на карте'),
        onTap: () => _startPick(f),
      ),
      const Divider(height: 1),
      for (final s in _suggestions)
        ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: s.subtitle.isEmpty
              ? null
              : Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _pickSuggestion(f, s),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: _closeSearch, child: const Text('Закрыть')),
      ),
    ];
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
