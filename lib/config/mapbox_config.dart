class MapboxConfig {
  static const String accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: 'YOUR_MAPBOX_ACCESS_TOKEN',
  );

  static bool get hasValidAccessToken {
    final token = accessToken.trim();
    return token.startsWith('pk.') && token != 'YOUR_MAPBOX_ACCESS_TOKEN';
  }

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
  static const double defaultLatitude = 21.2318378;
  static const double defaultLongitude = 72.8366927;

  // Animation duration for map transitions
  static const Duration animationDuration = Duration(milliseconds: 800);
}
