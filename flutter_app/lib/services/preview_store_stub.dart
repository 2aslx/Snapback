import 'dart:typed_data';

/// 웹이 아닌 플랫폼용 빈 구현.
class PreviewStore {
  static bool get enabled => false;
  static Future<bool> put(String key, Uint8List bytes) async => false;
  static Future<Uint8List?> get(String key) async => null;
  static Future<void> clear() async {}
}
