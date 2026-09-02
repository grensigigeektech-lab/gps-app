import 'dart:math' as math;
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:sensors_plus/sensors_plus.dart' as magnetometer_sensor;

class CompassService {
  static double _currentHeading = 0.0;
  static StreamSubscription<MagnetometerEvent>? _subscription;

  static double get currentHeading => _currentHeading;

  static void startListening() {
    _subscription = magnetometer_sensor.magnetometerEventStream().listen((
      MagnetometerEvent event,
    ) {
      // Calculate heading from magnetometer data
      final x = event.x;
      final y = event.y;

      // Calculate heading in degrees
      double heading = math.atan2(y, x) * (180 / math.pi);
      heading = (heading + 90) % 360; // Adjust for compass orientation
      if (heading < 0) heading += 360;

      _currentHeading = heading;
    });
  }

  static void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  static String getDirection(double heading) {
    final directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((heading + 22.5) % 360) ~/ 45;
    return directions[index];
  }
}
