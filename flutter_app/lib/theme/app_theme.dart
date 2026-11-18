import 'package:material_ui/material_ui.dart';

class SnapbackColors extends ThemeExtension<SnapbackColors> {
  const SnapbackColors({
    required this.bg,
    required this.card,
    required this.ink,
    required this.mute,
    required this.pri,
    required this.soft,
    required this.line,
  });

  final Color bg;
  final Color card;
  final Color ink;
  final Color mute;
  final Color pri;
  final Color soft;
  final Color line;

  static const light = SnapbackColors(
    bg: Color(0xFFF4F1FB),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF1D1633),
    mute: Color(0xFF7B7494),
    pri: Color(0xFF6C4DE6),
    soft: Color(0xFFECE6FF),
    line: Color(0xFFE5DEF7),
  );

  static const dark = SnapbackColors(
    bg: Color(0xFF120E22),
    card: Color(0xFF1D1736),
    ink: Color(0xFFF1EDFF),
    mute: Color(0xFF9D95BD),
    pri: Color(0xFF6C4DE6),
    soft: Color(0xFF2A2150),
    line: Color(0xFF33295C),
  );

  @override
  SnapbackColors copyWith({
    Color? bg,
    Color? card,
    Color? ink,
    Color? mute,
    Color? pri,
    Color? soft,
    Color? line,
  }) =>
      SnapbackColors(
        bg: bg ?? this.bg,
        card: card ?? this.card,
        ink: ink ?? this.ink,
        mute: mute ?? this.mute,
        pri: pri ?? this.pri,
        soft: soft ?? this.soft,
        line: line ?? this.line,
      );

  @override
  SnapbackColors lerp(ThemeExtension<SnapbackColors>? other, double t) {
    if (other is! SnapbackColors) return this;
    return SnapbackColors(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      mute: Color.lerp(mute, other.mute, t)!,
      pri: Color.lerp(pri, other.pri, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      line: Color.lerp(line, other.line, t)!,
    );
  }
}

extension SnapbackThemeExt on BuildContext {
  SnapbackColors get sc =>
      Theme.of(this).extension<SnapbackColors>() ?? SnapbackColors.light;
}

const List<LinearGradient> kTileGradients = [
  LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF6B988), Color(0xFFE86F8C)],
  ),
  LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7BC4A8), Color(0xFF3A7F9C)],
  ),
  LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF3D58A), Color(0xFFC98A4B)],
  ),
  LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB9A2FF), Color(0xFF6C4DE6)],
  ),
  LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFC4DD), Color(0xFFF27FB0)],
  ),
  LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9AD2FF), Color(0xFF4A82E0)],
  ),
];

ThemeData buildSnapbackTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? SnapbackColors.dark
      : SnapbackColors.light;
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.pri,
      brightness: brightness,
      primary: c.pri,
      surface: c.card,
    ),
    useMaterial3: true,
    extensions: [c],
  );
}
