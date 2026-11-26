import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// iOS·데스크톱: 사진 id → 256차원 벡터를 파일 하나(embeddings.bin)에 저장하고 메모리에 들고 있는다.
/// 파일 형식: [int32 사진 id][float32 × 256] 의 반복 (사진 2,000장 ≈ 2MB).
class EmbeddingStore {
  static const dim = 256;
  static final Map<int, Float32List> _mem = {};
  static bool _loaded = false;
  static Timer? _flush;

  /// 테스트용: 저장 폴더를 직접 지정 (null 이면 앱 지원 폴더)
  static Directory? debugDirectory;

  /// 테스트용: 파일을 쓰지 않고 메모리에만 (위젯 테스트는 실제 파일 입출력이 끝나지 않음)
  static bool debugMemoryOnly = false;

  static Future<File?> _file() async {
    if (debugMemoryOnly) return null;
    try {
      final dir = debugDirectory ?? await getApplicationSupportDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);
      return File('${dir.path}/embeddings.bin');
    } catch (_) {
      return null; // 파일을 못 쓰는 환경이면 메모리에만 (앱은 계속 동작)
    }
  }

  static int get count => _mem.length;
  static bool has(int id) => _mem.containsKey(id);
  static Float32List? get(int id) => _mem[id];

  /// 앱 시작 때 한 번: 파일에서 모두 읽어 메모리에 (여러 곳에서 불러도 한 번만 읽고 같은 결과를 기다림)
  static Future<void>? _loading;
  static Future<void> load() => _loading ??= _load();
  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final f = await _file();
    if (f == null || !await f.exists()) return;
    try {
      final bytes = await f.readAsBytes();
      final data = ByteData.sublistView(bytes);
      const rec = 4 + dim * 4;
      for (var o = 0; o + rec <= bytes.length; o += rec) {
        final id = data.getInt32(o, Endian.little);
        final v = Float32List(dim);
        for (var i = 0; i < dim; i++) {
          v[i] = data.getFloat32(o + 4 + i * 4, Endian.little);
        }
        _mem[id] = v;
      }
    } catch (_) {}
  }

  static Future<void> put(int id, Float32List v) async {
    if (v.length != dim) return;
    _mem[id] = v;
    _scheduleFlush();
  }

  static Future<void> putAll(Map<int, Float32List> vs) async {
    vs.forEach((id, v) {
      if (v.length == dim) _mem[id] = v;
    });
    _scheduleFlush();
  }

  static Future<void> remove(Iterable<int> ids) async {
    var changed = false;
    for (final id in ids) {
      changed = _mem.remove(id) != null || changed;
    }
    if (changed) _scheduleFlush();
  }

  static Future<void> clear() async {
    _flush?.cancel();
    _mem.clear();
    final f = await _file();
    try {
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 바뀔 때마다 쓰지 않고 1초에 한 번 파일 전체를 다시 쓴다 (분석 중 여러 장이 연달아 바뀜)
  static void _scheduleFlush() {
    _flush?.cancel();
    _flush = Timer(const Duration(seconds: 1), () => flush());
  }

  static Future<void> flush() async {
    _flush?.cancel();
    final f = await _file();
    if (f == null) return;
    const rec = 4 + dim * 4;
    final out = ByteData(_mem.length * rec);
    var o = 0;
    _mem.forEach((id, v) {
      out.setInt32(o, id, Endian.little);
      for (var i = 0; i < dim; i++) {
        out.setFloat32(o + 4 + i * 4, v[i], Endian.little);
      }
      o += rec;
    });
    try {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(out.buffer.asUint8List(), flush: true);
      await tmp.rename(f.path); // 쓰는 도중 앱이 꺼져도 예전 파일은 남도록
    } catch (_) {}
  }

  /// 테스트용: 메모리만 비우고 다시 읽을 수 있게
  static void debugReset() {
    _flush?.cancel();
    _mem.clear();
    _loaded = false;
    _loading = null;
  }
}
