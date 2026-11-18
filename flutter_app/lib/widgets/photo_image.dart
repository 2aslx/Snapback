import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../models/photo_item.dart';
import '../services/preview_store.dart';
import 'common_widgets.dart' show decodeDataUrl;

/// 사진을 화면 크기에 맞는 화질로 보여주는 ImageProvider.
/// - iOS: 사진 보관함 원본(assetId)에서 [logicalSize]×기기배율 크기로 바로 불러옴
/// - 웹: 큰 칸이면 IndexedDB 의 1080px 미리보기, 작은 칸이면 160px 썸네일
/// - 데모 사진처럼 이미지가 없으면 null (그라데이션 + 아이콘)
ImageProvider? photoImageProvider(
  PhotoItem d, {
  required double logicalSize,
  double dpr = 3,
}) {
  final thumb = decodeDataUrl(d.thumbDataUrl);
  if (!kIsWeb && d.assetId != null) {
    final px = (logicalSize * dpr).clamp(96, 2400).round();
    return AssetEntityImageProvider(
      AssetEntity(
        id: d.assetId!,
        typeInt: 1,
        width: d.assetW ?? 0,
        height: d.assetH ?? 0,
      ),
      isOriginal: false,
      thumbnailSize: ThumbnailSize.square(px),
    );
  }
  if (d.previewKey != null && logicalSize > 120) {
    return PreviewImageProvider(d.previewKey!, fallback: thumb);
  }
  return thumb == null ? null : MemoryImage(thumb);
}

/// IndexedDB 에 저장된 미리보기를 읽는 ImageProvider (없으면 [fallback] 썸네일).
@immutable
class PreviewImageProvider extends ImageProvider<PreviewImageProvider> {
  const PreviewImageProvider(this.key, {this.fallback});
  final String key;
  final Uint8List? fallback;

  @override
  Future<PreviewImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    PreviewImageProvider key,
    ImageDecoderCallback decode,
  ) =>
      OneFrameImageStreamCompleter(_load(decode));

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final bytes = await PreviewStore.get(key) ?? fallback;
    if (bytes == null) throw StateError('preview missing: $key');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is PreviewImageProvider && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
