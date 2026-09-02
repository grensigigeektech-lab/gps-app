import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Test with the coordinates from your image
  double lat = 21.231827;
  double lng = 72.836705;

  debugPrint('Testing geocoding for coordinates: $lat, $lng');

  try {
    List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
    debugPrint('Found ${placemarks.length} placemarks');

    if (placemarks.isNotEmpty) {
      Placemark place = placemarks.first;
      debugPrint('Placemark details:');
      debugPrint('  Street: ${place.street}');
      debugPrint('  SubLocality: ${place.subLocality}');
      debugPrint('  Locality: ${place.locality}');
      debugPrint('  AdministrativeArea: ${place.administrativeArea}');
      debugPrint('  PostalCode: ${place.postalCode}');
      debugPrint('  Country: ${place.country}');

      // Format address like the app does
      List<String> parts = [];
      if (place.street?.isNotEmpty == true) parts.add(place.street!);
      if (place.subLocality?.isNotEmpty == true) parts.add(place.subLocality!);
      if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
      if (place.administrativeArea?.isNotEmpty == true) {
        parts.add(place.administrativeArea!);
      }
      if (place.postalCode?.isNotEmpty == true) parts.add(place.postalCode!);
      if (place.country?.isNotEmpty == true) parts.add(place.country!);

      String formattedAddress = parts.join(', ');
      debugPrint('Formatted address: $formattedAddress');
    } else {
      debugPrint('No placemarks found');
    }
  } catch (e) {
    debugPrint('Geocoding failed: $e');
  }
}
