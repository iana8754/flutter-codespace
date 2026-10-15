import 'package:flutter/material.dart';

class DayForecast {
  final DateTime date;
  final double max, min;
  final int code;
  DayForecast(this.date, this.max, this.min, this.code);
}

class Weather {
  final double temp, feels, wind;
  final int humidity, code;
  final List<DayForecast> days;

  Weather({
    required this.temp, required this.feels, required this.wind,
    required this.humidity, required this.code, required this.days,
  });

  factory Weather.fromJson(Map<String, dynamic> j) {
    final cur = j['current'];
    final d = j['daily'];
    final days = List.generate(
      (d['time'] as List).length,
      (i) => DayForecast(
        DateTime.parse(d['time'][i]),
        (d['temperature_2m_max'][i] as num).toDouble(),
        (d['temperature_2m_min'][i] as num).toDouble(),
        d['weather_code'][i] as int,
      ),
    );
    return Weather(
      temp: (cur['temperature_2m'] as num).toDouble(),
      feels: (cur['apparent_temperature'] as num).toDouble(),
      wind: (cur['wind_speed_10m'] as num).toDouble(),
      humidity: cur['relative_humidity_2m'] as int,
      code: cur['weather_code'] as int,
      days: days,
    );
  }
}

/// Эмодзи, описание и цвета фона для кода погоды (WMO)
class WeatherInfo {
  final String emoji, text;
  final List<Color> colors;
  const WeatherInfo(this.emoji, this.text, this.colors);
}

WeatherInfo infoFor(int c) {
  if (c == 0) return const WeatherInfo('☀️', 'Ясно', [Color(0xFF4FC3F7), Color(0xFF1565C0)]);
  if (c <= 3) return const WeatherInfo('⛅', 'Облачно', [Color(0xFF78909C), Color(0xFF37474F)]);
  if (c == 45 || c == 48) return const WeatherInfo('🌫️', 'Туман', [Color(0xFF90A4AE), Color(0xFF546E7A)]);
  if (c >= 51 && c <= 57) return const WeatherInfo('🌦️', 'Морось', [Color(0xFF5C6BC0), Color(0xFF283593)]);
  if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82)) {
    return const WeatherInfo('🌧️', 'Дождь', [Color(0xFF455A64), Color(0xFF1A237E)]);
  }
  if ((c >= 71 && c <= 77) || c == 85 || c == 86) {
    return const WeatherInfo('❄️', 'Снег', [Color(0xFF81D4FA), Color(0xFF5C6BC0)]);
  }
  if (c >= 95) return const WeatherInfo('⛈️', 'Гроза', [Color(0xFF311B92), Color(0xFF000000)]);
  return const WeatherInfo('🌡️', 'Нет данных', [Color(0xFF607D8B), Color(0xFF263238)]);
}