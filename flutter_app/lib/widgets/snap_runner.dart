import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// 캐릭터 상태 — index.html 의 .runner / #hb 클래스(run · .pause · .done)에 대응.
enum RunnerMode { run, idle, done }

const _skin = Color(0xFFF3A877); // 앞쪽 팔·다리
const _skinBack = Color(0xFFE08A55); // 뒤쪽 팔·다리
const _ink = Color(0xFF3A2418);
const _speed = Color(0xFFF4A574);
const _shadow = Color(0xFFE8793A);
// <radialGradient id="cg" cx=".35" cy=".3" r=".8"> #fff1e4 → #f4a574
const _grad = RadialGradient(
  center: Alignment(-0.3, -0.4),
  radius: 0.8,
  colors: [Color(0xFFFFF1E4), Color(0xFFF4A574)],
);

/// 분석 진행 트랙의 달리는 캐릭터 (viewBox 0 0 80 84).
/// [shadowed] 는 미니 진행 카드용 drop-shadow(0 1px 1.5px rgba(110,40,5,.45)).
class SnapRunner extends StatefulWidget {
  const SnapRunner({
    super.key,
    this.width = 66,
    this.mode = RunnerMode.run,
    this.shadowed = false,
  });

  final double width;
  final RunnerMode mode;
  final bool shadowed;

  @override
  State<SnapRunner> createState() => _SnapRunnerState();
}

class _SnapRunnerState extends State<SnapRunner>
    with SingleTickerProviderStateMixin {
  // 하나의 시계로 모든 주기(0.56s 달리기, 1.8s 숨쉬기, 0.9s 점프)를 계산
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final mode = reduce && widget.mode == RunnerMode.run
        ? RunnerMode.idle // @media(prefers-reduced-motion) → .idle, animation:none
        : widget.mode;
    Widget paint(Color? tint) => CustomPaint(
          size: Size(widget.width, widget.width * 84 / 80),
          painter: _RunnerPainter(
            clock: _clock,
            mode: mode,
            still: reduce,
            tint: tint,
          ),
        );
    if (!widget.shadowed) return paint(null);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Transform.translate(
          offset: const Offset(0, 1),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 0.75, sigmaY: 0.75),
            child: paint(const Color(0x736E2805)),
          ),
        ),
        paint(null),
      ],
    );
  }
}

/// 정적인 캐릭터 심볼 (`<symbol id="ch">`) — 시작 화면·잠금화면 위젯용.
class SnapCharacter extends StatelessWidget {
  const SnapCharacter({super.key, this.size = 84});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SymbolPainter());
}

Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint _fillGrad(Rect r) => Paint()..shader = _grad.createShader(r);

/// 9개 키프레임 값을 [t](0~1)에서 선형 보간 (SMIL calcMode="linear").
double _kf(List<double> v, double t) {
  final x = (t % 1) * (v.length - 1);
  final i = x.floor().clamp(0, v.length - 2);
  return v[i] + (v[i + 1] - v[i]) * (x - i);
}

double _rad(double deg) => deg * math.pi / 180;

void _rotateAt(Canvas c, double deg, double cx, double cy) {
  c.translate(cx, cy);
  c.rotate(_rad(deg));
  c.translate(-cx, -cy);
}

void _head(Canvas c, Paint Function(Color, double) s, Color? tint,
    {required List<double> eyes, required List<double> smile}) {
  final head = Rect.fromCircle(center: const Offset(40, 24), radius: 17);
  c.drawOval(head, tint == null ? _fillGrad(head) : (Paint()..color = tint));
  final ink = Paint()..color = tint ?? _ink;
  c.drawCircle(Offset(eyes[0], eyes[1]), 1.9, ink);
  c.drawCircle(Offset(eyes[2], eyes[3]), 1.9, ink);
  c.drawPath(
    Path()
      ..moveTo(smile[0], smile[1])
      ..quadraticBezierTo(smile[2], smile[3], smile[4], smile[5]),
    s(tint ?? _ink, 1.8),
  );
}

class _RunnerPainter extends CustomPainter {
  _RunnerPainter({
    required this.clock,
    required this.mode,
    required this.still,
    this.tint,
  }) : super(repaint: clock);

  final AnimationController clock;
  final RunnerMode mode;
  final bool still;
  final Color? tint; // 그림자용 단색

  double get _sec =>
      still ? 0 : (clock.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;

  Paint _s(Color c, double w) => _stroke(tint ?? c, w);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 80);
    final sec = _sec;
    final t = (sec / 0.56) % 1; // 달리기 주기

    // 바닥 그림자 (모든 상태에서 rx 가 숨쉬듯 변함)
    if (tint == null) {
      final rx = _kf(const [16, 18, 19, 18, 16, 18, 19, 18, 16], t);
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(40, 79), width: rx * 2, height: 6.4),
        Paint()..color = _shadow.withValues(alpha: 0.22),
      );
    }
    if (mode == RunnerMode.run) {
      _run(canvas, t);
    } else {
      _idle(canvas, sec);
    }
  }

  void _run(Canvas canvas, double t) {
    // 속도선: translateX 6→-8, opacity 0→1(30%)→0, 0.56s, 지연 0 / -.19s / -.37s
    if (tint == null) {
      const lines = [
        [6.0, 34.0, 15.0, 0.0],
        [2.0, 45.0, 12.0, 0.19],
        [7.0, 56.0, 15.0, 0.37],
      ];
      for (final l in lines) {
        final p = ((t + l[3] / 0.56) % 1);
        final dx = 6 - 14 * p;
        final op = p < 0.3 ? p / 0.3 : 1 - (p - 0.3) / 0.7;
        canvas.drawLine(
          Offset(l[0] + dx, l[1]),
          Offset(l[2] + dx, l[1]),
          _stroke(_speed.withValues(alpha: op.clamp(0, 1)), 2.5),
        );
      }
    }

    canvas.save();
    _rotateAt(canvas, 6, 40, 78);
    canvas.translate(0, _kf(const [-2, 0, 1.5, 0, -2, 0, 1.5, 0, -2], t));

    void arm(Color color, List<double> rot) {
      canvas.save();
      canvas.translate(41, 42);
      canvas.rotate(_rad(_kf(rot, t)));
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(2, 6, 0, 11),
        _s(color, 5.5),
      );
      canvas.drawCircle(const Offset(0, 12), 3.3, Paint()..color = tint ?? color);
      canvas.restore();
    }

    void leg(Color color, List<double> thigh, List<double> shin) {
      canvas.save();
      canvas.translate(40, 60);
      canvas.rotate(_rad(_kf(thigh, t)));
      canvas.drawLine(Offset.zero, const Offset(0, 9), _s(color, 7));
      canvas.translate(0, 9);
      canvas.rotate(_rad(_kf(shin, t)));
      canvas.drawLine(Offset.zero, const Offset(0, 9), _s(color, 7));
      canvas.restore();
    }

    arm(_skinBack, const [-60, -38, 0, 38, 52, 38, 0, -38, -60]);
    leg(_skinBack, const [38, 25, 0, -22, -32, -18, 0, 22, 38],
        const [20, 65, 95, 55, 8, 15, 22, 15, 20]);
    leg(_skin, const [-32, -18, 0, 22, 38, 25, 0, -22, -32],
        const [8, 15, 22, 15, 20, 65, 95, 55, 8]);

    // 몸통 (12° 기울임)
    canvas.save();
    _rotateAt(canvas, 12, 40, 52);
    final body = Rect.fromCenter(center: const Offset(40, 52), width: 24, height: 28);
    canvas.drawOval(body, tint == null ? _fillGrad(body) : (Paint()..color = tint!));
    canvas.restore();

    // 머리 (±2° 흔들림, 중심 40,40)
    canvas.save();
    _rotateAt(canvas, _kf(const [-2, 0, 2, 0, -2, 0, 2, 0, -2], t), 40, 40);
    _head(canvas, _s, tint,
        eyes: const [44, 22, 52, 22], smile: const [45, 29, 48.5, 33, 52, 29]);
    canvas.restore();

    arm(_skin, const [52, 38, 0, -38, -60, -38, 0, 38, 52]);
    canvas.restore();
  }

  void _idle(Canvas canvas, double sec) {
    canvas.save();
    if (mode == RunnerMode.done) {
      // @keyframes hop .9s ease-in-out: 0,55%,100% → 0 / 25% → -9px
      final p = (sec / 0.9) % 1;
      double y = 0;
      if (p < 0.25) {
        y = -9 * Curves.easeInOut.transform(p / 0.25);
      } else if (p < 0.55) {
        y = -9 * (1 - Curves.easeInOut.transform((p - 0.25) / 0.3));
      }
      canvas.translate(0, y);
    } else {
      // @keyframes breathe 1.8s ease-in-out: 50% → scaleY(.97), 기준점 = 발끝(y 77)
      final p = (sec / 1.8) % 1;
      final k = p < 0.5
          ? Curves.easeInOut.transform(p / 0.5)
          : 1 - Curves.easeInOut.transform((p - 0.5) / 0.5);
      final sy = 1 - 0.03 * k;
      canvas.translate(0, 77);
      canvas.scale(1, sy);
      canvas.translate(0, -77);
    }

    canvas.drawPath(
      Path()
        ..moveTo(37, 60)
        ..lineTo(35, 77)
        ..moveTo(43, 60)
        ..lineTo(45, 77),
      _s(_skin, 7),
    );
    if (mode == RunnerMode.done) {
      // .cheer — 만세
      canvas.drawPath(
        Path()
          ..moveTo(30, 45)
          ..quadraticBezierTo(21, 41, 20, 32)
          ..moveTo(50, 45)
          ..quadraticBezierTo(59, 41, 60, 32),
        _s(_skin, 6),
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(30, 46)
          ..quadraticBezierTo(26, 52, 28, 58)
          ..moveTo(50, 46)
          ..quadraticBezierTo(54, 52, 52, 58),
        _s(_skin, 6),
      );
    }
    final body = Rect.fromCenter(center: const Offset(40, 52), width: 24, height: 28);
    canvas.drawOval(body, tint == null ? _fillGrad(body) : (Paint()..color = tint!));
    _head(canvas, _s, tint,
        eyes: const [34, 23, 46, 23], smile: const [36, 29, 40, 33, 44, 29]);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RunnerPainter old) =>
      old.mode != mode || old.still != still || old.tint != tint;
}

class _SymbolPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 80);
    canvas.drawPath(
      Path()
        ..moveTo(37, 60)
        ..lineTo(35, 75)
        ..moveTo(43, 60)
        ..lineTo(45, 75),
      _stroke(_skin, 7),
    );
    canvas.drawPath(
      Path()
        ..moveTo(30, 46)
        ..quadraticBezierTo(26, 52, 28, 58)
        ..moveTo(50, 46)
        ..quadraticBezierTo(54, 52, 52, 58),
      _stroke(_skin, 6),
    );
    final body = Rect.fromCenter(center: const Offset(40, 52), width: 24, height: 28);
    canvas.drawOval(body, _fillGrad(body));
    _head(canvas, _stroke, null,
        eyes: const [34, 23, 46, 23], smile: const [36, 29, 40, 33, 44, 29]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
