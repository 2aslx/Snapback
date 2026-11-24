import 'dart:convert';
import 'dart:math' as math;
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/photo_item.dart';
import 'browser_image.dart';
import 'preview_store.dart';

/// AI 분석용 이미지 긴 변(px). 서버가 저해상도 모드(detail: low)로 보내므로
/// 모델이 실제로 보는 최대 크기인 512에 맞춘다 (더 크게 보내도 정확도는 같고 느리기만 함).
const kAnalyzeSize = 512;

/// 사진 형식을 읽을 수 없음 (예: 브라우저가 지원하지 않는 HEIC, 손상된 파일)
class UnsupportedImageException implements Exception {
  const UnsupportedImageException();
  @override
  String toString() => '사진 형식을 읽을 수 없어요 (HEIC 등은 JPEG 로 바꿔 올려 주세요)';
}

class ProcessedImage {
  ProcessedImage({
    required this.analyzeDataUrl,
    required this.thumbDataUrl,
    required this.dateStr,
    required this.hasExifDate,
    this.gps,
    this.previewBytes,
    this.takenAt,
  });

  final String analyzeDataUrl;
  final String thumbDataUrl;
  final String dateStr;
  final bool hasExifDate;
  final List<double>? gps;

  /// 웹 전용 1080px 미리보기 JPEG (IndexedDB 저장용)
  final Uint8List? previewBytes;

  /// 촬영 시각 (EXIF 원본 시각 → 없으면 파일 시각)
  final DateTime? takenAt;
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
  // 읽을 수 없는 형식을 JPEG 인 척 보내면 AI 가 거절하므로, 분명한 오류로 알린다
  if (decoded == null) throw const UnsupportedImageException();
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
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?')
      .firstMatch(raw.trim());
  if (m == null) return null;
  final y = int.tryParse(m.group(1)!);
  final mo = int.tryParse(m.group(2)!);
  final d = int.tryParse(m.group(3)!);
  if (y == null || mo == null || d == null) return null;
  int t(int g) => int.tryParse(m.group(g) ?? '') ?? 0;
  return DateTime(y, mo, d, t(4), t(5), t(6));
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

    String jpegUrl(Uint8List b) => 'data:image/jpeg;base64,${base64Encode(b)}';
    String analyzeUrl, thumbUrl;
    Uint8List? preview;
    // 웹: 브라우저 내장 해독(빠름 · 회전 정보 반영 · HEIC 는 변환 후)으로 분석용/썸네일/미리보기를 한 번에
    final viaBrowser = kIsWeb
        ? await browserResizeJpegs(
            bytes,
            const [(kAnalyzeSize, 0.8), (160, 0.6), (1080, 0.82)],
            mime: file.mimeType,
          )
        : null;
    if (viaBrowser != null) {
      analyzeUrl = jpegUrl(viaBrowser[0]);
      thumbUrl = jpegUrl(viaBrowser[1]);
      preview = viaBrowser[2];
    } else {
      analyzeUrl = await compute(_resizeAndEncode, _ResizeRequest(bytes, kAnalyzeSize, 80));
      thumbUrl = await compute(_resizeAndEncode, _ResizeRequest(bytes, 160, 60));
      // 웹은 원본을 다시 읽을 수 없으니 큰 화면용 미리보기를 따로 만들어 둔다
      preview = kIsWeb
          ? await compute(_resizeToJpeg, _ResizeRequest(bytes, 1080, 82))
          : null;
    }

    return ProcessedImage(
      analyzeDataUrl: analyzeUrl,
      thumbDataUrl: thumbUrl,
      dateStr: dateStr,
      hasExifDate: exifDt != null,
      gps: gps,
      previewBytes: preview,
      takenAt: dt,
    );
  }

  /// 다시 분석(재라벨링)용: 이미 분석한 사진의 AI 분석용 이미지(512px)만 다시 만든다.
  /// iOS 는 사진 보관함 원본에서, 웹은 저장해 둔 1080px 미리보기에서. 원본이 없으면 null.
  static Future<String?> analyzeUrlFor(PhotoItem d) async {
    try {
      if (!kIsWeb && d.assetId != null) {
        final a = await AssetEntity.fromId(d.assetId!);
        final b = await a?.thumbnailDataWithOption(
          ThumbnailOption.ios(
            size: const ThumbnailSize.square(kAnalyzeSize),
            quality: 80,
            deliveryMode: DeliveryMode.highQualityFormat,
            resizeMode: ResizeMode.exact,
            resizeContentMode: ResizeContentMode.fit,
          ),
        );
        return b == null ? null : 'data:image/jpeg;base64,${base64Encode(b)}';
      }
      if (d.previewKey != null && PreviewStore.enabled) {
        final bytes = await PreviewStore.get(d.previewKey!);
        if (bytes == null) return null;
        return await compute(_resizeAndEncode, _ResizeRequest(bytes, kAnalyzeSize, 80));
      }
    } catch (_) {}
    return null;
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
      analyzeDataUrl: await jpeg(kAnalyzeSize, 80),
      thumbDataUrl: await jpeg(160, 60),
      dateStr: _dateStr(asset.createDateTime),
      hasExifDate: true,
      gps: gps,
      takenAt: asset.createDateTime,
    );
  }
}

/// 정밀 분석용 큰 이미지 크기 (글자를 읽을 수 있게 긴 변 1280px, 비율 유지·자르지 않음)
const kDetailSize = 1280;

/// 사진 보관함 에셋 → 정밀 분석용 1280px JPEG (분석 처음, 글자가 많은 이미지일 때)
Future<String?> hiResDataUrlForAsset(AssetEntity a) async {
  try {
    final b = await a.thumbnailDataWithOption(
      ThumbnailOption.ios(
        size: const ThumbnailSize.square(kDetailSize),
        quality: 82,
        deliveryMode: DeliveryMode.highQualityFormat,
        resizeMode: ResizeMode.exact,
        resizeContentMode: ResizeContentMode.fit,
      ),
    );
    return b == null ? null : 'data:image/jpeg;base64,${base64Encode(b)}';
  } catch (_) {
    return null;
  }
}

/// 기록 초안용 큰 이미지 (문서 글자를 읽을 수 있게 긴 변 1280px).
/// iOS 는 사진 보관함 원본에서, 웹은 저장해 둔 1080px 미리보기에서. 없으면 null(분석 정보만 사용).
Future<String?> recordImageDataUrl(PhotoItem d) async {
  try {
    Uint8List? bytes;
    if (!kIsWeb && d.assetId != null) {
      final a = await AssetEntity.fromId(d.assetId!);
      bytes = await a?.thumbnailDataWithOption(
        ThumbnailOption.ios(
          size: const ThumbnailSize.square(1280),
          quality: 82,
          deliveryMode: DeliveryMode.highQualityFormat,
          resizeMode: ResizeMode.exact,
          resizeContentMode: ResizeContentMode.fit,
        ),
      );
    } else if (d.previewKey != null && PreviewStore.enabled) {
      bytes = await PreviewStore.get(d.previewKey!);
    }
    return bytes == null ? null : 'data:image/jpeg;base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}
