part of '../main_screens.dart';

// 사진 상세: 관련된 추억 · 사진 정보 · 다시 분석 · 공유

/// ⑤ 사진 상세 — 찾은 사진(크게) → 관련된 추억(앨범 2개) → 사진 정보(펼치기)
class Screen10MemoryDetail extends StatefulWidget {
  const Screen10MemoryDetail({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen10MemoryDetail> createState() => _Screen10MemoryDetailState();
}

class _Screen10MemoryDetailState extends State<Screen10MemoryDetail> {
  bool _infoOpen = false; // 사진 정보는 기본으로 접힘
  int? _shownId;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final item = s.db.firstWhere(
      (x) => x.id == s.activeMemoryId,
      orElse: () => s.db.first,
    );
    if (s.lockedAlbumForPhoto(item.id) case final lockedAlbum?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapbackTopBar(
            title: '잠긴 사진',
            onBack: () {
              if (!s.backFromRelated()) s.go(s.detailReturn);
            },
          ),
          const SizedBox(height: 18),
          PinPad(
            title: lockedAlbum.title,
            message: '잠긴 앨범에 들어 있는 사진이에요.\n비밀번호 4자리를 입력하세요.',
            onComplete: (pin) async => s.unlockAlbum(lockedAlbum.id, pin),
          ),
        ],
      );
    }
    if (_shownId != item.id) {
      _shownId = item.id; // 다른 사진으로 이동하면 정보는 다시 접힌 상태
      _infoOpen = false;
    }
    final rel = s.relatedFor(item);
    final record = s.recordForPhoto(item.id);
    final isDoc = record?.type == 'document';
    // 관련 사진을 가상 앨범으로 묶어 보여준다. 사진이 없는 앨범은 숨김.
    final relatedTiles = <Widget>[
      if (rel.sameDay.isNotEmpty)
        RelatedTile(
          icon: 'photos',
          title: '그날의 사진',
          count: rel.sameDay.length,
          onTap: () => s.openRelatedAlbum(0),
        ),
      if (rel.similarMood.isNotEmpty)
        RelatedTile(
          icon: 'flower',
          title: isDoc ? '비슷한 문서' : '비슷한 분위기',
          count: rel.similarMood.length,
          cool: true,
          onTap: () => s.openRelatedAlbum(1),
        ),
    ];

    // 감지되지 않은 내용('인원수 알 수 없음', '특정 복장 없음' 등)은 쉼표 단위로 빼고,
    // 남는 내용이 없으면 그 줄 자체를 숨긴다
    String join(Iterable<String> xs) => xs
        .expand((x) => x.split(RegExp(r'[,，/]')))
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty && !isUnknownInfo(x))
        .join(' · ');
    // 촬영 장소 = 장소 유형 + 시·구·동 주소 (예: 카페 · 서울특별시 마포구 동교동).
    // 위치 정보(GPS)는 있는데 주소를 아직 못 받았으면 '주소 확인 중…', 끝내 못 받으면 안내 (눌러서 지도로 볼 수 있음)
    final addr = s.placeNameFor(item);
    final addrLine = addr ??
        (item.gps == null
            ? ''
            : (s.placeLookupFailed(item) ? '주소를 불러오지 못했어요 · 눌러서 지도 보기' : '주소 확인 중…'));
    final placeLine = join([item.place, addrLine]);
    final info = <(String, String, String)>[
      if (item.isInfoImage) ...[
        // 스크린샷·문서 등 정보성 이미지: 내용 중심 (촬영 장소 대신 출처)
        ('calendar', '저장 날짜', item.date),
        (
          'image',
          '이미지 유형',
          join([
            imageTypeLabel(item.imageType),
            ...item.semanticCategory.take(2),
          ]),
        ),
        ('store', '출처', item.sourcePlatform),
        ('target', '핵심 주제', item.mainTopic),
        ('doc', '주요 내용', item.contentSummary),
        // 위치 정보가 실제로 있는 경우만 (없으면 '촬영 장소' 줄을 아예 표시하지 않음)
        if (item.gps != null)
          ('pin', '촬영 장소', placeLine),
      ] else ...[
        ('calendar', '촬영 날짜·시간', join([item.date, item.time])),
        // 장소 유형 + 시·구·동 주소 (좌표는 표시하지 않음)
        (
          'pin',
          '촬영 장소',
          // GPS 만 있고 장소 이름·주소가 아직 없으면 지도로 볼 수 있게 줄은 남긴다
          placeLine,
        ),
        // 사람: 새 분석은 '주인공: … / 배경: …' 형식 → 주인공과 배경 인물을 따로 표시
        if (_peopleParts(item.people) case (final main?, final back)) ...[
          ('person', '주인공', join([main])),
          ('person', '배경 인물', join([?back])),
          ('image', '주요 객체·장면', join([...item.food, item.background])),
        ] else
          (
            'image',
            '주요 객체·장면',
            join([...item.food, item.people, item.background]),
          ),
        ('palette', '분위기·특징', join([item.weather, item.caption])),
      ],
    ].where((x) => x.$3.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: item.isInfoImage
              ? imageTypeLabel(item.imageType)
              : (item.place.isEmpty ? '사진' : item.place),
          onBack: () {
            if (!s.backFromRelated()) s.go(s.detailReturn);
          },
          trailing: Text(item.date),
        ),
        RoundedPhoto(item: item),
        if (record != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              record.title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: c.ink,
              ),
            ),
          ),
        if (relatedTiles.isNotEmpty) ...[
          if (record == null)
            const SnapH3('관련된 추억')
          else
            const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: relatedTiles[0]),
              const SizedBox(width: 12),
              Expanded(
                child: relatedTiles.length > 1
                    ? relatedTiles[1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
        // 사진 정보 (펼치기/접기)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: SnapCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                Pressable(
                  onTap: () => setState(() => _infoOpen = !_infoOpen),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const IconBadge('sparkle', size: 34, radius: 9),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '사진 정보',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: c.ink,
                            ),
                          ),
                        ),
                        AnimatedRotation(
                          turns: _infoOpen ? 0 : -0.25,
                          duration: const Duration(milliseconds: 200),
                          child: SnapIcon('down', size: 20, color: c.pk),
                        ),
                      ],
                    ),
                  ),
                ),
                // 눌렀을 때 툭 나오지 않고 스르륵: 높이가 부드럽게 늘어나며 내용이 살짝 내려오면서 나타남
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !_infoOpen
                      ? const SizedBox(width: double.infinity)
                      : TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOut,
                          builder: (_, t, child) => Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, -8 * (1 - t)),
                              child: child,
                            ),
                          ),
                          child: Column(
                            children: [
                  Container(height: 0.5, color: c.line),
                  InfoRows(
                    rows: info,
                    // GPS 가 있는 사진만: 촬영 장소를 누르면 지도 팝업
                    actions: {
                      if (item.gps case [final lat, final lng, ...])
                        '촬영 장소': () => showPhotoMap(
                          context,
                          lat: lat,
                          lng: lng,
                          title: isUnknownInfo(item.place) || item.place.isEmpty
                              ? '촬영 장소'
                              : item.place,
                          address: s.placeNameFor(item),
                        ),
                    },
                  ),
                  // 관련 키워드 (의미 기반 검색어)
                  if (item.searchKeywords.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final k in item.searchKeywords.take(8))
                            SnapTag(label: '#$k'),
                        ],
                      ),
                    ),
                  // 추출된 정보 미리보기 (structured_data 핵심 3~5개)
                  if (structuredPreview(item.structuredData) case final lines
                      when lines.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: c.soft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '추출된 정보',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.pk,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (final l in lines)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                keepWords('•  $l'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: c.ink,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  // 이 사진만 고해상도로 다시 분석
                  _ReanalyzeLink(state: s, item: item),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        // 공유하기 (사진 정보 아래 · 기록 버튼 위)
        _ShareButton(item: item, title: s.memoryTitle(item)),
        // 기록으로 남기기 / 나의 기록 보기
        SnapButton(
          label: record == null ? '기록으로 남기기' : '나의 기록 보기',
          icon: 'bookmark',
          top: 10,
          onTap: record == null
              ? () => s.startRecord(item.id)
              : () => s.openRecord(record.id),
        ),
      ],
    );
  }
}

/// '주인공: … / 배경: …' 형식이면 (주인공, 배경) 으로 나눈다. 예전 형식이면 (null, null).
(String?, String?) _peopleParts(String people) {
  final m = RegExp(r'주인공\s*[:：]\s*([^/]*)').firstMatch(people);
  if (m == null) return (null, null);
  final b = RegExp(r'배경\s*[:：]\s*([^/]*)').firstMatch(people);
  return (m.group(1)!.trim(), b?.group(1)?.trim());
}

/// 사진 정보 카드 아래쪽 '다시 분석하기' — 이 사진 한 장만 고해상도(글자까지)로 다시 분석
class _ReanalyzeLink extends StatelessWidget {
  const _ReanalyzeLink({required this.state, required this.item});
  final SnapbackState state;
  final PhotoItem item;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    final busy = s.reanalyzingId == item.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.analysisVersion >= 2
                      ? '정보가 정확하지 않다면 다시 분석해 보세요'
                      : '예전 방식으로 분석된 사진이에요',
                  style: TextStyle(fontSize: 12.5, color: c.mute),
                ),
              ),
              Pressable(
                onTap: busy || s.reanalyzingId != null
                    ? null
                    : () => s.reanalyzePhoto(item.id),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SnapIcon(
                        busy ? 'refresh' : 'sparkle',
                        size: 15,
                        color: c.pk,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        busy ? '정밀 분석 중…' : '다시 분석하기',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.pk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (s.reanalyzeError != null && !busy)
            SnapNote(s.reanalyzeError!, icon: 'alert', top: 6),
        ],
      ),
    );
  }
}

/// 사진 상세의 '공유하기' — 누르면 시스템 공유 창 (원본을 가져오는 동안은 '준비 중')
class _ShareButton extends StatefulWidget {
  const _ShareButton({required this.item, required this.title});
  final PhotoItem item;
  final String title;

  @override
  State<_ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<_ShareButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (btnContext) => SnapButton(
      label: _busy ? '공유 준비 중…' : '공유하기',
      icon: _busy ? null : 'share',
      ghost: true,
      top: 20,
      onTap: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await sharePhoto(btnContext, widget.item, widget.title);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    ),
  );
}
