import 'package:material_ui/material_ui.dart';
import '../models/photo_album.dart';
import '../models/photo_item.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class Screen5Home extends StatefulWidget {
  const Screen5Home({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen5Home> createState() => _Screen5HomeState();
}

class _Screen5HomeState extends State<Screen5Home> {
  String _chip = '전체';
  final _searchBoxKey = GlobalKey();

  void _openSearch(SnapbackState s) {
    final box = _searchBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return s.go(13);
    s.openSearchFrom(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final photos = s.visiblePhotos.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final shown = photos.take(24).toList();
    final pct = s.analysisTotal > 0
        ? ((s.analysisDone / s.analysisTotal) * 100).round().clamp(0, 100)
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: 'Snapback',
          trailing: GestureDetector(
            onTap: () => s.go(12),
            child: const Text('⚙️', style: TextStyle(fontSize: 18)),
          ),
        ),
        // 검색 화면과 같은 검색창: 누르면 이 창이 그대로 검색 화면 위치로 내려간다
        GestureDetector(
          onTap: () => _openSearch(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SearchBoxField(key: _searchBoxKey, enabled: false),
          ),
        ),
        GestureDetector(
          onTap: () => s.go(4),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: c.pri,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                const Text('🏃', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '분석 진행 상황 ${s.analysisTotal > 0 ? '$pct%' : ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: LinearProgressIndicator(
                          value: pct / 100.0,
                          minHeight: 6,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final label in [
                '전체',
                '🍜 음식',
                '🧑 인물',
                '📍 장소',
                '🌅 배경',
                '📱 스크린샷',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SnapChip(
                    label: label,
                    selected: _chip == label,
                    onTap: () {
                      setState(() => _chip = label);
                      if (label == '📱 스크린샷') {
                        s.go(11);
                      } else if (label != '전체') {
                        s.go(6);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '2026년 10월',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 7),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: shown.length,
          itemBuilder: (_, i) => PhotoTile(
            item: shown[i],
            onTap: () => s.openMemory(shown[i].id),
          ),
        ),
      ],
    );
  }
}

class Screen6FoodCategory extends StatefulWidget {
  const Screen6FoodCategory({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen6FoodCategory> createState() => _Screen6FoodCategoryState();
}

class _Screen6FoodCategoryState extends State<Screen6FoodCategory> {
  String _sub = '전체';

  static const _items = [
    ['🍜', '면'],
    ['🍰', '디저트'],
    ['☕', '커피'],
    ['🍺', '술'],
    ['🍝', '면'],
    ['🧁', '디저트'],
    ['🍵', '커피'],
    ['🍷', '술'],
    ['🥐', '디저트'],
    ['🍲', '면'],
    ['🍮', '디저트'],
    ['🥤', '커피'],
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final filtered =
        _items.where((x) => _sub == '전체' || x[1] == _sub).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '🍜 음식',
          onBack: () => widget.state.go(5),
          trailing: Text(
            '412장',
            style: TextStyle(fontSize: 12, color: c.mute),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['전체', '디저트', '면', '커피', '술']
                .map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SnapChip(
                      label: t,
                      selected: _sub == t,
                      onTap: () => setState(() => _sub = t),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: filtered.length,
          itemBuilder: (_, i) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: kTileGradients[i % kTileGradients.length],
            ),
            alignment: Alignment.center,
            child: Text(filtered[i][0], style: const TextStyle(fontSize: 24)),
          ),
        ),
      ],
    );
  }
}

class Screen7PhotoInfo extends StatelessWidget {
  const Screen7PhotoInfo({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '사진 정보', onBack: () => state.go(5)),
        Container(
          height: 200,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: kTileGradients[0],
          ),
          alignment: Alignment.center,
          child: const Text('🍰', style: TextStyle(fontSize: 60)),
        ),
        Text(
          '메타데이터',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 7),
        const Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            SnapChip(label: '🕓 2026.10.15 14:32'),
            SnapChip(label: '📍 37.54, 127.05'),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '이미지 분석',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 7),
        const Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            SnapChip(label: '🍰 디저트'),
            SnapChip(label: '🏠 카페(실내)'),
            SnapChip(label: '🪟 큰 창·비'),
            SnapChip(label: '🧑 2명 · 니트'),
          ],
        ),
        const SizedBox(height: 6),
        SnapRowCard(
          leading: buildIconBox(context, '🗂️'),
          title: '검색 DB 저장 완료',
          subtitle: '사진 ID #20261015-0832',
        ),
        SnapButton(
          label: '이 사진의 기억 보기',
          ghost: true,
          onTap: () => state.go(10),
        ),
      ],
    );
  }
}

class Screen8PrototypeChat extends StatefulWidget {
  const Screen8PrototypeChat({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen8PrototypeChat> createState() => _Screen8PrototypeChatState();
}

class _Screen8PrototypeChatState extends State<Screen8PrototypeChat> {
  final _ctrl = TextEditingController(text: '비 오는 날 창가에서 먹은 디저트');
  final List<String> _answers = [];

  static const _questions = [
    ('낮이었나요, 저녁이었나요?', ['낮', '저녁'], 128, 19),
    ('누구와 함께였나요?', ['혼자', '친구와'], 19, 4),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final step = _answers.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '기억으로 찾기', onBack: () => widget.state.go(5)),
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(fontSize: 14, color: c.ink),
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _answers.clear()),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.pri,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('➤', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i <= step && i <= _questions.length; i++) ...[
          if (i < _questions.length) ...[
            _Bubble(
              text:
                  '후보 ${_questions[i].$3}장 → 질문 ${i + 1}/2\n${_questions[i].$1}',
              isMe: false,
            ),
            if (i == step)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ..._questions[i].$2.map(
                        (opt) => SnapChip(
                          label: opt,
                          onTap: () => setState(() => _answers.add(opt)),
                        ),
                      ),
                  SnapChip(
                    label: '기억 안 나요 (건너뛰기)',
                    dashed: true,
                    onTap: () => setState(() => _answers.add('기억 안 나요')),
                  ),
                ],
              )
            else
              _Bubble(text: _answers[i], isMe: true),
          ] else ...[
            const _Bubble(text: '후보가 4장으로 줄었어요!', isMe: false),
            SnapButton(
              label: '결과 보기',
              onTap: () => widget.state.go(9),
            ),
          ],
        ],
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isMe});
  final String text;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isMe ? c.pri : c.soft,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: isMe ? Colors.white : c.ink,
          ),
        ),
      ),
    );
  }
}

class Screen9PrototypeResults extends StatelessWidget {
  const Screen9PrototypeResults({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '검색 결과',
          onBack: () => state.go(8),
          trailing: Text(
            '4장',
            style: TextStyle(fontSize: 12, color: c.mute),
          ),
        ),
        const SizedBox(height: 6),
        SnapRowCard(
          leading: buildIconBox(context, '🍰', gradIndex: 0),
          title: '성수동 카페 · 2026.10.15',
          subtitle: '✔ 비 오는 날 ✔ 창가 ✔ 디저트 · 📍 성수동',
          trailingText: '92%',
          onTap: () => state.go(10),
        ),
        SnapRowCard(
          leading: buildIconBox(context, '🥐', gradIndex: 2),
          title: '합정 베이커리 · 2026.07.02',
          subtitle: '✔ 디저트 ✔ 창가 · 비 정보 없음',
          trailingText: '71%',
        ),
        SnapRowCard(
          leading: buildIconBox(context, '🍓', gradIndex: 4),
          title: '연남동 카페 · 2025.06.21',
          subtitle: '✔ 디저트 · 위치 확인 불가',
          trailingText: '58%',
        ),
        SnapRowCard(
          leading: buildIconBox(context, '🍵', gradIndex: 1),
          title: '서촌 찻집 · 2025.04.09',
          subtitle: '✔ 창가 · 디저트 낮은 확신',
          trailingText: '44%',
        ),
        const SizedBox(height: 9),
        Center(
          child: Text(
            '단서에 맞은 항목을 표시해요 · 눌러서 자세히',
            style: TextStyle(fontSize: 11, color: c.mute),
          ),
        ),
      ],
    );
  }
}

class Screen10MemoryDetail extends StatelessWidget {
  const Screen10MemoryDetail({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    final item = s.db.firstWhere(
      (x) => x.id == s.activeMemoryId,
      orElse: () => s.db.first,
    );
    final rel = s.relatedFor(item);
    final bytes = decodeDataUrl(item.thumbDataUrl);
    final sub = [
      item.date,
      if (item.gps != null) '📍 GPS',
      if (item.caption.isNotEmpty)
        item.caption
      else if (item.food.isNotEmpty)
        item.food.join(', '),
    ].join(' · ');

    Widget horizontalList(List<PhotoItem> list) {
      if (list.isEmpty) {
        return Text('없어요', style: TextStyle(fontSize: 11, color: c.mute));
      }
      return SizedBox(
        height: 82,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => PhotoTile(
            item: list[i],
            width: 80,
            height: 80,
            onTap: () => s.openMemory(list[i].id),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: 'Snapback', onBack: () => s.go(13)),
        Container(
          height: 200,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: bytes == null
                ? kTileGradients[item.id % kTileGradients.length]
                : null,
            image: bytes != null
                ? DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover)
                : null,
          ),
          alignment: Alignment.center,
          child: bytes == null
              ? Text(item.emoji, style: const TextStyle(fontSize: 60))
              : null,
        ),
        Text(
          item.place,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(sub, style: TextStyle(fontSize: 13, color: c.mute)),
        const SizedBox(height: 16),
        Text(
          '🗓️ 같은 날의 사진 (${rel.sameDay.length})',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 7),
        horizontalList(rel.sameDay),
        const SizedBox(height: 16),
        Text(
          '📍 가까운 장소에서 (${rel.nearPlace.length})',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 7),
        horizontalList(rel.nearPlace),
        const SizedBox(height: 16),
        Text(
          '🎨 비슷한 분위기·배경 (${rel.similarMood.length})',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 7),
        horizontalList(rel.similarMood),
        const SizedBox(height: 16),
        Text(
          '🏪 방문 장소',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        Container(
          height: 90,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: const Text('📍', style: TextStyle(fontSize: 26)),
        ),
        SnapRowCard(
          leading: buildIconBox(context, '☕'),
          title: '카페 ○○',
          subtitle: '영업시간 10:00–21:00 · 연결 확실도 높음',
        ),
      ],
    );
  }
}

class Screen11Albums extends StatelessWidget {
  const Screen11Albums({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.sc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SnapbackTopBar(title: '앨범·도구'),
        const SizedBox(height: 4),
        SnapRowCard(
          leading: buildIconBox(context, '👶'),
          title: '성장 기록 · 레퍼런스 보드',
          subtitle: '활용 모드',
          onTap: () => s.go(15),
        ),
        const SizedBox(height: 16),
        Text(
          '내 앨범',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 8),
        if (s.albums.isEmpty)
          GestureDetector(
            onTap: () => s.go(13),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line, width: 1.5),
              ),
              child: Column(
                children: [
                  const Text('🗂️', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: 6),
                  Text(
                    '아직 앨범이 없어요',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '🔍 사진을 검색하면 어울리는 앨범을 제안해 드려요',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: c.mute),
                  ),
                ],
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
              childAspectRatio: 1.4,
            ),
            itemCount: s.albums.length,
            itemBuilder: (_, i) {
              final a = s.albums[i];
              final photos = s.albumPhotos(a);
              final cover =
                  photos.isEmpty ? null : decodeDataUrl(photos.first.thumbDataUrl);
              return GestureDetector(
                onTap: () => s.openAlbum(a.id),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: cover == null
                        ? kTileGradients[(a.id + 4) % kTileGradients.length]
                        : null,
                    image: cover != null
                        ? DecorationImage(
                            image: MemoryImage(cover),
                            fit: BoxFit.cover,
                            colorFilter: const ColorFilter.mode(
                              Color(0x33000000),
                              BlendMode.darken,
                            ),
                          )
                        : null,
                  ),
                  child: Stack(
                    children: [
                      if (cover == null)
                        Center(
                          child: Text(
                            a.emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 6,
                        child: Text(
                          '${a.title} · ${photos.length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 16),
        Text(
          '📱 스크린샷 정보 추출',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        SnapRowCard(
          leading: buildIconBox(context, '👟', gradIndex: 3),
          title: '운동화',
          subtitle: '브랜드·모델·₩129,000',
          trailingText: '복사',
        ),
        SnapRowCard(
          leading: buildIconBox(context, '🧾', gradIndex: 2),
          title: '예약 확인서',
          subtitle: '11.20 · 2명 · 장소',
          trailingText: '일정 추가',
        ),
        const SizedBox(height: 16),
        Text(
          '🧭 취향 요약',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        SnapRowCard(
          leading: buildIconBox(context, '☕'),
          title: '“카페와 미술관을 자주 가요”',
          subtitle: '다음 나들이: 한남 · 삼청 일대 추천',
        ),
      ],
    );
  }
}


class Screen16AlbumDetail extends StatefulWidget {
  const Screen16AlbumDetail({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen16AlbumDetail> createState() => _Screen16AlbumDetailState();
}

class _Screen16AlbumDetailState extends State<Screen16AlbumDetail> {
  bool _confirmDelete = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final album = s.albumById(s.activeAlbumId);
    if (album == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapbackTopBar(title: '앨범', onBack: () => s.go(11)),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '앨범을 찾을 수 없어요',
              style: TextStyle(fontSize: 13, color: c.mute),
            ),
          ),
        ],
      );
    }
    final photos = s.albumPhotos(album);
    final created = DateTime.fromMillisecondsSinceEpoch(album.createdAtMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: album.title, onBack: () => s.go(11)),
        const SizedBox(height: 6),
        Text(
          '${album.emoji} 사진 ${photos.length}장 · '
          '${created.year}.${created.month}.${created.day} 검색에서 만듦',
          style: TextStyle(fontSize: 12, color: c.mute),
        ),
        const SizedBox(height: 10),
        if (photos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                '이 앨범의 사진이 삭제되었거나 숨김 처리되었어요',
                style: TextStyle(fontSize: 12.5, color: c.mute),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: photos.length,
            itemBuilder: (_, i) => PhotoTile(
              item: photos[i],
              onTap: () => s.openMemory(photos[i].id),
            ),
          ),
        const SizedBox(height: 14),
        SnapButton(
          label: _confirmDelete ? '한 번 더 누르면 앨범이 삭제돼요' : '앨범 삭제',
          ghost: true,
          onTap: () {
            if (_confirmDelete) {
              s.deleteAlbum(album.id);
              s.go(11);
            } else {
              setState(() => _confirmDelete = true);
            }
          },
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            '앨범을 지워도 사진과 분석 정보는 그대로 남아요',
            style: TextStyle(fontSize: 11, color: c.mute),
          ),
        ),
      ],
    );
  }
}

class Screen12Settings extends StatefulWidget {
  const Screen12Settings({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen12Settings> createState() => _Screen12SettingsState();
}

class _Screen12SettingsState extends State<Screen12Settings> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.state.serverUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final yearCounts = <String, int>{};
    for (final d in s.db) {
      if (d.date.length >= 4) {
        final y = d.date.substring(0, 4);
        yearCounts[y] = (yearCounts[y] ?? 0) + 1;
      }
    }
    final years = yearCounts.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '설정 · 개인정보', onBack: () => s.go(5)),
        const SizedBox(height: 14),
        Text(
          '접근 범위 (연도별)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        ...years.map((y) {
          final isVisible = !s.db.any((d) => d.date.startsWith(y) && d.hidden);
          return SnapOptionCard(
            icon: '📅',
            title: '$y년 사진 (${yearCounts[y]}장)',
            trailing: Switch(
              value: isVisible,
              activeThumbColor: c.pri,
              onChanged: (_) => s.toggleYearVisibility(y),
            ),
          );
        }),
        if (s.hiddenWarning.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEFD6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              s.hiddenWarning,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A5200)),
            ),
          ),
        SnapOptionCard(
          icon: '🧪',
          title: '사용성 테스트 모드',
          subtitle: 'Top-5 포함률·시간·질문 수 측정',
          onTap: () => s.go(14),
          trailing: Text('›', style: TextStyle(fontSize: 20, color: c.pri)),
        ),
        const SizedBox(height: 14),
        Text(
          '분석',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        SnapOptionCard(
          icon: '🔋',
          title: '백그라운드 분석',
          trailing: Switch(
            value: s.backgroundAnalysis,
            activeThumbColor: c.pri,
            onChanged: (v) {
              s.backgroundAnalysis = v;
              s.go(12);
            },
          ),
        ),
        SnapOptionCard(
          icon: '🔄',
          title: '분석 순서 다시 선택',
          onTap: () => s.go(3),
          trailing: Text('›', style: TextStyle(fontSize: 20, color: c.pri)),
        ),
        const SizedBox(height: 14),
        Text(
          'API 서버 주소 (iOS 실기기 테스트용)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  style: TextStyle(fontSize: 13, color: c.ink),
                  decoration: InputDecoration(
                    hintText: '예: http://192.168.0.10:3000',
                    hintStyle: TextStyle(color: c.mute),
                    border: InputBorder.none,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => s.setServerUrl(_urlCtrl.text),
                child: Text('적용', style: TextStyle(color: c.pri)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class Screen13Search extends StatefulWidget {
  const Screen13Search({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen13Search> createState() => _Screen13SearchState();
}

class _Screen13SearchState extends State<Screen13Search>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _boxKey = GlobalKey();
  // 진입 애니메이션: 홈 검색창 위치 → 제자리로 스르르, 나머지는 뒤따라 페이드 인
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  late final Animation<double> _boxMove = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0, 0.8, curve: Curves.easeInOutCubic),
  );
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.4, 1, curve: Curves.easeOut),
  );
  double _fromDy = 0;
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    final from = widget.state.takeSearchOrigin();
    if (from == null) {
      _enter.value = 1;
      return;
    }
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      setState(() {
        _measuring = false;
        if (box != null && box.hasSize && !reduceMotion) {
          _fromDy = from.top - box.localToGlobal(Offset.zero).dy;
        }
      });
      if (reduceMotion) {
        _enter.value = 1;
        _focus.requestFocus();
        return;
      }
      _enter.forward().whenComplete(() {
        if (mounted) _focus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Widget _revealed(Widget child, {double rise = 0}) => AnimatedBuilder(
        animation: _reveal,
        builder: (_, w) => Opacity(
          opacity: _reveal.value,
          child: Transform.translate(
            offset: Offset(0, rise * (1 - _reveal.value)),
            child: w,
          ),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final byId = {for (final d in s.db) d.id: d};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _revealed(
          SnapbackTopBar(
            title: '검색',
            onBack: () => s.go(5),
            trailing: SnapChip(label: s.aiStatusText),
          ),
        ),
        const SizedBox(height: 24),
        _revealed(
          rise: 10,
          Text(
            '어떤 사진을\n찾고 계시나요?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: c.ink,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: AnimatedBuilder(
            animation: _boxMove,
            builder: (_, w) => Opacity(
              opacity: _measuring ? 0 : 1,
              child: Transform.translate(
                offset: Offset(0, _fromDy * (1 - _boxMove.value)),
                child: w,
              ),
            ),
            child: SearchBoxField(
              key: _boxKey,
              controller: _ctrl,
              focusNode: _focus,
              busy: s.searchBusy,
              onSubmit: () => s.startNewSearch(_ctrl.text),
            ),
          ),
        ),
        _revealed(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
        if (s.testSession != null && s.searchHistory.isEmpty)
          Center(
            child: Text(
              '🧪 테스트 중 — 목표 사진을 떠올려 기억나는 대로 입력하고, 찾으면 그 사진을 누르세요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.mute),
            ),
          ),
        if (s.searchBusy)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                'AI가 기억을 더듬는 중…',
                style: TextStyle(fontSize: 12, color: c.mute),
              ),
            ),
          )
        else if (s.searchError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '⚠️ ${s.searchError}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFC0392B)),
              ),
            ),
          )
        else if (s.searchResults.isNotEmpty) ...[
          ...() {
            final valid = s.searchResults
                .where((x) => byId.containsKey(x.id))
                .toList()
              ..sort((a, b) => b.score.compareTo(a.score));
            if (valid.isEmpty) return <Widget>[];
            final top = valid.first;
            final topPhoto = byId[top.id]!;
            final topBytes = decodeDataUrl(topPhoto.thumbDataUrl);
            final topMatched =
                top.matched.isNotEmpty ? '✔ ${top.matched.join(' ✔ ')}' : '';
            final topMissing =
                top.missing.isNotEmpty ? ' · ? ${top.missing.join(', ')}' : '';
            final rest = valid.skip(1).toList();

            return <Widget>[
              GestureDetector(
                onTap: () => s.openMemory(topPhoto.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: topBytes == null
                            ? kTileGradients[
                                topPhoto.id % kTileGradients.length]
                            : null,
                        image: topBytes != null
                            ? DecorationImage(
                                image: MemoryImage(topBytes),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: topBytes == null
                          ? Text(
                              topPhoto.emoji,
                              style: const TextStyle(fontSize: 64),
                            )
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.soft,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '일치 확률 ${top.score}%',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: c.pri,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${topPhoto.place} · ${topPhoto.date}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (topMatched.isNotEmpty || topMissing.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$topMatched$topMissing',
                        style: TextStyle(fontSize: 12, color: c.mute),
                      ),
                    ],
                  ],
                ),
              ),
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '다음으로 확률이 높은 사진',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.mute,
                  ),
                ),
                const SizedBox(height: 2),
                ...rest.map((x) {
                  final d = byId[x.id]!;
                  final bytes = decodeDataUrl(d.thumbDataUrl);
                  final matched =
                      x.matched.isNotEmpty ? '✔ ${x.matched.join(' ✔ ')}' : '';
                  final missing =
                      x.missing.isNotEmpty ? ' · ? ${x.missing.join(', ')}' : '';
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
                          ? Text(d.emoji, style: const TextStyle(fontSize: 18))
                          : null,
                    ),
                    title: '${d.place} · ${d.date}',
                    subtitle: '$matched$missing',
                    trailingText: '${x.score}%',
                    onTap: () => s.openMemory(d.id),
                  );
                }),
              ],
            ];
          }(),
          if (s.activeQuestion != null) ...[
            const SizedBox(height: 6),
            _Bubble(text: s.activeQuestion!.text, isMe: false),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...s.activeQuestion!.options.map(
                  (opt) => SnapChip(
                    label: opt,
                    onTap: () => s.answerFollowUp(opt),
                  ),
                ),
                SnapChip(
                  label: '기억 안 나요',
                  dashed: true,
                  onTap: () => s.answerFollowUp('기억 안 나요'),
                ),
              ],
            ),
          ] else if (s.searchCompleted)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '✅ 후보가 충분히 좁혀졌어요',
                  style: TextStyle(fontSize: 11.5, color: c.mute),
                ),
              ),
            ),
          if (s.albumSuggestion case final sug?)
            _AlbumSuggestionCard(
              key: ValueKey('album-sug-${s.searchHistory.first}'),
              state: s,
              suggestion: sug,
            )
          else if (s.albumById(s.lastCreatedAlbumId) case final made?)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SnapRowCard(
                leading: buildIconBox(context, made.emoji),
                title: '✅ \'${made.title}\' 앨범을 만들었어요',
                subtitle: '사진 ${made.photoIds.length}장 · 앨범 탭에서 볼 수 있어요',
                trailingText: '보러 가기',
                onTap: () => s.openAlbum(made.id),
              ),
            ),
        ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 검색 결과 아래 "이런 앨범으로 만들어 드릴까요?" 제안 카드.
class _AlbumSuggestionCard extends StatefulWidget {
  const _AlbumSuggestionCard({
    super.key,
    required this.state,
    required this.suggestion,
  });

  final SnapbackState state;
  final AlbumSuggestion suggestion;

  @override
  State<_AlbumSuggestionCard> createState() => _AlbumSuggestionCardState();
}

class _AlbumSuggestionCardState extends State<_AlbumSuggestionCard> {
  late final TextEditingController _title =
      TextEditingController(text: widget.suggestion.title);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final sug = widget.suggestion;
    final c = context.sc;
    final byId = {for (final d in s.db) d.id: d};
    final photos = [
      for (final id in sug.photoIds)
        if (byId[id] != null) byId[id]!,
    ];
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📁 이런 앨범으로 만들어 드릴까요?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '이번 검색과 잘 맞는 사진 ${photos.length}장을 묶을게요',
            style: TextStyle(fontSize: 12, color: c.mute),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => PhotoTile(
                item: photos[i],
                width: 52,
                height: 52,
                showDate: false,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line, width: 1.5),
            ),
            child: Row(
              children: [
                Text(sug.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _title,
                    style: TextStyle(fontSize: 14, color: c.ink),
                    decoration: InputDecoration(
                      hintText: '앨범 이름',
                      hintStyle: TextStyle(color: c.mute),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Text('✏️', style: TextStyle(fontSize: 12, color: c.mute)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SnapButton(
                  label: '괜찮아요',
                  ghost: true,
                  onTap: s.dismissAlbumSuggestion,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SnapButton(
                  label: '앨범 만들기',
                  onTap: () => s.createAlbumFromSuggestion(sug, _title.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class Screen14UsabilityTest extends StatefulWidget {
  const Screen14UsabilityTest({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen14UsabilityTest> createState() => _Screen14UsabilityTestState();
}

class _Screen14UsabilityTestState extends State<Screen14UsabilityTest> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final vis = s.visiblePhotos;
    final currentId = (_selectedId != null && vis.any((d) => d.id == _selectedId))
        ? _selectedId!
        : (vis.isNotEmpty ? vis.first.id : 1);
    final logs = s.testLogs;
    final n = logs.length;
    final top5Count = logs.where((x) => x.firstRank > 0).length;
    final hitCount = logs.where((x) => x.hit).length;
    final avgSec = n > 0
        ? (logs.fold<int>(0, (p, e) => p + e.ms) / n / 1000).round()
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '테스트 모드', onBack: () => s.go(12)),
        const SizedBox(height: 8),
        Text(
          '진행자가 목표 사진을 보여 주면, 참가자가 기억나는 대로 검색해 찾습니다. 시간·질문 수·순위를 자동 기록해요.',
          style: TextStyle(fontSize: 13, color: c.mute),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: DropdownButton<int>(
            value: currentId,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: c.card,
            items: vis
                .map(
                  (d) => DropdownMenuItem(
                    value: d.id,
                    child: Text(
                      '#${d.id} ${d.place} · ${d.date}',
                      style: TextStyle(color: c.ink, fontSize: 13.5),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedId = v),
          ),
        ),
        SnapButton(
          label: '테스트 시작',
          onTap: () => s.startUsabilityTest(currentId),
        ),
        const SizedBox(height: 16),
        Text(
          '결과',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 8),
        if (n == 0)
          Center(
            child: Text(
              '아직 기록이 없어요',
              style: TextStyle(fontSize: 11, color: c.mute),
            ),
          )
        else ...[
          Row(
            children: [
              _StatBox(value: '$top5Count/$n', label: '첫 입력 Top-5'),
              const SizedBox(width: 7),
              _StatBox(value: '$hitCount/$n', label: '찾음'),
              const SizedBox(width: 7),
              _StatBox(value: '$avgSec초', label: '평균 시간'),
            ],
          ),
          ...logs.map(
            (x) => SnapRowCard(
              leading: buildIconBox(context, x.hit ? '✅' : '❌'),
              title: '#${x.id}',
              subtitle:
                  '${(x.ms / 1000).round()}초 · 질문 ${x.questions}회 · 첫 순위 ${x.firstRank > 0 ? x.firstRank : '밖'} · ${x.hit ? '✔ 찾음' : '✘ 못 찾음'}',
            ),
          ),
        ],
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Expanded(
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
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 11, color: c.mute)),
          ],
        ),
      ),
    );
  }
}

class Screen15Mode extends StatefulWidget {
  const Screen15Mode({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen15Mode> createState() => _Screen15ModeState();
}

class _Screen15ModeState extends State<Screen15Mode> {
  bool _growthMode = true;
  final _bdCtrl = TextEditingController(text: '2026-01-01');
  final _bqCtrl = TextEditingController();

  @override
  void dispose() {
    _bdCtrl.dispose();
    _bqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final vis = s.visiblePhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(title: '활용 모드', onBack: () => s.go(11)),
        const SizedBox(height: 10),
        Row(
          children: [
            SnapChip(
              label: '👶 성장 기록',
              selected: _growthMode,
              onTap: () => setState(() => _growthMode = true),
            ),
            const SizedBox(width: 6),
            SnapChip(
              label: '🏠 레퍼런스 보드',
              selected: !_growthMode,
              onTap: () => setState(() => _growthMode = false),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_growthMode) ...[
          Text(
            '아이 생일을 입력하면 월령별로 모아 보여요',
            style: TextStyle(fontSize: 13, color: c.mute),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bdCtrl,
                    style: TextStyle(fontSize: 14, color: c.ink),
                    decoration: const InputDecoration(
                      hintText: 'YYYY-MM-DD',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {}),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.pri,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child:
                        const Text('⟳', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          ...() {
            final birth = DateTime.tryParse(_bdCtrl.text) ?? DateTime(2026, 1, 1);
            final groups = <String, List<PhotoItem>>{};
            for (final d in vis) {
              if (d.date.length >= 7) {
                groups.putIfAbsent(d.date.substring(0, 7), () => []).add(d);
              }
            }
            final keys = groups.keys.toList()..sort();
            return keys.map((k) {
              final parts = k.split('-');
              final y = int.parse(parts[0]);
              final m = int.parse(parts[1]);
              final age = (y - birth.year) * 12 + (m - birth.month);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '$y.$m ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        age >= 0 ? '생후 $age개월' : '출생 전',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.pri,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: groups[k]!.length,
                    itemBuilder: (_, i) => PhotoTile(
                      item: groups[k]![i],
                      onTap: () => s.openMemory(groups[k]![i].id),
                    ),
                  ),
                ],
              );
            });
          }(),
        ] else ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bqCtrl,
                    style: TextStyle(fontSize: 14, color: c.ink),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '공간·분위기 (예: 창, 조명, 실내)',
                      hintStyle: TextStyle(color: c.mute),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {}),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.pri,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text('🔍', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
          ...() {
            final q = _bqCtrl.text.trim();
            final matched = vis.where((d) {
              if (q.isEmpty) return true;
              final hay =
                  '${d.place} ${d.background} ${d.caption} ${d.food.join(' ')} ${d.weather}';
              return hay.contains(q);
            }).toList();
            return [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: matched.length,
                itemBuilder: (_, i) => PhotoTile(
                  item: matched[i],
                  onTap: () => s.openMemory(matched[i].id),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${matched.length}장',
                  style: TextStyle(fontSize: 11, color: c.mute),
                ),
              ),
            ];
          }(),
        ],
      ],
    );
  }
}

/// 홈(누르면 검색으로 이동)과 검색 화면이 함께 쓰는 검색창.
/// 두 화면에서 모양·크기가 같아야 전환 때 같은 창이 내려오는 것처럼 보인다.
class SearchBoxField extends StatelessWidget {
  const SearchBoxField({
    super.key,
    this.enabled = true,
    this.controller,
    this.focusNode,
    this.busy = false,
    this.onSubmit,
  });

  final bool enabled;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool busy;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: IgnorePointer(
              ignoring: !enabled,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: !enabled,
                style: TextStyle(fontSize: 14, color: c.ink),
                onSubmitted: (_) => onSubmit?.call(),
                decoration: InputDecoration(
                  hintText: '🔍 기억나는 대로 말해보세요 (예: 비 오는 날 창가 디저트)',
                  hintStyle: TextStyle(color: c.mute, fontSize: 13.5),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: enabled ? onSubmit : null,
            child: Opacity(
              opacity: busy ? 0.5 : 1.0,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.pri,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('➤', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
