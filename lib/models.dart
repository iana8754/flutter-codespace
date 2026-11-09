import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;

enum TravelMode {
  drive('Авто', Icons.directions_car),
  walk('Пешком', Icons.directions_walk),
  transit('Транспорт', Icons.directions_transit);

  const TravelMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class RouteException implements Exception {
  RouteException(this.message);
  final String message;
  @override
  String toString() => message;
}

String formatDuration(int seconds) {
  final minutes = (seconds / 60).round();
  final m = minutes < 1 ? 1 : minutes;
  if (m < 60) return '$m мин';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h ч' : '$h ч $r мин';
}

String formatDistance(int meters) => meters < 1000
    ? '$meters м'
    : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} км';

/// Приводит список типов транспорта от Яндекса к одному из наших видов.
String normalizeVehicle(List<String> types) {
  for (final raw in types) {
    final t = raw.toLowerCase();
    if (t.contains('minibus')) return 'minibus';
    if (t.contains('trolleybus')) return 'trolleybus';
    if (t.contains('bus')) return 'bus';
    if (t.contains('tram')) return 'tram';
    if (t.contains('underground') || t.contains('metro') || t.contains('subway')) {
      return 'subway';
    }
    if (t.contains('suburban') || t.contains('rail') || t.contains('train')) {
      return 'train';
    }
    if (t.contains('water') || t.contains('ferry')) return 'ferry';
  }
  return 'other';
}

IconData vehicleIcon(String kind) {
  switch (kind) {
    case 'bus':
      return Icons.directions_bus;
    case 'minibus':
      return Icons.airport_shuttle;
    case 'trolleybus':
      return Icons.directions_bus_filled;
    case 'tram':
      return Icons.tram;
    case 'subway':
      return Icons.subway;
    case 'train':
      return Icons.train;
    case 'ferry':
      return Icons.directions_boat;
    default:
      return Icons.directions_transit;
  }
}

String vehicleLabel(String kind) {
  switch (kind) {
    case 'bus':
      return 'Автобус';
    case 'minibus':
      return 'Маршрутка';
    case 'trolleybus':
      return 'Троллейбус';
    case 'tram':
      return 'Трамвай';
    case 'subway':
      return 'Метро';
    case 'train':
      return 'Электричка';
    case 'ferry':
      return 'Паром';
    default:
      return 'Транспорт';
  }
}

Color vehicleDefaultColor(String kind) {
  switch (kind) {
    case 'bus':
      return const Color(0xFF2E9E5B);
    case 'minibus':
      return const Color(0xFFF57C00);
    case 'trolleybus':
      return const Color(0xFF1976D2);
    case 'tram':
      return const Color(0xFFD32F2F);
    case 'subway':
      return const Color(0xFF7B1FA2);
    case 'train':
      return const Color(0xFF455A64);
    case 'ferry':
      return const Color(0xFF00838F);
    default:
      return const Color(0xFF546E7A);
  }
}

class AppPlace {
  const AppPlace({
    required this.name,
    required this.address,
    required this.point,
  });
  final String name;
  final String address;
  final ymk.Point point;
}

class Suggestion {
  const Suggestion({
    required this.title,
    required this.subtitle,
    required this.searchText,
    required this.center,
  });
  final String title;
  final String subtitle;
  final String searchText;
  final ymk.Point? center;
}

/// Кусок маршрута одного цвета (для пробок: свой цвет на каждый участок).
class RouteSegment {
  const RouteSegment(this.polyline, this.color, {this.width = 9.0});
  final ymk.Polyline polyline;
  final Color color;
  final double width;
}

/// Значок линии для карточки маршрута: [🚌 175].
class LineInfo {
  const LineInfo({required this.kind, required this.label, required this.color});
  final String kind;
  final String label;
  final Color color;
}

enum StepKind { walk, ride }

class StepInfo {
  const StepInfo({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.seconds,
    required this.color,
    this.vehicle = 'other',
  });
  final StepKind kind;
  final String title;
  final String subtitle;
  final int seconds;
  final Color color;
  final String vehicle;
}

class StopMark {
  const StopMark({required this.point, required this.title, required this.boarding});
  final ymk.Point point;
  final String title;
  final bool boarding;
}

class RouteResult {
  const RouteResult({
    required this.mode,
    required this.seconds,
    required this.meters,
    required this.full,
    required this.segments,
    required this.points,
    this.walkMeters = 0,
    this.transfers = 0,
    this.steps = const [],
    this.stops = const [],
    this.lines = const [],
  });

  final TravelMode mode;
  final int seconds;

  /// Авто и пешком: длина маршрута. Транспорт: не используется (см. walkMeters).
  final int meters;
  final int walkMeters;
  final int transfers;
  final ymk.Polyline full;
  final List<RouteSegment> segments;
  final List<ymk.Point> points;
  final List<StepInfo> steps;
  final List<StopMark> stops;
  final List<LineInfo> lines;
}
