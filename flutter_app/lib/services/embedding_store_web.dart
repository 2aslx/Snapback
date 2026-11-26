import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

/// 웹: IndexedDB('snapback_embed' / 'embeddings')에 사진 id → 1KB 바이너리(Float32 × 256)로 저장, 메모리에도 들고 있는다.
/// localStorage(약 5MB)는 쓰지 않는다.
class EmbeddingStore {
  static const dim = 256;
  static const _storeName = 'embeddings';
  static Future<Database>? _db;
  static final Map<int, Float32List> _mem = {};
  static bool _loaded = false;

  static Future<Database> _open() => _db ??= idbFactoryBrowser.open(
    'snapback_embed',
    version: 1,
    onUpgradeNeeded: (e) {
      final db = e.database;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    },
  );

  static int get count => _mem.length;
  static bool has(int id) => _mem.containsKey(id);
  static Float32List? get(int id) => _mem[id];

  static Float32List? _decode(Object? v) {
    final bytes = v is Uint8List
        ? v
        : (v is ByteBuffer ? v.asUint8List() : (v is List ? Uint8List.fromList(v.cast<int>()) : null));
    if (bytes == null || bytes.length != dim * 4) return null;
    return Float32List.fromList(bytes.buffer.asFloat32List(bytes.offsetInBytes, dim));
  }

  static Future<void>? _loading;
  static Future<void> load() => _loading ??= _load();
  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, idbModeReadOnly);
      await for (final c in tx.objectStore(_storeName).openCursor(autoAdvance: true)) {
        final id = int.tryParse('${c.key}');
        final v = _decode(c.value);
        if (id != null && v != null) _mem[id] = v;
      }
      await tx.completed;
    } catch (_) {
      _db = null;
    }
  }

  static Uint8List _bytes(Float32List v) =>
      Uint8List.fromList(Float32List.fromList(v).buffer.asUint8List());

  static Future<void> put(int id, Float32List v) => putAll({id: v});

  static Future<void> putAll(Map<int, Float32List> vs) async {
    final ok = {
      for (final e in vs.entries)
        if (e.value.length == dim) e.key: e.value,
    };
    _mem.addAll(ok);
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, idbModeReadWrite);
      final store = tx.objectStore(_storeName);
      for (final e in ok.entries) {
        await store.put(_bytes(e.value), '${e.key}');
      }
      await tx.completed;
    } catch (_) {
      _db = null; // 저장을 못 해도 이번 실행 동안은 메모리로 동작
    }
  }

  static Future<void> remove(Iterable<int> ids) async {
    final list = ids.toList();
    list.forEach(_mem.remove);
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, idbModeReadWrite);
      for (final id in list) {
        await tx.objectStore(_storeName).delete('$id');
      }
      await tx.completed;
    } catch (_) {}
  }

  static Future<void> clear() async {
    _mem.clear();
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, idbModeReadWrite);
      await tx.objectStore(_storeName).clear();
      await tx.completed;
    } catch (_) {}
  }

  static Future<void> flush() async {}

  /// io 구현과 맞추기 위한 테스트용 설정 (웹에서는 쓰지 않음)
  static bool debugMemoryOnly = false;
}
