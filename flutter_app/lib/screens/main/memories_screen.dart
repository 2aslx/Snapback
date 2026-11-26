part of '../main_screens.dart';

// 기억 탭(찾은 사진) · 관련된 추억 앨범

/// ⑤′ 기억 탭 — 지금까지 검색으로 찾은 사진들을 갤러리로. 누르면 사진 상세(관련된 추억 등).
class Screen19Memories extends StatefulWidget {
  const Screen19Memories({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen19Memories> createState() => _Screen19MemoriesState();
}

class _Screen19MemoriesState extends State<Screen19Memories> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final photos = s.foundPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LargeTitle(
          title: '기억',
          actions: [
            if (photos.isNotEmpty)
              Pressable(
                onTap: () => setState(() => _editing = !_editing),
                child: Text(
                  _editing ? '완료' : '편집',
                  style: TextStyle(fontSize: 17, color: c.pk),
                ),
              ),
          ],
        ),
        // 월간 리캡: 누르면 달마다 모아 둔 리캡 목록(화면 23)으로
        if (s.visiblePhotos.isNotEmpty) ...[
          _RecapButton(onTap: s.openRecaps),
          const SizedBox(height: 22),
        ],
        // 기록으로 남긴 사진은 하단 '기록' 탭으로 옮김
        if (photos.isEmpty) ...[
          const SnapEmpty(
            icon: 'heart',
            text: '아직 찾은 사진이 없어요.\n사진 탭에서 기억나는 장면을 말해 보세요.',
          ),
          SnapButton(label: '기억으로 찾기', icon: 'search', onTap: s.openNewSearch),
        ] else ...[
          SnapSub(
            _editing
                ? '기록에서 뺄 사진을 누르세요 · 사진은 지워지지 않아요'
                : '검색으로 찾은 사진 ${photos.length}장 · 최근에 찾은 순',
          ),
          const SizedBox(height: 12),
          if (_editing)
            Bleed(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: photos.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => s.forgetFound(photos[i].id),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: 0.7,
                        child: PhotoTile(
                          item: photos[i],
                          radius: 16,
                          showDate: false,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: c.pri,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const SnapIcon(
                            'close',
                            size: 13,
                            color: Colors.white,
                            strokeWidth: 2.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            PhotoGrid(items: photos, onTap: (d) => s.openMemory(d.id)),
        ],
      ],
    );
  }
}

/// '2026-10-15' → '10월 15일'
String _md(String date) {
  final p = date.split('-');
  if (p.length != 3) return date;
  return '${int.tryParse(p[1]) ?? p[1]}월 ${int.tryParse(p[2]) ?? p[2]}일';
}

/// 관련된 추억 앨범 — 사진 상세에서 연 가상 앨범(그날의 사진 / 비슷한 분위기)의 전체 사진.
/// 갤러리에 실제 앨범을 만들지 않고 앱 안에서만 묶어 보여준다.
class Screen18RelatedAlbum extends StatelessWidget {
  const Screen18RelatedAlbum({super.key, required this.state});
  final SnapbackState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final sameDay = s.relatedAlbumKind == 0;
    final title = sameDay ? '그날의 사진' : '비슷한 분위기';
    void back() {
      if (!s.backFromRelated()) s.go(10);
    }

    final base = s.db.where((x) => x.id == s.relatedBaseId).firstOrNull;
    if (base == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapbackTopBar(title: title, onBack: back),
          const SnapEmpty(icon: 'image', text: '사진을 찾을 수 없어요'),
        ],
      );
    }
    final rel = s.relatedFor(base);
    var photos = sameDay ? rel.sameDay : rel.similarMood;
    if (sameDay) {
      // 그날의 사진은 찍은 순서대로
      int key(PhotoItem x) => x.takenAtMs ?? x.id;
      photos = [...photos]..sort((a, b) => key(a).compareTo(key(b)));
    }
    final where = base.place.isEmpty || base.place == '알 수 없음'
        ? ''
        : ' · ${base.place}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: title,
          onBack: back,
          trailing: Text('${photos.length}장'),
        ),
        SnapSub(
          sameDay
              ? '${base.date}$where에서 함께 찍은 사진 ${photos.length}장'
              : '이 사진과 분위기가 비슷한 사진 ${photos.length}장',
        ),
        const SizedBox(height: 12),
        if (photos.isEmpty)
          const SnapEmpty(icon: 'image', text: '이 앨범에 남은 사진이 없어요')
        else
          PhotoGrid(items: photos, onTap: (d) => s.openFromRelatedAlbum(d.id)),
        if (photos.isNotEmpty)
          SnapButton(
            label: '이 사진들로 앨범 만들기',
            icon: 'stack',
            top: 18,
            onTap: () => s.draftAlbumFromRelated(
              sameDay
                  ? '${_md(base.date)} ${s.memoryTitle(base)}'
                  : '${s.memoryTitle(base)}의 분위기',
              base,
              photos,
            ),
          ),
        const SnapNote('사진 앱에 앨범을 만들지 않고, Snapback 안에서만 묶어 보여줘요'),
      ],
    );
  }
}
