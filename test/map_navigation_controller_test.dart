import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:geotag_camera/screens/map_navigation_screen.dart';
import 'package:geotag_camera/services/location_service.dart';
import 'package:geotag_camera/services/navigation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapNavigationController location handling', () {
    test(
      'surfaces disabled Location Services with a settings action',
      () async {
        final controller = _controllerForLocation(
          LocationResult.failure(
            LocationError.serviceDisabled,
            'GPS is turned off.',
          ),
        );
        addTearDown(controller.onClose);

        await controller.loadCurrentLocation();

        expect(controller.isLocating.value, isFalse);
        expect(controller.currentLocation.value, isNull);
        expect(controller.locationError.value, LocationError.serviceDisabled);
        expect(controller.errorActionLabel, 'GPS settings');
        expect(controller.errorMessage.value, 'GPS is turned off.');
      },
    );

    test('surfaces denied permission with a retry action', () async {
      final controller = _controllerForLocation(
        LocationResult.failure(
          LocationError.permissionDenied,
          'Location permission was denied.',
        ),
      );
      addTearDown(controller.onClose);

      await controller.loadCurrentLocation();

      expect(controller.locationError.value, LocationError.permissionDenied);
      expect(controller.errorActionLabel, 'Retry');
      expect(controller.currentLocation.value, isNull);
    });

    test(
      'surfaces permanently denied permission with an app settings action',
      () async {
        final controller = _controllerForLocation(
          LocationResult.failure(
            LocationError.permissionPermanentlyDenied,
            'Location access is permanently denied.',
          ),
        );
        addTearDown(controller.onClose);

        await controller.loadCurrentLocation();

        expect(
          controller.locationError.value,
          LocationError.permissionPermanentlyDenied,
        );
        expect(controller.errorActionLabel, 'App settings');
      },
    );

    test('surfaces unavailable GPS fixes with a retry action', () async {
      final controller = _controllerForLocation(
        LocationResult.failure(LocationError.timeout, 'No fresh GPS fix.'),
      );
      addTearDown(controller.onClose);

      await controller.loadCurrentLocation();

      expect(controller.locationError.value, LocationError.timeout);
      expect(controller.errorActionLabel, 'Retry');
      expect(controller.isLocating.value, isFalse);
    });

    test(
      'publishes the current GPS coordinate after a successful fix',
      () async {
        final controller = _controllerForLocation(_successfulLocation());
        addTearDown(controller.onClose);

        await controller.loadCurrentLocation();

        expect(controller.currentLocation.value?.latitude, 21.2);
        expect(controller.currentLocation.value?.longitude, 72.8);
        expect(controller.locationError.value, isNull);
        expect(controller.errorMessage.value, isEmpty);
      },
    );
  });

  group('MapNavigationController route handling', () {
    test('rejects an empty destination without requesting location', () async {
      var requestedLocation = false;
      final controller = MapNavigationController(
        navigationService: _navigationService(),
        locationProvider: ({bool forceRefresh = false}) async {
          requestedLocation = true;
          return _successfulLocation();
        },
      );
      addTearDown(controller.onClose);
      controller.destinationController.text = '   ';

      await controller.findRoute();

      expect(requestedLocation, isFalse);
      expect(
        controller.navigationError.value,
        NavigationFailureType.invalidDestination,
      );
      expect(controller.errorActionLabel, 'Edit');
      expect(controller.isRouting.value, isFalse);
    });

    test('loads the destination, route, distance, and travel time', () async {
      final controller = _controllerForLocation(_successfulLocation());
      addTearDown(controller.onClose);
      controller.destinationController.text = 'Pune Station';

      await controller.findRoute();

      expect(controller.destination.value?.name, 'Pune Station, India');
      expect(controller.route.value?.coordinates, hasLength(2));
      expect(controller.route.value?.distanceLabel, '1.5 km');
      expect(controller.route.value?.durationLabel, '10 min');
      expect(controller.errorMessage.value, isEmpty);
      expect(controller.isRouting.value, isFalse);
    });

    test('clears a generated route when the destination changes', () async {
      final controller = _controllerForLocation(_successfulLocation());
      addTearDown(controller.onClose);
      controller.destinationController.text = 'Pune Station';
      await controller.findRoute();

      controller.destinationController.text = 'Mumbai';
      controller.onDestinationChanged('Mumbai');

      expect(controller.destination.value, isNull);
      expect(controller.route.value, isNull);
    });

    test(
      'discards a stale route when its destination changes mid-request',
      () async {
        final response = Completer<http.Response>();
        final controller = MapNavigationController(
          navigationService: NavigationService(
            accessToken: 'pk.test-token',
            client: MockClient((request) async {
              if (request.url.path.contains('/geocoding/')) {
                return response.future;
              }
              return _routeResponse();
            }),
          ),
          locationProvider: ({bool forceRefresh = false}) async =>
              _successfulLocation(),
        );
        addTearDown(controller.onClose);
        controller.destinationController.text = 'Pune Station';

        final routing = controller.findRoute();
        await Future<void>.delayed(Duration.zero);
        controller.destinationController.text = 'Mumbai';
        controller.onDestinationChanged('Mumbai');
        response.complete(_destinationResponse());
        await routing;

        expect(controller.destination.value, isNull);
        expect(controller.route.value, isNull);
        expect(controller.isRouting.value, isFalse);
      },
    );

    test('reports unavailable routes with a retry action', () async {
      final controller = MapNavigationController(
        navigationService: NavigationService(
          accessToken: 'pk.test-token',
          client: MockClient((request) async {
            if (request.url.path.contains('/geocoding/')) {
              return _destinationResponse();
            }
            return http.Response('{"routes": []}', 200);
          }),
        ),
        locationProvider: ({bool forceRefresh = false}) async =>
            _successfulLocation(),
      );
      addTearDown(controller.onClose);
      controller.destinationController.text = 'Pune Station';

      await controller.findRoute();

      expect(controller.navigationError.value, NavigationFailureType.noRoute);
      expect(controller.errorActionLabel, 'Retry');
      expect(controller.route.value, isNull);
      expect(controller.isRouting.value, isFalse);
    });
  });
}

MapNavigationController _controllerForLocation(LocationResult locationResult) {
  return MapNavigationController(
    navigationService: _navigationService(),
    locationProvider: ({bool forceRefresh = false}) async => locationResult,
  );
}

NavigationService _navigationService() {
  return NavigationService(
    accessToken: 'pk.test-token',
    client: MockClient((request) async {
      if (request.url.path.contains('/geocoding/')) {
        return _destinationResponse();
      }
      return _routeResponse();
    }),
  );
}

LocationResult _successfulLocation() {
  return LocationResult.success(
    LocationInfo(latitude: 21.2, longitude: 72.8, timestamp: DateTime(2026)),
  );
}

http.Response _destinationResponse() {
  return http.Response('''{
      "features": [
        {
          "place_name": "Pune Station, India",
          "center": [73.8746, 18.5289]
        }
      ]
    }''', 200);
}

http.Response _routeResponse() {
  return http.Response('''{
      "routes": [
        {
          "distance": 1500,
          "duration": 600,
          "geometry": {
            "coordinates": [[72.8, 21.2], [73.8746, 18.5289]]
          }
        }
      ]
    }''', 200);
}
