import 'package:flutter_test/flutter_test.dart';
import 'package:ican/main.dart';

void main() {
  testWidgets('iCan app smoke test', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const ICanApp());

    // Verify the home screen loads with the "Say a Location" button.
    expect(find.text('Say a Location'), findsOneWidget);
    expect(find.text('iCan'), findsOneWidget);
  });
}
