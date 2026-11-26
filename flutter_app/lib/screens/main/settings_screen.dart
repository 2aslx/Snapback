part of '../main_screens.dart';

// 설정 · 사진 다시 분석하기

/// ⑥ 설정 · 개인정보
class Screen12Settings extends StatefulWidget {
  const Screen12Settings({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen12Settings> createState() => _Screen12SettingsState();
}

class _Screen12SettingsState extends State<Screen12Settings> {
  late final _url = TextEditingController(text: widget.state.serverUrl);

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final counts = <String, int>{};
    for (final d in s.db) {
      final y = d.date.substring(0, 4);
      counts[y] = (counts[y] ?? 0) + 1;
    }
    final years = counts.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '설정 · 개인정보', onBack: () => s.go(5)),
        const SnapH3('접근 범위 (연도별)', small: true),
        SnapGroup(
          top: 0,
          separatorInset: 14,
          children: [
            for (final y in years)
              SnapRow(
                leading: SnapIcon('calendar', size: 18.4, color: c.ink),
                title: '$y년 사진 (${counts[y]}장)',
                trailing: SnapSwitch(
                  value: !s.db.any((d) => d.date.startsWith(y) && d.hidden),
                  onChanged: (_) => s.toggleYearVisibility(y),
                ),
              ),
          ],
        ),
        if (s.hiddenWarning.isNotEmpty) SnapWarn(s.hiddenWarning),
        const SnapH3('분석', small: true),
        SnapGroup(
          top: 0,
          separatorInset: 14,
          children: [
            SnapRow(
              leading: SnapIcon('battery', size: 18.4, color: c.ink),
              title: '백그라운드 분석',
              trailing: SnapSwitch(
                value: s.backgroundAnalysis,
                onChanged: (v) {
                  s.backgroundAnalysis = v;
                  s.touch();
                },
              ),
            ),
            SnapRow(
              leading: SnapIcon('refresh', size: 18.4, color: c.ink),
              title: '분석 순서 다시 선택',
              trailing: const Chevron(),
              onTap: () => s.go(3),
            ),
          ],
        ),
        _RelabelSection(state: s),
        // Flutter 추가: iOS 앱이 연결할 API 서버 주소
        const SnapH3('서버', small: true),
        SnapSearchBar(
          controller: _url,
          showIcon: false,
          hint: '비우면 기본 서버',
          buttonIcon: 'check',
          keyboardType: TextInputType.url,
          onSubmit: () => s.setServerUrl(_url.text),
        ),
        if (s.aiStatusText.isNotEmpty) SnapNote(s.aiStatusText),
        // OpenStreetMap 이용 조건: 출처 표시
        const SnapNote('촬영 장소 주소: © OpenStreetMap 기여자'),
        // 앱 초기화 (확인 팝업)
        const SnapH3('초기화', small: true),
        Pressable(
          onTap: () async {
            final ok = await showSnapConfirm(
              context,
              title: '앱을 초기화할까요?',
              message: '분석한 사진 정보, 앨범, 기록, 찾은 사진이 모두 지워지고\n처음 화면으로 돌아가요.\n사진 앱의 원본 사진은 지워지지 않아요.',
              confirmLabel: '초기화',
            );
            if (ok) await s.resetAll();
          },
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 50),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD93A2B)),
            ),
            child: const Text(
              '앱 초기화',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFFD93A2B),
              ),
            ),
          ),
        ),
        const SnapNote('모든 분석 정보·앨범·기록을 지우고 처음부터 다시 시작해요'),
      ],
    );
  }
}

/// 설정 > 사진 다시 분석하기: 이미 분석한 사진의 설명을 새로 만든다 (두 번 눌러 시작)
class _RelabelSection extends StatefulWidget {
  const _RelabelSection({required this.state});
  final SnapbackState state;

  @override
  State<_RelabelSection> createState() => _RelabelSectionState();
}

class _RelabelSectionState extends State<_RelabelSection> {
  bool _confirm = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final n = s.relabelTargets.length;
    final busy = s.analysisRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapGroup(
          top: 12,
          children: [
            SnapRow(
              leading: const IconBadge('sparkle'),
              title: s.relabelRunning
                  ? '다시 분석하는 중 · ${s.relabelDone} / ${s.relabelTotal}장'
                  : _confirm
                  ? '한 번 더 누르면 $n장을 다시 분석해요'
                  : '사진 다시 분석하기',
              subtitle: s.relabelRunning
                  ? '앱을 쓰는 동안 계속 진행돼요'
                  : '분석한 사진 $n장의 설명을 최신 AI로 새로 만들어요',
              trailing: s.relabelRunning
                  ? Pressable(
                      onTap: s.cancelRelabel,
                      child: Text(
                        '중지',
                        style: TextStyle(fontSize: 15, color: c.pk),
                      ),
                    )
                  : const Chevron(),
              onTap: s.relabelRunning || n == 0 || busy
                  ? null
                  : () {
                      if (_confirm) {
                        _confirm = false;
                        s.relabelAll();
                      } else {
                        setState(() => _confirm = true);
                      }
                    },
            ),
          ],
        ),
        if (s.relabelRunning)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
            child: SnapBar(
              value: s.relabelTotal == 0 ? 0 : s.relabelDone / s.relabelTotal,
              background: c.fill,
              color: c.pri,
            ),
          ),
        if (s.relabelFinished && !s.relabelRunning)
          SnapNote(
            [
              '다시 분석 완료: ${s.relabelDone - s.relabelSkipped - s.relabelFailed}장',
              if (s.relabelSkipped > 0) '원본을 찾을 수 없어 건너뜀 ${s.relabelSkipped}장',
              if (s.relabelFailed > 0) '실패 ${s.relabelFailed}장',
            ].join(' · '),
          ),
        if (busy && !s.relabelRunning)
          const SnapNote('사진 분석이 끝난 뒤에 다시 분석할 수 있어요'),
        if (n == 0) const SnapNote('아직 분석한 사진이 없어요'),
        if (!s.relabelRunning && !s.relabelFinished && n > 0 && !busy)
          const SnapNote('사진·앨범·기록은 그대로 두고 설명만 바꿔요 · 기록과 앨범도 그대로예요'),
      ],
    );
  }
}
