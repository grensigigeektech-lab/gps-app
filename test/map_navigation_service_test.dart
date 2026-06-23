import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geotag_camera/services/map_navigation_service.dart';

void main() {
  group('MapNavigationService parsing', () {
    const origin = NavigationCoordinate(latitude: 21.1, longitude: 72.8);
    const destination = DestinationSearchResult(
      coordinate: NavigationCoordinate(latitude: 21.2, longitude: 72.9),
      placeName: 'Destination Place',
    );

    test('parses geocoding results into destination coordinates', () {
      final result = MapNavigationService.parseGeocodingResponse(
        200,
        jsonEncode({
          'features': [
            {
              'place_name': 'Surat, Gujarat, India',
              'center': [72.8311, 21.1702],
            },
          ],
        }),
      );

      expect(result.placeName, 'Surat, Gujarat, India');
      expect(result.coordinate.latitude, 21.1702);
      expect(result.coordinate.longitude, 72.8311);
    });

    test('throws invalid destination when geocoding has no results', () {
      expect(
        () => MapNavigationService.parseGeocodingResponse(
          200,
          jsonEncode({'features': []}),
        ),
        throwsA(
          isA<MapNavigationException>().having(
            (error) => error.type,
            'type',
            MapNavigationErrorType.invalidDestination,
          ),
        ),
      );
    });

    test('rejects blank destination before requesting location', () async {
      await expectLater(
        MapNavigationService.createRouteToDestination('   '),
        throwsA(
          isA<MapNavigationException>().having(
            (error) => error.type,
            'type',
            MapNavigationErrorType.invalidDestination,
          ),
        ),
      );
    });

    test('classifies rejected Mapbox token without decoding body', () {
      expect(
        () => MapNavigationService.parseGeocodingResponse(401, 'Unauthorized'),
        throwsA(
          isA<MapNavigationException>().having(
            (error) => error.type,
            'type',
            MapNavigationErrorType.mapboxConfiguration,
          ),
        ),
      );
    });

    test('classifies invalid geocoding coordinates as invalid destination', () {
      expect(
        () => MapNavigationService.parseGeocodingResponse(
          200,
          jsonEncode({
            'features': [
              {
                'place_name': 'Broken result',
                'center': ['not-a-number', 21.1702],
              },
            ],
          }),
        ),
        throwsA(
          isA<MapNavigationException>().having(
            (error) => error.type,
            'type',
            MapNavigationErrorType.invalidDestination,
          ),
        ),
      );
    });

    test('parses route distance, duration and geometry', () {
      final route = MapNavigationService.parseDirectionsResponse(
        statusCode: 200,
        body: jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 2450.0,
              'duration': 780.0,
              'geometry': {
                'coordinates': [
                  [72.8, 21.1],
                  [72.85, 21.15],
                  [72.9, 21.2],
                ],
              },
            },
          ],
        }),
        origin: origin,
        destination: destination,
      );

      expect(route.destinationName, 'Destination Place');
      expect(route.formattedDistance, '2.5 km');
      expect(route.formattedDuration, '13 min');
      expect(route.routePoints, hasLength(3));
    });

    test('throws no route when directions response has no route', () {
      expect(
        () => MapNavigationService.parseDirectionsResponse(
          statusCode: 200,
          body: jsonEncode({'code': 'NoRoute', 'routes': []}),
          origin: origin,
          destination: destination,
        ),
        throwsA(
          isA<MapNavigationException>().having(
            (error) => error.type,
            'type',
            MapNavigationErrorType.noRoute,
          ),
        ),
      );
    });

    test('classifies non-success NoRoute response as no route', () {
      expect(
        () => MapNavigationService.parseDirectionsResponse(
          statusCode: 422,
          body: jsonEncode({'code': 'NoRoute', 'routes': []}),
          origin: origin,
          destination: destination,
        ),
        throwsA(
          isA<MapNavigationException>().having(
            (error) => error.type,
            'type',
            MapNavigationErrorType.noRoute,
          ),
        ),
      );
    });

    test('rejects negative route metrics', () {
      expect(
        () => MapNavigationService.parseDirectionsResponse(
          statusCode: 200,
          body: jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': -1,
                'duration': 10,
                'geometry': {
                  'coordinates': [
                    [72.8, 21.1],
                    [72.9, 21.2],
                  ],
                },
              },
            ],
          }),
          origin: origin,
          destination: destination,
        ),
        throwsA(
          isA<MapNavigationException>().having(
            (error) => error.type,
            'type',
            MapNavigationErrorType.noRoute,
          ),
        ),
      );
    });
  });
}
