import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/weather.dart';

class WeatherService {
  static const _ua = {
    'User-Agent': 'FlutterWeatherApp/1.0 (github.com/iana8754/flutter-codespace)'
  };

  static double _n(dynamic v, [double def = 0]) => v is num ? v.toDouble() : def;

  static Future<Weather> fetch(double lat, double lon, {bool isGps = false}) async {
    try {
      return await _openMeteo(lat, lon);
    } catch (e1) {
      try {
        return await _metNo(lat, lon, isGps);
      } catch (e2) {
        throw 'Не удалось получить погоду. Проверьте интернет.\n\nOpen-Meteo: $e1\nMET Norway: $e2';
      }
    }
  }

  // ---------- Основной источник: Open-Meteo ----------
  static Future<Weather> _openMeteo(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current':
          'temperature_2m,apparent_temperature,relative_humidity_2m,is_day,precipitation,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,visibility',
      'hourly': 'temperature_2m,weather_code,is_day,precipitation_probability',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max',
      'forecast_days': '7',
      'timezone': 'auto',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw 'код ${res.statusCode}';
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = j['current'] as Map<String, dynamic>;
    final h = j['hourly'] as Map<String, dynamic>;
    final d = j['daily'] as Map<String, dynamic>;

    final now = DateTime.parse(cur['time'] as String);
    final from = DateTime(now.year, now.month, now.day, now.hour);
    final times = h['time'] as List;
    final hours = <HourForecast>[];
    for (var i = 0; i < times.length && hours.length < 24; i++) {
      final t = DateTime.parse(times[i] as String);
      if (t.isBefore(from)) continue;
      hours.add(HourForecast(
        t,
        _n(h['temperature_2m'][i]),
        (h['weather_code'][i] as num?)?.toInt() ?? 0,
        _n(h['is_day'][i], 1) == 1,
        (h['precipitation_probability'][i] as num?)?.toInt(),
      ));
    }

    final dt = d['time'] as List;
    final days = List.generate(
      dt.length,
      (i) => DayForecast(
        DateTime.parse(dt[i] as String),
        _n(d['temperature_2m_max'][i]),
        _n(d['temperature_2m_min'][i]),
        (d['weather_code'][i] as num?)?.toInt() ?? 0,
      ),
    );

    DateTime? first(dynamic l) =>
        (l is List && l.isNotEmpty && l[0] is String) ? DateTime.parse(l[0] as String) : null;
    final uvList = d['uv_index_max'];
    final uv = (uvList is List && uvList.isNotEmpty && uvList[0] is num)
        ? (uvList[0] as num).toDouble()
        : null;
    final vis = cur['visibility'];

    return Weather(
      temp: _n(cur['temperature_2m']),
      feels: _n(cur['apparent_temperature']),
      wind: _n(cur['wind_speed_10m']),
      gust: _n(cur['wind_gusts_10m']),
      windDir: _n(cur['wind_direction_10m']),
      precip: _n(cur['precipitation']),
      pressure: _n(cur['pressure_msl'], 1013),
      humidity: _n(cur['relative_humidity_2m']).round(),
      code: (cur['weather_code'] as num?)?.toInt() ?? 0,
      isDay: _n(cur['is_day'], 1) == 1,
      uv: uv,
      visibilityKm: vis is num ? vis.toDouble() / 1000 : null,
      sunrise: first(d['sunrise']),
      sunset: first(d['sunset']),
      hours: hours,
      days: days,
      source: 'Open-Meteo',
    );
  }

  // ---------- Запасной источник: MET Norway ----------
  static int _metToCode(String s) {
    final b = s.split('_').first;
    if (b.contains('thunder')) return 95;
    if (b.contains('sleet')) return 67;
    if (b.contains('snow')) return 73;
    if (b.contains('rain')) return b.contains('heavy') ? 65 : 63;
    if (b == 'fog') return 45;
    if (b == 'clearsky') return 0;
    if (b == 'fair') return 1;
    if (b == 'partlycloudy') return 2;
    return 3;
  }

  static Future<Weather> _metNo(double lat, double lon, bool isGps) async {
    final uri = Uri.https('api.met.no', '/weatherapi/locationforecast/2.0/compact', {
      'lat': lat.toStringAsFixed(4),
      'lon': lon.toStringAsFixed(4),
    });
    final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw 'код ${res.statusCode}';
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final series = (j['properties']['timeseries'] as List).cast<Map<String, dynamic>>();

    // MET отдаёт время в UTC; часовой пояс оцениваем приблизительно
    final off = isGps ? DateTime.now().timeZoneOffset : Duration(hours: (lon / 15).round());
    DateTime local(Map<String, dynamic> e) => DateTime.parse(e['time'] as String).toUtc().add(off);
    final nowL = DateTime.now().toUtc().add(off);
    final from = DateTime.utc(nowL.year, nowL.month, nowL.day, nowL.hour);

    Map<String, dynamic> det(Map<String, dynamic> e) =>
        e['data']['instant']['details'] as Map<String, dynamic>;
    String? sym(Map<String, dynamic> e) {
      for (final k in ['next_1_hours', 'next_6_hours', 'next_12_hours']) {
        final s = e['data'][k]?['summary']?['symbol_code'];
        if (s is String) return s;
      }
      return null;
    }

    var start = series.indexWhere((e) => !local(e).isBefore(from));
    if (start < 0) start = 0;
    final c = series[start];
    final cd = det(c);
    final cs = sym(c) ?? 'cloudy';
    final wind = _n(cd['wind_speed']) * 3.6;

    final hours = <HourForecast>[];
    for (var i = start; i < series.length && hours.length < 24; i++) {
      final e = series[i];
      if (e['data']['next_1_hours'] == null) continue;
      final s = sym(e) ?? 'cloudy';
      hours.add(HourForecast(local(e), _n(det(e)['air_temperature']), _metToCode(s),
          !s.endsWith('_night'), null));
    }

    final byDay = <String, List<Map<String, dynamic>>>{};
    for (var i = start; i < series.length; i++) {
      final t = local(series[i]);
      byDay.putIfAbsent('${t.year}-${t.month}-${t.day}', () => []).add(series[i]);
    }
    final days = <DayForecast>[];
    for (final list in byDay.values.take(7)) {
      final temps = list.map((e) => _n(det(e)['air_temperature'])).toList();
      final mid = list.reduce((a, b) =>
          (local(a).hour - 12).abs() <= (local(b).hour - 12).abs() ? a : b);
      days.add(DayForecast(local(list.first), temps.reduce(math.max), temps.reduce(math.min),
          _metToCode(sym(mid) ?? 'cloudy')));
    }

    return Weather(
      temp: _n(cd['air_temperature']),
      feels: _n(cd['air_temperature']),
      wind: wind,
      gust: cd['wind_speed_of_gust'] is num ? _n(cd['wind_speed_of_gust']) * 3.6 : wind,
      windDir: _n(cd['wind_from_direction']),
      precip: _n(c['data']['next_1_hours']?['details']?['precipitation_amount']),
      pressure: _n(cd['air_pressure_at_sea_level'], 1013),
      humidity: _n(cd['relative_humidity']).round(),
      code: _metToCode(cs),
      isDay: !cs.endsWith('_night'),
      uv: cd['ultraviolet_index_clear_sky'] is num ? _n(cd['ultraviolet_index_clear_sky']) : null,
      hours: hours,
      days: days,
      source: 'MET Norway (запасной источник)',
    );
  }
}