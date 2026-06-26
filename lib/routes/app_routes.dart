import 'package:get/get.dart';
import '../screens/enhanced_camera_screen.dart';
import '../screens/enhanced_camera_binding.dart';
import '../screens/map_navigation_binding.dart';
import '../screens/map_navigation_screen.dart';

class AppRoutes {
  static const String enhancedCamera = '/enhanced_camera';
  static const String mapNavigation = '/map-navigation';

  static List<GetPage> pages = [
    GetPage(
      name: enhancedCamera,
      page: () => const EnhancedCameraScreen(),
      binding: EnhancedCameraBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 500),
    ),
    GetPage(
      name: mapNavigation,
      page: () => const MapNavigationScreen(),
      binding: MapNavigationBinding(),
      transition: Transition.cupertino,
    ),
  ];
}
