import 'package:material_ui/material_ui.dart';
import 'screens/main_screens.dart';
import 'screens/onboarding_screens.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

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

  static const Set<int> _tabScreens = {5, 6, 7, 10, 11, 13, 14, 15, 16};

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
      default:
        return Screen0Welcome(state: state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final showTabs = _tabScreens.contains(state.screen);

    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 430),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.28],
              colors: [c.soft, c.card],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x1F4B30B7), blurRadius: 40),
            ],
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  // 화면 전환: 새 화면이 살짝 위로 떠오르며 페이드 인 (프로토타입 .25s 효과)
                  child: AnimatedSwitcher(
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    reverseDuration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.012),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    // 화면마다 스크롤 뷰를 새로 만들어 항상 맨 위에서 시작
                    child: SingleChildScrollView(
                      key: ValueKey(state.screen),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        showTabs ? 20 : 24,
                      ),
                      child: _buildScreen(),
                    ),
                  ),
                ),
                if (showTabs) _BottomTabBar(state: state),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({required this.state});
  final SnapbackState state;

  static const _tabs = [
    (5, '🖼️', '사진'),
    (10, '💜', '기억'),
    (11, '🗂️', '앨범'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: _tabs.map((t) {
          final active =
              state.screen == t.$1 || (t.$1 == 11 && state.screen == 16);
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => state.go(t.$1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(t.$2, style: const TextStyle(fontSize: 19)),
                  const SizedBox(height: 2),
                  Text(
                    t.$3,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: active ? c.pri : c.mute,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
