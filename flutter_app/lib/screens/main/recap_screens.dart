part of '../main_screens.dart';

// 월간 리캡: 기억 탭의 '월간 리캡' 버튼 → 달별 목록(23) → 그 달의 요약 + 사진(24)

/// 기억 탭 맨 위 '월간 리캡' 버튼
class _RecapButton extends StatelessWidget {
  const _RecapButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.soft, shape: BoxShape.circle),
              child: SnapIcon('sparkle', size: 20, color: c.pk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '월간 리캡',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '달마다 자주 간 동네·음식·분위기 돌아보기',
                    style: TextStyle(fontSize: 13, color: c.mute),
                  ),
                ],
              ),
            ),
            SnapIcon('next', size: 18, color: c.mute),
          ],
        ),
      ),
    );
  }
}

/// 화면 23 — 월간 리캡 목록: 'N월 리캡' 을 최근 달부터
class Screen23Recaps extends StatelessWidget {
  const Screen23Recaps({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    final recaps = s.monthlyRecaps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '월간 리캡', onBack: () => s.go(19)),
        const SnapSub('달마다 자주 간 동네·먹은 음식·분위기를 모아 봤어요'),
        const SizedBox(height: 12),
        if (recaps.isEmpty)
          const SnapEmpty(icon: 'image', text: '날짜가 있는 사진이 아직 없어요')
        else
          for (final r in recaps) ...[
            _RecapRow(state: s, recap: r, onTap: () => s.openRecap(r)),
            Divider(height: 1, color: c.line),
          ],
      ],
    );
  }
}

class _RecapRow extends StatelessWidget {
  const _RecapRow({
    required this.state,
    required this.recap,
    required this.onTap,
  });
  final SnapbackState state;
  final MonthlyRecap recap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final cover = state.photoById(recap.coverId);
    final hints = [
      if (recap.places.isNotEmpty) recap.places.first.$1,
      if (recap.foods.isNotEmpty) recap.foods.first.$1,
      if (recap.moods.isNotEmpty) recap.moods.first.$1,
    ];
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: cover == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    )
                  : PhotoTile(item: cover, radius: 12, showDate: false),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${recap.month}월 리캡',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      '${recap.year}년',
                      '사진 ${recap.photoIds.length}장',
                      ...hints,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.mute),
                  ),
                ],
              ),
            ),
            SnapIcon('next', size: 18, color: c.mute),
          ],
        ),
      ),
    );
  }
}

/// 화면 24 — 한 달의 리캡: 맨 위 자주 간 동네·음식·분위기, 아래 그 달 사진 3열
class Screen24RecapMonth extends StatelessWidget {
  const Screen24RecapMonth({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final r = s.selectedRecap;
    void back() => s.go(23);
    if (r == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapbackTopBar(title: '월간 리캡', onBack: back),
          const SnapEmpty(icon: 'image', text: '이 달의 사진이 없어요'),
        ],
      );
    }
    final byId = {for (final d in s.visiblePhotos) d.id: d};
    final photos = [for (final id in r.photoIds) ?byId[id]];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '${r.month}월 리캡',
          onBack: back,
          trailing: Text('${photos.length}장'),
        ),
        SnapSub('${r.year}년 ${r.month}월에 찍은 사진 ${photos.length}장'),
        RecapCard(state: s, recap: r, showHeader: false, returnTo: 24),
        const SizedBox(height: 18),
        PhotoGrid(items: photos, onTap: (d) => s.openMemory(d.id)),
        // 그 달 사진 전체로 앨범 초안 → 미리보기에서 원하지 않는 사진을 눌러 빼고 저장
        if (photos.isNotEmpty) ...[
          SnapButton(
            label: '이 리캡으로 앨범 만들기',
            icon: 'stack',
            top: 22,
            onTap: () => s.draftAlbum('${r.year}년 ${r.month}월의 기록', [
              for (final d in photos) d.id,
            ], returnTo: 24),
          ),
          const SnapNote('다음 화면에서 빼고 싶은 사진을 눌러 고른 뒤 저장할 수 있어요'),
        ],
      ],
    );
  }
}
