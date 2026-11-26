// iOS 충전 중 백그라운드 분석(BGProcessingTask) 연결 테스트 — iOS 쪽 요청을 흉내 낸다
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapback_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snapback_app/main.dart';
import 'package:snapback_app/screens/main_screens.dart';
import 'package:snapback_app/services/background_analysis.dart';
import 'package:snapback_app/services/embedding_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const ch = BackgroundAnalysis.channel;
  final sent = <MethodCall>[];

  setUp(() {
    BackgroundAnalysis.debugSupported = true;
    BackgroundAnalysis.debugReset();
    sent.clear();
    messenger.setMockMethodCallHandler(ch, (call) async {
      sent.add(call);
      return null;
    });
  });
  tearDown(() {
    BackgroundAnalysis.debugSupported = null;
    messenger.setMockMethodCallHandler(ch, null);
  });

  /// iOS → 앱 요청을 흉내 내고 응답을 돌려받는다
  Future<Object?> fromIos(String method) async {
    final reply = await messenger.handlePlatformMessage(
      ch.name,
      ch.codec.encodeMethodCall(MethodCall(method)),
      (_) {},
    );
    return reply == null ? null : ch.codec.decodeEnvelope(reply);
  }

  test('setPending: 바뀔 때만 iOS 에 알림', () {
    BackgroundAnalysis.setPending(true);
    BackgroundAnalysis.setPending(true);
    BackgroundAnalysis.setPending(false);
    expect(sent.map((c) => '${c.method}:${c.arguments}'), ['setPending:true', 'setPending:false']);
  });

  test('지원하지 않는 플랫폼(웹·안드로이드)에서는 아무것도 보내지 않음', () {
    BackgroundAnalysis.debugSupported = false;
    BackgroundAnalysis.setPending(true);
    expect(sent, isEmpty);
  });

  test('attach: 준비됐다고 알리고, iOS 의 run·expire 요청을 처리', () async {
    var expired = 0;
    BackgroundAnalysis.attach(run: () async => true, expire: () => expired++);
    expect(sent.single.method, 'ready');
    expect(await fromIos('run'), true);
    await fromIos('expire');
    expect(expired, 1);
  });

  testWidgets('앱 상태: 남은 사진이 없으면 바로 완료, 시간이 끝나면 멈추고 대기열 저장', (tester) async {
    EmbeddingStore.debugMemoryOnly = true;
    EmbeddingStore.debugReset();
    SharedPreferences.setMockInitialValues({
      'snapback_onboarded': true,
      'snapback_db': jsonEncode([
        {'id': 12, 'date': '2026-01-01', 'place': '카페'},
      ]),
    });
    await tester.pumpWidget(const SnapbackApp());
    await tester.pump(const Duration(milliseconds: 600));
    final s = tester.widget<Screen5Home>(find.byType(Screen5Home)).state;
    expect(sent.any((c) => c.method == 'ready'), true, reason: '앱이 준비되면 iOS 에 알림');
    expect(await s.runQueuedAnalysisInBackground(), true);
    // 분석 중에 시간이 끝나면: 멈춤 상태로
    s.analysisRunning = true;
    s.pauseForBackgroundExpiry();
    expect(s.analysisRunning, false);
    expect(s.analysisPaused, true);
  });
}
