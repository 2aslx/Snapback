import 'dart:convert';
import 'dart:math' as math;
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

class ProcessedImage {
  ProcessedImage({
    required this.analyzeDataUrl,
    required this.thumbDataUrl,
    required this.dateStr,
    required this.hasExifDate,
    this.gps,
    this.previewBytes,
  });

  final String analyzeDataUrl;
  final String thumbDataUrl;
  final String dateStr;
  final bool hasExifDate;
  final List<double>? gps;

  /// 웹 전용 1080px 미리보기 JPEG (IndexedDB 저장용)
  final Uint8List? previewBytes;
}

Uint8List _resizeToJpeg(_ResizeRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) return req.bytes;
  final maxSide = math.max(decoded.width, decoded.height);
  final resized = maxSide > req.maxDim
      ? (decoded.width >= decoded.height
          ? img.copyResize(decoded, width: req.maxDim)
          : img.copyResize(decoded, height: req.maxDim))
      : decoded;
  return img.encodeJpg(resized, quality: req.quality);
}

String _dateStr(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

class _ResizeRequest {
  _ResizeRequest(this.bytes, this.maxDim, this.quality);
  final Uint8List bytes;
  final int maxDim;
  final int quality;
}

String _resizeAndEncode(_ResizeRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) {
    return 'data:image/jpeg;base64,${base64Encode(req.bytes)}';
  }
  final maxSide = math.max(decoded.width, decoded.height);
  final resized = maxSide > req.maxDim
      ? (decoded.width >= decoded.height
          ? img.copyResize(decoded, width: req.maxDim)
          : img.copyResize(decoded, height: req.maxDim))
      : decoded;
  final jpg = img.encodeJpg(resized, quality: req.quality);
  return 'data:image/jpeg;base64,${base64Encode(jpg)}';
}

double? _toCoord(IfdTag? tag, IfdTag? refTag) {
  if (tag == null) return null;
  final values = tag.values.toList();
  if (values.length < 3) return null;
  double ratioToDouble(dynamic v) {
    if (v is Ratio) {
      return v.denominator == 0 ? 0 : v.numerator / v.denominator;
    }
    if (v is num) return v.toDouble();
    return 0;
  }

  final d = ratioToDouble(values[0]);
  final m = ratioToDouble(values[1]);
  final s = ratioToDouble(values[2]);
  var coord = d + m / 60.0 + s / 3600.0;
  final ref = refTag?.printable.trim().toUpperCase() ?? '';
  if (ref == 'S' || ref == 'W') coord = -coord;
  return coord;
}

DateTime? _parseExifDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  // Format: "YYYY:MM:DD HH:MM:SS"
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})').firstMatch(raw.trim());
  if (m == null) return null;
  final y = int.tryParse(m.group(1)!);
  final mo = int.tryParse(m.group(2)!);
  final d = int.tryParse(m.group(3)!);
  if (y == null || mo == null || d == null) return null;
  return DateTime(y, mo, d);
}

class ImageProcessor {
  static Future<ProcessedImage> process(
    XFile file,
    DateTime fallbackDate,
  ) async {
    final bytes = await file.readAsBytes();

    DateTime? exifDt;
    List<double>? gps;
    try {
      final tags = await readExifFromBytes(bytes);
      exifDt = _parseExifDate(
        tags['EXIF DateTimeOriginal']?.printable ??
            tags['Image DateTime']?.printable,
      );
      final lat = _toCoord(tags['GPS GPSLatitude'], tags['GPS GPSLatitudeRef']);
      final lng =
          _toCoord(tags['GPS GPSLongitude'], tags['GPS GPSLongitudeRef']);
      if (lat != null && lng != null && (lat != 0 || lng != 0)) {
        gps = [lat, lng];
      }
    } catch (_) {}

    final dt = exifDt ?? fallbackDate;
    final dateStr =
        '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    final analyzeUrl = await compute(
      _resizeAndEncode,
      _ResizeRequest(bytes, 640, 75),
    );
    final thumbUrl = await compute(
      _resizeAndEncode,
      _ResizeRequest(bytes, 160, 60),
    );
    // 웹은 원본을 다시 읽을 수 없으니 큰 화면용 미리보기를 따로 만들어 둔다
    final preview = kIsWeb
        ? await compute(_resizeToJpeg, _ResizeRequest(bytes, 1080, 82))
        : null;

    return ProcessedImage(
      analyzeDataUrl: analyzeUrl,
      thumbDataUrl: thumbUrl,
      dateStr: dateStr,
      hasExifDate: exifDt != null,
      gps: gps,
      previewBytes: preview,
    );
  }

  /// iOS 사진 보관함 에셋: 원본 파일을 통째로 읽지 않고 필요한 크기만 시스템에서 받아온다.
  static Future<ProcessedImage> processAsset(AssetEntity asset) async {
    Future<String> jpeg(int size, int quality) async {
      final b = await asset.thumbnailDataWithOption(
        ThumbnailOption.ios(
          size: ThumbnailSize.square(size),
          quality: quality,
          deliveryMode: DeliveryMode.highQualityFormat,
          resizeMode: ResizeMode.exact,
          resizeContentMode: ResizeContentMode.fit,
        ),
      );
      if (b == null) throw StateError('asset_unavailable');
      return 'data:image/jpeg;base64,${base64Encode(b)}';
    }

    List<double>? gps;
    try {
      final ll = await asset.latlngAsync();
      if (ll != null && (ll.latitude != 0 || ll.longitude != 0)) {
        gps = [ll.latitude, ll.longitude];
      }
    } catch (_) {}

    return ProcessedImage(
      analyzeDataUrl: await jpeg(640, 75),
      thumbDataUrl: await jpeg(160, 60),
      dateStr: _dateStr(asset.createDateTime),
      hasExifDate: true,
      gps: gps,
    );
  }
}
