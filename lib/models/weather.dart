import 'package:flutter/material.dart';

class HourForecast {
  final DateTime time;
  final double temp;
  final int code;
  final bool isDay;
  final int? rainProb;
  HourForecast(this.time, this.temp, this.code, this.isDay, this.rainProb);
}

class DayForecast {
  final DateTime date;
  final double max, min;
  final int code;
  DayForecast(this.date, this.max, this.min, this.code);
}

class Weather {
  final double temp, feels, wind, gust, windDir, precip, pressure;
  final double? uv, visibilityKm;
  final int humidity, code;
  final bool isDay;
  final DateTime? sunrise, sunset;
  final List<HourForecast> hours;
  final List<DayForecast> days;
  final String source;

  Weather({
    required this.temp,
    required this.feels,
    required this.wind,
    required this.gust,
    required this.windDir,
    required this.precip,
    required this.pressure,
    required this.humidity,
    required this.code,
    required this.isDay,
    required this.hours,
    required this.days,
    required this.source,
    this.uv,
    this.visibilityKm,
    this.sunrise,
    this.sunset,
  });
}

class WeatherInfo {
  final String emoji, text;
  final List<Color> colors;
  const WeatherInfo(this.emoji, this.text, this.colors);
}

WeatherInfo infoFor(int c, {bool isDay = true}) {
  const clearDay = [Color(0xFF2B6CD9), Color(0xFF74B9F5)];
  const clearNight = [Color(0xFF0B1B3F), Color(0xFF2E4482)];
  const cloudDay = [Color(0xFF5B7796), Color(0xFF9CB3C9)];
  const cloudNight = [Color(0xFF1C2838), Color(0xFF3E4E62)];
  const rainDay = [Color(0xFF3A4A5E), Color(0xFF7388A0)];
  const rainNight = [Color(0xFF141C29), Color(0xFF2E3C4E)];
  const snowDay = [Color(0xFF7F9BB8), Color(0xFFCADAE8)];
  const snowNight = [Color(0xFF2A3548), Color(0xFF55657D)];
  const stormy = [Color(0xFF2B2740), Color(0xFF55497A)];
  const foggy = [Color(0xFF7C8A96), Color(0xFFB8C2CA)];

  List<Color> pick(List<Color> d, List<Color> n) => isDay ? d : n;

  if (c == 0) return WeatherInfo(isDay ? '☀️' : '🌙', 'Ясно', pick(clearDay, clearNight));
  if (c == 1) return WeatherInfo(isDay ? '🌤️' : '🌙', 'Малооблачно', pick(clearDay, clearNight));
  if (c == 2) return WeatherInfo(isDay ? '⛅' : '☁️', 'Переменная облачность', pick(cloudDay, cloudNight));
  if (c == 3) return WeatherInfo('☁️', 'Пасмурно', pick(cloudDay, cloudNight));
  if (c == 45 || c == 48) return WeatherInfo('🌫️', 'Туман', foggy);
  if (c >= 51 && c <= 57) return WeatherInfo('🌦️', 'Морось', pick(rainDay, rainNight));
  if (c == 66 || c == 67) return WeatherInfo('🌧️', 'Ледяной дождь', pick(rainDay, rainNight));
  if (c >= 61 && c <= 65) return WeatherInfo('🌧️', 'Дождь', pick(rainDay, rainNight));
  if (c >= 80 && c <= 82) return WeatherInfo('🌧️', 'Ливень', pick(rainDay, rainNight));
  if ((c >= 71 && c <= 77) || c == 85 || c == 86) {
    return WeatherInfo('❄️', 'Снег', pick(snowDay, snowNight));
  }
  if (c >= 95) return WeatherInfo('⛈️', 'Гроза', stormy);
  return WeatherInfo('🌡️', 'Нет данных', pick(cloudDay, cloudNight));
}

String windDirName(double deg) {
  const n = ['С', 'СВ', 'В', 'ЮВ', 'Ю', 'ЮЗ', 'З', 'СЗ'];
  return n[((deg + 22.5) / 45).floor() % 8];
}

String uvLabel(double uv) {
  if (uv < 3) return 'Низкий';
  if (uv < 6) return 'Умеренный';
  if (uv < 8) return 'Высокий';
  if (uv < 11) return 'Очень высокий';
  return 'Экстремальный';
}