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

  static Future<void> put(String key, Uint8List bytes) async {
    _mem[key] = bytes;
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, idbModeReadWrite);
      await tx.objectStore(_storeName).put(bytes, key);
      await tx.completed;
    } catch (_) {}
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
      if (bytes != null) _mem[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
