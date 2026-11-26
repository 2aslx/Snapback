import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 충전 중 장기 백그라운드 분석 (BGProcessingTask) 연결 — MethodChannel "snapback/background".
///
/// - 앱 → iOS: [setPending] 분석할 사진이 남았는지. 남은 채로 앱이 백그라운드로 가면 iOS 가 작업을 예약한다
///   (충전 중 · 네트워크 연결 · 기기를 쓰지 않을 때 iOS 가 정한 시점에 몇 분 동안 실행).
/// - iOS → 앱: `run` 남은 사진 분석을 이어 하고 끝나면 true / `expire` 허락된 시간이 끝남 → 멈추고 저장.
/// iOS 외에는 아무 것도 하지 않는다.
class BackgroundAnalysis {
  static const channel = MethodChannel('snapback/background');

  /// 테스트용: 플랫폼을 강제로 지원으로 볼지
  static bool? debugSupported;
  static bool get supported =>
      debugSupported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  static bool? _pending;

  /// iOS 가 보내는 요청을 받는다. 앱 상태가 준비된 뒤(대기열 복원 후) 한 번 부른다.
  static void attach({
    required Future<bool> Function() run,
    required void Function() expire,
  }) {
    if (!supported) return;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'run':
          return run();
        case 'expire':
          expire();
          return null;
      }
      throw MissingPluginException(call.method);
    });
    // iOS 가 앱 준비 전에 작업을 시작했으면 이제 보내도 된다고 알린다
    channel.invokeMethod('ready').catchError((_) {});
  }

  /// 분석할 사진이 남았는지 (바뀔 때만 보냄)
  static void setPending(bool pending) {
    if (!supported || _pending == pending) return;
    _pending = pending;
    channel.invokeMethod('setPending', pending).catchError((_) {});
  }

  @visibleForTesting
  static void debugReset() => _pending = null;
}
