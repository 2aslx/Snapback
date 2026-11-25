import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../models/photo_album.dart';
import '../models/photo_item.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/pin_pad.dart';
import '../widgets/snap_runner.dart';
import '../widgets/map_popup.dart';
import '../widgets/share_photo.dart';
import 'record_screens.dart';

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
    final picked = await showDialog<String>(
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
        if (s.analysisFailed > 0 && !s.analysisRunning)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Pressable(
              onTap: () => s.go(4),
              child: SnapWarn(
                '사진 ${s.analysisFailed}장을 분석하지 못했어요. 눌러서 이유를 확인해 보세요.',
              ),
            ),
          ),
        // 사진을 고를 때 건너뛴 사진 안내 (이미 분석한 사진 등)
        if (s.pickNotice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SnapNote(s.pickNotice, icon: 'alert', top: 0),
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
                if (_editing)
                  Padding(
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
                if (_editing)
                  SnapButton(
                    label: _sel.isEmpty
                        ? '지울 사진을 골라 주세요'
                        : '선택한 사진 ${_sel.length}장 지우기',
                    onTap: _sel.isEmpty ? null : () => _deleteSelected(s),
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
    ('bowl', '면'),
    ('cake', '디저트'),
    ('cup', '커피'),
    ('glass', '술'),
    ('bowl', '면'),
    ('cake', '디저트'),
    ('cup', '커피'),
    ('glass', '술'),
    ('bread', '디저트'),
    ('bowl', '면'),
    ('cake', '디저트'),
    ('cup', '커피'),
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
        SnapButton(label: '이 사진의 기억 보기', ghost: true, onTap: () => s.go(10)),
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
              onTap: () => s.go(10),
            ),
            const SnapRow(
              leading: IconBadge('bread', gradIndex: 2),
              title: '합정 베이커리 · 2026.07.02',
              subtitle: '✓ 디저트 ✓ 창가 · 비 정보 없음',
            ),
            const SnapRow(
              leading: IconBadge('bowl', gradIndex: 4),
              title: '연남동 카페 · 2025.06.21',
              subtitle: '✓ 디저트 · 위치 확인 불가',
            ),
            const SnapRow(
              leading: IconBadge('cup', gradIndex: 1),
              title: '서촌 찻집 · 2025.04.09',
              subtitle: '✓ 창가 · 디저트 낮은 확신',
            ),
          ],
        ),
        const SnapNote('단서에 맞은 항목을 표시해요 · 눌러서 자세히'),
      ],
    );
  }
}

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
    final placeText = join([item.place, s.placeNameFor(item) ?? '']);
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
          ('pin', '촬영 장소', placeText.isNotEmpty ? placeText : '위치 정보 있음'),
      ] else ...[
        ('calendar', '촬영 날짜·시간', join([item.date, item.time])),
        // 장소 유형 + 시·구·동 주소 (좌표는 표시하지 않음)
        (
          'pin',
          '촬영 장소',
          // GPS 만 있고 장소 이름·주소가 아직 없으면 지도로 볼 수 있게 줄은 남긴다
          placeText.isNotEmpty
              ? placeText
              : (item.gps != null ? '위치 정보 있음' : ''),
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
                if (_infoOpen) ...[
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

/// ⑤′ 기억 탭 — 지금까지 검색으로 찾은 사진들을 갤러리로. 누르면 사진 상세(관련된 추억 등).
class Screen19Memories extends StatefulWidget {
  const Screen19Memories({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen19Memories> createState() => _Screen19MemoriesState();
}

class _Screen19MemoriesState extends State<Screen19Memories> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final photos = s.foundPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LargeTitle(
          title: '기억',
          actions: [
            if (photos.isNotEmpty)
              Pressable(
                onTap: () => setState(() => _editing = !_editing),
                child: Text(
                  _editing ? '완료' : '편집',
                  style: TextStyle(fontSize: 17, color: c.pk),
                ),
              ),
          ],
        ),
        // 기록으로 남긴 사진은 하단 '기록' 탭으로 옮김
        if (photos.isEmpty) ...[
          const SnapEmpty(
            icon: 'heart',
            text: '아직 찾은 사진이 없어요.\n사진 탭에서 기억나는 장면을 말해 보세요.',
          ),
          SnapButton(label: '기억으로 찾기', icon: 'search', onTap: s.openNewSearch),
        ] else ...[
          SnapSub(
            _editing
                ? '기록에서 뺄 사진을 누르세요 · 사진은 지워지지 않아요'
                : '검색으로 찾은 사진 ${photos.length}장 · 최근에 찾은 순',
          ),
          const SizedBox(height: 12),
          if (_editing)
            Bleed(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: photos.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => s.forgetFound(photos[i].id),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: 0.7,
                        child: PhotoTile(
                          item: photos[i],
                          radius: 16,
                          showDate: false,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: c.pri,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const SnapIcon(
                            'close',
                            size: 13,
                            color: Colors.white,
                            strokeWidth: 2.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            PhotoGrid(items: photos, onTap: (d) => s.openMemory(d.id)),
        ],
      ],
    );
  }
}

/// '2026-10-15' → '10월 15일'
String _md(String date) {
  final p = date.split('-');
  if (p.length != 3) return date;
  return '${int.tryParse(p[1]) ?? p[1]}월 ${int.tryParse(p[2]) ?? p[2]}일';
}

/// 관련된 추억 앨범 — 사진 상세에서 연 가상 앨범(그날의 사진 / 비슷한 분위기)의 전체 사진.
/// 갤러리에 실제 앨범을 만들지 않고 앱 안에서만 묶어 보여준다.
class Screen18RelatedAlbum extends StatelessWidget {
  const Screen18RelatedAlbum({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final sameDay = s.relatedAlbumKind == 0;
    final title = sameDay ? '그날의 사진' : '비슷한 분위기';
    void back() {
      if (!s.backFromRelated()) s.go(10);
    }

    final base = s.db.where((x) => x.id == s.relatedBaseId).firstOrNull;
    if (base == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapbackTopBar(title: title, onBack: back),
          const SnapEmpty(icon: 'image', text: '사진을 찾을 수 없어요'),
        ],
      );
    }
    final rel = s.relatedFor(base);
    var photos = sameDay ? rel.sameDay : rel.similarMood;
    if (sameDay) {
      // 그날의 사진은 찍은 순서대로
      int key(PhotoItem x) => x.takenAtMs ?? x.id;
      photos = [...photos]..sort((a, b) => key(a).compareTo(key(b)));
    }
    final where = base.place.isEmpty || base.place == '알 수 없음'
        ? ''
        : ' · ${base.place}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: title,
          onBack: back,
          trailing: Text('${photos.length}장'),
        ),
        SnapSub(
          sameDay
              ? '${base.date}$where에서 함께 찍은 사진 ${photos.length}장'
              : '이 사진과 분위기가 비슷한 사진 ${photos.length}장',
        ),
        const SizedBox(height: 12),
        if (photos.isEmpty)
          const SnapEmpty(icon: 'image', text: '이 앨범에 남은 사진이 없어요')
        else
          PhotoGrid(items: photos, onTap: (d) => s.openFromRelatedAlbum(d.id)),
        if (photos.isNotEmpty)
          SnapButton(
            label: '이 사진들로 앨범 만들기',
            icon: 'stack',
            top: 18,
            onTap: () => s.draftAlbumFromRelated(
              sameDay
                  ? '${_md(base.date)} ${s.memoryTitle(base)}'
                  : '${s.memoryTitle(base)}의 분위기',
              base,
              photos,
            ),
          ),
        const SnapNote('사진 앱에 앨범을 만들지 않고, Snapback 안에서만 묶어 보여줘요'),
      ],
    );
  }
}

/// ⑥ 앨범 — 흩어진 순간 모으기(AI 앨범) + 카테고리별 내 앨범
class Screen11Albums extends StatefulWidget {
  const Screen11Albums({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen11Albums> createState() => _Screen11AlbumsState();
}

class _Screen11AlbumsState extends State<Screen11Albums> {
  final _req = TextEditingController();
  static const _examples = ['올여름 친구들과 함께했던 순간들', '저장해 둔 네일 디자인 사진만 모아줘'];
  bool _confirmRemove = false;

  @override
  void dispose() {
    _req.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final shown = s.filteredAlbums;
    final filterCat = s.categoryById(s.albumFilter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LargeTitle(title: '앨범'),
        // AI 대화형 앨범 만들기
        Container(
          margin: const EdgeInsets.only(top: 2),
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
                  SnapIcon('sparkle', size: 19.5, color: c.pk),
                  const SizedBox(width: 6),
                  Text(
                    '흩어진 순간 모으기',
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
                '흩어진 사진들을 의미 있는 하나의 앨범으로.',
                style: TextStyle(fontSize: 13, color: c.mute),
              ),
              const SizedBox(height: 10),
              SnapSearchBar(
                controller: _req,
                showIcon: false,
                hint: '어떤 순간을 모아볼까요?',
                busy: s.albumBusy,
                onSubmit: () => s.composeAlbum(_req.text),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // 내 사진 DB 로 만든 제안 (없으면 기본 예시)
                  for (final e
                      in s.albumSuggestions.isNotEmpty
                          ? s.albumSuggestions
                          : _examples)
                    SnapChip(
                      label: e,
                      icon: s.albumSuggestions.isNotEmpty ? 'sparkle' : null,
                      onTap: () {
                        _req.text = e;
                        s.composeAlbum(e);
                      },
                    ),
                ],
              ),
              if (s.albumBusy) const SnapNote('어울리는 사진을 모으는 중…'),
              if (s.albumError != null && !s.albumBusy)
                SnapNote(
                  s.albumError!,
                  icon: 'alert',
                  color: const Color(0xFFC0392B),
                ),
            ],
          ),
        ),
        const SnapH3('내 앨범'),
        CategoryChips(
          state: s,
          selected: s.albumFilter,
          includeAll: true,
          onSelect: (id) {
            _confirmRemove = false;
            s.setAlbumFilter(id);
          },
        ),
        if (filterCat != null && !filterCat.builtIn)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Pressable(
              onTap: () {
                if (_confirmRemove) {
                  _confirmRemove = false;
                  s.removeCategory(filterCat.id);
                } else {
                  setState(() => _confirmRemove = true);
                }
              },
              child: Text(
                _confirmRemove
                    ? '한 번 더 누르면 카테고리가 삭제돼요 (앨범은 남아요)'
                    : "'${filterCat.label}' 카테고리 삭제",
                style: TextStyle(fontSize: 13, color: c.mute),
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (s.albums.isEmpty)
          const SnapEmpty(
            icon: 'stack',
            text: '아직 앨범이 없어요.\n위에서 모아 보고 싶은 순간을 적어 보세요.',
          )
        else if (shown.isEmpty)
          SnapEmpty(
            icon: 'stack',
            text:
                "'${filterCat?.label ?? ''}' 카테고리에 앨범이 없어요.\n앨범을 열어 카테고리를 바꿀 수 있어요.",
          )
        else
          AlbumCardGrid(
            children: [
              for (final a in shown)
                () {
                  final photos = s.albumPhotos(a);
                  return AlbumCard(
                    locked: a.locked,
                    cover: photos.isNotEmpty
                        ? photos.first
                        : PhotoItem(id: a.id + 4, date: '', place: ''),
                    title: a.title,
                    count: photos.length,
                    badge: s.albumFilter == null
                        ? s.categoryById(a.category)?.label
                        : null,
                    onTap: () => s.openAlbum(a.id),
                  );
                }(),
            ],
          ),
      ],
    );
  }
}

/// 앨범 카테고리 캡슐 버튼 줄 (가로 스크롤) + 맨 끝 '＋ 추가'.
/// includeAll: 맨 앞에 '전체'(null) 포함 — 앨범 탭 필터용.
/// includeAll 이 false 면 선택한 칩을 다시 누를 때 '분류 없음'(null)으로 돌아간다.
class CategoryChips extends StatefulWidget {
  const CategoryChips({
    super.key,
    required this.state,
    required this.selected,
    required this.onSelect,
    this.includeAll = false,
    this.aiId,
  });

  final SnapbackState state;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final bool includeAll;

  /// AI 가 추천한 카테고리 id — 칩에 반짝이 아이콘 표시
  final String? aiId;

  @override
  State<CategoryChips> createState() => _CategoryChipsState();
}

class _CategoryChipsState extends State<CategoryChips> {
  bool _adding = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final c = widget.state.addCategory(_name.text);
    _name.clear();
    setState(() => _adding = false);
    if (c != null) widget.onSelect(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Bleed(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (widget.includeAll)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SnapChip(
                      label: '전체',
                      accent: true,
                      selected: sel == null,
                      onTap: () => widget.onSelect(null),
                    ),
                  ),
                for (final cat in widget.state.allCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SnapChip(
                      label: cat.label,
                      icon: cat.id == widget.aiId ? 'sparkle' : null,
                      accent: true,
                      selected: sel == cat.id,
                      onTap: () => widget.onSelect(
                        !widget.includeAll && sel == cat.id ? null : cat.id,
                      ),
                    ),
                  ),
                SnapChip(
                  label: '추가',
                  icon: 'plus',
                  dashed: true,
                  onTap: () => setState(() => _adding = !_adding),
                ),
              ],
            ),
          ),
        ),
        if (_adding)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SnapSearchBar(
              controller: _name,
              showIcon: false,
              hint: '새 카테고리 이름 (예: 반려동물)',
              buttonIcon: 'check',
              onSubmit: _submit,
            ),
          ),
      ],
    );
  }
}

/// 앨범 미리보기 — AI가 고른 사진 확인 · 빼고 싶은 사진 선택/제외 · 이름 수정 · 최종 생성
class Screen17AlbumPreview extends StatefulWidget {
  const Screen17AlbumPreview({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen17AlbumPreview> createState() => _Screen17AlbumPreviewState();
}

class _Screen17AlbumPreviewState extends State<Screen17AlbumPreview> {
  late final _title = TextEditingController(
    text: widget.state.albumDraft?.title ?? '',
  );

  /// 처음 받은 AI 추천 카테고리 (사용자가 바꿔도 표시용으로 유지)
  late final String? _aiCategory = widget.state.albumDraft?.category;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final draft = s.albumDraft;
    if (draft == null) {
      return Column(
        children: [
          SnapbackTopBar(
            title: '앨범 미리보기',
            onBack: () => s.go(s.albumDraftReturn),
          ),
          const SnapEmpty(icon: 'stack', text: '미리볼 앨범이 없어요'),
        ],
      );
    }
    final byId = {for (final d in s.db) d.id: d};
    final photos = [
      for (final id in draft.photoIds)
        if (byId[id] != null) byId[id]!,
    ];
    final sel = s.albumDraftSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '앨범 미리보기',
          onBack: () => s.go(s.albumDraftReturn),
          trailing: Text('${photos.length}장'),
        ),
        const SnapH3('앨범 이름', small: true),
        SnapSearchBar(
          controller: _title,
          showIcon: false,
          hint: '앨범 이름',
          buttonIcon: 'check',
          onSubmit: () => FocusScope.of(context).unfocus(),
        ),
        const SnapH3('카테고리', small: true),
        CategoryChips(
          state: s,
          selected: draft.category,
          aiId: _aiCategory,
          onSelect: s.setDraftCategory,
        ),
        if (_aiCategory != null)
          SnapNote(
            "AI 추천: '${s.categoryById(_aiCategory)?.label ?? ''}' · 눌러서 바꿀 수 있어요",
            top: 8,
          ),
        // 기본은 모두 선택. 빼고 싶은 사진을 눌러 선택 해제
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SnapSub(
                  sel.isEmpty
                      ? 'AI가 고른 사진 ${photos.length}장이 모두 선택돼 있어요. 빼고 싶은 사진을 눌러 선택을 해제하세요.'
                      : '${photos.length}장 중 ${photos.length - sel.length}장 선택됨',
                ),
              ),
              const SizedBox(width: 10),
              Pressable(
                onTap: () => s.setAllDraftPhotos(sel.isNotEmpty),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    sel.isEmpty ? '전체 해제' : '전체 선택',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.pk,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: photos.length,
          itemBuilder: (_, i) {
            final d = photos[i];
            final on = !sel.contains(d.id); // 선택됨 = 앨범에 들어감
            return GestureDetector(
              onTap: () => s.toggleDraftPhoto(d.id),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 선택 해제된 사진은 흐리게
                  Opacity(
                    opacity: on ? 1 : 0.4,
                    child: PhotoTile(item: d),
                  ),
                  if (on)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: c.pri, width: 3),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 5,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: on ? c.pri : const Color(0x99FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: on
                          ? const SnapIcon(
                              'check',
                              size: 12,
                              color: Colors.white,
                              strokeWidth: 2.6,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        SnapButton(
          label: photos.length - sel.length <= 0
              ? '앨범에 넣을 사진을 골라 주세요'
              : '앨범 만들기 (${photos.length - sel.length}장)',
          onTap: photos.length - sel.length <= 0
              ? null
              : () => s.confirmAlbumDraft(_title.text),
        ),
        const SnapNote('만들기 전까지는 저장되지 않아요'),
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
        _RelabelSection(state: s),
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
        if (s.aiStatusText.isNotEmpty) SnapNote(s.aiStatusText),
        // OpenStreetMap 이용 조건: 출처 표시
        const SnapNote('촬영 장소 주소: © OpenStreetMap 기여자'),
        // 앱 초기화 (확인 팝업)
        const SnapH3('초기화', small: true),
        Pressable(
          onTap: () async {
            final ok = await showSnapConfirm(
              context,
              title: '앱을 초기화할까요?',
              message: '분석한 사진 정보, 앨범, 기록, 찾은 사진이 모두 지워지고\n처음 화면으로 돌아가요.\n사진 앱의 원본 사진은 지워지지 않아요.',
              confirmLabel: '초기화',
            );
            if (ok) await s.resetAll();
          },
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 50),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD93A2B)),
            ),
            child: const Text(
              '앱 초기화',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFFD93A2B),
              ),
            ),
          ),
        ),
        const SnapNote('모든 분석 정보·앨범·기록을 지우고 처음부터 다시 시작해요'),
      ],
    );
  }
}

/// 설정 > 사진 다시 분석하기: 이미 분석한 사진의 설명을 새로 만든다 (두 번 눌러 시작)
class _RelabelSection extends StatefulWidget {
  const _RelabelSection({required this.state});
  final SnapbackState state;

  @override
  State<_RelabelSection> createState() => _RelabelSectionState();
}

class _RelabelSectionState extends State<_RelabelSection> {
  bool _confirm = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final n = s.relabelTargets.length;
    final busy = s.analysisRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapGroup(
          top: 12,
          children: [
            SnapRow(
              leading: const IconBadge('sparkle'),
              title: s.relabelRunning
                  ? '다시 분석하는 중 · ${s.relabelDone} / ${s.relabelTotal}장'
                  : _confirm
                  ? '한 번 더 누르면 $n장을 다시 분석해요'
                  : '사진 다시 분석하기',
              subtitle: s.relabelRunning
                  ? '앱을 쓰는 동안 계속 진행돼요'
                  : '분석한 사진 $n장의 설명을 최신 AI로 새로 만들어요',
              trailing: s.relabelRunning
                  ? Pressable(
                      onTap: s.cancelRelabel,
                      child: Text(
                        '중지',
                        style: TextStyle(fontSize: 15, color: c.pk),
                      ),
                    )
                  : const Chevron(),
              onTap: s.relabelRunning || n == 0 || busy
                  ? null
                  : () {
                      if (_confirm) {
                        _confirm = false;
                        s.relabelAll();
                      } else {
                        setState(() => _confirm = true);
                      }
                    },
            ),
          ],
        ),
        if (s.relabelRunning)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
            child: SnapBar(
              value: s.relabelTotal == 0 ? 0 : s.relabelDone / s.relabelTotal,
              background: c.fill,
              color: c.pri,
            ),
          ),
        if (s.relabelFinished && !s.relabelRunning)
          SnapNote(
            [
              '다시 분석 완료: ${s.relabelDone - s.relabelSkipped - s.relabelFailed}장',
              if (s.relabelSkipped > 0) '원본을 찾을 수 없어 건너뜀 ${s.relabelSkipped}장',
              if (s.relabelFailed > 0) '실패 ${s.relabelFailed}장',
            ].join(' · '),
          ),
        if (busy && !s.relabelRunning)
          const SnapNote('사진 분석이 끝난 뒤에 다시 분석할 수 있어요'),
        if (n == 0) const SnapNote('아직 분석한 사진이 없어요'),
        if (!s.relabelRunning && !s.relabelFinished && n > 0 && !busy)
          const SnapNote('사진·앨범·기록은 그대로 두고 설명만 바꿔요 · 기록과 앨범도 그대로예요'),
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
  /// AI 질문에 보기 대신 직접 적는 답
  final _answer = TextEditingController();

  /// 크게 보여 주는 사진 위치 (다른 후보를 누르면 여기로 스크롤)
  final _topResultKey = GlobalKey();

  void _sendAnswer() {
    final t = _answer.text.trim();
    if (t.isEmpty || widget.state.searchBusy) return;
    _answer.clear();
    FocusScope.of(context).unfocus();
    widget.state.answerFollowUp(t.length > 200 ? t.substring(0, 200) : t);
  }

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
    _answer.dispose();
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
        _revealed(SnapbackTopBar(title: '기억으로 찾기', onBack: _back)),
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
    if (s.searchError != null) {
      return SnapNote(
        s.searchError!,
        icon: 'alert',
        color: const Color(0xFFC0392B),
      );
    }
    if (s.searchResults.isEmpty) {
      if (s.searchBusy) return const SnapNote('AI가 기억을 더듬는 중…');
      // 질문에 답하며 후보를 제외하다 남은 후보가 없을 때
      if (s.searchHistory.length > 1) {
        return const SnapEmpty(
          icon: 'sparkle',
          text: '남은 후보 중에 맞는 사진이 없어요.\n기억나는 장면을 다시 적어 새로 검색해 보세요.',
        );
      }
      return SnapEmpty(
        icon: 'sparkle',
        text: s.testSession != null
            ? '테스트 중 — 목표 사진을 떠올려 기억나는 대로 입력하고,\n찾으면 그 사진을 누르세요'
            : '날짜나 장소가 기억나지 않아도 괜찮아요.\n떠오르는 장면을 그대로 적어 보세요.',
      );
    }
    final valid = s.searchResults.where((x) => byId.containsKey(x.id)).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (valid.isEmpty) return const SnapNote('찾은 사진이 없어요');
    String clues(SearchRankedItem x) =>
        '${x.matched.isNotEmpty ? '✓ ${x.matched.join(' ✓ ')}' : ''}'
        '${x.missing.isNotEmpty ? ' · ? ${x.missing.join(', ')}' : ''}';
    // 다른 후보를 눌러 크게 올려 둔 사진이 있으면 그것을, 아니면 1순위를 크게
    final top = valid.firstWhere(
      (x) => x.id == s.pinnedResultId,
      orElse: () => valid.first,
    );
    final pinned = top.id != valid.first.id;
    final topPhoto = byId[top.id]!;
    // 다른 후보: 1순위 일치도가 85% 이상이면 없음(그 사진 하나만).
    // 85% 미만이면 일치도 60~85% 사진을 일치도 순으로 (지금 크게 보고 있는 사진은 제외)
    final sure = valid.first.score >= SnapbackState.kSureScore;
    final rest = sure
        ? <SearchRankedItem>[]
        : valid
              .where((x) => x.id != top.id)
              .where(
                (x) =>
                    x.score >= SnapbackState.kMinScore &&
                    x.score < SnapbackState.kSureScore,
              )
              .toList();
    // 답변 기록 (Q: … / A: …) — 지금까지 더한 기억 단서
    final answers = s.searchHistory
        .skip(1)
        .map((h) => RegExp(r'^Q:\s*(.+?)\s*/\s*A:\s*(.+)$').firstMatch(h))
        .whereType<RegExpMatch>()
        .toList();

    return AnimatedOpacity(
      opacity: s.searchBusy ? 0.45 : 1,
      duration: const Duration(milliseconds: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (answers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                children: [
                  for (final m in answers)
                    SnapTag(icon: 'check', label: m.group(2)!),
                ],
              ),
            ),
          // 다른 후보를 올려 보고 있으면 안내 + 1순위로 돌아가기
          if (pinned)
            Padding(
              key: _topResultKey,
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '다른 후보를 크게 보고 있어요 · 맞으면 "맞아요"를 눌러 주세요',
                      style: TextStyle(fontSize: 13, color: c.mute),
                    ),
                  ),
                  Pressable(
                    onTap: () => s.pinResult(null),
                    child: Text(
                      '1순위 보기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.pk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 가장 가능성이 높은 사진(또는 고른 후보) — 크게. 누르면 '맞아요'와 같음
          GestureDetector(
            key: pinned ? null : _topResultKey,
            onTap: () => s.openMemory(top.id),
            // 가로 폭에 맞추고 높이는 사진 비율대로 → 사진 전체가 크게
            child: FullWidthPhoto(
              item: topPhoto,
              radius: 13,
              fallbackHeight: 260,
            ),
          ),
          const SizedBox(height: 10),
          // 일치 확률은 보여 주지 않음 (내부 기준에만 사용)
          Text(
            '${topPhoto.place} · ${topPhoto.date}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: c.ink,
            ),
          ),
          if (clues(top).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                clues(top),
                style: TextStyle(fontSize: 13, color: c.mute),
              ),
            ),
          // [맞아요] / [질문 한 번 더하기]
          if (!s.questionShown)
            Row(
              children: [
                Expanded(
                  child: SnapButton(
                    label: '맞아요',
                    icon: 'check',
                    onTap: s.searchBusy ? null : () => s.openMemory(top.id),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SnapButton(
                    label: s.searchBusy ? '질문 만드는 중…' : '질문 한 번 더하기',
                    icon: s.searchBusy ? null : 'chat',
                    ghost: true,
                    onTap: s.searchBusy ? null : s.askMore,
                  ),
                ),
              ],
            )
          else if (s.activeQuestion != null) ...[
            const SizedBox(height: 8),
            SnapBubble(child: Text(keepWords(s.activeQuestion!.text))),
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
            // 보기에 맞는 답이 없을 때: 직접 입력 (답 또는 새로 떠오른 단서)
            const SizedBox(height: 10),
            SnapSearchBar(
              controller: _answer,
              showIcon: false,
              hint: '직접 입력하기 (예: 창가 자리였어요)',
              busy: s.searchBusy,
              onSubmit: _sendAnswer,
            ),
          ] else ...[
            SnapNote(
              rest.isEmpty
                  ? '더 구분할 질문이 없어요.'
                  : '더 구분할 질문이 없어요. 아래 다른 후보도 확인해 보세요.',
            ),
            SnapButton(
              label: '맞아요',
              icon: 'check',
              onTap: () => s.openMemory(top.id),
            ),
          ],
          // 다른 후보: 3열 바둑판, 일치도 순 (일치도는 표시하지 않음)
          if (rest.isNotEmpty) ...[
            const SnapH3('다른 후보'),
            PhotoGrid(
              items: [for (final x in rest) byId[x.id]!],
              // 바로 상세로 가지 않고 위로 크게 올려 '맞아요'로 확인 (그래야 기억 탭에 저장됨)
              onTap: (d) {
                s.pinResult(d.id);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final ctx = _topResultKey.currentContext;
                  if (ctx != null) {
                    Scrollable.ensureVisible(
                      ctx,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: 0.1,
                    );
                  }
                });
              },
            ),
          ],
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
    final current = (_selectedId != null && vis.any((d) => d.id == _selectedId))
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
                  subtitle:
                      '${(x.ms / 1000).round()}초 · 질문 ${x.questions}회 · '
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
                  TextSpan(
                    text: _age(k),
                    style: TextStyle(color: c.pk),
                  ),
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
            (d) => [
              d.place,
              d.background,
              d.caption,
              ...d.food,
              d.weather,
            ].join(' ').contains(q),
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
  bool _editing = false;
  final _name = TextEditingController();
  final _nameFocus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _startEdit(String title) {
    _name.text = title;
    _name.selection = TextSelection(baseOffset: 0, extentOffset: title.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _nameFocus.requestFocus(),
    );
  }

  void _finishEdit(int albumId) {
    if (!_editing) return;
    widget.state.renameAlbum(albumId, _name.text);
    setState(() => _editing = false);
  }

  /// 삭제 확인 팝업
  Future<void> _toggleLock(PhotoAlbum album) async {
    final s = widget.state;
    if (album.locked) {
      final ok = await showSnapConfirm(
        context,
        title: '잠금을 풀까요?',
        message: "'${album.title}' 앨범을 비밀번호 없이\n볼 수 있게 돼요.",
        confirmLabel: '잠금 풀기',
        destructive: false,
      );
      if (ok) s.removeAlbumLock(album.id);
      return;
    }
    final pin = await showPinSetup(context);
    if (pin != null) s.lockAlbum(album.id, pin);
  }

  Future<void> _confirmForgot(int albumId, String title) async {
    final ok = await showSnapConfirm(
      context,
      title: '비밀번호를 잊으셨나요?',
      message: '비밀번호는 찾을 수 없어요.\n앨범을 지우면 다시 만들 수 있고,\n사진과 분석 정보는 그대로 남아요.',
      confirmLabel: '앨범 삭제',
    );
    if (ok) {
      widget.state.deleteAlbum(albumId);
      widget.state.go(11);
    }
  }

  Future<void> _confirmDelete(int albumId, String title) async {
    final ok = await showSnapConfirm(
      context,
      title: '앨범을 삭제할까요?',
      message: "'$title' 앨범만 지워지고,\n사진과 분석 정보는 그대로 남아요.",
    );
    if (ok) {
      widget.state.deleteAlbum(albumId);
      widget.state.go(11);
    }
  }

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
    // 잠긴 앨범: 비밀번호 4자리를 맞게 입력해야 사진이 보인다
    if (s.isAlbumHidden(album)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapbackTopBar(title: album.title, onBack: () => s.go(11)),
          const SizedBox(height: 12),
          PinPad(
            title: '잠긴 앨범',
            message: '비밀번호 4자리를 입력하면 사진을 볼 수 있어요.',
            onComplete: (pin) async => s.unlockAlbum(album.id, pin),
            footer: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Pressable(
                onTap: () => _confirmForgot(album.id, album.title),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '비밀번호를 잊었어요',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.sc.mute,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final photos = s.albumPhotos(album);
    final made = DateTime.fromMillisecondsSinceEpoch(album.createdAtMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 제목을 누르면 그 자리에서 앨범 이름 편집
        SnapbackTopBar(
          title: album.title,
          onBack: () {
            _finishEdit(album.id);
            s.go(11);
          },
          titleWidget: _editing
              ? IntrinsicWidth(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: context.sc.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.sc.pri, width: 1.2),
                    ),
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      textAlign: TextAlign.center,
                      maxLength: 30,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _finishEdit(album.id),
                      onTapOutside: (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        _finishEdit(album.id);
                      },
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        color: context.sc.ink,
                      ),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        counterText: '',
                      ),
                    ),
                  ),
                )
              : Pressable(
                  onTap: () => _startEdit(album.title),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                            color: context.sc.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SnapIcon('pencil', size: 15, color: context.sc.mute),
                    ],
                  ),
                ),
        ),
        SnapSub(
          '사진 ${photos.length}장 · ${made.year}.${made.month}.${made.day} 만듦',
        ),
        const SizedBox(height: 12),
        CategoryChips(
          state: s,
          selected: album.category,
          onSelect: (id) => s.setAlbumCategory(album.id, id),
        ),
        SnapNote(
          album.category == null
              ? '카테고리를 고르면 앨범 탭에서 모아 볼 수 있어요'
              : '고른 카테고리를 한 번 더 누르면 분류가 해제돼요',
          top: 8,
        ),
        const SizedBox(height: 14),
        if (photos.isEmpty)
          const SnapEmpty(icon: 'image', text: '이 앨범의 사진이 삭제되었거나\n숨김 처리되었어요')
        else
          PhotoGrid(items: photos, onTap: (d) => s.openMemory(d.id)),
        SnapButton(
          label: album.locked ? '잠금 풀기' : '앨범 잠그기',
          icon: 'lock',
          ghost: true,
          onTap: () => _toggleLock(album),
        ),
        SnapNote(
          album.locked
              ? '앨범 목록에서는 사진이 가려지고, 열 때마다 비밀번호를 물어요'
              : '잠그면 앨범 목록에서 사진이 가려지고, 비밀번호 4자리로만 열 수 있어요',
        ),
        SnapButton(
          label: '앨범 삭제',
          ghost: true,
          onTap: () => _confirmDelete(album.id, album.title),
        ),
        const SnapNote('앨범을 지워도 사진과 분석 정보는 그대로 남아요'),
      ],
    );
  }
}
