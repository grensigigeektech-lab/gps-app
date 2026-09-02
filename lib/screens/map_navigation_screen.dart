import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';
import '../services/location_service.dart';
import 'map_navigation_controller.dart';

class MapNavigationScreen extends GetView<MapNavigationController> {
  const MapNavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map navigation')),
      // Search remains above the keyboard without squeezing the native map.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller.destinationInput,
                      decoration: const InputDecoration(
                        labelText: 'Destination',
                        hintText: 'Enter an address or city',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 256,
                      textInputAction: TextInputAction.search,
                      onChanged: controller.destinationChanged,
                      onSubmitted: (_) => _search(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Obx(
                    () => IconButton.filled(
                      tooltip: 'Search destination',
                      onPressed: controller.busy || !controller.configured
                          ? null
                          : () => _search(context),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ],
              ),
            ),
            Obx(() {
              if (!controller.busy) return const SizedBox.shrink();
              return Semantics(
                liveRegion: true,
                child: Column(
                  children: [
                    const LinearProgressIndicator(),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(controller.progressLabel),
                    ),
                  ],
                ),
              );
            }),
            Obx(() {
              final message = controller.message.value;
              if (message == null) return const SizedBox.shrink();
              final error = controller.locationError.value;
              return _feedback(
                context,
                message,
                actions: [
                  if (controller.configured)
                    TextButton(
                      onPressed: controller.busy ? null : controller.retry,
                      child: const Text('Retry'),
                    ),
                  if (error == LocationError.serviceDisabled ||
                      error == LocationError.permissionPermanentlyDenied)
                    TextButton(
                      onPressed: controller.openSettings,
                      child: Text(
                        error == LocationError.serviceDisabled
                            ? 'Location Settings'
                            : 'App Settings',
                      ),
                    ),
                ],
              );
            }),
            Obx(() {
              if (controller.candidates.isEmpty) return const SizedBox.shrink();
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Choose your destination'),
                    ),
                    ...controller.candidates.map(
                      (place) => ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(place.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          controller.selectDestination(place);
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Obx(() {
                      final version = controller.mapVersion.value;
                      if (!controller.configured) {
                        return const Center(
                          child: Icon(Icons.map_outlined, size: 64),
                        );
                      }
                      return MapWidget(
                        key: ValueKey('navigation_map_$version'),
                        styleUri: MapboxConfig.streetStyle,
                        viewport: const CameraViewportState(
                          zoom: 1,
                          pitch: 0,
                          bearing: 0,
                        ),
                        onMapCreated: (map) =>
                            controller.onMapCreated(map, version),
                        onStyleLoadedListener: (_) =>
                            controller.onStyleLoaded(version),
                        onMapLoadErrorListener: (_) =>
                            controller.onMapLoadError(version),
                      );
                    }),
                  ),
                  Obx(
                    () => controller.mapLoading.value
                        ? const Center(
                            child: CircularProgressIndicator(
                              semanticsLabel: 'Loading map',
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Obx(() {
                      final error = controller.mapError.value;
                      if (error == null) return const SizedBox.shrink();
                      return _feedback(
                        context,
                        error,
                        actions: [
                          TextButton(
                            onPressed: controller.retryMap,
                            child: const Text('Retry map'),
                          ),
                        ],
                      );
                    }),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 32,
                    child: Obx(
                      () => Column(
                        children: [
                          if (controller.route.value != null)
                            FloatingActionButton.small(
                              heroTag: 'fit_route',
                              tooltip: 'Show entire route',
                              onPressed: controller.fitRoute,
                              child: const Icon(Icons.route),
                            ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'refresh_location',
                            tooltip: 'Refresh current location',
                            onPressed: controller.busy || !controller.configured
                                ? null
                                : controller.refreshLocation,
                            child: const Icon(Icons.my_location),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Obx(() {
              final route = controller.route.value;
              final location = controller.location.value;
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (route != null) ...[
                      Text(
                        route.destination.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${route.distanceLabel} · ${route.durationLabel} estimated',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text(
                        'Driving route · Estimate excludes live traffic',
                      ),
                    ] else if (location != null)
                      Text(
                        'Current location: ${location.latitude.toStringAsFixed(5)}, '
                        '${location.longitude.toStringAsFixed(5)}',
                      ),
                    if (route == null &&
                        controller.stage.value == NavigationStage.idle)
                      const Text(
                        'Search an address or city to plan a driving route.',
                      ),
                    const SizedBox(height: 4),
                    const Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      children: [
                        Text(
                          '● Current location',
                          style: TextStyle(color: Colors.lightBlueAccent),
                        ),
                        Text(
                          '● Destination',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _search(BuildContext context) {
    FocusScope.of(context).unfocus();
    controller.search();
  }

  Widget _feedback(
    BuildContext context,
    String message, {
    required List<Widget> actions,
  }) {
    return Semantics(
      liveRegion: true,
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              if (actions.isNotEmpty) Wrap(children: actions),
            ],
          ),
        ),
      ),
    );
  }
}
