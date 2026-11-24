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

  // 디자인 B3 · 화이트 오렌지: 하얀 배경 + 오렌지 포인트, 카드·입력창은 아주 옅은 회색
  static const light = SnapbackColors(
    bg: Color(0xFFFFFFFF),
    card: Color(0xFFF6F5F3),
    ink: Color(0xFF1C1714),
    mute: Color(0xFF77706A),
    line: Color(0x14000000), // rgba(0,0,0,.08)
    fill: Color(0x0D000000), // rgba(0,0,0,.05)
    soft: Color(0xFFFFF0E6),
    pri: Color(0xFFF26B1D),
    pk: Color(0xFFC9520F),
    bar: Color(0xD9FFFFFF), // rgba(255,255,255,.85)
    tabMute: Color(0xFF8E8780),
  );

  static const dark = SnapbackColors(
    bg: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    ink: Color(0xFFF5F5F7),
    mute: Color(0xFF98989F),
    line: Color(0x8C545458), // rgba(84,84,88,.55)
    fill: Color(0x3D767680), // rgba(118,118,128,.24)
    soft: Color(0xFF3A2414),
    pri: Color(0xFFF26B1D),
    pk: Color(0xFFFF9A5C),
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
  _g(0xFFFFE1C9, 0xFFFF9E63),
  _g(0xFFFBEEDB, 0xFFF2C48F),
  _g(0xFFF8DDD5, 0xFFEC9F8A),
  _g(0xFFFFE6D2, 0xFFFFAD75),
  _g(0xFFEFECE8, 0xFFCFC6BC),
  _g(0xFFFFDCC4, 0xFFF98D55),
];

/// 글꼴: 영문·숫자는 Inter(assets/fonts), 한글은 iOS 기본(Apple SD Gothic Neo) → 앱에 넣은 SnapbackKR(Pretendard 기반)
/// → Noto Sans KR. 웹은 기기 글꼴이 없어 SnapbackKR 이 쓰이므로 한글이 깨지지 않는다.
const kFontFamily = 'Inter';
const kFontFallback = ['Apple SD Gothic Neo', 'SnapbackKR', 'Noto Sans KR'];

ThemeData buildSnapbackTheme(Brightness brightness) {
  final c =
      brightness == Brightness.dark ? SnapbackColors.dark : SnapbackColors.light;
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: kFontFamily,
  );
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
