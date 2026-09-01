import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/mapbox_config.dart';
import 'map_navigation_controller.dart';

class MapNavigationScreen extends GetView<MapNavigationController> {
  const MapNavigationScreen({super.key, this.mapBuilder});

  // Allows widget tests to exercise the real controls without a native map view.
  final WidgetBuilder? mapBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map navigation')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              // Keep controls outside the map so camera padding is stable on every
              // screen size, with the keyboard open, and at larger text scales.
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .48,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: controller.destinationInput,
                          maxLength: 256,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            labelText: 'Destination',
                            hintText: 'Street address or place and city',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          onChanged: controller.destinationChanged,
                          onSubmitted: (_) => _search(context),
                        ),
                        const SizedBox(height: 8),
                        Obx(
                          () => FilledButton.icon(
                            onPressed: controller.isBusy
                                ? null
                                : () => _search(context),
                            icon: const Icon(Icons.directions_car),
                            label: const Text('Find driving route'),
                          ),
                        ),
                        Obx(() {
                          if (!controller.isBusy)
                            return const SizedBox.shrink();
                          return Semantics(
                            liveRegion: true,
                            child: Column(
                              children: [
                                const LinearProgressIndicator(),
                                const SizedBox(height: 8),
                                Text(controller.progressLabel),
                              ],
                            ),
                          );
                        }),
                        Obx(
                          () => controller.errorText.value.isEmpty
                              ? const SizedBox.shrink()
                              : Semantics(
                                  liveRegion: true,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        controller.errorText.value,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          TextButton(
                                            onPressed: controller.isBusy
                                                ? null
                                                : controller.retry,
                                            child: const Text('Retry'),
                                          ),
                                          if (controller.canOpenSettings)
                                            TextButton(
                                              onPressed:
                                                  controller.openSettings,
                                              child: const Text(
                                                'Open settings',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        Obx(
                          () => controller.candidates.isEmpty
                              ? const SizedBox.shrink()
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Choose your destination'),
                                    ...controller.candidates.map(
                                      (place) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(Icons.place),
                                        title: Text(place.name),
                                        onTap: () =>
                                            controller.selectDestination(place),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: _buildMap(context)),
              Obx(() {
                final route = controller.route.value;
                final destination = controller.destination.value;
                final location = controller.location.value;
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .35,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Wrap(
                            spacing: 16,
                            children: [
                              _Legend(
                                color: Color(0xFF1976D2),
                                label: 'Your location',
                              ),
                              _Legend(
                                color: Color(0xFFE65100),
                                label: 'Destination',
                              ),
                            ],
                          ),
                          if (destination != null)
                            Text(
                              destination.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (route != null)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                '${route.distanceLabel} · ${route.durationLabel} estimated driving time',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          if (route != null)
                            const Text(
                              'Route preview · Not turn-by-turn guidance or live traffic',
                              style: TextStyle(fontSize: 12),
                            ),
                          if (location != null)
                            Text(
                              'GPS fix: ${TimeOfDay.fromDateTime(location.timestamp.toLocal()).format(context)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: controller.isBusy
                                    ? null
                                    : controller.retry,
                                icon: const Icon(Icons.my_location),
                                label: const Text('Refresh GPS / route'),
                              ),
                              if (route != null)
                                TextButton.icon(
                                  onPressed: controller.fitRoute,
                                  icon: const Icon(Icons.fit_screen),
                                  label: const Text('Show entire route'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _search(BuildContext context) {
    if (controller.isBusy) return;
    FocusScope.of(context).unfocus();
    controller.search();
  }

  Widget _buildMap(BuildContext context) {
    if (mapBuilder != null) return mapBuilder!(context);
    if (!controller.mapsConfigured) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Maps are not configured. Please contact the app administrator.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return const Center(
        child: Text('Open the Android or iOS app to view the map.'),
      );
    }
    return Obx(() {
      final revision = controller.mapRevision.value;
      return Stack(
        children: [
          MapWidget(
            key: ValueKey('navigation-map-$revision'),
            styleUri: MapboxConfig.streetStyle,
            cameraOptions: CameraOptions(zoom: 2),
            onMapCreated: (map) => controller.onMapCreated(map, revision),
            onStyleLoadedListener: (_) => controller.onStyleLoaded(revision),
            onMapLoadErrorListener: (_) => controller.onMapError(revision),
          ),
          if (controller.mapLoading.value)
            const Center(child: CircularProgressIndicator()),
          if (controller.mapError.value.isNotEmpty)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.mapError.value,
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: controller.reloadMap,
                        child: const Text('Reload map'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, color: color, size: 12),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
