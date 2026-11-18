import 'package:material_ui/material_ui.dart';

import '../models/photo_album.dart';
import '../models/photo_item.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

// index.html(2aslx-patch-1) 의 섹션 5~15 + Flutter 추가 화면(16 앨범 상세).

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
  // 검색에서 뒤로 왔을 때: 검색창은 이미 제자리, 나머지 내용만 페이드 인
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  static const _sugg = [
    ('비 오는 날 카페', '비 오는 날 카페에서 먹은 디저트'),
    ('노을 진 강가', '노을 질 때 강가'),
    ('친구랑 저녁', '친구들이랑 저녁 먹은 날'),
    ('여행지의 꽃', '여행 가서 찍은 꽃'),
  ];

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
    if (box == null || !box.hasSize) return s.go(13);
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
    // 월별 묶음 (최신 월부터)
    final groups = <String, List<PhotoItem>>{};
    final photos = s.visiblePhotos.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
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
            actions: [
              TitleButton(
                icon: 'plus',
                onTap: () => s.pickPhotosFromGallery(startImmediately: true),
              ),
              TitleButton(icon: 'gear', onTap: () => s.go(12)),
            ],
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
              hint: '어떤 순간을 찾고 있나요?',
            ),
          ),
        ),
        _faded(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // .sugg — 가로 스크롤 추천 칩 (가장자리까지)
              Padding(
                padding: EdgeInsets.zero,
                child: Bleed(
                  child: SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _sugg.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 7),
                      itemBuilder: (_, i) => SnapChip(
                        label: _sugg[i].$1,
                        card: true,
                        onTap: () {
                          s.go(13);
                          s.startNewSearch(_sugg[i].$2);
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (months.isEmpty)
                const SnapEmpty(
                  icon: 'image',
                  text: '아직 사진이 없어요.\n오른쪽 위 ＋ 를 눌러 사진을 추가해 보세요.',
                )
              else
                for (final k in months) ...[
                  SnapH3('${k.substring(0, 4)}년 ${int.parse(k.substring(5))}월'),
                  PhotoGrid(
                    items: groups[k]!,
                    onTap: (d) => s.openMemory(d.id),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

/// ③ 카테고리 탐색 (음식)
class Screen6FoodCategory extends StatefulWidget {
  const Screen6FoodCategory({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen6FoodCategory> createState() => _Screen6FoodCategoryState();
}

class _Screen6FoodCategoryState extends State<Screen6FoodCategory> {
  String _chip = '전체';
  static const _labels = ['전체', '디저트', '면', '커피', '술'];
  static const _food = [
    ('bowl', '면'), ('cake', '디저트'), ('cup', '커피'), ('glass', '술'),
    ('bowl', '면'), ('cake', '디저트'), ('cup', '커피'), ('glass', '술'),
    ('bread', '디저트'), ('bowl', '면'), ('cake', '디저트'), ('cup', '커피'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final shown = _food.where((x) => _chip == '전체' || x.$2 == _chip).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '음식',
          leadingIcon: 'food',
          onBack: () => s.go(5),
          trailing: Text('412장', style: TextStyle(fontSize: 12, color: c.mute)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: _labels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => SnapChip(
                label: _labels[i],
                selected: _chip == _labels[i],
                onTap: () => setState(() => _chip = _labels[i]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Bleed(
          child: GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: shown.length,
            itemBuilder: (_, i) => Container(
              decoration: BoxDecoration(gradient: kTileGradients[i % 6]),
              alignment: Alignment.center,
              child: Opacity(
                opacity: 0.92,
                child: SnapIcon(
                  shown[i].$1,
                  size: 30,
                  color: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ③ 사진 정보 (추출 결과)
class Screen7PhotoInfo extends StatelessWidget {
  const Screen7PhotoInfo({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '사진 정보', onBack: () => s.go(5)),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Bleed(
            child: Container(
              height: 280,
              decoration: BoxDecoration(gradient: kTileGradients[0]),
              alignment: Alignment.center,
              child: const Opacity(
                opacity: 0.92,
                child: SnapIcon(
                  'cake',
                  size: 66,
                  color: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
            ),
          ),
        ),
        const SnapH3('메타데이터'),
        const Wrap(
          children: [
            SnapTag(icon: 'clock', label: '2026.10.15 14:32'),
            SnapTag(icon: 'pin', label: '37.54, 127.05'),
          ],
        ),
        const SnapH3('이미지 분석'),
        const Wrap(
          children: [
            SnapTag(icon: 'cake', label: '디저트'),
            SnapTag(icon: 'home', label: '카페(실내)'),
            SnapTag(icon: 'window', label: '큰 창·비'),
            SnapTag(icon: 'person', label: '2명 · 니트'),
          ],
        ),
        const SnapGroup(
          children: [
            SnapRow(
              leading: IconBadge('stack'),
              title: '검색 DB 저장 완료',
              subtitle: '사진 ID #20261015-0832',
            ),
          ],
        ),
        SnapButton(
          label: '이 사진의 기억 보기',
          ghost: true,
          onTap: () => s.go(10),
        ),
      ],
    );
  }
}

/// ④ 대화형 검색 (프로토타입 데모)
class Screen8PrototypeChat extends StatefulWidget {
  const Screen8PrototypeChat({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen8PrototypeChat> createState() => _Screen8PrototypeChatState();
}

class _Screen8PrototypeChatState extends State<Screen8PrototypeChat> {
  final _q = TextEditingController(text: '비 오는 날 창가에서 먹은 디저트');
  static const _questions = [
    ('낮이었나요, 저녁이었나요?', ['낮', '저녁'], 128, 19),
    ('누구와 함께였나요?', ['혼자', '친구와'], 19, 4),
  ];
  final List<String> _answers = [];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    const bold = TextStyle(fontWeight: FontWeight.w700);
    final log = <Widget>[];
    for (var n = 0; n <= _answers.length && n < _questions.length; n++) {
      final q = _questions[n];
      log.add(
        SnapBubble(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: '후보 '),
                TextSpan(text: '${q.$3}장', style: bold),
                TextSpan(text: ' → 질문 ${n + 1}/2\n'),
                TextSpan(text: q.$1, style: bold),
              ],
            ),
          ),
        ),
      );
      if (n < _answers.length) {
        log.add(SnapBubble(isMe: true, child: Text(_answers[n])));
        log.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SnapBar(value: (100 - q.$4 / 1.3) / 100),
          ),
        );
      } else {
        log.add(
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in q.$2)
                SnapChip(
                  label: a,
                  onTap: () => setState(() => _answers.add(a)),
                ),
              SnapChip(
                label: '기억 안 나요 (건너뛰기)',
                dashed: true,
                onTap: () => setState(() => _answers.add('기억 안 나요')),
              ),
            ],
          ),
        );
      }
    }
    final done = _answers.length >= _questions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '기억으로 찾기', onBack: () => s.go(5)),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 12),
          child: SnapSearchBar(
            controller: _q,
            showIcon: false,
            onSubmit: () => setState(_answers.clear),
          ),
        ),
        ...log,
        if (done) ...[
          const SnapBubble(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '후보가 '),
                  TextSpan(text: '4장', style: bold),
                  TextSpan(text: '으로 줄었어요!'),
                ],
              ),
            ),
          ),
          SnapButton(label: '결과 보기', onTap: () => s.go(9)),
        ],
      ],
    );
  }
}

/// ④ 검색 결과 (프로토타입 데모)
class Screen9PrototypeResults extends StatelessWidget {
  const Screen9PrototypeResults({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '검색 결과',
          onBack: () => s.go(8),
          trailing: Text('4장', style: TextStyle(fontSize: 12, color: c.mute)),
        ),
        SnapGroup(
          children: [
            SnapRow(
              leading: const IconBadge('cake', gradIndex: 0),
              title: '성수동 카페 · 2026.10.15',
              subtitle: '✓ 비 오는 날 ✓ 창가 ✓ 디저트 · 성수동',
              trailingText: '92%',
              onTap: () => s.go(10),
            ),
            const SnapRow(
              leading: IconBadge('bread', gradIndex: 2),
              title: '합정 베이커리 · 2026.07.02',
              subtitle: '✓ 디저트 ✓ 창가 · 비 정보 없음',
              trailingText: '71%',
            ),
            const SnapRow(
              leading: IconBadge('bowl', gradIndex: 4),
              title: '연남동 카페 · 2025.06.21',
              subtitle: '✓ 디저트 · 위치 확인 불가',
              trailingText: '58%',
            ),
            const SnapRow(
              leading: IconBadge('cup', gradIndex: 1),
              title: '서촌 찻집 · 2025.04.09',
              subtitle: '✓ 창가 · 디저트 낮은 확신',
              trailingText: '44%',
            ),
          ],
        ),
        const SnapNote('단서에 맞은 항목을 표시해요 · 눌러서 자세히'),
      ],
    );
  }
}

/// ⑤ 기억 상세 · 연쇄 소환
class Screen10MemoryDetail extends StatelessWidget {
  const Screen10MemoryDetail({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final item = s.db.firstWhere(
      (x) => x.id == s.activeMemoryId,
      orElse: () => s.db.first,
    );
    final rel = s.relatedFor(item);
    final detail =
        item.caption.isNotEmpty ? item.caption : item.food.join(', ');

    Widget section(String icon, String title, List<PhotoItem> list) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SnapH3(title, icon: icon, trailing: '(${list.length})'),
            if (list.isEmpty)
              const SnapNote('없어요', top: 0)
            else
              PhotoStrip(items: list, onTap: (d) => s.openMemory(d.id)),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: 'Snapback', onBack: () => s.go(13)),
        SnapHero(item: item),
        SnapH2(item.place.isEmpty ? '사진' : item.place, fontSize: 19),
        SnapSub('${item.date}${item.gps != null ? ' · GPS' : ''} · $detail'),
        section('calendar', '같은 날의 사진', rel.sameDay),
        section('pin', '가까운 장소에서', rel.nearPlace),
        section('palette', '비슷한 분위기·배경', rel.similarMood),
        const SnapH3('방문 장소', icon: 'store'),
        const SnapMapBox(),
        const SnapGroup(
          children: [
            SnapRow(
              leading: IconBadge('cup'),
              title: '카페 ○○',
              subtitle: '영업시간 10:00–21:00 · 연결 확실도 높음',
            ),
          ],
        ),
      ],
    );
  }
}

/// ⑥ 앨범 · 스크린샷 (확장). 앨범은 검색 결과 제안으로만 만든다.
class Screen11Albums extends StatelessWidget {
  const Screen11Albums({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LargeTitle(title: '앨범'),
        SnapGroup(
          top: 10,
          children: [
            SnapRow(
              leading: const IconBadge('heart'),
              title: '성장 기록 · 레퍼런스 보드',
              subtitle: '활용 모드',
              onTap: () => s.go(15),
            ),
          ],
        ),
        const SnapH3('내 앨범'),
        if (s.albums.isEmpty)
          GestureDetector(
            onTap: () => s.go(13),
            child: const SnapEmpty(
              icon: 'stack',
              text: '아직 앨범이 없어요.\n사진을 검색하면 어울리는 앨범을 제안해 드려요.',
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
            ),
            itemCount: s.albums.length,
            itemBuilder: (_, i) {
              final a = s.albums[i];
              final photos = s.albumPhotos(a);
              return PhotoTile(
                item: photos.isNotEmpty
                    ? photos.first
                    : PhotoItem(id: a.id + 4, date: '', place: ''),
                radius: 12,
                label: '${a.title} · ${photos.length}',
                onTap: () => s.openAlbum(a.id),
              );
            },
          ),
        const SnapH3('스크린샷 정보 추출', icon: 'phone'),
        const SnapGroup(
          children: [
            SnapRow(
              leading: IconBadge('tag', gradIndex: 3),
              title: '운동화',
              subtitle: '브랜드·모델·₩129,000',
              trailingText: '복사',
            ),
            SnapRow(
              leading: IconBadge('receipt', gradIndex: 2),
              title: '예약 확인서',
              subtitle: '11.20 · 2명 · 장소',
              trailingText: '일정 추가',
            ),
          ],
        ),
        const SnapH3('취향 요약', icon: 'compass'),
        const SnapGroup(
          children: [
            SnapRow(
              leading: IconBadge('cup'),
              title: '“카페와 미술관을 자주 가요”',
              subtitle: '다음 나들이: 한남 · 삼청 일대 추천',
            ),
          ],
        ),
      ],
    );
  }
}

/// ⑥ 설정 · 개인정보
class Screen12Settings extends StatefulWidget {
  const Screen12Settings({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen12Settings> createState() => _Screen12SettingsState();
}

class _Screen12SettingsState extends State<Screen12Settings> {
  late final _url = TextEditingController(text: widget.state.serverUrl);

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final counts = <String, int>{};
    for (final d in s.db) {
      final y = d.date.substring(0, 4);
      counts[y] = (counts[y] ?? 0) + 1;
    }
    final years = counts.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '설정 · 개인정보', onBack: () => s.go(5)),
        const SnapH3('접근 범위 (연도별)', small: true),
        SnapGroup(
          top: 0,
          separatorInset: 14,
          children: [
            for (final y in years)
              SnapRow(
                leading: SnapIcon('calendar', size: 18.4, color: c.ink),
                title: '$y년 사진 (${counts[y]}장)',
                trailing: SnapSwitch(
                  value: !s.db.any((d) => d.date.startsWith(y) && d.hidden),
                  onChanged: (_) => s.toggleYearVisibility(y),
                ),
              ),
          ],
        ),
        if (s.hiddenWarning.isNotEmpty) SnapWarn(s.hiddenWarning),
        SnapGroup(
          children: [
            SnapRow(
              leading: const IconBadge('flask'),
              title: '사용성 테스트 모드',
              subtitle: 'Top-5 포함률·시간·질문 수 측정',
              trailing: const Chevron(),
              onTap: () => s.go(14),
            ),
          ],
        ),
        const SnapH3('분석', small: true),
        SnapGroup(
          top: 0,
          separatorInset: 14,
          children: [
            SnapRow(
              leading: SnapIcon('battery', size: 18.4, color: c.ink),
              title: '백그라운드 분석',
              trailing: SnapSwitch(
                value: s.backgroundAnalysis,
                onChanged: (v) {
                  s.backgroundAnalysis = v;
                  s.touch();
                },
              ),
            ),
            SnapRow(
              leading: SnapIcon('refresh', size: 18.4, color: c.ink),
              title: '분석 순서 다시 선택',
              trailing: const Chevron(),
              onTap: () => s.go(3),
            ),
          ],
        ),
        // Flutter 추가: iOS 앱이 연결할 API 서버 주소
        const SnapH3('서버', small: true),
        SnapSearchBar(
          controller: _url,
          showIcon: false,
          hint: '비우면 기본 서버',
          buttonIcon: 'check',
          keyboardType: TextInputType.url,
          onSubmit: () => s.setServerUrl(_url.text),
        ),
        SnapNote(s.aiStatusText),
      ],
    );
  }
}

/// ★ 기억으로 찾기 (AI)
class Screen13Search extends StatefulWidget {
  const Screen13Search({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen13Search> createState() => _Screen13SearchState();
}

class _Screen13SearchState extends State<Screen13Search>
    with SingleTickerProviderStateMixin {
  late final _ctrl = TextEditingController(
    text: widget.state.searchHistory.isNotEmpty
        ? widget.state.searchHistory.first
        : '',
  );
  final _focus = FocusNode();
  final _boxKey = GlobalKey();
  // 진입 애니메이션: 홈 검색창 위치 → 제자리로 스르르, 나머지는 뒤따라 페이드 인
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    reverseDuration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _boxMove = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0, 0.8, curve: Curves.easeInOutCubic),
  );
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.4, 1, curve: Curves.easeOut),
  );
  double _fromDy = 0;
  bool _measuring = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    final from = widget.state.takeSearchOrigin();
    if (from == null) {
      _enter.value = 1;
      return;
    }
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      setState(() {
        _measuring = false;
        if (box != null && box.hasSize && !reduceMotion) {
          _fromDy = from.top - box.localToGlobal(Offset.zero).dy;
        }
      });
      if (reduceMotion) {
        _enter.value = 1;
        _focus.requestFocus();
        return;
      }
      _enter.forward().whenComplete(() {
        if (mounted) _focus.requestFocus();
      });
    });
  }

  /// 뒤로가기: 제목·결과가 먼저 사라지고 검색창이 홈의 제자리로 스르르 올라간 뒤 홈으로.
  Future<void> _back() async {
    final s = widget.state;
    if (_leaving) return;
    final target = s.homeSearchBoxTop;
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (target == null ||
        box == null ||
        !box.hasSize ||
        MediaQuery.of(context).disableAnimations) {
      return s.go(5);
    }
    _leaving = true;
    _focus.unfocus();
    final rest =
        box.localToGlobal(Offset.zero).dy - _fromDy * (1 - _boxMove.value);
    setState(() => _fromDy = target - rest);
    await _enter.reverse(from: _enter.value);
    if (mounted) s.returnHomeFromSearch();
  }

  @override
  void dispose() {
    _enter.dispose();
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Widget _revealed(Widget child, {double rise = 0}) => AnimatedBuilder(
        animation: _reveal,
        builder: (_, w) => Opacity(
          opacity: _reveal.value,
          child: Transform.translate(
            offset: Offset(0, rise * (1 - _reveal.value)),
            child: w,
          ),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _revealed(
          SnapbackTopBar(
            title: '기억으로 찾기',
            onBack: _back,
            trailing: Text(s.aiStatusText),
          ),
        ),
        _revealed(rise: 10, const SnapH2('어떤 사진을\n찾고 계시나요?')),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: AnimatedBuilder(
            animation: _boxMove,
            builder: (_, w) => Opacity(
              opacity: _measuring ? 0 : 1,
              child: Transform.translate(
                offset: Offset(0, _fromDy * (1 - _boxMove.value)),
                child: w,
              ),
            ),
            child: SnapSearchBar(
              key: _boxKey,
              controller: _ctrl,
              focusNode: _focus,
              hint: '기억나는 대로 말해요',
              busy: s.searchBusy,
              onSubmit: () => s.startNewSearch(_ctrl.text),
            ),
          ),
        ),
        _revealed(_results(s, c)),
      ],
    );
  }

  Widget _results(SnapbackState s, SnapbackColors c) {
    final byId = {for (final d in s.db) d.id: d};
    if (s.searchBusy) return const SnapNote('AI가 기억을 더듬는 중…');
    if (s.searchError != null) {
      return SnapNote(
        s.searchError!,
        icon: 'alert',
        color: const Color(0xFFC0392B),
      );
    }
    if (s.searchResults.isEmpty) {
      return SnapEmpty(
        icon: 'sparkle',
        text: s.testSession != null
            ? '테스트 중 — 목표 사진을 떠올려 기억나는 대로 입력하고,\n찾으면 그 사진을 누르세요'
            : '날짜나 장소가 기억나지 않아도 괜찮아요.\n떠오르는 장면을 그대로 적어 보세요.',
      );
    }
    final valid = s.searchResults.where((x) => byId.containsKey(x.id)).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    String clues(SearchRankedItem x) =>
        '✓ ${x.matched.join(' ✓ ')}${x.missing.isNotEmpty ? ' · ? ${x.missing.join(', ')}' : ''}';
    final top = valid.isNotEmpty ? valid.first : null;
    final rest = valid.skip(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1순위 — 크게
        if (top != null)
          Pressable(
            onTap: () => s.openMemory(top.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhotoTile(
                  item: byId[top.id]!,
                  height: 220,
                  width: double.infinity,
                  radius: 13,
                  showDate: false,
                  iconSize: 60,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.soft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '일치 확률 ${top.score}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.pk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${byId[top.id]!.place} · ${byId[top.id]!.date}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    clues(top),
                    style: TextStyle(fontSize: 13, color: c.mute),
                  ),
                ),
              ],
            ),
          ),
        // 2순위 이하 — #ao .row (58 썸네일)
        if (rest.isNotEmpty) ...[
          const SnapH3('다음으로 확률이 높은 사진'),
          SnapGroup(
            top: 0,
            separatorInset: 86,
            children: [
              for (final x in rest)
                SnapRow(
                  leading: IconBadge(
                    byId[x.id]!.icon,
                    gradIndex: x.id,
                    size: 58,
                    radius: 10,
                    image: decodeDataUrl(byId[x.id]!.thumbDataUrl),
                  ),
                  title: byId[x.id]!.place,
                  subtitle: byId[x.id]!.date,
                  subtitle2: clues(x),
                  trailingText: '${x.score}%',
                  onTap: () => s.openMemory(x.id),
                ),
            ],
          ),
        ],
        if (s.activeQuestion != null) ...[
          SnapBubble(child: Text(s.activeQuestion!.text)),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in s.activeQuestion!.options)
                SnapChip(label: o, onTap: () => s.answerFollowUp(o)),
              SnapChip(
                label: '기억 안 나요',
                dashed: true,
                onTap: () => s.answerFollowUp('기억 안 나요'),
              ),
            ],
          ),
        ] else if (s.searchCompleted)
          const SnapNote('후보가 충분히 좁혀졌어요', icon: 'check'),
        if (s.albumSuggestion case final sug?)
          _AlbumSuggestionCard(
            key: ValueKey('album-sug-${s.searchHistory.first}'),
            state: s,
            suggestion: sug,
          )
        else if (s.albumById(s.lastCreatedAlbumId) case final made?)
          SnapGroup(
            top: 16,
            children: [
              SnapRow(
                leading: const IconBadge('check'),
                title: '‘${made.title}’ 앨범을 만들었어요',
                subtitle: '사진 ${made.photoIds.length}장 · 앨범 탭에서 볼 수 있어요',
                trailingText: '보러 가기',
                onTap: () => s.openAlbum(made.id),
              ),
            ],
          ),
      ],
    );
  }
}

/// 검색 결과 아래 "이런 앨범으로 만들어 드릴까요?" 제안 카드.
class _AlbumSuggestionCard extends StatefulWidget {
  const _AlbumSuggestionCard({
    super.key,
    required this.state,
    required this.suggestion,
  });

  final SnapbackState state;
  final AlbumSuggestion suggestion;

  @override
  State<_AlbumSuggestionCard> createState() => _AlbumSuggestionCardState();
}

class _AlbumSuggestionCardState extends State<_AlbumSuggestionCard> {
  late final TextEditingController _title =
      TextEditingController(text: widget.suggestion.title);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final sug = widget.suggestion;
    final c = context.sc;
    final byId = {for (final d in s.db) d.id: d};
    final photos = [
      for (final id in sug.photoIds)
        if (byId[id] != null) byId[id]!,
    ];
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SnapIcon('folder', size: 19.5, color: c.pk),
              const SizedBox(width: 6),
              Text(
                '이런 앨범으로 만들어 드릴까요?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: c.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '이번 검색과 잘 맞는 사진 ${photos.length}장을 묶을게요',
            style: TextStyle(fontSize: 13, color: c.mute),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => PhotoTile(
                item: photos[i],
                width: 56,
                height: 56,
                radius: 10,
                iconSize: 22,
                showDate: false,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SnapSearchBar(
            controller: _title,
            showIcon: false,
            hint: '앨범 이름',
            buttonIcon: 'check',
            onSubmit: () => s.createAlbumFromSuggestion(sug, _title.text),
          ),
          Row(
            children: [
              Expanded(
                child: SnapButton(
                  label: '괜찮아요',
                  ghost: true,
                  top: 12,
                  onTap: s.dismissAlbumSuggestion,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SnapButton(
                  label: '앨범 만들기',
                  top: 12,
                  onTap: () => s.createAlbumFromSuggestion(sug, _title.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ⑥ 사용성 테스트 모드
class Screen14UsabilityTest extends StatefulWidget {
  const Screen14UsabilityTest({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen14UsabilityTest> createState() => _Screen14UsabilityTestState();
}

class _Screen14UsabilityTestState extends State<Screen14UsabilityTest> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final vis = s.visiblePhotos;
    final current =
        (_selectedId != null && vis.any((d) => d.id == _selectedId))
            ? _selectedId!
            : (vis.isNotEmpty ? vis.first.id : 1);
    final logs = s.testLogs;
    final n = logs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '테스트 모드', onBack: () => s.go(12)),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: SnapSub(
            '진행자가 목표 사진을 보여 주면, 참가자가 기억나는 대로 검색해 찾습니다. 시간·질문 수·순위를 자동 기록해요.',
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: vis.any((d) => d.id == current) ? current : null,
              dropdownColor: c.card,
              style: TextStyle(fontSize: 15, color: c.ink),
              items: [
                for (final d in vis)
                  DropdownMenuItem(
                    value: d.id,
                    child: Text('#${d.id} ${d.place} · ${d.date}'),
                  ),
              ],
              onChanged: (v) => setState(() => _selectedId = v),
            ),
          ),
        ),
        SnapButton(
          label: '테스트 시작',
          onTap: vis.isEmpty ? null : () => s.startUsabilityTest(current),
        ),
        const SnapH3('결과'),
        if (n == 0)
          const SnapNote('아직 기록이 없어요', top: 0)
        else ...[
          StatBoxes(
            items: [
              ('${logs.where((x) => x.firstRank > 0).length}/$n', '첫 입력 Top-5'),
              ('${logs.where((x) => x.hit).length}/$n', '찾음'),
              (
                '${(logs.fold<int>(0, (p, e) => p + e.ms) / n / 1000).round()}초',
                '평균 시간',
              ),
            ],
          ),
          SnapGroup(
            separatorInset: 14,
            children: [
              for (final x in logs)
                SnapRow(
                  title: '#${x.id}',
                  subtitle: '${(x.ms / 1000).round()}초 · 질문 ${x.questions}회 · '
                      '첫 순위 ${x.firstRank > 0 ? x.firstRank : '밖'} · '
                      '${x.hit ? '✓ 찾음' : '✕ 못 찾음'}',
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// ⑤ 활용 모드 (성장 기록 · 레퍼런스 보드)
class Screen15Mode extends StatefulWidget {
  const Screen15Mode({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen15Mode> createState() => _Screen15ModeState();
}

class _Screen15ModeState extends State<Screen15Mode> {
  bool _growth = true;
  final _birth = TextEditingController(text: '2026-01-01');
  final _query = TextEditingController();
  DateTime _birthDate = DateTime(2026, 1, 1);

  @override
  void dispose() {
    _birth.dispose();
    _query.dispose();
    super.dispose();
  }

  String _age(String ym) {
    final y = int.parse(ym.substring(0, 4));
    final m = int.parse(ym.substring(5));
    final age = (y - _birthDate.year) * 12 + (m - _birthDate.month);
    return age >= 0 ? '생후 $age개월' : '출생 전';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final vis = s.visiblePhotos;
    final children = <Widget>[];

    if (_growth) {
      final groups = <String, List<PhotoItem>>{};
      for (final d in vis) {
        groups.putIfAbsent(d.date.substring(0, 7), () => []).add(d);
      }
      final keys = groups.keys.toList()..sort();
      children.addAll([
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 10),
          child: SnapSub('아이 생일을 입력하면 월령별로 모아 보여요'),
        ),
        SnapSearchBar(
          controller: _birth,
          showIcon: false,
          buttonText: '⟳',
          keyboardType: TextInputType.datetime,
          onSubmit: () => setState(() {
            _birthDate = DateTime.tryParse(_birth.text.trim()) ?? _birthDate;
          }),
        ),
        for (final k in keys) ...[
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 10),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${k.substring(0, 4)}.${k.substring(5)} '),
                  TextSpan(text: _age(k), style: TextStyle(color: c.pk)),
                ],
              ),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: c.ink,
              ),
            ),
          ),
          PhotoGrid(items: groups[k]!, onTap: (d) => s.openMemory(d.id)),
        ],
      ]);
    } else {
      final q = _query.text;
      final list = vis
          .where(
            (d) => [d.place, d.background, d.caption, ...d.food, d.weather]
                .join(' ')
                .contains(q),
          )
          .toList();
      children.addAll([
        const SizedBox(height: 10),
        SnapSearchBar(
          controller: _query,
          showIcon: false,
          hint: '공간·분위기 (예: 창, 조명, 실내)',
          buttonIcon: 'search',
          onChanged: (_) => setState(() {}),
          onSubmit: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        PhotoGrid(items: list, onTap: (d) => s.openMemory(d.id)),
        SnapNote('${list.length}장'),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '활용 모드', onBack: () => s.go(11)),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SnapChip(
                label: '성장 기록',
                icon: 'heart',
                selected: _growth,
                onTap: () => setState(() => _growth = true),
              ),
              SnapChip(
                label: '레퍼런스 보드',
                icon: 'home',
                selected: !_growth,
                onTap: () => setState(() => _growth = false),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

/// 앨범 상세 (Flutter 추가)
class Screen16AlbumDetail extends StatefulWidget {
  const Screen16AlbumDetail({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen16AlbumDetail> createState() => _Screen16AlbumDetailState();
}

class _Screen16AlbumDetailState extends State<Screen16AlbumDetail> {
  bool _confirmDelete = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final album = s.albumById(s.activeAlbumId);
    if (album == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapbackTopBar(title: '앨범', onBack: () => s.go(11)),
          const SnapEmpty(icon: 'stack', text: '앨범을 찾을 수 없어요'),
        ],
      );
    }
    final photos = s.albumPhotos(album);
    final made = DateTime.fromMillisecondsSinceEpoch(album.createdAtMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: album.title, onBack: () => s.go(11)),
        SnapSub(
          '사진 ${photos.length}장 · ${made.year}.${made.month}.${made.day} 검색에서 만듦',
        ),
        const SizedBox(height: 12),
        if (photos.isEmpty)
          const SnapEmpty(
            icon: 'image',
            text: '이 앨범의 사진이 삭제되었거나\n숨김 처리되었어요',
          )
        else
          PhotoGrid(items: photos, onTap: (d) => s.openMemory(d.id)),
        SnapButton(
          label: _confirmDelete ? '한 번 더 누르면 앨범이 삭제돼요' : '앨범 삭제',
          ghost: true,
          onTap: () {
            if (_confirmDelete) {
              s.deleteAlbum(album.id);
              s.go(11);
            } else {
              setState(() => _confirmDelete = true);
            }
          },
        ),
        const SnapNote('앨범을 지워도 사진과 분석 정보는 그대로 남아요'),
      ],
    );
  }
}
