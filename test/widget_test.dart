import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/main.dart';

void main() {
  testWidgets('Harmoniq smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(SplashScreen), findsOneWidget);
    // Fast-forward splash screen timer
    await tester.pump(const Duration(milliseconds: 3000));
  });
}
