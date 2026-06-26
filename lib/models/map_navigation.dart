class NavigationCoordinate {
  const NavigationCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  String get mapboxValue => '$longitude,$latitude';
}

class NavigationDestination {
  const NavigationDestination({required this.name, required this.coordinate});

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

  final NavigationDestination destination;
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
    final minutes = (durationSeconds / 60).ceil();
    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '$hours hr'
        : '$hours hr $remainingMinutes min';
  }
}
