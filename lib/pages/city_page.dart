import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/city.dart';
import '../models/weather.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';

const _big = TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w400);
const _label = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600);
const _note = TextStyle(color: Colors.white70, fontSize: 12);

class CityPage extends StatefulWidget {
  final City city;
  const CityPage({super.key, required this.city});

  @override
  State<CityPage> createState() => _CityPageState();
}

class _CityPageState extends State<CityPage> with AutomaticKeepAliveClientMixin {
  Weather? w;
  String? placeName;
  String? error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => error = null);
    try {
      var lat = widget.city.lat, lon = widget.city.lon;
      if (widget.city.isGps) {
        final pos = await LocationService.getPosition();
        lat = pos.latitude;
        lon = pos.longitude;
        LocationService.getCity(lat, lon).then((n) {
          if (mounted) setState(() => placeName = n);
        });
      }
      final res = await WeatherService.fetch(lat, lon, isGps: widget.city.isGps);
      if (mounted) setState(() => w = res);
    } catch (e) {
      if (!mounted) return;
      if (w == null) {
        setState(() => error = e.toString());
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Не удалось обновить данные')));
      }
    }
  }

  String get _title => widget.city.isGps ? 'Моё местоположение' : widget.city.name;
  String get _sub => widget.city.isGps ? (placeName ?? '') : (widget.city.region ?? '');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final info = w != null ? infoFor(w!.code, isDay: w!.isDay) : infoFor(3);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: info.colors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(bottom: false, child: _content(info)),
    );
  }

  Widget _content(WeatherInfo info) {
    final x = w;
    if (x == null) {
      if (error != null) return _errorView();
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(widget.city.isGps ? 'Определяем местоположение…' : 'Загрузка…',
              style: const TextStyle(color: Colors.white70)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 110),
        children: [
          _header(x, info),
          const SizedBox(height: 24),
          _hourly(x),
          const SizedBox(height: 12),
          _daily(x),
          const SizedBox(height: 12),
          _wind(x),
          const SizedBox(height: 12),
          ..._tiles(x),
          Center(
            child: Text('Данные: ${x.source}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, color: Colors.white, size: 64),
            const SizedBox(height: 16),
            Text(error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 16),
            FilledButton(onPressed: load, child: const Text('Повторить')),
          ]),
        ),
      );

  Widget _header(Weather x, WeatherInfo info) {
    final today = x.days.isNotEmpty ? x.days.first : null;
    return Column(children: [
      Text(_title, textAlign: TextAlign.center, style: _big),
      if (_sub.isNotEmpty)
        Text(_sub, style: const TextStyle(color: Colors.white70, fontSize: 15)),
      const SizedBox(height: 8),
      Text('${x.temp.round()}°',
          style: const TextStyle(
              color: Colors.white, fontSize: 96, fontWeight: FontWeight.w200, height: 1.1)),
      Text('${info.emoji}  ${info.text}',
          style: const TextStyle(color: Colors.white, fontSize: 20)),
      if (today != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Макс.: ${today.max.round()}°   Мин.: ${today.min.round()}°',
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
        ),
    ]);
  }

  Widget _glass({required IconData icon, required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _hourly(Weather x) => _glass(
        icon: Icons.schedule,
        title: 'ПОЧАСОВОЙ ПРОГНОЗ',
        child: SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: x.hours.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (_, i) {
              final h = x.hours[i];
              final hi = infoFor(h.code, isDay: h.isDay);
              final rain = h.rainProb ?? 0;
              return Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(i == 0 ? 'Сейчас' : DateFormat('HH').format(h.time),
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                Text(hi.emoji, style: const TextStyle(fontSize: 26)),
                Text('${h.temp.round()}°', style: _label),
                Text(rain >= 20 ? '$rain%' : ' ',
                    style: const TextStyle(color: Color(0xFF9BDCFF), fontSize: 11)),
              ]);
            },
          ),
        ),
      );

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _daily(Weather x) {
    if (x.days.isEmpty) return const SizedBox.shrink();
    final gLo = x.days.map((d) => d.min).reduce(math.min);
    final gHi = x.days.map((d) => d.max).reduce(math.max);
    return _glass(
      icon: Icons.calendar_month,
      title: '${x.days.length}-ДНЕВНЫЙ ПРОГНОЗ',
      child: Column(children: [
        for (var i = 0; i < x.days.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(
                width: 76,
                child: Text(
                  i == 0 ? 'Сегодня' : _cap(DateFormat.E('ru').format(x.days[i].date)),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              Text(infoFor(x.days[i].code).emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text('${x.days[i].min.round()}°',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white60, fontSize: 16)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RangeBar(lo: x.days[i].min, hi: x.days[i].max, gLo: gLo, gHi: gHi),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text('${x.days[i].max.round()}°',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _kv(String v, String text) => Row(children: [
        Text(v, style: const TextStyle(color: Colors.white, fontSize: 30)),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]);

  Widget _wind(Weather x) => _glass(
        icon: Icons.air,
        title: 'ВЕТЕР',
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kv('${x.wind.round()}', 'км/ч  Ветер'),
              const Divider(color: Colors.white24, height: 18),
              _kv('${x.gust.round()}', 'км/ч  Порывы'),
              const SizedBox(height: 6),
              Text('Направление: ${windDirName(x.windDir)}', style: _note),
            ]),
          ),
          _compass(x.windDir),
        ]),
      );

  Widget _compass(double dir) {
    const t = TextStyle(color: Colors.white70, fontSize: 11);
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          decoration: BoxDecoration(
              shape: BoxShape.circle, border: Border.all(color: Colors.white38, width: 1.5)),
        ),
        const Positioned(top: 4, child: Text('С', style: t)),
        const Positioned(bottom: 4, child: Text('Ю', style: t)),
        const Positioned(left: 8, child: Text('З', style: t)),
        const Positioned(right: 8, child: Text('В', style: t)),
        Transform.rotate(
          angle: (dir + 180) * math.pi / 180,
          child: const Icon(Icons.navigation, color: Colors.white, size: 34),
        ),
      ]),
    );
  }

  Widget _tile(IconData icon, String title, List<Widget> children) => SizedBox(
        height: 160,
        child: _glass(
          icon: icon,
          title: title,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

  double _dew(double t, int rh) {
    final g = math.log(math.max(rh, 1) / 100) + (17.625 * t) / (243.04 + t);
    return 243.04 * g / (17.625 - g);
  }

  List<Widget> _tiles(Weather x) {
    final t = <Widget>[];
    final hm = DateFormat.Hm();

    if (x.uv != null) {
      t.add(_tile(Icons.wb_sunny_outlined, 'УФ-ИНДЕКС', [
        Text('${x.uv!.round()}', style: _big),
        Text(uvLabel(x.uv!), style: _label),
        const SizedBox(height: 10),
        _UvBar(v: x.uv!),
      ]));
    }
    if (x.sunset != null && x.sunrise != null) {
      t.add(_tile(Icons.wb_twilight, 'ЗАКАТ', [
        Text(hm.format(x.sunset!), style: _big),
        const SizedBox(height: 6),
        Text('Восход: ${hm.format(x.sunrise!)}', style: _note),
      ]));
    }
    final diff = x.feels - x.temp;
    t.add(_tile(Icons.thermostat, 'ОЩУЩАЕТСЯ', [
      Text('${x.feels.round()}°', style: _big),
      const SizedBox(height: 6),
      Text(
        diff.abs() < 1.5
            ? 'Близко к фактической температуре.'
            : (diff < 0 ? 'Ощущается холоднее.' : 'Ощущается теплее.'),
        style: _note,
      ),
    ]));
    t.add(_tile(Icons.water_drop_outlined, 'ОСАДКИ', [
      Text('${x.precip.toStringAsFixed(1)} мм', style: _big),
      const SizedBox(height: 6),
      const Text('за последний час', style: _note),
    ]));
    if (x.visibilityKm != null) {
      final v = x.visibilityKm!;
      t.add(_tile(Icons.visibility_outlined, 'ВИДИМОСТЬ', [
        Text('${v >= 10 ? v.round().toString() : v.toStringAsFixed(1)} км', style: _big),
        const SizedBox(height: 6),
        Text(v >= 10 ? 'Отличная видимость.' : (v >= 4 ? 'Хорошая видимость.' : 'Видимость плохая.'),
            style: _note),
      ]));
    }
    t.add(_tile(Icons.opacity, 'ВЛАЖНОСТЬ', [
      Text('${x.humidity}%', style: _big),
      const SizedBox(height: 6),
      Text('Точка росы: ${_dew(x.temp, x.humidity).round()}°', style: _note),
    ]));
    t.add(_tile(Icons.speed, 'ДАВЛЕНИЕ', [
      Text('${(x.pressure * 0.750062).round()}', style: _big),
      const SizedBox(height: 6),
      const Text('мм рт. ст.', style: _note),
    ]));

    final rows = <Widget>[];
    for (var i = 0; i < t.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: t[i]),
          const SizedBox(width: 12),
          Expanded(child: i + 1 < t.length ? t[i + 1] : const SizedBox()),
        ]),
      ));
    }
    return rows;
  }
}

class _RangeBar extends StatelessWidget {
  final double lo, hi, gLo, gHi;
  const _RangeBar({required this.lo, required this.hi, required this.gLo, required this.gHi});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final span = (gHi - gLo) == 0 ? 1.0 : (gHi - gLo);
      final l = (lo - gLo) / span * c.maxWidth;
      final r = (hi - gLo) / span * c.maxWidth;
      final left = math.min(l, c.maxWidth - 6);
      final width = math.min(math.max(r - l, 6.0), c.maxWidth - left);
      return SizedBox(
        height: 5,
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(3)),
          ),
          Positioned(
            left: left,
            width: width,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(
                    colors: [Color(0xFF7FD6FF), Color(0xFFFFD166)]),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

class _UvBar extends StatelessWidget {
  final double v;
  const _UvBar({required this.v});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final pos = math.min(math.max(v, 0.0), 11.0) / 11 * c.maxWidth;
      return SizedBox(
        height: 10,
        child: Stack(alignment: Alignment.centerLeft, children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(colors: [
                Color(0xFF4CAF50),
                Color(0xFFFFEB3B),
                Color(0xFFFF9800),
                Color(0xFFF44336),
                Color(0xFF9C27B0),
              ]),
            ),
          ),
          Positioned(
            left: math.max(0, pos - 5),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26),
              ),
            ),
          ),
        ]),
      );
    });
  }
}