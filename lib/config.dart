/// Ключ MapKit Mobile SDK.
/// Лучше передавать при сборке: --dart-define=MAPKIT_API_KEY=...
/// (в GitHub Actions он берётся из секрета MAPKIT_API_KEY).
/// Если очень хочется прямо в коде — вставьте ключ вместо '' в defaultValue.
const String kMapkitKey =
    String.fromEnvironment('MAPKIT_API_KEY', defaultValue: '');
