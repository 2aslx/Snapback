import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class Screen0Welcome extends StatelessWidget {
  const Screen0Welcome({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('🌀', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 8),
        Text(
          'Snapback',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '스냅사진 + 되돌아가다. 흐릿한 기억을 말하면 사진을 찾아 주고, 그날의 경험까지 다시 꺼내 주는 스마트 갤러리',
          style: TextStyle(fontSize: 13, height: 1.5, color: c.mute),
        ),
        const SizedBox(height: 8),
        SnapRowCard(
          leading: buildIconBox(context, '💬'),
          title: '기억나는 대로 말하면 돼요',
          subtitle: '“비 오는 날 창가에서 먹은 디저트”',
        ),
        SnapRowCard(
          leading: buildIconBox(context, '⏱️'),
          title: '처음엔 분석 시간이 필요해요',
          subtitle: '사진 3,000장 기준 약 10분 · 화면을 꺼도 계속돼요',
        ),
        SnapRowCard(
          leading: buildIconBox(context, '🔐'),
          title: '내가 허용한 사진만 분석해요',
          subtitle: '범위는 언제든 바꿀 수 있어요',
        ),
        SnapButton(label: '시작하기', onTap: () => state.go(1)),
      ],
    );
  }
}

class Screen1Scope extends StatelessWidget {
  const Screen1Scope({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '사진 접근 범위', onBack: () => state.go(0)),
        const SizedBox(height: 12),
        Text(
          '어떤 사진을\n허용할까요?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 6),
        SnapOptionCard(
          icon: '🖼️',
          title: '전체 사진',
          subtitle: '3,420장',
          selected: state.scopeSelection == 0,
          onTap: () {
            state.scopeSelection = 0;
            state.go(1);
          },
        ),
        SnapOptionCard(
          icon: '📁',
          title: '앨범 선택',
          subtitle: '원하는 앨범만',
          selected: state.scopeSelection == 1,
          onTap: () {
            state.scopeSelection = 1;
            state.go(1);
          },
        ),
        SnapOptionCard(
          icon: '✋',
          title: '사진 직접 고르기',
          subtitle: '눌러서 하나씩 선택',
          selected: state.scopeSelection == 2,
          onTap: () {
            state.scopeSelection = 2;
            state.go(2);
          },
        ),
        SnapOptionCard(
          icon: '📅',
          title: '기간 지정',
          subtitle: '2022.01 ~ 지금',
          selected: state.scopeSelection == 3,
          onTap: () {
            state.scopeSelection = 3;
            state.go(1);
          },
        ),
        SnapButton(label: '다음', onTap: () => state.go(3)),
      ],
    );
  }
}

class Screen2PickPhotos extends StatelessWidget {
  const Screen2PickPhotos({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final count = state.pickQueue.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '사진 선택',
          onBack: () => state.go(1),
          trailing: Text(
            '$count장',
            style: TextStyle(fontSize: 12, color: c.pri),
          ),
        ),
        const SizedBox(height: 6),
        SnapButton(
          label: '📷 분석할 사진 선택',
          ghost: true,
          onTap: () => state.pickPhotosFromGallery(),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            '선택한 사진: $count장 (이미 분석한 사진은 건너뛰어요)',
            style: TextStyle(fontSize: 11, color: c.mute),
          ),
        ),
        SnapButton(label: '다음', onTap: () => state.go(3)),
      ],
    );
  }
}

class Screen3Order extends StatelessWidget {
  const Screen3Order({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    const years = ['2026', '2025', '2024', '2023', '2022'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '분석 순서', onBack: () => state.go(1)),
        const SizedBox(height: 12),
        Text(
          '어디부터\n돌아볼까요?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '먼저 분석된 사진부터 바로 검색할 수 있어요.',
          style: TextStyle(fontSize: 13, color: c.mute),
        ),
        const SizedBox(height: 6),
        SnapOptionCard(
          icon: '🌱',
          title: '최근 사진부터',
          subtitle: '요즘 찍은 사진을 먼저',
          selected: state.orderSelection == 0,
          onTap: () {
            state.orderSelection = 0;
            state.go(3);
          },
        ),
        SnapOptionCard(
          icon: '🕰️',
          title: '오래된 사진부터',
          subtitle: '2022년부터 차근차근',
          selected: state.orderSelection == 1,
          onTap: () {
            state.orderSelection = 1;
            state.go(3);
          },
        ),
        SnapOptionCard(
          icon: '🎯',
          title: '지정 기간 우선',
          subtitle: '고른 기간을 먼저 분석',
          selected: state.orderSelection == 2,
          onTap: () {
            state.orderSelection = 2;
            state.go(3);
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: years
              .map(
                (y) => SnapChip(
                  label: y,
                  selected: state.priorityYear == y,
                  onTap: () {
                    state.priorityYear = y;
                    state.go(3);
                  },
                ),
              )
              .toList(),
        ),
        SnapButton(
          label: '분석 시작',
          onTap: () {
            state.go(4);
            state.startAnalysis();
          },
        ),
      ],
    );
  }
}

class Screen4Progress extends StatefulWidget {
  const Screen4Progress({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen4Progress> createState() => _Screen4ProgressState();
}

class _Screen4ProgressState extends State<Screen4Progress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  String _formatEta(SnapbackState s) {
    if (s.analysisTotal == 0) return '-';
    if (s.analysisFinished) return '완료';
    if (s.etaMs <= 0) return '계산 중';
    final sec = math.max(1, (s.etaMs / 1000).round());
    return sec < 60 ? '~$sec초' : '~${(sec / 60).round()}분';
  }

  String _statusSubtitle(SnapbackState s) {
    if (s.analysisTotal == 0) return '분석할 사진을 선택해 주세요';
    if (s.analysisFinished) return '모든 사진을 기억했어요 ✨';
    if (s.currentFileDate != null) {
      final d = s.currentFileDate!;
      return '${d.year}년 ${d.month}월 사진 분석 중…';
    }
    return '시작합니다';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final tot = s.analysisTotal;
    final dn = s.analysisDone;
    final pct = tot > 0 ? ((dn / tot) * 100).round().clamp(0, 100) : 0;
    final progress = pct / 100.0;
    final paused = s.analysisPaused;
    final statusLabel = tot == 0
        ? '대기 중'
        : (paused ? '일시정지' : (s.analysisFinished ? '완료!' : '분석 중'));
    final yearMap = s.yearProgress();
    final sortedYears = yearMap.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '분석 진행', onBack: () => s.go(5)),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: 160,
            height: 160,
            child: CustomPaint(
              painter: _RingPainter(
                progress: progress,
                color: c.pri,
                trackColor: c.line,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      statusLabel,
                      style: TextStyle(fontSize: 12, color: c.mute),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth - 40;
            final leftPos = (maxW * progress).clamp(0.0, maxW);
            return SizedBox(
              height: 54,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Container(
                      height: 7,
                      decoration: BoxDecoration(
                        color: c.line,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            gradient: LinearGradient(
                              colors: [const Color(0xFFA58BFF), c.pri],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    right: 0,
                    bottom: 12,
                    child: Text('🏁', style: TextStyle(fontSize: 20)),
                  ),
                  AnimatedBuilder(
                    animation: _anim,
                    builder: (_, _) {
                      final bob =
                          (!paused && s.analysisRunning) ? -4 * _anim.value : 0.0;
                      return Positioned(
                        left: leftPos,
                        bottom: 13 + bob,
                        child: const Text('🏃', style: TextStyle(fontSize: 24)),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
        Center(
          child: Text(
            _statusSubtitle(s),
            style: TextStyle(fontSize: 13, color: c.mute),
          ),
        ),
        SnapButton(
          label: '📷 사진 올려서 바로 분석하기',
          onTap: () => s.pickPhotosFromGallery(startImmediately: true),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: c.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$dn',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '완료 / $tot',
                      style: TextStyle(fontSize: 11, color: c.mute),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: c.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatEta(s),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '남은 시간',
                      style: TextStyle(fontSize: 11, color: c.mute),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (s.analysisLogs.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...s.analysisLogs.take(6).map((log) {
            if (log.isError) {
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  log.text,
                  style: const TextStyle(fontSize: 11, color: Color(0xFFC0392B)),
                ),
              );
            }
            final bytes = decodeDataUrl(log.thumbDataUrl);
            return SnapRowCard(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.soft,
                  borderRadius: BorderRadius.circular(11),
                  image: bytes != null
                      ? DecorationImage(
                          image: MemoryImage(bytes),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: bytes == null
                    ? const Text('🧠', style: TextStyle(fontSize: 18))
                    : null,
              ),
              title: log.text,
              subtitle: log.subtext,
            );
          }),
        ],
        const SizedBox(height: 16),
        Text(
          '시기별 진행',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 6),
        if (sortedYears.isEmpty)
          Text(
            '사진을 올리면 연도별 진행률이 표시돼요',
            style: TextStyle(fontSize: 11, color: c.mute),
          )
        else
          ...sortedYears.map((y) {
            final pair = yearMap[y]!;
            final ratio = pair[1] > 0 ? pair[0] / pair[1] : 0.0;
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(y, style: TextStyle(fontSize: 12, color: c.ink)),
                      Text(
                        '${pair[0]}/${pair[1]}',
                        style: TextStyle(fontSize: 12, color: c.mute),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: c.line,
                      valueColor: AlwaysStoppedAnimation(c.pri),
                    ),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 16),
        Text(
          '잠금화면에서도 보여요',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [Color(0xFF232766), Color(0xFF6A4CC4)],
            ),
          ),
          child: Row(
            children: [
              const Text('🌀', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Analyzing your photos…',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFFC9B8FF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SnapButton(
          label: paused ? '▶ 이어서 분석' : '⏸ 일시정지',
          ghost: true,
          onTap: s.togglePauseAnalysis,
        ),
        SnapButton(label: '분석된 사진 먼저 보기', onTap: () => s.go(5)),
        const SizedBox(height: 9),
        Center(
          child: Text(
            '중단돼도 완료한 지점부터 이어서 분석해요 · 잠금화면에서 진행률 확인',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: c.mute),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    final bgPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13;
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
