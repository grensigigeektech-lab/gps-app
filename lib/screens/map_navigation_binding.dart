import 'package:get/get.dart';

import 'map_navigation_controller.dart';

class MapNavigationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MapNavigationController>(MapNavigationController.new);
  }
}
