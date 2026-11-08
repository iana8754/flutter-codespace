/// Ключ MapKit Mobile SDK. Передаётся при сборке:
/// --dart-define=MAPKIT_API_KEY=...  (в GitHub Actions берётся из секрета).
const String kMapkitKey =
    String.fromEnvironment('MAPKIT_API_KEY', defaultValue: '');
