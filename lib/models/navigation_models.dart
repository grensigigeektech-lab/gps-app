class NavigationCoordinate {
  const NavigationCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class GeocodedDestination {
  const GeocodedDestination({required this.name, required this.coordinate});

  final String name;
  final NavigationCoordinate coordinate;
}

class NavigationRoute {
  const NavigationRoute({
    required this.destination,
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final GeocodedDestination destination;
  final List<NavigationCoordinate> coordinates;
  final double distanceMeters;
  final double durationSeconds;

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    final totalMinutes = (durationSeconds / 60).ceil();
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }
}

enum NavigationFailureType {
  permissionDenied,
  permissionPermanentlyDenied,
  locationServiceDisabled,
  locationUnavailable,
  invalidDestination,
  network,
  noRoute,
  mapConfiguration,
  mapLoad,
  unknown,
}

class NavigationException implements Exception {
  const NavigationException(this.type, this.message);

  final NavigationFailureType type;
  final String message;

  @override
  String toString() => message;
}
