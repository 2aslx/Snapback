import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import 'screens/main_screens.dart';
import 'screens/onboarding_screens.dart';
import 'screens/record_screens.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/common_widgets.dart';
import 'widgets/snap_runner.dart';

void main() {
  runApp(const SnapbackApp());
}

class SnapbackApp extends StatefulWidget {
  const SnapbackApp({super.key});

  @override
  State<SnapbackApp> createState() => _SnapbackAppState();
}

class _SnapbackAppState extends State<SnapbackApp> {
  final SnapbackState _state = SnapbackState();

  @override
  void initState() {
    super.initState();
    // 웹 개발용: ?screen=N 으로 특정 화면부터 열기 (디자인 비교·QA)
    final n = kIsWeb
        ? int.tryParse(Uri.base.queryParameters['screen'] ?? '')
        : null;
    if (n != null) _state.go(n);
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snapback',
      debugShowCheckedModeBanner: false,
      theme: buildSnapbackTheme(Brightness.light),
      darkTheme: buildSnapbackTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: AnimatedBuilder(
        animation: _state,
        builder: (context, _) => _SnapbackShell(state: _state),
      ),
    );
  }
}

class _SnapbackShell extends StatelessWidget {
  const _SnapbackShell({required this.state});
  final SnapbackState state;

  // .scr.tb — 하단 탭바가 보이는 화면
  static const Set<int> _tabScreens = {5, 6, 7, 10, 11, 13, 14, 15, 16, 18, 19, 21};

  Widget _buildScreen() {
    switch (state.screen) {
      case 0:
        return Screen0Welcome(state: state);
      case 1:
        return Screen1Scope(state: state);
      case 2:
        return Screen2PickPhotos(state: state);
      case 3:
        return Screen3Order(state: state);
      case 4:
        return Screen4Progress(state: state);
      case 5:
        return Screen5Home(state: state);
      case 6:
        return Screen6FoodCategory(state: state);
      case 7:
        return Screen7PhotoInfo(state: state);
      case 8:
        return Screen8PrototypeChat(state: state);
      case 9:
        return Screen9PrototypeResults(state: state);
      case 10:
        return Screen10MemoryDetail(state: state);
      case 11:
        return Screen11Albums(state: state);
      case 12:
        return Screen12Settings(state: state);
      case 13:
        return Screen13Search(state: state);
      case 14:
        return Screen14UsabilityTest(state: state);
      case 15:
        return Screen15Mode(state: state);
      case 16:
        return Screen16AlbumDetail(state: state);
      case 17:
        return Screen17AlbumPreview(state: state);
      case 18:
        return Screen18RelatedAlbum(state: state);
      case 19:
        return Screen19Memories(state: state);
      case 20:
        return Screen20RecordEdit(state: state);
      case 21:
        return Screen21RecordView(state: state);
      default:
        return Screen0Welcome(state: state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    // 저장된 설정을 읽기 전에는 배경만 (초기 설정을 마친 사람에게 시작 안내가 깜빡이지 않게)
    if (!state.ready) return Scaffold(backgroundColor: c.bg);
    final showTabs = _tabScreens.contains(state.screen);
    final reduce = MediaQuery.of(context).disableAnimations;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ColoredBox(
            color: c.bg,
            child: _MiniHost(
              state: state,
              builder: (miniVisible) => Stack(
                children: [
                  // 화면 전환: .scr.on { animation: in .25s } — 투명→불투명 + 8px 위로
                  Positioned.fill(
                    child: SafeArea(
                      bottom: false,
                      child: AnimatedSwitcher(
                        duration: reduce || state.seamlessSwitch
                            ? Duration.zero
                            : const Duration(milliseconds: 250),
                        switchInCurve: Curves.ease,
                        // 이전 화면은 바로 사라진다 (display:none)
                        layoutBuilder: (current, previous) =>
                            Stack(fit: StackFit.expand, children: [?current]),
                        transitionBuilder: (child, anim) => AnimatedBuilder(
                          animation: anim,
                          builder: (_, w) => Opacity(
                            opacity: anim.value,
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1 - anim.value)),
                              child: w,
                            ),
                          ),
                          child: child,
                        ),
                        // 사진 보관함 고르기(2, iOS)는 그리드가 직접 스크롤 → 바깥 스크롤 없이 높이 고정
                        child: state.screen == 2 && state.useLibrary
                            ? Padding(
                                key: ValueKey(state.screen),
                                padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomInset),
                                child: _buildScreen(),
                              )
                            : SingleChildScrollView(
                                key: ValueKey(state.screen),
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  showTabs
                                      ? (miniVisible ? 180 : 104) + bottomInset
                                      : 36 + bottomInset,
                                ),
                                child: _buildScreen(),
                              ),
                      ),
                    ),
                  ),
                  if (showTabs)
                    Positioned(
                      left: 56,
                      right: 56,
                      bottom: (bottomInset > 0 ? bottomInset : 20) + 4,
                      child: _BottomTabBar(state: state),
                    ),
                  if (showTabs && miniVisible)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: (bottomInset > 0 ? bottomInset : 20) + 76,
                      child: _MiniProgressCard(state: state),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// .tabs — 반투명 블러 바 (84), 아이콘 25 / 라벨 10
class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({required this.state});
  final SnapbackState state;

  static const _tabs = [
    (5, 'image', '사진'),
    (19, 'heart', '기억'),
    (11, 'stack', '앨범'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    // 디자인 B3 — 화면 위에 떠 있는 유리 알약 모양 탭바
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 30, offset: Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 60,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: c.bar,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: c.line, width: 0.5),
          ),
          child: Row(
            children: _tabs.map((t) {
              final active =
                  state.screen == t.$1 ||
                  (t.$1 == 19 && const {10, 18, 20, 21}.contains(state.screen)) ||
                  (t.$1 == 11 && (state.screen == 16 || state.screen == 17));
              final col = active ? c.pk : c.tabMute;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => state.go(t.$1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: active ? c.soft : null,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 26,
                        child: Center(
                          child: SnapIcon(t.$2, size: 24, color: col),
                        ),
                      ),
                      Text(
                        t.$3,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: col,
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      ),
    );
  }
}

/// 미니 진행 카드 표시 여부: 분석이 있으면 보이고, 완료 후 5초 뒤 숨김.
class _MiniHost extends StatefulWidget {
  const _MiniHost({required this.state, required this.builder});
  final SnapbackState state;
  final Widget Function(bool miniVisible) builder;

  @override
  State<_MiniHost> createState() => _MiniHostState();
}

class _MiniHostState extends State<_MiniHost> {
  Timer? _hide;
  bool _hidden = false;
  bool _wasDone = false;

  @override
  void didUpdateWidget(covariant _MiniHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    final s = widget.state;
    final done = s.analysisFinished && s.analysisTotal > 0;
    if (done && !_wasDone) {
      _hide?.cancel();
      _hide = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _hidden = true);
      });
    } else if (!done && _wasDone) {
      _hide?.cancel();
      _hidden = false;
    }
    _wasDone = done;
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(widget.state.analysisTotal > 0 && !_hidden);
}

/// #hb — 탭바 위 하단 분석 진행 바 (작업을 가리지 않도록 한 줄 + 트랙)
class _MiniProgressCard extends StatelessWidget {
  const _MiniProgressCard({required this.state});
  final SnapbackState state;

  static String _n(int v) => v.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  @override
  Widget build(BuildContext context) {
    final s = state;
    final v = AnalysisView(s);
    final status = v.done ? '분석 완료' : (v.paused ? '일시정지됨' : '사진 분석 중');
    final c = context.sc;
    final white = TextStyle(
      color: c.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // 디자인 B3 — 흰 반투명 카드: 캐릭터 · 상태 · 개수/퍼센트 · 주황 진행선 · 검은 일시정지 버튼
    return GestureDetector(
      onTap: () => s.go(4), // 자세히 보기 (선택)
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: c.bar,
          border: Border.all(color: c.line, width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 30,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            SnapRunner(width: 40, mode: v.mode),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          status,
                          style: white.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${_n(v.dn)} / ${_n(v.tot)} · ${v.pct}%',
                        style: white.copyWith(fontSize: 14, color: c.mute),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SnapBar(
                    value: v.p,
                    height: 5,
                    background: c.fill,
                    color: c.pri,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!v.done)
              Pressable(
                onTap: s.togglePauseAnalysis,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.ink,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: SnapIcon(
                    v.paused ? 'play' : 'pause',
                    size: 18,
                    color: c.bg,
                  ),
                ),
              )
            else
              const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
