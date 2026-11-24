import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

/// 웹 미리보기 저장소 — IndexedDB('snapback' / 'previews'). localStorage(약 5MB)보다 훨씬 크다.
class PreviewStore {
  static const _storeName = 'previews';
  static Future<Database>? _db;
  static final Map<String, Uint8List> _mem = {};

  static bool get enabled => true;

  static Future<Database> _open() => _db ??= idbFactoryBrowser.open(
        'snapback',
        version: 1,
        onUpgradeNeeded: (e) {
          final db = e.database;
          if (!db.objectStoreNames.contains(_storeName)) {
            db.createObjectStore(_storeName);
          }
        },
      );

  /// 저장. 성공하면 true (사생활 보호 모드 등 IndexedDB 를 못 쓰면 false — 앱은 계속 동작)
  /// 메모리에는 담아 두지 않는다 (사진이 많으면 휴대폰 브라우저 메모리가 넘쳐 탭이 새로고침됨)
  static Future<bool> put(String key, Uint8List bytes) async {
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, idbModeReadWrite);
      await tx.objectStore(_storeName).put(bytes, key);
      await tx.completed;
      return true;
    } catch (_) {
      _db = null; // 다음에 다시 열어 본다
      return false;
    }
  }

  static Future<Uint8List?> get(String key) async {
    final hit = _mem[key];
    if (hit != null) return hit;
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, idbModeReadOnly);
      final v = await tx.objectStore(_storeName).getObject(key);
      await tx.completed;
      final bytes = v is Uint8List
          ? v
          : (v is List ? Uint8List.fromList(v.cast<int>()) : null);
      if (bytes != null) {
        // 최근에 본 미리보기 몇 장만 메모리에 (메모리 보호)
        if (_mem.length >= 24) _mem.remove(_mem.keys.first);
        _mem[key] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
