import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/search.dart' as srch;

import 'models.dart';

/// Подсказки адресов при вводе и поиск точки по тексту.
class SearchService {
  srch.SearchManager? _manager;
  srch.SearchSuggestSession? _suggestSession;
  srch.SearchSession? _searchSession;
  // ignore: unused_field
  srch.SearchSuggestSessionSuggestListener? _suggestListener;
  // ignore: unused_field
  srch.SearchSessionSearchListener? _searchListener;

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
    _suggestListener = listener;
    _suggestSession!.suggest(
      area,
      srch.SuggestOptions(
        suggestTypes: srch.SuggestType.Geo | srch.SuggestType.Biz,
      ),
      listener,
      text: text,
    );
  }

  void resolve(
    String text,
    ymk.Point near, {
    required void Function(AppPlace?) onResult,
    required void Function(String) onError,
  }) {
    _searchSession?.cancel();
    final listener = srch.SearchSessionSearchListener(
      onSearchResponse: (response) {
        final geoObjects = response.collection.children
            .map((it) => it.asGeoObject())
            .whereType<ymk.GeoObject>();
        for (final g in geoObjects) {
          for (final geometry in g.geometry) {
            final p = geometry.asPoint();
            if (p != null) {
              onResult(AppPlace(
                name: g.name ?? text,
                address: '',
                point: p,
              ));
              return;
            }
          }
        }
        onResult(null);
      },
      onSearchError: (error) => onError(error.toString()),
    );
    _searchListener = listener;
    _searchSession = _m.submit(
      ymk.Geometry.fromPoint(near),
      srch.SearchOptions(
        searchTypes: srch.SearchType.Geo | srch.SearchType.Biz,
      ),
      listener,
      text: text,
    );
  }

  void dispose() {
    _searchSession?.cancel();
    _suggestSession?.reset();
  }
}
