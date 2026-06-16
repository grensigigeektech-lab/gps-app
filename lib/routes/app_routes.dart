import 'package:get/get.dart';
import '../screens/enhanced_camera_screen.dart';
import '../screens/enhanced_camera_binding.dart';

class AppRoutes {
  static const String enhancedCamera = '/enhanced_camera';

  static List<GetPage> pages = [
    GetPage(
      name: enhancedCamera,
      page: () => const EnhancedCameraScreen(),
      binding: EnhancedCameraBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 500),
    ),
  ];
}
