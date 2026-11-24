import 'dart:typed_data';

/// 웹이 아니면 쓰지 않는다 (null → 기존 Dart 변환 사용)
Future<List<Uint8List>?> browserResizeJpegs(
  Uint8List bytes,
  List<(int, double)> sizes, {
  String? mime,
}) async => null;
