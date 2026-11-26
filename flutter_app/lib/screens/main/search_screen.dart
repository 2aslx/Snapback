part of '../main_screens.dart';

// 기억으로 찾기(대화형 검색): 결과 · 질문 · 다른 후보 · 되돌리기

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
    // 다른 후보를 크게 보고 있었으면 홈이 아니라 바로 전에 보던 사진으로
    if (s.popPinnedResult()) {
      _scrollToTop();
      return;
    }
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

  /// 크게 보여 주는 사진 위치로 스크롤
  void _scrollToTop() {
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
    // '이전 단계로 되돌리기': 질문에 잘못 답했거나 남은 후보가 없을 때, 다시 검색하지 않고 직전 상태로
    Widget undoButton({bool big = false}) => big
        ? SnapButton(
            label: '이전 단계로 되돌리기',
            icon: 'history',
            ghost: true,
            onTap: s.undoLastAnswer,
          )
        : Pressable(
            onTap: s.undoLastAnswer,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SnapIcon('history', size: 15, color: c.pk),
                  const SizedBox(width: 4),
                  Text(
                    '이전 단계로 되돌리기',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.pk,
                    ),
                  ),
                ],
              ),
            ),
          );
    if (s.searchError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapNote(
            s.searchError!,
            icon: 'alert',
            color: const Color(0xFFC0392B),
          ),
          if (s.canUndoSearch) undoButton(big: true),
        ],
      );
    }
    if (s.searchResults.isEmpty) {
      if (s.searchBusy) return const SnapNote('AI가 기억을 더듬는 중…');
      // 질문에 답하며 후보를 제외하다 남은 후보가 없을 때
      if (s.searchHistory.length > 1) {
        return Column(
          children: [
            const SnapEmpty(
              icon: 'sparkle',
              text: '남은 후보 중에 맞는 사진이 없어요.\n방금 답을 되돌리거나, 기억나는 장면을 다시 적어 새로 검색해 보세요.',
            ),
            if (s.canUndoSearch) undoButton(big: true),
          ],
        );
      }
      return SnapEmpty(
        icon: 'sparkle',
        text: '날짜나 장소가 기억나지 않아도 괜찮아요.\n떠오르는 장면을 그대로 적어 보세요.',
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
    // 다른 후보: 일치도 60% 이상인 연관 사진을 모두 일치도 순으로 (지금 크게 보고 있는 사진은 제외)
    final rest = valid
        .where((x) => x.id != top.id)
        .where((x) => x.score >= SnapbackState.kMinScore)
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
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final m in answers)
                    SnapTag(icon: 'check', label: m.group(2)!),
                  if (s.canUndoSearch && !s.searchBusy) undoButton(),
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
          // 버튼 ↔ 질문 ↔ '더 구분할 질문이 없어요' 가 바뀔 때 부드럽게
          SnapSwap(
            child: !s.questionShown
                ? KeyedSubtree(
                    key: const ValueKey('buttons'),
                    child: Row(
                      children: [
                        Expanded(
                          child: SnapButton(
                            label: '맞아요',
                            icon: 'check',
                            onTap: s.searchBusy
                                ? null
                                : () => s.openMemory(top.id),
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
                    ),
                  )
                : s.activeQuestion != null
                ? KeyedSubtree(
                    key: const ValueKey('question'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        SnapBubble(
                          child: Text(keepWords(s.activeQuestion!.text)),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final o in s.activeQuestion!.options)
                              SnapChip(
                                label: o,
                                onTap: () => s.answerFollowUp(o),
                              ),
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
                      ],
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey('done'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                    ),
                  ),
          ),
          // 다른 후보: 3열 바둑판, 일치도 순 (일치도는 표시하지 않음)
          SnapReveal(
            visible: rest.isNotEmpty,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SnapH3('다른 후보'),
                PhotoGrid(
                  items: [for (final x in rest) byId[x.id]!],
                  // 바로 상세로 가지 않고 위로 크게 올려 '맞아요'로 확인 (그래야 기억 탭에 저장됨)
                  onTap: (d) {
                    s.pinResult(d.id);
                    _scrollToTop();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
