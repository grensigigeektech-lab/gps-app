import 'package:get/get.dart';
import 'enhanced_camera_screen.dart';

class EnhancedCameraBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<EnhancedCameraController>(() => EnhancedCameraController());
  }
}
