# GeoTag Camera

A Flutter application that captures photos with automatic geotag information overlay, including GPS coordinates, address, and timestamp.

## Features

- **Camera Integration**: Live camera preview with high-quality image capture
- **Location Services**: Automatic GPS location fetching and address geocoding
- **Image Overlay**: Adds geotag information (coordinates, address, timestamp) as overlay on captured images
- **Save & Share**: Save processed images to device gallery and share with other apps
- **Permission Handling**: Graceful permission requests for camera, location, and storage
- **Map Navigation**: Destination search, GPS origin, route polyline, automatic camera fitting, distance, and estimated driving time
- **Material 3 UI**: Clean, modern interface following Material Design 3 guidelines

## Requirements

- Flutter SDK (>= 3.38.4, Dart >= 3.10.0)
- Android: API level 21+ (Android 5.0)
- iOS: iOS 11.0+

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd geotag_camera
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app with a Mapbox public access token:
```bash
flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_public_token
```

## Permissions

The app requires the following permissions:

### Android
- `CAMERA` - To capture photos
- `ACCESS_FINE_LOCATION` - To get precise GPS location
- `ACCESS_COARSE_LOCATION` - To get approximate location
- `WRITE_EXTERNAL_STORAGE` - To save images to gallery
- `READ_EXTERNAL_STORAGE` - To access saved images
- `INTERNET` - For geocoding services

### iOS
- `NSCameraUsageDescription` - Camera access for photo capture
- `NSLocationWhenInUseUsageDescription` - Location access for geotagging
- `NSPhotoLibraryAddUsageDescription` - Save photos to library
- `NSPhotoLibraryUsageDescription` - Access photo library

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── screens/
│   ├── camera_screen.dart    # Camera preview and capture
│   └── map_navigation_screen.dart # Destination search and route map
├── services/
│   ├── camera_service.dart   # Camera operations
│   ├── location_service.dart # GPS and geocoding
│   ├── map_navigation_service.dart # Mapbox geocoding and directions
│   └── image_service.dart    # Image processing and overlay
├── widgets/
│   └── permission_dialog.dart # Permission request dialog
└── utils/
    └── app_error.dart        # Error handling utilities
```

## Usage

1. **Launch the App**: Open the app and grant required permissions
2. **Camera Preview**: View live camera feed with location status
3. **Capture Photo**: Tap the capture button to take a photo
4. **Preview**: Review the captured image with geotag overlay
5. **Save/Share**: Save to gallery or share with other apps
6. **Navigate**: Tap **Map Data**, enter a destination, and review the fitted route, distance, and estimated driving time

## Key Dependencies

- `camera: ^0.12.0+1` - Camera functionality
- `geolocator: ^10.1.0` - GPS location services
- `mapbox_maps_flutter: ^2.23.0` - Map rendering and annotations
- `http: ^1.2.0` - Mapbox geocoding and directions requests
- `screenshot: ^3.0.0` - Widget to image conversion
- `share_plus: ^9.0.0` - Share functionality
- `permission_handler: ^11.3.1` - Permission management
- `flutter_screenutil: ^5.9.3` - Responsive design

## Error Handling

The app includes comprehensive error handling for:
- Camera initialization failures
- Location service unavailability
- Permission denials
- Storage issues
- Network connectivity problems

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and feature requests, please open an issue on the GitHub repository.
# gps
# gps-app
