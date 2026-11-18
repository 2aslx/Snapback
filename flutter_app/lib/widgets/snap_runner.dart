import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 분석 진행 화면의 달리는 캐릭터 (public/index.html 프로토타입의 SVG 캐릭터 이식).
/// [running] 이 true 면 통통 튀고(bob) 다리를 젓고 속도선이 깜빡인다.
/// [effects] 가 false 면 그림자·속도선 없이 캐릭터만 그린다 (잠금화면 위젯용).
class SnapRunner extends StatefulWidget {
  const SnapRunner({
    super.key,
    this.width = 66,
    this.running = true,
    this.effects = true,
  });

  final double width;
  final bool running;
  final bool effects;

  @override
  State<SnapRunner> createState() => _SnapRunnerState();
}

class _SnapRunnerState extends State<SnapRunner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SnapRunner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) _sync();
  }

  void _sync() {
    if (widget.running) {
      _c.repeat(reverse: true);
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.width * 84 / 80,
      child: CustomPaint(
        painter: _RunnerPainter(
          anim: _c,
          running: widget.running,
          effects: widget.effects,
        ),
      ),
    );
  }
}

class _RunnerPainter extends CustomPainter {
  _RunnerPainter({
    required this.anim,
    required this.running,
    required this.effects,
  }) : super(repaint: anim);

  final Animation<double> anim;
  final bool running;
  final bool effects;

  static const _limb = Color(0xFFB9A4FF);
  static const _ink = Color(0xFF2B2160);
  static const _speed = Color(0xFFA58BFF);
  static const _shadow = Color(0xFF6C4DE6);
  // SVG radialGradient #cg (cx .35, cy .3, r .8)
  static const _grad = RadialGradient(
    center: Alignment(-0.3, -0.4),
    radius: 0.8,
    colors: [Color(0xFFEFEAFF), Color(0xFFA58BFF)],
  );

  Paint _stroke(Color color, double w) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  void _leg(Canvas canvas, Offset hip, Offset foot, double deg) {
    canvas.save();
    canvas.translate(hip.dx, hip.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-hip.dx, -hip.dy);
    canvas.drawLine(hip, foot, _stroke(_limb, 7));
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 80);
    final v = running ? anim.value : 0.0;

    if (effects) {
      // 속도선: 0.45초 주기로 가운데에서 흐려지며 뒤로 밀림
      if (running) {
        final f = 1 - (2 * v - 1).abs();
        canvas.save();
        canvas.translate(-5 * f, 0);
        final p = _stroke(_speed.withValues(alpha: 1 - 0.8 * f), 2.5);
        canvas.drawLine(const Offset(2, 36), const Offset(14, 36), p);
        canvas.drawLine(const Offset(6, 46), const Offset(16, 46), p);
        canvas.restore();
      }
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(40, 79), width: 40, height: 7),
        Paint()..color = _shadow.withValues(alpha: 0.25),
      );
    }

    canvas.save();
    canvas.translate(0, -4 * Curves.easeInOut.transform(v)); // bob

    // 다리 (서로 반대로 ±30° 스윙, 정지 시 0°)
    final swing = running ? -30 + 60 * Curves.ease.transform(v) : 0.0;
    _leg(canvas, const Offset(36, 62), const Offset(30, 76), swing);
    _leg(canvas, const Offset(44, 62), const Offset(52, 74), -swing);

    // 팔
    final arms = Path()
      ..moveTo(32, 46)
      ..quadraticBezierTo(22, 50, 24, 58)
      ..moveTo(48, 46)
      ..quadraticBezierTo(58, 48, 56, 40);
    canvas.drawPath(arms, _stroke(_limb, 6.5));

    // 몸통 (12° 기울인 타원)
    canvas.save();
    canvas.translate(40, 52);
    canvas.rotate(12 * math.pi / 180);
    final body = Rect.fromCenter(center: Offset.zero, width: 24, height: 28);
    canvas.drawOval(body, Paint()..shader = _grad.createShader(body));
    canvas.restore();

    // 머리
    final head = Rect.fromCircle(center: const Offset(40, 24), radius: 17);
    canvas.drawOval(head, Paint()..shader = _grad.createShader(head));

    // 눈·입
    final ink = Paint()..color = _ink;
    canvas.drawCircle(const Offset(44, 22), 1.9, ink);
    canvas.drawCircle(const Offset(52, 22), 1.9, ink);
    final smile = Path()
      ..moveTo(45, 29)
      ..quadraticBezierTo(48.5, 33, 52, 29);
    canvas.drawPath(smile, _stroke(_ink, 1.8));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RunnerPainter old) =>
      old.running != running || old.effects != effects;
}
