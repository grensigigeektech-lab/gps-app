class NavigationCoordinate {
  final double latitude;
  final double longitude;
  final String label;

  const NavigationCoordinate({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  String get coordinates => '$latitude, $longitude';
}

class NavigationRoute {
  final NavigationCoordinate origin;
  final NavigationCoordinate destination;
  final List<NavigationCoordinate> path;
  final double distanceMeters;
  final double durationSeconds;

  const NavigationRoute({
    required this.origin,
    required this.destination,
    required this.path,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }

    final kilometers = distanceMeters / 1000;
    final precision = kilometers >= 10 ? 0 : 1;
    return '${kilometers.toStringAsFixed(precision)} km';
  }

  String get formattedDuration {
    final roundedMinutes = (durationSeconds / 60).round();
    final totalMinutes = roundedMinutes < 1 ? 1 : roundedMinutes;
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) {
      return '${hours}h';
    }

    return '${hours}h ${minutes}min';
  }
}

enum NavigationFailureType {
  missingToken,
  invalidDestination,
  network,
  noRoute,
  location,
  map,
  unknown,
}

class NavigationException implements Exception {
  final NavigationFailureType type;
  final String message;

  const NavigationException(this.type, this.message);

  @override
  String toString() => message;
}
