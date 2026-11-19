import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/snap_runner.dart';

import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

// index.html 의 ① 시작 안내 ~ ② 분석 진행 (섹션 0~4)

/// ① 시작 안내
class Screen0Welcome extends StatelessWidget {
  const Screen0Welcome({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SnapCharacter(size: 84),
        const SnapH2('Snapback'),
        const SnapSub(
          '스냅사진 + 되돌아가다. 흐릿한 기억을 말하면 사진을 찾아 주고, 그날의 경험까지 다시 꺼내 주는 스마트 갤러리',
        ),
        const SnapGroup(
          children: [
            SnapRow(
              leading: IconBadge('chat'),
              title: '기억나는 대로 말하면 돼요',
              subtitle: '“비 오는 날 창가에서 먹은 디저트”',
            ),
            SnapRow(
              leading: IconBadge('clock'),
              title: '처음엔 분석 시간이 필요해요',
              subtitle: '사진 3,000장 기준 약 10분 · 화면을 꺼도 계속돼요',
            ),
            SnapRow(
              leading: IconBadge('lock'),
              title: '내가 허용한 사진만 분석해요',
              subtitle: '범위는 언제든 바꿀 수 있어요',
            ),
          ],
        ),
        SnapButton(label: '시작하기', onTap: () => state.go(1)),
      ],
    );
  }
}

/// ② 사진 범위 선택
class Screen1Scope extends StatelessWidget {
  const Screen1Scope({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    s.ensureLibraryOnce(); // iOS: 사진 보관함 권한 · 전체 사진 수 · 앨범 목록
    SnapRow opt(int i, String icon, String title, String sub, [int? go]) =>
        SnapRow(
          leading: IconBadge(icon),
          title: title,
          subtitle: sub,
          checked: s.scopeSelection == i,
          onTap: () {
            s.scopeSelection = i;
            go != null ? s.go(go) : s.touch();
          },
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '사진 접근 범위', onBack: () => s.go(0)),
        const SnapH2('어떤 사진을\n허용할까요?'),
        SnapGroup(
          children: [
            opt(
              0,
              'image',
              '전체 사진',
              s.useLibrary ? '${s.libraryCount}장' : '3,420장',
            ),
            opt(
              1,
              'folder',
              '앨범 선택',
              s.useLibrary && s.selectedAlbumIds.isNotEmpty
                  ? '앨범 ${s.selectedAlbumIds.length}개 · ${s.selectedAlbumPhotoCount}장'
                  : '원하는 앨범만',
            ),
            opt(2, 'select', '사진 직접 고르기', '눌러서 하나씩 선택', 2),
            opt(3, 'calendar', '기간 지정', '2022.01 ~ 지금'),
          ],
        ),
        // iOS: '앨범 선택'이면 기기 사진 보관함의 실제 앨범 목록 (여러 개 선택)
        if (s.useLibrary && s.scopeSelection == 1) ...[
          const SnapH3('분석할 앨범을 골라 주세요 · 여러 개 선택 가능', small: true),
          if (s.libraryAlbumsLoading && s.libraryAlbums.isEmpty)
            const SnapNote('앨범을 불러오는 중…', top: 0)
          else if (s.libraryAlbums.isEmpty)
            const SnapNote('사진이 들어 있는 앨범이 없어요', top: 0)
          else
            SnapGroup(
              top: 0,
              separatorInset: 58,
              children: [
                for (final a in s.libraryAlbums)
                  SnapRow(
                    leading: IconBadge(
                      'folder',
                      size: 40,
                      radius: 8,
                      image: a.cover == null
                          ? null
                          : AssetEntityImageProvider(
                              a.cover!,
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize.square(160),
                            ),
                    ),
                    title: a.path.name,
                    subtitle: '${a.count}장',
                    checked: s.selectedAlbumIds.contains(a.path.id),
                    onTap: () => s.toggleLibraryAlbum(a.path.id),
                  ),
              ],
            ),
        ],
        if (s.libraryDenied) ...[
          const SnapWarn('사진 보관함 접근이 허용되지 않았어요. 설정에서 사진 접근을 허용해 주세요.'),
          SnapButton(label: '설정 열기', ghost: true, onTap: s.openLibrarySettings),
        ],
        if (s.useLibrary &&
            s.libraryPermission?.isAuth == false &&
            !s.libraryDenied)
          SnapNote('일부 사진만 허용됨 · 허용한 사진 안에서 분석해요', color: c.mute),
        if (s.useLibrary && s.scopeSelection == 1 && s.selectedAlbumIds.isEmpty)
          const SnapButton(label: '앨범을 하나 이상 골라 주세요', onTap: null)
        else
          SnapButton(label: '다음', onTap: () => s.go(3)),
      ],
    );
  }
}

/// ②′ 사진 직접 고르기
class Screen2PickPhotos extends StatelessWidget {
  const Screen2PickPhotos({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    if (s.useLibrary) return _LibraryPicker(state: s);
    final n = s.pickQueue.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '사진 선택',
          onBack: () => s.go(1),
          trailing: Text('$n장', style: TextStyle(fontSize: 12, color: c.pk)),
        ),
        SnapButton(
          label: '분석할 사진 선택',
          icon: 'camera',
          ghost: true,
          top: 14,
          onTap: () => s.pickPhotosFromGallery(),
        ),
        SnapNote(n == 0 ? '선택한 사진: 0장' : '선택한 사진: $n장 (이미 분석한 사진은 건너뛰어요)'),
        SnapButton(label: '다음', onTap: () => s.go(3)),
      ],
    );
  }
}

/// ② 분석 순서
class Screen3Order extends StatelessWidget {
  const Screen3Order({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    SnapRow opt(int i, String icon, String title, String sub) => SnapRow(
      leading: IconBadge(icon),
      title: title,
      subtitle: sub,
      checked: s.orderSelection == i,
      onTap: () {
        s.orderSelection = i;
        s.touch();
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '분석 순서', onBack: () => s.go(1)),
        const SnapH2('어디부터\n돌아볼까요?'),
        const SnapSub('먼저 분석된 사진부터 바로 검색할 수 있어요.'),
        SnapGroup(
          children: [
            opt(0, 'sprout', '최근 사진부터', '요즘 찍은 사진을 먼저'),
            opt(1, 'history', '오래된 사진부터', '2022년부터 차근차근'),
            opt(2, 'target', '지정 기간 우선', '고른 기간을 먼저 분석'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final y in const ['2026', '2025', '2024', '2023', '2022'])
                SnapChip(
                  label: y,
                  selected: s.priorityYear == y,
                  onTap: () {
                    s.priorityYear = y;
                    s.touch();
                  },
                ),
            ],
          ),
        ),
        SnapButton(
          label: '분석 시작',
          onTap: () async {
            // iOS: 접근 범위 + 분석 순서 기준으로 사진 보관함에서 대기열을 만든다
            if (s.useLibrary) {
              await s.queueFromLibrary();
              if (s.libraryDenied) return;
            }
            // 전체 화면 대신 홈으로 — 진행 상황은 하단 진행 바에서 확인
            s.go(5);
            s.startAnalysis();
          },
        ),
        if (s.libraryDenied) const SnapWarn('사진 보관함 접근이 허용되지 않아 분석할 수 없어요.'),
        if (s.useLibrary) const SnapNote('한 번에 최대 300장까지 분석해요'),
      ],
    );
  }
}

/// 분석 진행 공통 계산 (진행 화면 · 미니 카드가 함께 사용)
class AnalysisView {
  AnalysisView(SnapbackState s)
    : tot = s.analysisTotal,
      dn = s.analysisDone,
      paused = s.analysisPaused,
      done = s.analysisFinished && s.analysisTotal > 0;

  final int tot;
  final int dn;
  final bool paused;
  final bool done;

  int get pct => tot > 0 ? (dn / tot * 100).round().clamp(0, 100) : 0;
  double get p => pct / 100;
  RunnerMode get mode => done
      ? RunnerMode.done
      : (paused || tot == 0 ? RunnerMode.idle : RunnerMode.run);
}

/// ② 분석 진행
class Screen4Progress extends StatelessWidget {
  const Screen4Progress({super.key, required this.state});
  final SnapbackState state;

  String _eta(SnapbackState s, AnalysisView v) {
    if (v.done) return '완료';
    if (v.tot == 0 || s.etaMs <= 0) return '-';
    return '~${math.max(1, (s.etaMs / 60000).round())}분';
  }

  String _year(SnapbackState s, AnalysisView v) {
    if (v.tot == 0) return '먼저 사진을 선택해 주세요';
    if (v.done) return '모든 사진을 기억했어요';
    final d = s.currentFileDate;
    if (d != null) return '${d.year}년 ${d.month}월을 돌아보는 중';
    return '시작합니다';
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    final v = AnalysisView(s);
    final status = v.tot == 0
        ? '대기 중'
        : v.done
        ? '완료!'
        : (v.paused ? '일시정지' : '분석 중');
    final years = s.yearProgress();
    final keys = years.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '분석 진행', onBack: () => s.go(5)),
        // .ring — 160, conic(pri p%, line), 안쪽 134 원(bg)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 160,
              height: 160,
              child: CustomPaint(
                painter: _RingPainter(v.p, c.pri, c.line),
                child: Center(
                  child: Container(
                    width: 134,
                    height: 134,
                    decoration: BoxDecoration(
                      color: c.bg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${v.pct}%',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          status,
                          style: TextStyle(fontSize: 12, color: c.mute),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // .trk — 92 높이, margin 4 8 0, 선 bottom 8 h7, 깃발, 달리는 캐릭터
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: LayoutBuilder(
            builder: (_, k) => SizedBox(
              height: 92,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        height: 7,
                        color: c.line,
                        alignment: Alignment.centerLeft,
                        child: AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 600),
                          widthFactor: v.p,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              gradient: LinearGradient(
                                colors: [const Color(0xFFF4A574), c.pri],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -6,
                    bottom: 12,
                    child: SnapIcon('flag', size: 23, color: c.ink),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 600),
                    left: (k.maxWidth - 66) * v.p,
                    bottom: 12,
                    child: SnapRunner(mode: v.mode),
                  ),
                ],
              ),
            ),
          ),
        ),
        SnapSub(_year(s, v), center: true),
        StatBoxes(
          items: [('${v.dn}', ' 완료 / ${v.tot}'), (_eta(s, v), '남은 시간')],
        ),
        const SnapH3('시기별 진행'),
        if (keys.isEmpty)
          const SnapNote('아직 선택한 사진이 없어요', top: 0)
        else
          for (final y in keys) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Row(
                children: [
                  Text(y, style: TextStyle(fontSize: 12, color: c.ink)),
                  const Spacer(),
                  Text(
                    '${years[y]![0]}/${years[y]![1]}',
                    style: TextStyle(fontSize: 12, color: c.mute),
                  ),
                ],
              ),
            ),
            SnapBar(value: years[y]![1] == 0 ? 0 : years[y]![0] / years[y]![1]),
          ],
        const SnapH3('잠금화면에서도 보여요'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6B3418), Color(0xFFE0753A)],
            ),
          ),
          child: Row(
            children: [
              const SnapCharacter(size: 46),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${v.pct}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      '사진을 분석하고 있어요…',
                      style: TextStyle(fontSize: 11, color: Color(0xCCFFFFFF)),
                    ),
                    const SizedBox(height: 5),
                    SnapBar(
                      value: v.p,
                      background: const Color(0x33FFFFFF),
                      color: const Color(0xFFFFD2B0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SnapButton(
          label: v.paused ? '이어서 분석' : '일시정지',
          ghost: true,
          onTap: s.togglePauseAnalysis,
        ),
        SnapButton(label: '분석된 사진 먼저 보기', onTap: () => s.go(5)),
        const SnapNote('중단돼도 완료한 지점부터 이어서 분석해요 · 잠금화면에서 진행률 확인'),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.p, this.color, this.track);
  final double p;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawOval(r, Paint()..color = track);
    if (p > 0) {
      canvas.drawArc(
        r,
        -math.pi / 2,
        2 * math.pi * p,
        true,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.p != p || old.color != color || old.track != track;
}

/// iOS ②′ 사진 직접 고르기 — 사진 보관함 그리드에서 눌러서 선택 (.ph.sel)
class _LibraryPicker extends StatelessWidget {
  const _LibraryPicker({required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    if (s.pickerAssets.isEmpty && !s.pickerLoading && !s.libraryDenied) {
      Future.microtask(s.loadPickerAssets);
    }
    final n = s.pickedAssetIds.length;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '사진 선택',
          onBack: () => s.go(1),
          trailing: Text('$n장', style: TextStyle(fontSize: 12, color: c.pk)),
        ),
        if (s.libraryDenied) ...[
          const SnapWarn('사진 보관함 접근이 허용되지 않았어요.'),
          SnapButton(label: '설정 열기', ghost: true, onTap: s.openLibrarySettings),
        ] else ...[
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 10),
            child: SnapSub('분석할 사진을 눌러서 고르세요.'),
          ),
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: s.pickerAssets.length,
            itemBuilder: (_, i) {
              final a = s.pickerAssets[i];
              final on = s.pickedAssetIds.contains(a.id);
              return GestureDetector(
                onTap: () => s.togglePickAsset(a.id),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image(
                        image: AssetEntityImageProvider(
                          a,
                          isOriginal: false,
                          thumbnailSize: ThumbnailSize.square(
                            (130 * dpr).round(),
                          ),
                        ),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(color: c.fill),
                      ),
                    ),
                    if (on)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: c.pri, width: 3),
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 5,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: on ? c.pri : const Color(0x99FFFFFF),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: on
                            ? const SnapIcon(
                                'check',
                                size: 12,
                                color: Colors.white,
                                strokeWidth: 2.6,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (s.pickerLoading) const SnapNote('사진을 불러오는 중…'),
          if (s.pickerHasMore && !s.pickerLoading)
            SnapButton(
              label: '더 보기',
              ghost: true,
              onTap: () => s.loadPickerAssets(more: true),
            ),
          SnapButton(
            label: n == 0 ? '사진을 골라 주세요' : '선택 완료 ($n장)',
            onTap: n == 0 ? null : s.confirmPickedAssets,
          ),
        ],
      ],
    );
  }
}
