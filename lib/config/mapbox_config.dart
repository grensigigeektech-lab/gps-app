class MapboxConfig {
  // Public runtime token only. Never embed a secret downloads token in the app.
  static const String accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );
  static bool get isConfigured => accessToken.startsWith('pk.');

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
