class MapboxConfig {
  // Replace this with your actual Mapbox API key
  // You can get one from: https://account.mapbox.com/access-tokens/
  /// Configure with `--dart-define=MAPBOX_ACCESS_TOKEN=<public-token>`.
  ///
  /// The default preserves the existing local placeholder and lets the UI
  /// surface a clear configuration error instead of sending invalid requests.
  static const String accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: 'YOUR_MAPBOX_ACCESS_TOKEN',
  );

  // Map styles
  static const String streetStyle = 'mapbox://styles/mapbox/streets-v12';
  static const String satelliteStyle = 'mapbox://styles/mapbox/satellite-v9';
  static const String darkStyle = 'mapbox://styles/mapbox/dark-v11';
  static const String lightStyle = 'mapbox://styles/mapbox/light-v11';
  static const String outdoorsStyle = 'mapbox://styles/mapbox/outdoors-v12';

  // Map configuration
  static const double defaultZoom = 15.0;
  static const double minZoom = 1.0;
  static const double maxZoom = 20.0;

  // Animation duration for map transitions
  static const Duration animationDuration = Duration(milliseconds: 800);
}
