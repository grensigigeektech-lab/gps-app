import 'package:get/get.dart';
import '../screens/enhanced_camera_screen.dart';
import '../screens/enhanced_camera_binding.dart';
import '../screens/map_navigation_screen.dart';
import '../screens/map_navigation_binding.dart';

class AppRoutes {
  static const String mapNavigation = '/map_navigation';
  static const String enhancedCamera = '/enhanced_camera';

  static List<GetPage> pages = [
    GetPage(
      name: mapNavigation,
      page: () => const MapNavigationScreen(),
      binding: MapNavigationBinding(),
    ),
    GetPage(
      name: enhancedCamera,
      page: () => const EnhancedCameraScreen(),
      binding: EnhancedCameraBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 500),
    ),
  ];
}
