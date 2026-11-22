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
                        child: SingleChildScrollView(
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
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _BottomTabBar(state: state),
                    ),
                  if (showTabs && miniVisible)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 92 + bottomInset,
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 84 + (bottomInset > 34 ? bottomInset - 34 : 0),
          padding: const EdgeInsets.only(top: 7),
          decoration: BoxDecoration(
            color: c.bar,
            border: Border(top: BorderSide(color: c.line, width: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _tabs.map((t) {
              final active =
                  state.screen == t.$1 ||
                  (t.$1 == 19 && const {10, 18, 20, 21}.contains(state.screen)) ||
                  (t.$1 == 11 && (state.screen == 16 || state.screen == 17));
              final col = active ? c.pri : c.tabMute;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => state.go(t.$1),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 28,
                        child: Center(
                          child: SnapIcon(t.$2, size: 28.75, color: col),
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
              );
            }).toList(),
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
    const white = TextStyle(
      color: Colors.white,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return GestureDetector(
      onTap: () => s.go(4), // 자세히 보기 (선택)
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF4A45A), Color(0xFFE8793A)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x52AA460F),
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: status,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' · ${_n(v.dn)} / ${_n(v.tot)}장'),
                      ],
                    ),
                    style: white.copyWith(fontSize: 14),
                  ),
                  // .mtrk — 트랙 + 미니 러너
                  LayoutBuilder(
                    builder: (_, k) => SizedBox(
                      height: 30,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 4,
                            child: SnapBar(
                              value: v.p,
                              height: 4,
                              background: const Color(0x59FFFFFF),
                              color: Colors.white,
                            ),
                          ),
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 600),
                            left: (k.maxWidth - 26) * v.p,
                            bottom: 5,
                            child: SnapRunner(
                              width: 26,
                              mode: v.mode,
                              shadowed: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${v.pct}%',
              style: white.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            if (!v.done)
              Pressable(
                onTap: s.togglePauseAnalysis,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFF7A3A14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: SnapIcon(
                    v.paused ? 'play' : 'pause',
                    size: 18,
                    color: Colors.white,
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
