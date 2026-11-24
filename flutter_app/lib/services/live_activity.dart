import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS Live Activity (잠금화면 · 알림 센터 · 다이내믹 아일랜드)에 분석 진행을 보낸다.
/// 앱 하단 분석 진행 바와 같은 내용. iOS 외에는 아무 것도 하지 않는다.
class LiveActivity {
  static const _ch = MethodChannel('snapback/live_activity');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool _active = false;
  String? _sent;

  /// 상태가 바뀔 때마다 호출해도 된다 (같은 내용이면 보내지 않음).
  void sync({
    required int done,
    required int total,
    required bool running,
    required bool paused,
    required bool finished,
  }) {
    if (!supported || total <= 0) return;
    if (!_active && !running) return; // 분석이 실제로 시작될 때 띄운다
    final args = {
      'done': done,
      'total': total,
      'paused': paused && !finished,
      'finished': finished,
    };
    final key = args.toString();
    if (key == _sent) return;
    _sent = key;
    if (finished) {
      _active = false;
      _sent = null;
      _ch.invokeMethod('end', args).catchError((_) {});
    } else {
      _active = true;
      _ch.invokeMethod('update', args).catchError((_) {});
    }
  }

  /// 분석 취소: 잠금화면 표시를 바로 닫는다.
  void cancel() {
    if (!supported || !_active) return;
    _active = false;
    _sent = null;
    _ch.invokeMethod('cancel').catchError((_) {});
  }
}
