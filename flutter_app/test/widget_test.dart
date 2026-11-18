import 'package:flutter_test/flutter_test.dart';
import 'package:snapback_app/main.dart';

void main() {
  testWidgets('SnapbackApp renders welcome screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SnapbackApp());
    expect(find.text('Snapback'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
  });
}
