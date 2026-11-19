import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snapback_app/main.dart';

void main() {
  testWidgets('SnapbackApp renders welcome screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({}); // 처음 사용자
    await tester.pumpWidget(const SnapbackApp());
    await tester.pump(const Duration(milliseconds: 300)); // 저장된 설정 읽은 뒤 그려짐
    expect(find.text('Snapback'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
  });
}
