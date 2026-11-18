import 'package:material_ui/material_ui.dart';

/// 색상 토큰 — index.html 의 "iOS style layer" (:root) 값을 그대로 옮김.
class SnapbackColors extends ThemeExtension<SnapbackColors> {
  const SnapbackColors({
    required this.bg,
    required this.card,
    required this.ink,
    required this.mute,
    required this.line,
    required this.fill,
    required this.soft,
    required this.pri,
    required this.pk,
    required this.bar,
    required this.tabMute,
  });

  final Color bg;
  final Color card;
  final Color ink;
  final Color mute;
  final Color line;
  final Color fill;
  final Color soft;
  final Color pri;
  final Color pk;
  final Color bar;
  final Color tabMute;

  static const light = SnapbackColors(
    bg: Color(0xFFF4F1ED),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF1C1C1E),
    mute: Color(0xFF8A847E),
    line: Color(0x293C3C43), // rgba(60,60,67,.16)
    fill: Color(0x1F786E64), // rgba(120,110,100,.12)
    soft: Color(0xFFFDEEE2),
    pri: Color(0xFFE8793A),
    pk: Color(0xFFC9601F),
    bar: Color(0xDBFAF8F6), // rgba(250,248,246,.86)
    tabMute: Color(0xFF9A948E),
  );

  static const dark = SnapbackColors(
    bg: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    ink: Color(0xFFF5F5F7),
    mute: Color(0xFF98989F),
    line: Color(0x8C545458), // rgba(84,84,88,.55)
    fill: Color(0x3D767680), // rgba(118,118,128,.24)
    soft: Color(0xFF33241A),
    pri: Color(0xFFE8793A),
    pk: Color(0xFFF4A574),
    bar: Color(0xDB161618), // rgba(22,22,24,.86)
    tabMute: Color(0xFF9A948E),
  );

  @override
  SnapbackColors copyWith() => this;

  @override
  SnapbackColors lerp(ThemeExtension<SnapbackColors>? other, double t) {
    if (other is! SnapbackColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SnapbackColors(
      bg: l(bg, other.bg),
      card: l(card, other.card),
      ink: l(ink, other.ink),
      mute: l(mute, other.mute),
      line: l(line, other.line),
      fill: l(fill, other.fill),
      soft: l(soft, other.soft),
      pri: l(pri, other.pri),
      pk: l(pk, other.pk),
      bar: l(bar, other.bar),
      tabMute: l(tabMute, other.tabMute),
    );
  }
}

extension SnapbackThemeExt on BuildContext {
  SnapbackColors get sc =>
      Theme.of(this).extension<SnapbackColors>() ?? SnapbackColors.light;
}

/// .g1 ~ .g6 사진 타일 그라데이션 (135deg). 인덱스는 id % 6 (HTML 의 G[d.id%6]).
LinearGradient _g(int a, int b) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(a), Color(b)],
    );

final List<LinearGradient> kTileGradients = [
  _g(0xFFF6C7A1, 0xFFE2896A),
  _g(0xFFCFDCB4, 0xFF8FA77A),
  _g(0xFFF3D58A, 0xFFD39A4F),
  _g(0xFFF6BF95, 0xFFD9653A),
  _g(0xFFF6CDC4, 0xFFD98A85),
  _g(0xFFC2D8D6, 0xFF7FA3A8),
];

/// 본문 글꼴: -apple-system 계열, letter-spacing -.2px.
const kFontFallback = ['Apple SD Gothic Neo', 'Pretendard', 'Noto Sans KR'];

ThemeData buildSnapbackTheme(Brightness brightness) {
  final c =
      brightness == Brightness.dark ? SnapbackColors.dark : SnapbackColors.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.pri,
      brightness: brightness,
      primary: c.pri,
      surface: c.card,
    ),
    // CSS line-height:normal(≈1.2) · body letter-spacing -.2px
    textTheme: base.textTheme
        .apply(
          bodyColor: c.ink,
          displayColor: c.ink,
          fontFamilyFallback: kFontFallback,
        )
        .copyWith(
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            height: 1.2,
            letterSpacing: -0.2,
            color: c.ink,
            fontFamilyFallback: kFontFallback,
          ),
        ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.pri),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: [c],
  );
}
