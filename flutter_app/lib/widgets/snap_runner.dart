import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// 캐릭터 상태 — index.html 의 .runner / #hb 클래스(run · .pause · .done)에 대응.
enum RunnerMode { run, idle, done }

// 캐릭터: B · 찰칵이 (카메라 몸 + 렌즈 눈, 짧은 다리 + 동그란 발). 좌표계: viewBox 0 0 80 84 (발끝 y 79).
const _skin = Color(0xFFFFA66B); // 다리·팔·뷰파인더
const _skinBack = Color(0xFFF0884A); // 뒤쪽 다리
const _ink = Color(0xFF3A2418);
const _speed = Color(0xFFF4A574);
const _shadow = Color(0xFFF26B1D); // 렌즈 테두리 · 바닥 그림자
const _cream = Color(0xFFFFF8F1);
const _flash = Color(0xFFFFE2C4);
const _blush = Color(0xFFF48C7A);
const _white = Color(0xFFFFFFFF);
const _grad = RadialGradient(
  center: Alignment(-0.24, -0.4),
  radius: 0.85,
  colors: [Color(0xFFFFF4EA), Color(0xFFFFC999), Color(0xFFFF8F4F)],
  stops: [0, 0.6, 1],
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

/// 정적인 캐릭터 (서 있는 찰칵이) — 시작 화면·잠금화면 위젯·홈 제목 옆 로고용.
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

/// 서 있는 짧은 다리 + 동그란 발.
void _legs(Canvas c, Color? tint) {
  c.drawPath(
    Path()
      ..moveTo(33, 66)
      ..lineTo(33, 72)
      ..moveTo(47, 66)
      ..lineTo(47, 72),
    _stroke(tint ?? _skin, 6),
  );
  final foot = Paint()..color = tint ?? _skin;
  c.drawOval(Rect.fromCenter(center: const Offset(32, 74), width: 10, height: 6), foot);
  c.drawOval(Rect.fromCenter(center: const Offset(48, 74), width: 10, height: 6), foot);
}

/// 카메라 몸통 + 렌즈 + 얼굴. [tint] 가 있으면 그림자용 단색 실루엣만.
void _camera(Canvas c, Color? tint, {bool happy = false}) {
  Paint solid(Color col) => Paint()..color = tint ?? col;
  // 뷰파인더 · 플래시
  c.drawRRect(
    RRect.fromLTRBR(26, 20, 42, 30, const Radius.circular(4)),
    solid(_skin),
  );
  c.drawCircle(const Offset(57, 25), 3, solid(_flash));
  if (tint == null) c.drawCircle(const Offset(57, 25), 3, _stroke(_skin, 1.3));
  // 몸통
  final body = RRect.fromLTRBR(12, 26, 68, 68, const Radius.circular(15));
  c.drawRRect(body, tint == null ? _fillGrad(body.outerRect) : solid(_skin));
  if (tint != null) return;
  // 렌즈 (큰 눈)
  c.drawCircle(const Offset(40, 48), 13, Paint()..color = _cream);
  c.drawCircle(const Offset(40, 48), 13, _stroke(_shadow, 3.2));
  c.drawCircle(const Offset(40, 48), 6.8, Paint()..color = _ink);
  c.drawCircle(const Offset(37.6, 45.6), 2.2, Paint()..color = _white);
  c.drawCircle(
    const Offset(44.2, 50.4),
    1,
    Paint()..color = _white.withValues(alpha: 0.8),
  );
  // 눈 (완료 상태에서는 웃는 눈)
  if (happy) {
    final eye = _stroke(_ink, 1.8);
    c.drawPath(
      Path()
        ..moveTo(18.5, 38)
        ..quadraticBezierTo(21, 34.5, 23.5, 38)
        ..moveTo(56.5, 38)
        ..quadraticBezierTo(59, 34.5, 61.5, 38),
      eye,
    );
  } else {
    final ink = Paint()..color = _ink;
    c.drawOval(
      Rect.fromCenter(center: const Offset(21, 37), width: 4, height: 5),
      ink,
    );
    c.drawOval(
      Rect.fromCenter(center: const Offset(59, 37), width: 4, height: 5),
      ink,
    );
  }
  // 볼터치
  final blush = Paint()..color = _blush.withValues(alpha: 0.45);
  c.drawOval(
    Rect.fromCenter(center: const Offset(20.5, 45), width: 7.5, height: 5),
    blush,
  );
  c.drawOval(
    Rect.fromCenter(center: const Offset(59.5, 45), width: 7.5, height: 5),
    blush,
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
        [0.0, 36.0, 8.0, 0.0],
        [-3.0, 46.0, 6.0, 0.19],
        [0.0, 56.0, 8.0, 0.37],
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
    canvas.translate(0, 4); // 짧은 다리만큼 몸을 내려 발이 바닥에 닿게
    _rotateAt(canvas, 5, 40, 78); // 앞으로 살짝 기울임
    canvas.translate(0, _kf(const [-2, 0, 1.5, 0, -2, 0, 1.5, 0, -2], t));

    void leg(Color color, double hipX, List<double> rot) {
      canvas.save();
      canvas.translate(hipX, 66);
      canvas.rotate(_rad(_kf(rot, t)));
      canvas.drawLine(Offset.zero, const Offset(0, 7), _s(color, 6));
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, 8.5), width: 10, height: 6),
        Paint()..color = tint ?? color,
      );
      canvas.restore();
    }

    leg(_skinBack, 46, const [30, 18, 0, -18, -30, -18, 0, 18, 30]);
    leg(_skin, 34, const [-30, -18, 0, 18, 30, 18, 0, -18, -30]);

    // 몸통 (±2° 흔들림, 중심 40,47)
    canvas.save();
    _rotateAt(canvas, _kf(const [-2, 0, 2, 0, -2, 0, 2, 0, -2], t), 40, 47);
    _camera(canvas, tint);
    canvas.restore();
    canvas.restore();
  }

  void _idle(Canvas canvas, double sec) {
    canvas.save();
    final done = mode == RunnerMode.done;
    if (done) {
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
      // @keyframes breathe 1.8s ease-in-out: 50% → scaleY(.97), 기준점 = 발끝(y 78)
      final p = (sec / 1.8) % 1;
      final k = p < 0.5
          ? Curves.easeInOut.transform(p / 0.5)
          : 1 - Curves.easeInOut.transform((p - 0.5) / 0.5);
      final sy = 1 - 0.03 * k;
      canvas.translate(0, 78);
      canvas.scale(1, sy);
      canvas.translate(0, -78);
    }

    canvas.translate(0, 4);
    _legs(canvas, tint);
    if (done) {
      // 만세
      canvas.drawPath(
        Path()
          ..moveTo(14, 46)
          ..lineTo(6, 35)
          ..moveTo(66, 46)
          ..lineTo(74, 35),
        _s(_skin, 5),
      );
    }
    _camera(canvas, tint, happy: done);
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
    canvas.translate(0, 2);
    _legs(canvas, null);
    _camera(canvas, null);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
