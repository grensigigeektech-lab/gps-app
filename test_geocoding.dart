// ignore_for_file: avoid_print

import 'package:geocoding/geocoding.dart';

void main() async {
  // Test with the coordinates from your image
  double lat = 21.231827;
  double lng = 72.836705;
  
  print('Testing geocoding for coordinates: $lat, $lng');
  
  try {
    List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
    print('Found ${placemarks.length} placemarks');
    
    if (placemarks.isNotEmpty) {
      Placemark place = placemarks.first;
      print('Placemark details:');
      print('  Street: ${place.street}');
      print('  SubLocality: ${place.subLocality}');
      print('  Locality: ${place.locality}');
      print('  AdministrativeArea: ${place.administrativeArea}');
      print('  PostalCode: ${place.postalCode}');
      print('  Country: ${place.country}');
      
      // Format address like the app does
      List<String> parts = [];
      if (place.street?.isNotEmpty == true) parts.add(place.street!);
      if (place.subLocality?.isNotEmpty == true) parts.add(place.subLocality!);
      if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
      if (place.administrativeArea?.isNotEmpty == true) parts.add(place.administrativeArea!);
      if (place.postalCode?.isNotEmpty == true) parts.add(place.postalCode!);
      if (place.country?.isNotEmpty == true) parts.add(place.country!);
      
      String formattedAddress = parts.join(', ');
      print('Formatted address: $formattedAddress');
    } else {
      print('No placemarks found');
    }
  } catch (e) {
    print('Geocoding failed: $e');
  }
}
