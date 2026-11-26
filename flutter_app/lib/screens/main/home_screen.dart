part of '../main_screens.dart';

// 사진 탭(홈): 검색창 · 다시 꺼내 볼 기억 · 월간 리캡 · 모든 사진(정렬·편집)

/// ① 홈 (사진 + 기억으로 찾기)
class Screen5Home extends StatefulWidget {
  const Screen5Home({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen5Home> createState() => _Screen5HomeState();
}

class _Screen5HomeState extends State<Screen5Home>
    with SingleTickerProviderStateMixin {
  final _searchBoxKey = GlobalKey();
  bool _showAll = true; // 기본은 모든 사진(월별). '접기'를 누르면 최근 사진 9장만
  bool _editing = false; // '편집' — 사진을 골라 앱에서 지우기
  final Set<int> _sel = {};

  void _tapPhoto(SnapbackState s, PhotoItem d) {
    if (!_editing) return s.openMemory(d.id);
    setState(() => _sel.contains(d.id) ? _sel.remove(d.id) : _sel.add(d.id));
  }

  /// 사진 정렬 기준 고르기 (팝업): 시간순 / 추가순
  Future<void> _pickSort(SnapbackState s) async {
    final c = context.sc;
    const options = [
      ('time', '시간순', '찍은 날짜가 최근인 사진부터, 월별로'),
      ('added', '추가순', '앱에 최근 추가한 사진부터'),
    ];
    final picked = await showSnapDialog<String>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (ctx) => Dialog(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  '정렬 기준',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              for (final (id, label, hint) in options)
                Pressable(
                  onTap: () => Navigator.of(ctx).pop(id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: s.photoSort == id
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: s.photoSort == id ? c.pk : c.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hint,
                                style: TextStyle(fontSize: 13, color: c.mute),
                              ),
                            ],
                          ),
                        ),
                        if (s.photoSort == id)
                          SnapIcon('check', size: 18, color: c.pk),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) s.setPhotoSort(picked);
  }

  Future<void> _deleteSelected(SnapbackState s) async {
    final n = _sel.length;
    final ok = await showSnapConfirm(
      context,
      title: '사진 $n장을 지울까요?',
      message: 'Snapback 에서만 지워져요.\n사진 앱의 원본 사진은 그대로 남아요.\n지운 사진은 다시 분석하지 않아요.',
    );
    if (!ok || !mounted) return;
    s.removePhotos({..._sel});
    setState(() {
      _sel.clear();
      _editing = false;
    });
  }

  // 검색에서 뒤로 왔을 때: 검색창은 이미 제자리, 나머지 내용만 페이드 인
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.state.takeHomeReturn()) _reveal.forward(from: 0);
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _openSearch(SnapbackState s) {
    final box = _searchBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return s.openNewSearch();
    final top = box.localToGlobal(Offset.zero);
    // 스크롤 0 기준 위치를 기억해 두면, 돌아올 때(맨 위에서 시작) 이 자리로 올라온다
    final scrolled = Scrollable.maybeOf(context)?.position.pixels ?? 0;
    s.homeSearchBoxTop = top.dy + scrolled;
    s.openSearchFrom(top & box.size);
  }

  Widget _faded(Widget child) => FadeTransition(
    opacity: CurvedAnimation(parent: _reveal, curve: Curves.easeOut),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    // 정렬: 시간순(촬영 날짜, 월별 묶음) / 추가순(앱에 추가한 순서 — id 가 클수록 나중에 추가)
    final byAdded = s.photoSort == 'added';
    final groups = <String, List<PhotoItem>>{};
    final photos = s.visiblePhotos.toList()
      ..sort(
        (a, b) => byAdded
            ? b.id.compareTo(a.id)
            : b.date.compareTo(a.date) == 0
            ? b.id.compareTo(a.id)
            : b.date.compareTo(a.date),
      );
    for (final d in photos) {
      groups.putIfAbsent(d.date.substring(0, 7), () => []).add(d);
    }
    final months = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _faded(
          LargeTitle(
            title: 'Snapback',
            leading: const SnapCharacter(size: 34),
            fontSize: 18,
            fontWeight: FontWeight.w600,
            actions: [
              TitleButton(icon: 'plus', onTap: s.openAddPhotos),
              TitleButton(icon: 'gear', onTap: () => s.go(12)),
            ],
          ),
        ),
        // 디자인 B3 — 큰 안내 문구 (두 번째 줄만 오렌지)
        _faded(
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 0, 18),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '어떤 순간을\n'),
                  TextSpan(
                    text: '찾고 있나요?',
                    style: TextStyle(color: context.sc.pri),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 32,
                height: 1.18,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.2,
                color: context.sc.ink,
              ),
            ),
          ),
        ),
        // 지난 분석에서 실패한 사진이 있으면 알림 (누르면 분석 진행 화면의 기록으로)
        SnapReveal(
          visible: s.analysisFailed > 0 && !s.analysisRunning,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Pressable(
              onTap: () => s.go(4),
              child: SnapWarn(
                '사진 ${s.analysisFailed}장을 분석하지 못했어요. 눌러서 이유를 확인해 보세요.',
              ),
            ),
          ),
        ),
        // 사진을 고를 때 건너뛴 사진 안내 (이미 분석한 사진 등)
        SnapReveal(
          visible: s.pickNotice.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SnapNote(s.pickNotice, icon: 'alert', top: 0),
          ),
        ),
        // 검색창: 누르면 이 창이 그대로 검색 화면 위치로 내려간다
        GestureDetector(
          onTap: () => _openSearch(s),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SnapSearchBar(
              key: _searchBoxKey,
              enabled: false,
              showButton: true,
              hint: '기억나는 장면을 말해 보세요',
            ),
          ),
        ),
        _faded(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (months.isEmpty)
                const SnapEmpty(
                  icon: 'image',
                  text: '아직 사진이 없어요.\n오른쪽 위 ＋ 를 눌러 사진을 추가해 보세요.',
                )
              else ...[
                // 디자인 B3 — 다시 꺼내 볼 기억
                if (s.resurfaceMemory() case (final photo, final title))
                  _MemoryCard(
                    photo: photo,
                    title: title,
                    onTap: () => s.openMemory(photo.id),
                  ),
                // 월간 리캡: 이번 달 자주 간 동네·음식·분위기 + 자동 앨범
                if (s.monthlyRecap case final recap?)
                  RecapCard(state: s, recap: recap),
                // 최근 사진 · 모두 보기
                Padding(
                  padding: const EdgeInsets.only(top: 26, bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _showAll ? '모든 사진' : '최근 사진',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: context.sc.ink,
                          ),
                        ),
                      ),
                      // 정렬 기준: 시간순 / 추가순
                      Pressable(
                        onTap: () => _pickSort(s),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                byAdded ? '추가순' : '시간순',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: context.sc.pk,
                                ),
                              ),
                              const SizedBox(width: 2),
                              SnapIcon('down', size: 14, color: context.sc.pk),
                            ],
                          ),
                        ),
                      ),
                      // 편집: 사진을 골라 앱에서 지우기 (원본은 그대로)
                      Pressable(
                        onTap: () => setState(() {
                          _editing = !_editing;
                          _sel.clear();
                        }),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Text(
                            _editing ? '완료' : '편집',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.sc.pk,
                            ),
                          ),
                        ),
                      ),
                      if (photos.length > 9)
                        Pressable(
                          onTap: () => setState(() => _showAll = !_showAll),
                          child: Text(
                            _showAll ? '접기' : '모두 보기',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.sc.pk,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SnapReveal(
                  visible: _editing,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SnapSub(
                            _sel.isEmpty
                                ? '지울 사진을 눌러 고르세요 · 사진 앱의 원본은 지워지지 않아요'
                                : '${_sel.length}장 선택됨',
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 전체 선택 / 전체 해제 (모든 사진 기준, 선택이 보이게 모두 보기로 펼침)
                        Pressable(
                          onTap: () => setState(() {
                            final all = photos.map((d) => d.id).toSet();
                            if (_sel.length == all.length) {
                              _sel.clear();
                            } else {
                              _sel
                                ..clear()
                                ..addAll(all);
                              _showAll = true;
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: context.sc.soft,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              _sel.length == photos.length ? '전체 해제' : '전체 선택',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: context.sc.pk,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_showAll)
                  PhotoGrid(
                    items: photos.take(9).toList(),
                    selected: _editing ? _sel : null,
                    onTap: (d) => _tapPhoto(s, d),
                  )
                else if (byAdded)
                  PhotoGrid(
                    items: photos,
                    selected: _editing ? _sel : null,
                    onTap: (d) => _tapPhoto(s, d),
                  )
                else
                  for (final k in months) ...[
                    SnapH3(
                      '${k.substring(0, 4)}년 ${int.parse(k.substring(5))}월',
                      small: true,
                    ),
                    PhotoGrid(
                      items: groups[k]!,
                      selected: _editing ? _sel : null,
                      onTap: (d) => _tapPhoto(s, d),
                    ),
                  ],
                SnapReveal(
                  visible: _editing,
                  child: SnapButton(
                    label: _sel.isEmpty
                        ? '지울 사진을 골라 주세요'
                        : '선택한 사진 ${_sel.length}장 지우기',
                    onTap: _sel.isEmpty ? null : () => _deleteSelected(s),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 디자인 B3 — 홈 '다시 꺼내 볼 기억' 큰 카드 (사진 + 아래쪽 반투명 이름표)
class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.photo, required this.title, this.onTap});
  final PhotoItem photo;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final p = photo.date.split('-');
    final when = p.length == 3
        ? ' · ${int.tryParse(p[1]) ?? p[1]}월 ${int.tryParse(p[2]) ?? p[2]}일'
        : '';
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          height: 168,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PhotoTile(
                item: photo,
                radius: 26,
                showDate: false,
                iconSize: 0.01,
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
                      decoration: BoxDecoration(
                        color: c.bg.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '다시 꺼내 볼 기억$when',
                                  style: TextStyle(fontSize: 13, color: c.pk),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                    color: c.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SnapIcon('arrow', size: 22, color: c.ink),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
