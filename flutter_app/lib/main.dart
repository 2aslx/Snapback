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

/// 하단 탭바의 바닥 여백: 홈 인디케이터가 있으면 그 영역에 조금 걸치게, 없으면 12
double _tabBottom(double bottomInset) =>
    bottomInset > 0 ? bottomInset - 10 : 12;

class _SnapbackShell extends StatelessWidget {
  const _SnapbackShell({required this.state});
  final SnapbackState state;

  // .scr.tb — 하단 탭바가 보이는 화면
  static int _lastScreen = -1;
  static bool _back = false;

  static const Set<int> _tabScreens = {5, 6, 7, 10, 11, 13, 14, 15, 16, 18, 19, 21, 22};

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
      case 10:
        return Screen10MemoryDetail(state: state);
      case 11:
        return Screen11Albums(state: state);
      case 12:
        return Screen12Settings(state: state);
      case 13:
        return Screen13Search(state: state);
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
      case 22:
        return Screen22Records(state: state);
      default:
        return Screen0Welcome(state: state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    // 저장된 설정을 읽기 전에는 배경만 (초기 설정을 마친 사람에게 시작 안내가 깜빡이지 않게)
    // 저장된 설정을 읽는 동안: iOS 시작 화면과 같은 앱 아이콘을 그대로 이어서 보여줌
    if (!state.ready) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Image.asset('assets/brand/app_icon.png', width: 120, height: 120),
        ),
      );
    }
    // 화면이 바뀌는 순간의 방향을 기억 (뒤로가기 버튼이면 오른쪽으로 밀리는 전환)
    if (state.screen != _lastScreen) {
      _back = SnapNav.backPending;
      SnapNav.backPending = false;
      _lastScreen = state.screen;
    }
    final back = _back;
    final showTabs = _tabScreens.contains(state.screen);
    final reduce = MediaQuery.of(context).disableAnimations;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return LockedPhotosScope(
      lockedIds: state.lockedPhotoIds,
      child: Scaffold(
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
                            : Duration(milliseconds: back ? 320 : 250),
                        switchInCurve: back ? Curves.easeOutCubic : Curves.ease,
                        // 앞으로 갈 때: 이전 화면은 바로 사라짐 (display:none)
                        // 뒤로 갈 때: 이전 화면(나가는 화면)을 위에 두고 오른쪽으로 밀어낸다
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: back ? [?current, ...previous] : [?current],
                        ),
                        transitionBuilder: (child, anim) => AnimatedBuilder(
                          animation: anim,
                          builder: (_, w) {
                            if (!back) {
                              // .scr.on { animation: in .25s } — 투명→불투명 + 8px 위로
                              return Opacity(
                                opacity: anim.value,
                                child: Transform.translate(
                                  offset: Offset(0, 8 * (1 - anim.value)),
                                  child: w,
                                ),
                              );
                            }
                            final incoming = child.key == ValueKey(state.screen);
                            if (incoming) {
                              // 들어오는(이전) 화면: 왼쪽에서 살짝 따라 들어옴
                              return FractionalTranslation(
                                translation: Offset(-0.28 * (1 - anim.value), 0),
                                child: w,
                              );
                            }
                            // 나가는 화면: 오른쪽으로 밀려 나감 (왼쪽 가장자리에 옅은 그림자)
                            final t = Curves.easeOutCubic.transform(1 - anim.value);
                            return FractionalTranslation(
                              translation: Offset(t, 0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.bg,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x22000000),
                                      blurRadius: 16,
                                      offset: Offset(-4, 0),
                                    ),
                                  ],
                                ),
                                child: w,
                              ),
                            );
                          },
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
                      // 홈 인디케이터 영역 쪽으로 조금 더 내림 (이전보다 14 아래)
                      bottom: _tabBottom(bottomInset),
                      child: _BottomTabBar(state: state),
                    ),
                  // 하단 분석 진행 카드: 아래에서 살짝 올라오며 나타나고, 내려가며 사라진다
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: _tabBottom(bottomInset) + 72,
                    child: AnimatedSwitcher(
                      duration: reduce
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).animate(a),
                          child: c,
                        ),
                      ),
                      child: showTabs && miniVisible
                          ? _MiniProgressCard(
                              key: const ValueKey('mini'),
                              state: state,
                            )
                          : const SizedBox.shrink(key: ValueKey('none')),
                    ),
                  ),
                  // 검색·앨범·기록 초안 등을 기다리는 동안 맨 아래 얇은 진행 바 (하염없이 기다리지 않게)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: state.isLoading ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: SizedBox(
                          height: 3,
                          child: state.isLoading
                              ? LinearProgressIndicator(
                                  minHeight: 3,
                                  color: c.pri,
                                  backgroundColor: c.soft,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
    (22, 'bookmark', '기록'),
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
                  (t.$1 == 19 && const {10, 18, 20}.contains(state.screen)) ||
                  (t.$1 == 22 && state.screen == 21) ||
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
    final done = AnalysisView.mini(s).done;
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
      widget.builder(AnalysisView.mini(widget.state).tot > 0 && !_hidden);
}

/// #hb — 탭바 위 하단 분석 진행 바 (작업을 가리지 않도록 한 줄 + 트랙)
class _MiniProgressCard extends StatelessWidget {
  const _MiniProgressCard({super.key, required this.state});
  final SnapbackState state;

  static String _n(int v) => v.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  @override
  Widget build(BuildContext context) {
    final s = state;
    final v = AnalysisView.mini(s);
    final status = v.relabel
        ? (v.done ? '다시 분석 완료' : '사진 다시 분석 중')
        : (v.done ? '분석 완료' : (v.paused ? '일시정지됨' : '사진 분석 중'));
    final c = context.sc;
    final white = TextStyle(
      color: c.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // 디자인 B3 — 흰 반투명 카드: 캐릭터 · 상태 · 개수/퍼센트 · 주황 진행선 · 검은 일시정지 버튼
    return GestureDetector(
      onTap: () => s.go(v.relabel ? 12 : 4), // 자세히 보기 (다시 분석은 설정 화면)
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
                        '${_n(v.dn)} / ${_n(v.tot)} · ${v.pct}%'
                        '${!v.relabel && s.analysisFailed > 0 ? ' · 실패 ${s.analysisFailed}' : ''}',
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
                onTap: v.relabel ? s.cancelRelabel : s.togglePauseAnalysis,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.ink,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: SnapIcon(
                    v.relabel ? 'close' : (v.paused ? 'play' : 'pause'),
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
