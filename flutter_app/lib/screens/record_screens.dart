import 'package:material_ui/material_ui.dart';

import '../models/photo_item.dart';
import '../models/photo_record.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/snap_runner.dart';

// 기록으로 남기기: 사진 상세 → ⑳ 기록 다듬기 → ㉑ 나의 기록

// ── 공용 조각 ─────────────────────────────────────────────

/// 관련된 추억 타일 — 아이콘 + 이름 + "사진 N장" (따뜻한/차분한 두 가지 톤)
class RelatedTile extends StatelessWidget {
  const RelatedTile({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
    this.cool = false,
    this.onTap,
  });

  final String icon;
  final String title;
  final int count;
  final bool cool;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = cool
        ? (dark ? const Color(0xFF24323A) : const Color(0xFFE4ECEE))
        : Color.lerp(c.pri, c.card, dark ? 0.8 : 0.84)!;
    final fg = cool ? const Color(0xFF5E7C88) : c.pk;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            SnapIcon(icon, size: 30, color: fg, strokeWidth: 1.6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '사진 $count장',
                    style: TextStyle(fontSize: 13, color: c.mute),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 흰 카드 안의 '아이콘 · 이름 · 값' 정보 줄들
class InfoRows extends StatelessWidget {
  const InfoRows({super.key, required this.rows, this.actions = const {}});
  final List<(String, String, String)> rows; // (아이콘, 이름, 값)

  /// 줄 이름 → 눌렀을 때 동작 (예: '촬영 장소' → 지도 팝업). 있으면 오른쪽에 '지도' 표시.
  final Map<String, VoidCallback> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Container(height: 0.5, color: c.line),
            ),
          Pressable(
            onTap: actions[rows[i].$2],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 9, left: 4, right: 18),
                    child: SnapIcon(rows[i].$1, size: 22, color: c.mute),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].$2,
                          style: TextStyle(fontSize: 13, color: c.mute),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          keepWords(rows[i].$3),
                          style: TextStyle(fontSize: 16, color: c.ink),
                        ),
                      ],
                    ),
                  ),
                  if (actions[rows[i].$2] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, left: 8),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(9, 4, 6, 4),
                        decoration: BoxDecoration(
                          color: c.soft,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '지도',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: c.pk,
                              ),
                            ),
                            const SizedBox(width: 2),
                            SnapIcon('next', size: 13, color: c.pk),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 흰 둥근 카드
class SnapCard extends StatelessWidget {
  const SnapCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 6),
    decoration: BoxDecoration(
      color: context.sc.card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

/// 둥근 사진 카드 (사진 상세 · 나의 기록 맨 위): 가로 폭에 맞추고 높이는 사진 비율대로, 자르지 않음
class RoundedPhoto extends StatelessWidget {
  const RoundedPhoto({
    super.key,
    required this.item,
    this.height = 270,
    this.overlay = const [],
  });
  final PhotoItem item;

  /// 비율을 아직 모를 때의 높이
  final double height;
  final List<Widget> overlay;

  @override
  Widget build(BuildContext context) =>
      FullWidthPhoto(item: item, fallbackHeight: height, overlay: overlay);
}

String _typeLine(PhotoRecord r) => switch (r.type) {
  'place' => [
    if (r.kind.isNotEmpty) r.kind,
    if (r.date.isNotEmpty) r.date,
  ].join(' · '),
  'document' => ['문서', if (r.date.isNotEmpty) r.date].join(' · '),
  _ => ['추억', if (r.date.isNotEmpty) r.date].join(' · '),
};

String _typeIcon(PhotoRecord r) =>
    r.type == 'place' ? placeKindIcon(r.kind) : recordTypeOf(r.type).icon;

// ── ⑳ 기록 다듬기 ─────────────────────────────────────────

class Screen20RecordEdit extends StatelessWidget {
  const Screen20RecordEdit({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final d = s.recordDraft;
    if (d == null) {
      return Column(
        children: [
          SnapbackTopBar(title: '기록 다듬기', onBack: () => s.go(10)),
          const SnapEmpty(icon: 'bookmark', text: '다듬을 기록이 없어요'),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '기록 다듬기', onBack: s.cancelRecordDraft),
        if (s.recordBusy)
          const _DraftLoading()
        else
          _RecordForm(key: ValueKey(s.recordDraftVersion), state: s, draft: d),
      ],
    );
  }
}

class _DraftLoading extends StatelessWidget {
  const _DraftLoading();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 80),
    child: Center(
      child: Column(
        children: [
          const SnapRunner(width: 72, mode: RunnerMode.run),
          const SizedBox(height: 14),
          Text(
            'AI가 사진을 보고 기록 초안을 만드는 중…',
            style: TextStyle(fontSize: 15, color: context.sc.mute),
          ),
        ],
      ),
    ),
  );
}

class _RecordForm extends StatefulWidget {
  const _RecordForm({super.key, required this.state, required this.draft});
  final SnapbackState state;
  final PhotoRecord draft;

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  late final PhotoRecord d = widget.draft;
  late final _title = TextEditingController(text: d.title);
  late final _loc = TextEditingController(text: d.location);
  late final _date = TextEditingController(text: d.date);
  late final _lines = TextEditingController(text: d.lines.join('\n'));
  late final _summary = TextEditingController(text: d.summary);
  late final _memo = TextEditingController(text: d.memo);
  bool _kindOpen = false;

  @override
  void dispose() {
    for (final x in [_title, _loc, _date, _lines, _summary, _memo]) {
      x.dispose();
    }
    super.dispose();
  }

  /// 입력값을 초안에 옮긴 뒤 저장
  void _save() {
    final nextLines = _lines.text
        .split('\n')
        .map((x) => x.replaceFirst(RegExp(r'^\s*[•·\-]\s*'), '').trim())
        .where((x) => x.isNotEmpty)
        .toList();
    d
      ..title = _title.text.trim()
      ..location = _loc.text.trim()
      ..date = _date.text.trim()
      ..lines = nextLines
      ..checkedLines = d.checkedLines
          .where((i) => i >= 0 && i < nextLines.length)
          .toList()
      ..summary = _summary.text.trim()
      ..memo = _memo.text.trim();
    widget.state.saveRecordDraft();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final type = recordTypeOf(d.type);
    final photo = s.photoById(d.photoId);
    final warm = Color.lerp(c.pri, c.card, 0.86)!;
    final isDoc = d.type == 'document';
    final isPlace = d.type == 'place';

    Widget field(String label, Widget input) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: TextStyle(fontSize: 15, color: c.mute)),
          ),
          Expanded(child: input),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 민감정보 동의
        if (d.sensitiveType != null)
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: warm,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.pri.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SnapIcon('shield', size: 24, color: c.pk),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '민감한 ${d.sensitiveType} 확인 및 동의가 필요해요',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: c.pk,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '개인의 민감한 ${d.sensitiveType}가 포함된 이미지입니다. '
                  'AI가 추출한 내용이 정확한지 직접 확인하고, 저장에 동의해 주세요. '
                  '기록은 이 기기에만 저장돼요.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: c.ink),
                ),
                const SizedBox(height: 10),
                Pressable(
                  onTap: () => s.setRecordConsent(!s.recordConsent),
                  child: Row(
                    children: [
                      _CheckBox(on: s.recordConsent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '위 내용을 확인했으며, 내 ${d.sensitiveType}를 기록으로 저장하는 것에 동의합니다.',
                          style: TextStyle(fontSize: 12.5, color: c.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        // 사진 + 기록 종류
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null)
              SizedBox(
                width: 108,
                height: 108,
                child: PhotoTile(item: photo, radius: 14, showDate: false),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 108),
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                decoration: BoxDecoration(
                  color: warm,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SnapIcon(type.icon, size: 22, color: c.pk),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            type.label,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: c.pk,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      type.desc,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: c.mute,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // 기록 종류 세 가지를 항상 나란히 보여 주고 고르게 한다
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              for (final t in kRecordTypes) ...[
                if (t != kRecordTypes.first) const SizedBox(width: 8),
                Expanded(
                  child: Pressable(
                    onTap: () => s.setRecordType(t.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: t.id == d.type ? c.pri : c.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: t.id == d.type ? c.pri : c.line,
                        ),
                      ),
                      child: Column(
                        children: [
                          SnapIcon(
                            t.icon,
                            size: 20,
                            color: t.id == d.type ? Colors.white : c.ink,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.label,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: t.id == d.type ? Colors.white : c.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              SnapIcon(
                s.recordError == null ? 'sparkle' : 'alert',
                size: 18,
                color: s.recordError == null ? c.pri : c.mute,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.recordError ?? 'AI가 추출한 내용이에요. 확인하고 수정해 주세요.',
                  style: TextStyle(fontSize: 14, color: c.ink),
                ),
              ),
            ],
          ),
        ),
        // 종류별 입력칸
        field(
          isDoc ? '문서 제목' : (isPlace ? '장소 이름' : '제목'),
          _Input(controller: _title),
        ),
        if (isPlace) field('위치', _Input(controller: _loc, icon: 'pin')),
        field(
          isDoc ? '문서 날짜' : (isPlace ? '방문 날짜' : '날짜'),
          _Input(controller: _date, icon: 'calendar', hint: 'YYYY-MM-DD'),
        ),
        if (isPlace) ...[
          field(
            '장소 유형',
            Pressable(
              onTap: () => setState(() => _kindOpen = !_kindOpen),
              child: _Box(
                child: Row(
                  children: [
                    SnapIcon(placeKindIcon(d.kind), size: 20, color: c.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d.kind.isEmpty ? '기타' : d.kind,
                        style: TextStyle(fontSize: 16, color: c.ink),
                      ),
                    ),
                    SnapIcon('down', size: 18, color: c.mute),
                  ],
                ),
              ),
            ),
          ),
          if (_kindOpen)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 84),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in kPlaceKinds)
                    SnapChip(
                      label: k.$1,
                      icon: k.$2,
                      accent: true,
                      selected: d.kind == k.$1,
                      onTap: () => setState(() {
                        d.kind = k.$1;
                        _kindOpen = false;
                      }),
                    ),
                ],
              ),
            ),
        ],
        if (isDoc) ...[
          const _Label('추출된 주요 텍스트'),
          _Input(controller: _lines, lines: 6, edit: true, hint: '한 줄에 하나씩'),
          const _Label('핵심 정보 요약 (AI)'),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
            decoration: BoxDecoration(
              color: warm,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SnapIcon('sparkle', size: 20, color: c.pri),
                ),
                Expanded(
                  child: _Input(
                    controller: _summary,
                    lines: 3,
                    edit: true,
                    bare: true,
                  ),
                ),
              ],
            ),
          ),
        ],
        _Label(isDoc ? '개인 메모' : '메모'),
        _Input(
          controller: _memo,
          lines: 4,
          hint: isDoc ? '이 문서에 대해 남기고 싶은 말' : '이날의 기억을 짧게 남겨 보세요',
        ),
        if (!isDoc)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SnapCard(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Row(
                children: [
                  SnapIcon('star', size: 22, color: c.pri),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '즐겨찾기 추가',
                      style: TextStyle(fontSize: 16, color: c.ink),
                    ),
                  ),
                  SnapSwitch(
                    value: d.favorite,
                    onChanged: (v) => setState(() => d.favorite = v),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: SnapButton(
                label: '취소',
                ghost: true,
                onTap: s.cancelRecordDraft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: SnapButton(
                label: '기록 저장하기',
                onTap: s.canSaveRecord ? _save : null,
              ),
            ),
          ],
        ),
        if (d.sensitiveType != null && !s.recordConsent)
          const SnapNote('위의 동의에 체크하면 저장할 수 있어요'),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(text, style: TextStyle(fontSize: 15, color: context.sc.mute)),
  );
}

/// 테두리 있는 입력 상자
class _Box extends StatelessWidget {
  const _Box({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: context.sc.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.sc.line),
    ),
    child: child,
  );
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    this.icon,
    this.hint = '',
    this.lines = 1,
    this.edit = false,
    this.bare = false,
  });

  final TextEditingController controller;
  final String? icon;
  final String hint;
  final int lines;

  /// 오른쪽 위 연필 표시 (AI 추출 내용 수정 가능)
  final bool edit;

  /// 테두리 없이 (요약 상자 안)
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final field = TextField(
      controller: controller,
      // 입력칸 밖(화면 다른 곳)을 누르면 키보드를 내린다
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 4,
      style: TextStyle(fontSize: 16, height: 1.45, color: c.ink),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: hint,
        hintStyle: TextStyle(color: c.mute),
        contentPadding: EdgeInsets.symmetric(vertical: bare ? 10 : 0),
      ),
    );
    final row = Row(
      crossAxisAlignment: lines == 1
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          SnapIcon(icon!, size: 20, color: c.ink),
          const SizedBox(width: 8),
        ],
        Expanded(child: field),
        if (edit)
          Container(
            margin: const EdgeInsets.only(left: 6),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: c.line),
            ),
            alignment: Alignment.center,
            child: SnapIcon('pencil', size: 17, color: c.ink),
          ),
      ],
    );
    return bare ? row : _Box(child: row);
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: on ? c.pri : c.card,
        borderRadius: BorderRadius.circular(6),
        border: on ? null : Border.all(color: c.mute),
      ),
      alignment: Alignment.center,
      child: on
          ? const SnapIcon(
              'check',
              size: 15,
              color: Colors.white,
              strokeWidth: 2.6,
            )
          : null,
    );
  }
}

// ── ㉑ 나의 기록 ─────────────────────────────────────────

class Screen21RecordView extends StatefulWidget {
  const Screen21RecordView({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen21RecordView> createState() => _Screen21RecordViewState();
}

class _Screen21RecordViewState extends State<Screen21RecordView> {
  bool _menu = false;
  bool _confirmDelete = false;
  bool _allLinked = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final r = s.recordById(s.activeRecordId);
    void back() =>
        s.go(const {20, 21}.contains(s.recordReturn) ? 19 : s.recordReturn);
    if (r == null) {
      return Column(
        children: [
          SnapbackTopBar(title: '나의 기록', onBack: back),
          const SnapEmpty(icon: 'bookmark', text: '기록을 찾을 수 없어요'),
        ],
      );
    }
    final photo = s.photoById(r.photoId);
    final linked = [
      for (final id in r.linkedPhotoIds)
        if (s.photoById(id) case final p? when !p.hidden) p,
    ];
    final rows = <(String, String, String)>[
      if (r.type == 'place') ...[
        if (r.location.isNotEmpty) ('pin', '위치', r.location),
        if (r.date.isNotEmpty) ('calendar', '방문 날짜', r.date),
        ('tag', '장소 유형', r.kind.isEmpty ? '기타' : r.kind),
      ] else ...[
        if (r.date.isNotEmpty)
          ('calendar', r.type == 'document' ? '문서 날짜' : '날짜', r.date),
        if (r.sensitiveType != null && r.consentAtMs != null)
          (
            'shield',
            '민감정보',
            () {
              final t = DateTime.fromMillisecondsSinceEpoch(r.consentAtMs!);
              return '${r.sensitiveType} · ${t.year}.${t.month}.${t.day} 저장 동의';
            }(),
          ),
      ],
    ];
    final shownLinked = _allLinked || linked.length <= 3
        ? linked
        : linked.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '나의 기록', onBack: back),
        if (photo != null)
          RoundedPhoto(
            item: photo,
            height: 250,
            overlay: [
              // 즐겨찾기
              Positioned(
                top: 12,
                left: 12,
                child: Pressable(
                  onTap: () => s.toggleRecordFavorite(r.id),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                    decoration: BoxDecoration(
                      color: const Color(0xE6FFFFFF),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SnapIcon(
                          r.favorite ? 'star-fill' : 'star',
                          size: 16,
                          color: const Color(0xFFE0A030),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          r.favorite ? '즐겨찾기' : '즐겨찾기 추가',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ⋮ 메뉴
              Positioned(
                top: 6,
                right: 4,
                child: Pressable(
                  onTap: () => setState(() {
                    _menu = !_menu;
                    _confirmDelete = false;
                  }),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: SnapIcon('more', size: 24, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        if (_menu)
          SnapGroup(
            top: 8,
            children: [
              SnapRow(
                leading: const IconBadge('pencil'),
                title: '기록 수정',
                onTap: () {
                  _menu = false;
                  s.editRecord(r.id);
                },
              ),
              if (photo != null)
                SnapRow(
                  leading: const IconBadge('image'),
                  title: '사진 보기',
                  onTap: () {
                    _menu = false;
                    s.openMemory(photo.id);
                  },
                ),
              SnapRow(
                leading: const IconBadge('close'),
                title: _confirmDelete ? '한 번 더 누르면 삭제돼요' : '기록 삭제',
                onTap: () {
                  if (_confirmDelete) {
                    s.deleteRecord(r.id);
                    back();
                  } else {
                    setState(() => _confirmDelete = true);
                  }
                },
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            r.title,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: c.ink,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              SnapIcon(_typeIcon(r), size: 18, color: c.mute),
              const SizedBox(width: 6),
              Text(_typeLine(r), style: TextStyle(fontSize: 15, color: c.mute)),
            ],
          ),
        ),
        if (r.memo.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.fill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              keepWords(r.memo),
              style: TextStyle(fontSize: 16, height: 1.5, color: c.ink),
            ),
          ),
        if (r.type == 'document' && r.lines.isNotEmpty) ...[
          SnapH3(
            r.checkedLines.isEmpty
                ? '추출된 주요 항목 (${r.lines.length})'
                : '추출된 주요 항목 (${r.checkedLines.length}/${r.lines.length} 완료)',
            small: true,
          ),
          SnapCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < r.lines.length; i++)
                  Pressable(
                    onTap: () => s.toggleRecordLine(r.id, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1, right: 10),
                            child: _CheckBox(on: r.checkedLines.contains(i)),
                          ),
                          Expanded(
                            child: Text(
                              keepWords(r.lines[i]),
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: r.checkedLines.contains(i)
                                    ? c.mute
                                    : c.ink,
                                decoration: r.checkedLines.contains(i)
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (r.type == 'document' && r.summary.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Color.lerp(c.pri, c.card, 0.86),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SnapIcon('sparkle', size: 20, color: c.pri),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    keepWords(r.summary),
                    style: TextStyle(fontSize: 15, height: 1.45, color: c.ink),
                  ),
                ),
              ],
            ),
          ),
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SnapCard(child: InfoRows(rows: rows)),
          ),
        if (linked.isNotEmpty) ...[
          const SnapH3('연결된 사진'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.2,
            children: [
              for (final p in shownLinked)
                PhotoTile(
                  item: p,
                  radius: 12,
                  showDate: false,
                  onTap: () => s.openMemory(p.id),
                ),
              if (shownLinked.length < linked.length)
                Pressable(
                  onTap: () => setState(() => _allLinked = true),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PhotoTile(item: linked[2], radius: 12, showDate: false),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x73000000),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      Center(
                        child: Text(
                          '+${linked.length - 2}',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 기억 탭의 '나의 기록' 가로 목록
class RecordStrip extends StatelessWidget {
  const RecordStrip({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    final list = [...s.records]
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return b.createdAtMs.compareTo(a.createdAtMs);
      });
    return Bleed(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in list)
              if (s.photoById(r.photoId) case final p?)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Pressable(
                    onTap: () => s.openRecord(r.id),
                    child: SizedBox(
                      width: 148,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 110,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                PhotoTile(item: p, radius: 12, showDate: false),
                                if (r.favorite)
                                  const Positioned(
                                    top: 6,
                                    left: 6,
                                    child: SnapIcon(
                                      'star-fill',
                                      size: 18,
                                      color: Color(0xFFFFC14D),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            r.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            _typeLine(r),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.mute),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ── ㉒ 기록 탭 ─────────────────────────────────────────────
/// 하단 '기록' 탭: 기록으로 남긴 사진 모음. 위에 '즐겨찾기', 아래 '모든 기록'.
/// 카드의 별을 누르면 즐겨찾기가 켜지고 꺼지며, 켜진 기록은 위 '즐겨찾기'로 올라간다.
/// 기록 탭 정렬·보기 기준 (id, 이름)
const kRecordViews = [
  ('genre', '장르별 정렬'),
  ('default', '기본 정렬'),
  ('fav', '즐겨찾기'),
  ('moment', '추억 기록'),
  ('place', '장소 기록'),
  ('document', '문서 기록'),
];

class Screen22Records extends StatelessWidget {
  const Screen22Records({super.key, required this.state});
  final SnapbackState state;

  /// 오른쪽 위 정렬 기준 고르기 (팝업)
  Future<void> _pickView(BuildContext context) async {
    final s = state;
    final c = context.sc;
    final picked = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (ctx) => Dialog(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  '정렬 기준',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              for (final (id, label) in kRecordViews)
                Pressable(
                  onTap: () => Navigator.of(ctx).pop(id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: s.recordsView == id
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: s.recordsView == id ? c.pk : c.ink,
                            ),
                          ),
                        ),
                        if (s.recordsView == id)
                          SnapIcon('check', size: 18, color: c.pk),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) s.setRecordsView(picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    final byNew = [...s.records]
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    Widget grid(List<PhotoRecord> list) => AlbumCardGrid(
      children: [for (final r in list) _RecordCard(state: s, record: r)],
    );
    final view = s.recordsView;
    final viewLabel = kRecordViews
        .firstWhere((v) => v.$1 == view, orElse: () => kRecordViews[1])
        .$2;

    final sections = <Widget>[];
    switch (view) {
      case 'genre':
        // 장르별: 추억 · 장소 · 문서 순으로 묶어서 (각 묶음 안에서는 즐겨찾기 먼저)
        for (final t in kRecordTypes) {
          final list = byNew.where((r) => r.type == t.id).toList()
            ..sort((a, b) => (b.favorite ? 1 : 0) - (a.favorite ? 1 : 0));
          if (list.isEmpty) continue;
          sections
            ..add(SnapH3(t.label, icon: t.icon, trailing: '(${list.length})'))
            ..add(grid(list));
        }
      case 'fav':
        final list = byNew.where((r) => r.favorite).toList();
        if (list.isNotEmpty) {
          sections
            ..add(
              SnapH3('즐겨찾기', icon: 'star-fill', trailing: '(${list.length})'),
            )
            ..add(grid(list));
        }
      case 'moment' || 'place' || 'document':
        final t = recordTypeOf(view);
        final list = byNew.where((r) => r.type == view).toList();
        if (list.isNotEmpty) {
          sections
            ..add(SnapH3(t.label, icon: t.icon, trailing: '(${list.length})'))
            ..add(grid(list));
        }
      default:
        // 기본: 즐겨찾기를 위에 따로, 나머지는 아래
        final favs = byNew.where((r) => r.favorite).toList();
        final rest = byNew.where((r) => !r.favorite).toList();
        if (favs.isNotEmpty) {
          sections
            ..add(
              SnapH3('즐겨찾기', icon: 'star-fill', trailing: '(${favs.length})'),
            )
            ..add(grid(favs));
        }
        if (rest.isNotEmpty) {
          sections
            ..add(
              SnapH3(
                favs.isEmpty ? '모든 기록' : '다른 기록',
                trailing: '(${rest.length})',
              ),
            )
            ..add(grid(rest));
        }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LargeTitle(
          title: '기록',
          actions: [
            if (s.records.isNotEmpty)
              Pressable(
                onTap: () => _pickView(context),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 7, 9, 7),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        viewLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.pk,
                        ),
                      ),
                      const SizedBox(width: 3),
                      SnapIcon('down', size: 15, color: c.pk),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (s.records.isEmpty)
          const SnapEmpty(
            icon: 'bookmark',
            text: '아직 남긴 기록이 없어요.\n사진 상세에서 \'기록으로 남기기\'를 눌러 보세요.',
          )
        else if (sections.isEmpty)
          SnapEmpty(icon: 'bookmark', text: "'$viewLabel'에 해당하는 기록이 없어요")
        else ...[
          ...sections,
          const SnapNote('별을 누르면 즐겨찾기에 올라가요'),
        ],
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.state, required this.record});
  final SnapbackState state;
  final PhotoRecord record;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final r = record;
    final c = context.sc;
    final photo = s.photoById(r.photoId);
    return Pressable(
      onTap: () => s.openRecord(r.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null)
                  PhotoTile(item: photo, radius: 14, showDate: false)
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                // 즐겨찾기 별 (누르면 켜고 끄기)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Pressable(
                    onTap: () => s.toggleRecordFavorite(r.id),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xE6FFFFFF),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: SnapIcon(
                          r.favorite ? 'star-fill' : 'star',
                          size: 17,
                          color: r.favorite
                              ? const Color(0xFFE0A030)
                              : const Color(0xFF8E8780),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            r.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              SnapIcon(_typeIcon(r), size: 14, color: c.mute),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _typeLine(r),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.mute),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
