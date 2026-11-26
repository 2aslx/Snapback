import 'package:material_ui/material_ui.dart';

import '../services/recap.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// 월간 리캡 상세(화면 24) 맨 위 카드: "11월의 나" — 가장 자주 간 동네·먹은 음식·분위기 요약 + 자동 앨범 만들기.
/// 검색할 일이 없을 때도 앱을 열면 지난 한 달을 돌아보게 하는 카드. 기기 안에서 계산(AI 호출 없음).
class RecapCard extends StatelessWidget {
  const RecapCard({
    super.key,
    required this.state,
    required this.recap,
    this.showHeader = true,
    this.returnTo = 19,
  });
  final SnapbackState state;
  final MonthlyRecap recap;

  /// 대표 사진 + "N월의 나" 제목 줄 (상세 화면처럼 위에 제목이 이미 있으면 숨김)
  final bool showHeader;

  /// 자동 앨범 미리보기에서 돌아올 화면
  final int returnTo;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final s = state;
    final cover = s.photoById(recap.coverId);
    String counts(List<Count> list) =>
        list.map((e) => '${e.$1} ${e.$2}번').join(' · ');
    Widget row(String icon, String title, String value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapIcon(icon, size: 17, color: c.pk),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(title, style: TextStyle(fontSize: 13.5, color: c.mute)),
          ),
          Expanded(
            child: Text(
              keepWords(value),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
    final topPlace = recap.places.isNotEmpty ? recap.places.first.$1 : null;
    final topFood = recap.foods.isNotEmpty ? recap.foods.first.$1 : null;
    final placeChip = topPlace != null && recap.placePhotoIds.length >= 2;
    final foodChip = topFood != null && recap.foodPhotoIds.length >= 2;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Row(
              children: [
                if (cover != null)
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: PhotoTile(
                      item: cover,
                      radius: 12,
                      showDate: false,
                      onTap: () => s.openMemory(cover.id),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '월간 리캡 · ${recap.year}년',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.pk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${recap.label}의 나',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '사진 ${recap.photoIds.length}장',
                  style: TextStyle(fontSize: 13, color: c.mute),
                ),
              ],
            ),
          if (showHeader) const SizedBox(height: 4),
          if (recap.places.isEmpty &&
              recap.foods.isEmpty &&
              recap.moods.isEmpty)
            row('sparkle', '이달의 기록', '자주 간 곳·음식·분위기를 모을 만큼 사진이 많지 않아요'),
          if (recap.places.isNotEmpty)
            row('pin', '자주 간 동네', counts(recap.places)),
          if (recap.foods.isNotEmpty)
            row('food', '자주 먹은 음식', counts(recap.foods)),
          if (recap.moods.isNotEmpty)
            row('sparkle', '분위기·취향', recap.moods.map((e) => e.$1).join(' · ')),
          // 자동 앨범(자주 간 동네 · 음식 모음): 바로 저장하지 않고 앨범 미리보기에서 뺄 사진·이름을 다듬는다.
          // 그 달 전체 앨범은 화면 맨 아래 '이 리캡으로 앨범 만들기' 버튼으로.
          if (placeChip || foodChip) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (placeChip)
                  SnapChip(
                    label: '$topPlace에서',
                    icon: 'pin',
                    onTap: () => s.draftAlbum(
                      '${recap.month}월 $topPlace에서',
                      recap.placePhotoIds,
                      returnTo: returnTo,
                    ),
                  ),
                if (foodChip)
                  SnapChip(
                    label: '$topFood 모음',
                    icon: 'food',
                    onTap: () => s.draftAlbum(
                      '${recap.month}월의 $topFood',
                      recap.foodPhotoIds,
                      returnTo: returnTo,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
