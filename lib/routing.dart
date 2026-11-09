import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/directions.dart' as dir;
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/transport.dart' as tr;

import 'models.dart';

/// Строит маршруты: на машине (с пробками), пешком и на общественном транспорте.
/// MapKit хранит слабые ссылки, поэтому сессии и слушатели лежат в полях.
class RoutingService {
  dir.DrivingRouter? _driving;
  tr.PedestrianRouter? _pedestrian;
  tr.MasstransitRouter? _transit;

  dir.DrivingSession? _drivingSession;
  tr.MasstransitSession? _pedestrianSession;
  tr.MasstransitSession? _transitSession;

  // ignore: unused_field
  dir.DrivingSessionRouteListener? _drivingListener;
  // ignore: unused_field
  tr.RouteHandler? _pedestrianHandler;
  // ignore: unused_field
  tr.RouteHandler? _transitHandler;

  List<ymk.RequestPoint> _points(ymk.Point from, ymk.Point to) => [
        ymk.RequestPoint(from, ymk.RequestPointType.Waypoint, null, null, null),
        ymk.RequestPoint(to, ymk.RequestPointType.Waypoint, null, null, null),
      ];

  // ---------- Авто ----------

  Future<List<RouteResult>> drive(ymk.Point from, ymk.Point to) {
    final c = Completer<List<RouteResult>>();
    _driving ??= dir.DirectionsFactory.instance
        .createDrivingRouter(dir.DrivingRouterType.Combined);
    _drivingSession?.cancel();

    final listener = dir.DrivingSessionRouteListener(
      onDrivingRoutes: (routes) {
        if (c.isCompleted) return;
        if (routes.isEmpty) {
          c.completeError(RouteException('Маршрут на машине не найден'));
        } else {
          try {
            c.complete([for (final r in routes) _fromDriving(r)]);
          } catch (e) {
            c.completeError(e);
          }
        }
      },
      onDrivingRoutesError: (error) {
        if (!c.isCompleted) {
          c.completeError(RouteException(error.toString()));
        }
      },
    );
    _drivingListener = listener;
    _drivingSession = _driving!.requestRoutes(
      dir.DrivingOptions(routesCount: 3),
      dir.DrivingVehicleOptions(),
      listener,
      points: _points(from, to),
    );
    return c.future.timeout(const Duration(seconds: 25));
  }

  RouteResult _fromDriving(dir.DrivingRoute r) {
    final weight = r.metadata.weight;
    final seconds = weight.timeWithTraffic.value.round();
    final meters = weight.distance.value.round();

    // Один цвет на каждый подряд идущий участок с одинаковыми пробками.
    final jams = r.jamSegments;
    final segments = <RouteSegment>[];
    var i = 0;
    while (i < jams.length) {
      final type = jams[i].jamType;
      var j = i;
      while (j + 1 < jams.length && jams[j + 1].jamType == type) {
        j++;
      }
      final sub = ymk.Subpolyline(
        ymk.PolylinePosition(segmentIndex: i, segmentPosition: 0.0),
        ymk.PolylinePosition(segmentIndex: j + 1, segmentPosition: 0.0),
      );
      segments.add(RouteSegment(
        ymk.SubpolylineHelper.subpolyline(r.geometry, sub),
        _jamColor(type),
      ));
      i = j + 1;
    }
    if (segments.isEmpty) {
      segments.add(RouteSegment(r.geometry, const Color(0xFF2F80ED)));
    }

    return RouteResult(
      mode: TravelMode.drive,
      seconds: seconds,
      meters: meters,
      full: r.geometry,
      segments: segments,
      points: r.geometry.points,
    );
  }

  Color _jamColor(ymk.JamType t) {
    if (t == ymk.JamType.Free) return const Color(0xFF2EAD4B);
    if (t == ymk.JamType.Light) return const Color(0xFFF2B600);
    if (t == ymk.JamType.Hard) return const Color(0xFFE53935);
    if (t == ymk.JamType.VeryHard || t == ymk.JamType.Blocked) {
      return const Color(0xFF8E0000);
    }
    return const Color(0xFF2F80ED);
  }

  // ---------- Пешком ----------

  Future<List<RouteResult>> walk(ymk.Point from, ymk.Point to) {
    final c = Completer<List<RouteResult>>();
    _pedestrian ??= tr.TransportFactory.instance.createPedestrianRouter();
    _pedestrianSession?.cancel();

    final handler = tr.RouteHandler(
      onMasstransitRoutes: (routes) {
        if (c.isCompleted) return;
        if (routes.isEmpty) {
          c.completeError(RouteException('Пешеходный маршрут не найден'));
        } else {
          try {
            c.complete([for (final r in routes) _fromMasstransit(r, walking: true)]);
          } catch (e) {
            c.completeError(e);
          }
        }
      },
      onMasstransitRoutesError: (error) {
        if (!c.isCompleted) c.completeError(RouteException(error.toString()));
      },
    );
    _pedestrianHandler = handler;
    _pedestrianSession = _pedestrian!.requestRoutes(
      const tr.TimeOptions(),
      const tr.RouteOptions(tr.FitnessOptions()),
      handler,
      points: _points(from, to),
    );
    return c.future.timeout(const Duration(seconds: 25));
  }

  // ---------- Общественный транспорт ----------

  Future<List<RouteResult>> transit(ymk.Point from, ymk.Point to) {
    final c = Completer<List<RouteResult>>();
    _transit ??= tr.TransportFactory.instance.createMasstransitRouter();
    _transitSession?.cancel();

    final handler = tr.RouteHandler(
      onMasstransitRoutes: (routes) {
        if (c.isCompleted) return;
        if (routes.isEmpty) {
          c.completeError(RouteException(
              'Маршрут на транспорте не найден (в этом районе может не быть данных)'));
        } else {
          try {
            c.complete([for (final r in routes) _fromMasstransit(r, walking: false)]);
          } catch (e) {
            c.completeError(e);
          }
        }
      },
      onMasstransitRoutesError: (error) {
        if (!c.isCompleted) c.completeError(RouteException(error.toString()));
      },
    );
    _transitHandler = handler;
    _transitSession = _transit!.requestRoutes(
      const tr.TransitOptions(tr.TimeOptions()),
      const tr.RouteOptions(tr.FitnessOptions()),
      handler,
      points: _points(from, to),
    );
    return c.future.timeout(const Duration(seconds: 25));
  }

  RouteResult _fromMasstransit(tr.MasstransitRoute r, {required bool walking}) {
    final weight = r.metadata.weight;
    final seconds = weight.time.value.round();
    final walkMeters = weight.walkingDistance.value.round();

    if (walking) {
      return RouteResult(
        mode: TravelMode.walk,
        seconds: seconds,
        meters: walkMeters,
        full: r.geometry,
        segments: [RouteSegment(r.geometry, const Color(0xFF2F80ED))],
        points: r.geometry.points,
      );
    }

    final segments = <RouteSegment>[];
    final steps = <StepInfo>[];
    final stops = <StopMark>[];
    final lines = <LineInfo>[];

    for (final section in r.sections) {
      final data = section.metadata.data;
      if (data.asWait() != null) continue;

      final sectionWeight = section.metadata.weight;
      final secs = sectionWeight.time.value.round();
      final poly = ymk.SubpolylineHelper.subpolyline(r.geometry, section.geometry);
      final transports = data.asVectorMasstransitTransport();

      if (transports != null && transports.isNotEmpty) {
        final line = transports.first.line;
        final kind = normalizeVehicle(line.vehicleTypes);
        final label = line.shortName ?? line.name;
        final rawColor = line.style?.color;
        final color = rawColor != null
            ? Color(0xFF000000 | rawColor)
            : vehicleDefaultColor(kind);

        var fromName = '';
        var toName = '';
        final sectionStops = section.stops;
        if (sectionStops.isNotEmpty) {
          final first = sectionStops.first;
          final last = sectionStops.last;
          fromName = first.metadata.stop.name;
          toName = last.metadata.stop.name;
          stops.add(StopMark(point: first.position, title: fromName, boarding: true));
          stops.add(StopMark(point: last.position, title: toName, boarding: false));
        }
        final count = sectionStops.length > 1 ? sectionStops.length - 1 : 0;

        segments.add(RouteSegment(poly, color));
        lines.add(LineInfo(kind: kind, label: label, color: color));
        steps.add(StepInfo(
          kind: StepKind.ride,
          title: '${vehicleLabel(kind)} $label',
          subtitle: '$fromName → $toName\n$count ост. · ${formatDuration(secs)}',
          seconds: secs,
          color: color,
          vehicle: kind,
        ));
      } else {
        final meters = sectionWeight.walkingDistance.value.round();
        final isTransfer = data.asTransfer() != null;
        segments.add(RouteSegment(poly, const Color(0xFF607D8B), width: 6.0));
        steps.add(StepInfo(
          kind: StepKind.walk,
          title: isTransfer ? 'Переход' : 'Пешком ${formatDistance(meters)}',
          subtitle: formatDuration(secs),
          seconds: secs,
          color: const Color(0xFF607D8B),
        ));
      }
    }

    if (segments.isEmpty) {
      segments.add(RouteSegment(r.geometry, const Color(0xFF2F80ED)));
    }

    return RouteResult(
      mode: TravelMode.transit,
      seconds: seconds,
      meters: 0,
      walkMeters: walkMeters,
      transfers: weight.transfersCount,
      full: r.geometry,
      segments: segments,
      points: r.geometry.points,
      steps: steps,
      stops: stops,
      lines: lines,
    );
  }

  void dispose() {
    _drivingSession?.cancel();
    _pedestrianSession?.cancel();
    _transitSession?.cancel();
    // Слушатели нужны, пока живы сессии.
    _drivingListener = null;
    _pedestrianHandler = null;
    _transitHandler = null;
  }
}
