import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// HEIC(아이폰 사진)을 못 읽는 브라우저(크롬 등)에서만 그때 불러오는 변환 라이브러리
const _heicLib = 'https://cdn.jsdelivr.net/npm/heic2any@0.0.4/dist/heic2any.min.js';
Future<void>? _heicLoading;

Future<void> _loadHeicLib() => _heicLoading ??= () {
      final done = Completer<void>();
      final s = web.HTMLScriptElement()
        ..src = _heicLib
        ..async = true;
      s.onload = ((web.Event _) => done.complete()).toJS;
      s.onerror = ((web.Event _) => done.completeError('heic2any load failed')).toJS;
      web.document.head!.append(s);
      return done.future;
    }();

@JS('heic2any')
external JSPromise<JSAny> _heic2any(JSObject options);

/// HEIC → JPEG Blob (라이브러리를 그때 불러와서)
Future<web.Blob?> _heicToJpeg(web.Blob blob) async {
  try {
    await _loadHeicLib();
    final opts = JSObject()
      ..['blob'] = blob
      ..['toType'] = 'image/jpeg'.toJS
      ..['quality'] = 0.9.toJS;
    final out = await _heic2any(opts).toDart;
    if (out.isA<JSArray>()) return (out as JSArray<web.Blob>).toDart.first;
    return out as web.Blob;
  } catch (_) {
    return null;
  }
}

Future<web.ImageBitmap?> _decode(web.Blob blob) async {
  // 지원하는 브라우저(크롬·파이어폭스 등)는 가로 1280px 로 줄이면서 푼다 → 4800만 화소 사진도 메모리 수십 MB 대신 몇 MB.
  // 지원하지 않으면 옵션을 무시하거나 실패하므로, 그때는 원본 크기로 다시 푼다.
  try {
    return await web.window
        .createImageBitmap(
          blob,
          web.ImageBitmapOptions(resizeWidth: 1280, resizeQuality: 'high'),
        )
        .toDart;
  } catch (_) {}
  try {
    return await web.window.createImageBitmap(blob).toDart;
  } catch (_) {
    return null;
  }
}

/// 사진을 한 번 해독해서 [sizes] 의 (긴 변 px, JPEG 품질) 마다 JPEG 를 만든다.
/// 비율 유지·자르지 않음·사진의 회전 정보(EXIF) 반영. 읽을 수 없는 형식이면 null.
Future<List<Uint8List>?> browserResizeJpegs(
  Uint8List bytes,
  List<(int, double)> sizes, {
  String? mime,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime ?? ''),
  );
  var bitmap = await _decode(blob);
  if (bitmap == null) {
    // 브라우저가 못 읽는 형식(주로 HEIC) → JPEG 로 바꿔서 다시
    final jpeg = await _heicToJpeg(blob);
    if (jpeg != null) bitmap = await _decode(jpeg);
  }
  if (bitmap == null) return null;
  try {
    final out = <Uint8List>[];
    final w0 = bitmap.width, h0 = bitmap.height;
    for (final (maxDim, quality) in sizes) {
      final scale = (w0 > h0 ? maxDim / w0 : maxDim / h0).clamp(0.0, 1.0);
      final w = (w0 * scale).round().clamp(1, 100000);
      final h = (h0 * scale).round().clamp(1, 100000);
      final canvas = web.OffscreenCanvas(w, h);
      final ctx = canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D;
      ctx.drawImage(bitmap, 0, 0, w, h);
      final jpg = await canvas
          .convertToBlob(web.ImageEncodeOptions(type: 'image/jpeg', quality: quality))
          .toDart;
      final buf = await jpg.arrayBuffer().toDart;
      out.add(buf.toDart.asUint8List());
    }
    return out;
  } catch (_) {
    return null;
  } finally {
    bitmap.close();
  }
}
