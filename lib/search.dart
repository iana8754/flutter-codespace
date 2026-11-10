import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/search.dart' as srch;

import 'models.dart';

/// Подсказки адресов при вводе, поиск точки по тексту и адрес по точке на карте.
class SearchService {
  srch.SearchManager? _manager;
  srch.SearchSuggestSession? _suggestSession;
  srch.SearchSession? _resolveSession;
  srch.SearchSession? _reverseSession;

  /// MapKit хранит слабые ссылки: слушатели должны жить, пока идёт запрос.
  final Map<String, Object> _alive = {};

  srch.SearchManager get _m => _manager ??=
      srch.SearchFactory.instance.createSearchManager(srch.SearchManagerType.Combined);

  void suggest(
    String text,
    ymk.BoundingBox area, {
    required void Function(List<Suggestion>) onResult,
    required void Function(String) onError,
  }) {
    _suggestSession ??= _m.createSuggestSession();
    final listener = srch.SearchSuggestSessionSuggestListener(
      onResponse: (suggest) {
        onResult([
          for (final it in suggest.items)
            Suggestion(
              title: it.title.text,
              subtitle: it.subtitle?.text ?? '',
              searchText: it.searchText,
              center: it.center,
            ),
        ]);
      },
      onError: (error) => onError(error.toString()),
    );
    _alive['suggest'] = listener;
    _suggestSession!.suggest(
      area,
      srch.SuggestOptions(
        suggestTypes: srch.SuggestType.Geo | srch.SuggestType.Biz,
      ),
      listener,
      text: text,
    );
  }

  /// Находит точку по тексту (если у подсказки нет координат).
  void resolve(
    String text,
    ymk.Point near, {
    required void Function(AppPlace?) onResult,
    required void Function(String) onError,
  }) {
    _resolveSession?.cancel();
    final listener = srch.SearchSessionSearchListener(
      onSearchResponse: (response) {
        final geoObjects = response.collection.children
            .map((it) => it.asGeoObject())
            .whereType<ymk.GeoObject>();
        for (final g in geoObjects) {
          for (final geometry in g.geometry) {
            final p = geometry.asPoint();
            if (p != null) {
              onResult(AppPlace(name: g.name ?? text, address: '', point: p));
              return;
            }
          }
        }
        onResult(null);
      },
      onSearchError: (error) => onError(error.toString()),
    );
    _alive['resolve'] = listener;
    _resolveSession = _m.submit(
      ymk.Geometry.fromPoint(near),
      srch.SearchOptions(
        searchTypes: srch.SearchType.Geo | srch.SearchType.Biz,
      ),
      listener,
      text: text,
    );
  }

  /// Адрес по точке на карте.
  void reverse(
    ymk.Point point, {
    required void Function(String?) onResult,
    required void Function(String) onError,
  }) {
    _reverseSession?.cancel();
    final listener = srch.SearchSessionSearchListener(
      onSearchResponse: (response) {
        final geoObjects = response.collection.children
            .map((it) => it.asGeoObject())
            .whereType<ymk.GeoObject>();
        for (final g in geoObjects) {
          final name = g.name;
          if (name != null && name.isNotEmpty) {
            onResult(name);
            return;
          }
        }
        onResult(null);
      },
      onSearchError: (error) => onError(error.toString()),
    );
    _alive['reverse'] = listener;
    _reverseSession = _m.submitPoint(
      point,
      srch.SearchOptions(searchTypes: srch.SearchType.Geo),
      listener,
      zoom: 18,
    );
  }

  void dispose() {
    _resolveSession?.cancel();
    _reverseSession?.cancel();
    _suggestSession?.reset();
    _alive.clear();
  }
}
