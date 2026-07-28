import 'package:get/get.dart';

import 'map_navigation_screen.dart';

class MapNavigationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MapNavigationController>(() => MapNavigationController());
  }
}
