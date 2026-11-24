import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:material_ui/material_ui.dart';

import '../models/photo_item.dart';
import '../services/preview_store.dart';

/// 사진 공유: 시스템 공유 창(카카오톡·메시지·인스타그램 등)을 띄운다.
/// 앱은 사진을 복사해 두지 않으므로, 공유하는 순간에 원본을 가져온다.
/// - iOS: 사진 보관함에서 원본 파일 (iCloud 에만 있으면 내려받는 데 잠깐 걸릴 수 있음)
/// - 웹: 저장해 둔 1080px 미리보기
/// - 사진 파일이 없으면(예: 데모 사진) 제목·날짜 글만 공유
Future<void> sharePhoto(BuildContext context, PhotoItem d, String title) async {
  // iPad 는 공유 창이 버튼 위치에서 떠야 한다
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  XFile? file;
  try {
    if (!kIsWeb && d.assetId != null) {
      final a = await AssetEntity.fromId(d.assetId!);
      final f = await a?.file; // 사진 앱에서 보이는 그대로(편집 반영)의 원본
      if (f != null) file = XFile(f.path);
    } else if (d.previewKey != null && PreviewStore.enabled) {
      final bytes = await PreviewStore.get(d.previewKey!);
      if (bytes != null) {
        file = XFile.fromData(bytes, mimeType: 'image/jpeg', name: 'snapback_${d.id}.jpg');
      }
    }
  } catch (_) {}
  final text = [title, d.date].where((x) => x.isNotEmpty).join(' · ');
  await SharePlus.instance.share(
    file != null
        ? ShareParams(files: [file], sharePositionOrigin: origin)
        : ShareParams(text: text, sharePositionOrigin: origin),
  );
}
