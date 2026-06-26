import 'package:flutter_test/flutter_test.dart';
import 'package:geotag_camera/models/map_navigation.dart';
import 'package:geotag_camera/services/map_navigation_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('rejects an empty destination before making a request', () async {
    final service = MapNavigationService(
      accessToken: 'pk.test',
      client: MockClient((_) async => throw StateError('unexpected request')),
    );

    await expectLater(
      service.geocodeDestination('   '),
      throwsA(
        isA<MapNavigationException>().having(
          (error) => error.type,
          'type',
          MapNavigationFailureType.invalidDestination,
        ),
      ),
    );
  });

  test('geocodes a destination and parses a driving route', () async {
    final service = MapNavigationService(
      accessToken: 'pk.test',
      client: MockClient((request) async {
        if (request.url.path.contains('/geocoding/')) {
          expect(request.url.queryParameters['access_token'], 'pk.test');
          return http.Response(
            '{"features":[{"place_name":"Central Station, Test City",'
            '"center":[72.81,21.17]}]}',
            200,
          );
        }
        if (request.url.path.contains('/directions/')) {
          return http.Response(
            '{"routes":[{"distance":12500.0,"duration":1500.0,'
            '"geometry":{"coordinates":['
            '[72.80,21.16],[72.805,21.165],[72.81,21.17]]}}]}',
            200,
          );
        }
        return http.Response('not found', 404);
      }),
    );

    final destination = await service.geocodeDestination('Central Station');
    final route = await service.getDrivingRoute(
      origin: const NavigationCoordinate(latitude: 21.16, longitude: 72.80),
      destination: destination,
    );

    expect(destination.name, 'Central Station, Test City');
    expect(destination.coordinate.latitude, 21.17);
    expect(route.coordinates, hasLength(3));
    expect(route.formattedDistance, '12.5 km');
    expect(route.formattedDuration, '25 min');
  });

  test('reports a destination that cannot be found', () async {
    final service = MapNavigationService(
      accessToken: 'pk.test',
      client: MockClient((_) async => http.Response('{"features":[]}', 200)),
    );

    await expectLater(
      service.geocodeDestination('not a real place'),
      throwsA(
        isA<MapNavigationException>().having(
          (error) => error.type,
          'type',
          MapNavigationFailureType.destinationNotFound,
        ),
      ),
    );
  });

  test('reports when directions contain no route', () async {
    final service = MapNavigationService(
      accessToken: 'pk.test',
      client: MockClient((_) async => http.Response('{"routes":[]}', 200)),
    );
    const destination = NavigationDestination(
      name: 'Island',
      coordinate: NavigationCoordinate(latitude: 10, longitude: 20),
    );

    await expectLater(
      service.getDrivingRoute(
        origin: const NavigationCoordinate(latitude: 1, longitude: 2),
        destination: destination,
      ),
      throwsA(
        isA<MapNavigationException>().having(
          (error) => error.type,
          'type',
          MapNavigationFailureType.noRoute,
        ),
      ),
    );
  });
}
