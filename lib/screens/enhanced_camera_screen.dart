import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:camera/camera.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../config/mapbox_config.dart';
import '../routes/app_routes.dart';
import '../services/compass_service.dart';
import '../services/mapbox_location_service.dart';
import '../services/mapbox_service.dart';

class EnhancedCameraScreen extends GetView<EnhancedCameraController> {
  const EnhancedCameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Camera Preview
            Obx(() => controller.isInitialized.value
                ? CameraPreview(controller.cameraController!)
                : Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )),
      
            // Top Navigation Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 60,
                color: Colors.black.withOpacity(0.8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildTopNavBarIcon(Icons.settings),
                    _buildTopNavBarIcon(Icons.person),
                    _buildTopNavBarIcon(Icons.location_on),
                    _buildTopNavBarIcon(Icons.grid_view),
                    _buildTopNavBarIcon(Icons.more_vert),
                  ],
                ),
              ),
            ),
      
            // Location Information Card
            Positioned(
              bottom: 160,
              left: 16,
              right: 16,
              child: Obx(() => _buildLocationInfoCard()),
            ),
      
            // Bottom Tab Bar
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: _buildBottomTabBar(),
            ),
      
            // Bottom Navigation Icons
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: _buildBottomNavigation(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNavBarIcon(IconData icon) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        // Handle icon tap
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildLocationInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Map Thumbnail and Title Section
          Container(
            height: 120,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Stack(
              children: [
                // Mapbox Map
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: controller.isMapboxInitialized.value
                      ? MapWidget(
                          key: ValueKey('map_${controller.latitude.value}_${controller.longitude.value}'),
                          styleUri: MapboxConfig.streetStyle,
                          cameraOptions: CameraOptions(
                            center: Point(
                              coordinates: Position(
                                controller.longitude.value,
                                controller.latitude.value,
                              ),
                            ),
                            zoom: MapboxConfig.defaultZoom,
                          ),
                          onMapCreated: controller.onMapCreated,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.blue.shade400,
                                Colors.blue.shade600,
                              ],
                            ),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                ),
                // Location Marker Overlay
                if (controller.isMapboxInitialized.value)
                  Positioned(
                    top: 40,
                    left: 60,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                // Title Overlay
                Positioned(
                  bottom: 10,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      controller.locationInfo.value.isNotEmpty
                          ? controller.locationInfo.value
                          : 'Getting location...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Detailed Information Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Address and Plus Code
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.addressInfo.value.isNotEmpty
                                ? controller.addressInfo.value
                                : 'Unknown Address',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            controller.plusCode.value.isNotEmpty
                                ? controller.plusCode.value
                                : 'Plus Code: Loading...',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Date and Time
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          controller.dateInfo.value,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          controller.timeInfo.value,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Data Points Grid
                Row(
                  children: [
                    _buildDataPoint('Speed', '${controller.speed.value} km/h', Icons.speed),
                    const SizedBox(width: 16),
                    _buildDataPoint('Humidity', '${controller.humidity.value}%', Icons.water_drop),
                    const SizedBox(width: 16),
                    _buildDataPoint('Altitude', '${controller.altitude.value}m', Icons.terrain),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataPoint(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: Colors.blue.shade600,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomTabBar() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                controller.selectedTab.value = 'share';
              },
              child: Obx(() => Container(
                height: 40,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: controller.selectedTab.value == 'share'
                      ? Colors.blue.shade600
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    'QUICK SHARE',
                    style: TextStyle(
                      color: controller.selectedTab.value == 'share'
                          ? Colors.white
                          : Colors.grey.shade400,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                controller.selectedTab.value = 'photo';
              },
              child: Obx(() => Container(
                height: 40,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: controller.selectedTab.value == 'photo'
                      ? Colors.blue.shade600
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    'PHOTO',
                    style: TextStyle(
                      color: controller.selectedTab.value == 'photo'
                          ? Colors.white
                          : Colors.grey.shade400,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                controller.selectedTab.value = 'video';
              },
              child: Obx(() => Container(
                height: 40,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: controller.selectedTab.value == 'video'
                      ? Colors.blue.shade600
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    'VIDEO',
                    style: TextStyle(
                      color: controller.selectedTab.value == 'video'
                          ? Colors.white
                          : Colors.grey.shade400,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildBottomNavIcon(Icons.photo_library, 'Collection'),
        _buildBottomNavIcon(
          Icons.map,
          'Map Data',
          onTap: () => Get.toNamed(AppRoutes.mapNavigation),
        ),
        _buildCameraButton(),
        _buildBottomNavIcon(Icons.flight, 'USA Trip'),
        _buildBottomNavIcon(Icons.dashboard, 'Template'),
      ],
    );
  }

  Widget _buildBottomNavIcon(
    IconData icon,
    String label, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap?.call();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.heavyImpact();
        controller.capturePhoto();
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: Colors.grey.shade300,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.camera_alt,
          color: Colors.black,
          size: 28,
        ),
      ),
    );
  }
}

class EnhancedCameraController extends GetxController {
  // Camera
  CameraController? cameraController;
  RxBool isInitialized = false.obs;

  // Location Data
  RxString locationInfo = ''.obs;
  RxString addressInfo = ''.obs;
  RxString plusCode = ''.obs;
  RxDouble latitude = 0.0.obs;
  RxDouble longitude = 0.0.obs;
  RxDouble altitude = 0.0.obs;
  RxDouble speed = 0.0.obs;
  RxInt humidity = 65.obs;

  // Date/Time
  RxString dateInfo = ''.obs;
  RxString timeInfo = ''.obs;

  // Mapbox
  RxBool isMapboxInitialized = false.obs;

  // UI State
  RxString selectedTab = 'photo'.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeMapbox();
    _initializeCamera();
    _initializeLocation();
    _updateDateTime();
  }

  @override
  void onClose() {
    cameraController?.dispose();
    MapboxLocationService.dispose();
    MapboxService.dispose();
    super.onClose();
  }

  Future<void> _initializeMapbox() async {
    try {
      await MapboxService.initialize(MapboxConfig.accessToken);
      isMapboxInitialized.value = true;
    } catch (e) {
      print('Error initializing Mapbox: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        cameraController = CameraController(
          cameras.first,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await cameraController!.initialize();
        isInitialized.value = true;
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> _initializeLocation() async {
    try {
      await MapboxLocationService.initialize();
      final hasPermission = await MapboxLocationService.hasLocationPermission();
      if (hasPermission) {
        await _updateLocation();
        // Start continuous location updates
        await MapboxLocationService.startLocationUpdates((locationInfo) {
          _updateLocationFromMapbox(locationInfo);
        });
      }
    } catch (e) {
      print('Error initializing Mapbox location: $e');
    }
  }

  Future<void> _updateLocation() async {
    try {
      final locationData = await MapboxLocationService.getCurrentLocation();
      if (locationData != null) {
        _updateLocationFromMapbox(locationData);
      }
    } catch (e) {
      print('Error updating location: $e');
    }
  }

  void _updateLocationFromMapbox(MapboxLocationInfo locationData) {
    latitude.value = locationData.latitude;
    longitude.value = locationData.longitude;
    
    final addr = locationData.address;
    if (addr != null && addr.trim().isNotEmpty) {
      addressInfo.value = addr;
      locationInfo.value = addr;
    } else {
      addressInfo.value = 'No specific address found for this area';
      locationInfo.value = 'No specific address found for this area';
    }
    
    // Generate mock plus code (in real app, use proper plus code library)
    plusCode.value = _generatePlusCode(locationData.latitude, locationData.longitude);
    
    // Mock data (in real app, get from actual sensors)
    altitude.value = (math.Random().nextDouble() * 500 + 100).roundToDouble();
    speed.value = (math.Random().nextDouble() * 10).roundToDouble();
    humidity.value = (math.Random().nextInt(40) + 40);

    // Update Mapbox map if initialized
    if (isMapboxInitialized.value && MapboxService.isInitialized) {
      MapboxService.updateUserLocation(latitude.value, longitude.value);
    }
  }

  void onMapCreated(MapboxMap mapboxMap) {
    MapboxService.setMapController(mapboxMap);
    MapboxService.initializeAnnotationManager().then((_) {
      // Add current location marker when map is ready
      if (latitude.value != 0.0 && longitude.value != 0.0) {
        MapboxService.updateUserLocation(latitude.value, longitude.value);
      }
    });
  }

  void onMapIdle() {
    // Map is ready and idle, can perform additional operations if needed
  }

  String _generatePlusCode(double lat, double lng) {
    // Simple mock plus code generation
    return 'XXXX+${(lat * 1000).round()} ${(lng * 1000).round()}';
  }

  void _updateDateTime() {
    final now = DateTime.now();
    dateInfo.value = '${now.day}/${now.month}/${now.year}';
    timeInfo.value = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    
    // Update every minute
    Timer.periodic(const Duration(minutes: 1), (_) => _updateDateTime());
  }

  Future<void> capturePhoto() async {
    if (cameraController != null && cameraController!.value.isInitialized) {
      try {
        final image = await cameraController!.takePicture();
        // Handle captured photo
        Get.snackbar('Success', 'Photo captured: ${image.path}');
      } catch (e) {
        Get.snackbar('Error', 'Failed to capture photo: $e');
      }
    }
  }
}

class MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1;

    const gridSize = 20.0;
    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
