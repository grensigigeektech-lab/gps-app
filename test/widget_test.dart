import 'package:flutter_test/flutter_test.dart';
import 'package:geotag_camera/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GeoTagCameraApp());
    expect(find.byType(GeoTagCameraApp), findsOneWidget);
  });
}
