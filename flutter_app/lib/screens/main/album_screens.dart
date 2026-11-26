part of '../main_screens.dart';

// 앨범: 목록 · 카테고리 · 미리보기 · 상세(이름·잠금·삭제)

/// ⑥ 앨범 — 흩어진 순간 모으기(AI 앨범) + 카테고리별 내 앨범
class Screen11Albums extends StatefulWidget {
  const Screen11Albums({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen11Albums> createState() => _Screen11AlbumsState();
}

class _Screen11AlbumsState extends State<Screen11Albums> {
  final _req = TextEditingController();
  static const _examples = ['올여름 친구들과 함께했던 순간들', '저장해 둔 네일 디자인 사진만 모아줘'];
  bool _confirmRemove = false;

  @override
  void dispose() {
    _req.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final shown = s.filteredAlbums;
    final filterCat = s.categoryById(s.albumFilter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LargeTitle(title: '앨범'),
        // AI 대화형 앨범 만들기
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SnapIcon('sparkle', size: 19.5, color: c.pk),
                  const SizedBox(width: 6),
                  Text(
                    '흩어진 순간 모으기',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '흩어진 사진들을 의미 있는 하나의 앨범으로.',
                style: TextStyle(fontSize: 13, color: c.mute),
              ),
              const SizedBox(height: 10),
              SnapSearchBar(
                controller: _req,
                showIcon: false,
                hint: '어떤 순간을 모아볼까요?',
                busy: s.albumBusy,
                onSubmit: () => s.composeAlbum(_req.text),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // 내 사진 DB 로 만든 제안 (없으면 기본 예시)
                  for (final e
                      in s.albumSuggestions.isNotEmpty
                          ? s.albumSuggestions
                          : _examples)
                    SnapChip(
                      label: e,
                      icon: s.albumSuggestions.isNotEmpty ? 'sparkle' : null,
                      onTap: () {
                        _req.text = e;
                        s.composeAlbum(e);
                      },
                    ),
                ],
              ),
              if (s.albumBusy) const SnapNote('어울리는 사진을 모으는 중…'),
              if (s.albumError != null && !s.albumBusy)
                SnapNote(
                  s.albumError!,
                  icon: 'alert',
                  color: const Color(0xFFC0392B),
                ),
            ],
          ),
        ),
        const SnapH3('내 앨범'),
        CategoryChips(
          state: s,
          selected: s.albumFilter,
          includeAll: true,
          onSelect: (id) {
            _confirmRemove = false;
            s.setAlbumFilter(id);
          },
        ),
        if (filterCat != null && !filterCat.builtIn)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Pressable(
              onTap: () {
                if (_confirmRemove) {
                  _confirmRemove = false;
                  s.removeCategory(filterCat.id);
                } else {
                  setState(() => _confirmRemove = true);
                }
              },
              child: Text(
                _confirmRemove
                    ? '한 번 더 누르면 카테고리가 삭제돼요 (앨범은 남아요)'
                    : "'${filterCat.label}' 카테고리 삭제",
                style: TextStyle(fontSize: 13, color: c.mute),
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (s.albums.isEmpty)
          const SnapEmpty(
            icon: 'stack',
            text: '아직 앨범이 없어요.\n위에서 모아 보고 싶은 순간을 적어 보세요.',
          )
        else if (shown.isEmpty)
          SnapEmpty(
            icon: 'stack',
            text:
                "'${filterCat?.label ?? ''}' 카테고리에 앨범이 없어요.\n앨범을 열어 카테고리를 바꿀 수 있어요.",
          )
        else
          AlbumCardGrid(
            children: [
              for (final a in shown)
                () {
                  final photos = s.albumPhotos(a);
                  return AlbumCard(
                    locked: a.locked,
                    cover: photos.isNotEmpty
                        ? photos.first
                        : PhotoItem(id: a.id + 4, date: '', place: ''),
                    title: a.title,
                    count: photos.length,
                    badge: s.albumFilter == null
                        ? s.categoryById(a.category)?.label
                        : null,
                    onTap: () => s.openAlbum(a.id),
                  );
                }(),
            ],
          ),
      ],
    );
  }
}

/// 앨범 카테고리 캡슐 버튼 줄 (가로 스크롤) + 맨 끝 '＋ 추가'.
/// includeAll: 맨 앞에 '전체'(null) 포함 — 앨범 탭 필터용.
/// includeAll 이 false 면 선택한 칩을 다시 누를 때 '분류 없음'(null)으로 돌아간다.
class CategoryChips extends StatefulWidget {
  const CategoryChips({
    super.key,
    required this.state,
    required this.selected,
    required this.onSelect,
    this.includeAll = false,
    this.aiId,
  });

  final SnapbackState state;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final bool includeAll;

  /// AI 가 추천한 카테고리 id — 칩에 반짝이 아이콘 표시
  final String? aiId;

  @override
  State<CategoryChips> createState() => _CategoryChipsState();
}

class _CategoryChipsState extends State<CategoryChips> {
  bool _adding = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final c = widget.state.addCategory(_name.text);
    _name.clear();
    setState(() => _adding = false);
    if (c != null) widget.onSelect(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Bleed(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (widget.includeAll)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SnapChip(
                      label: '전체',
                      accent: true,
                      selected: sel == null,
                      onTap: () => widget.onSelect(null),
                    ),
                  ),
                for (final cat in widget.state.allCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SnapChip(
                      label: cat.label,
                      icon: cat.id == widget.aiId ? 'sparkle' : null,
                      accent: true,
                      selected: sel == cat.id,
                      onTap: () => widget.onSelect(
                        !widget.includeAll && sel == cat.id ? null : cat.id,
                      ),
                    ),
                  ),
                SnapChip(
                  label: '추가',
                  icon: 'plus',
                  dashed: true,
                  onTap: () => setState(() => _adding = !_adding),
                ),
              ],
            ),
          ),
        ),
        if (_adding)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SnapSearchBar(
              controller: _name,
              showIcon: false,
              hint: '새 카테고리 이름 (예: 반려동물)',
              buttonIcon: 'check',
              onSubmit: _submit,
            ),
          ),
      ],
    );
  }
}

/// 앨범 미리보기 — AI가 고른 사진 확인 · 빼고 싶은 사진 선택/제외 · 이름 수정 · 최종 생성
class Screen17AlbumPreview extends StatefulWidget {
  const Screen17AlbumPreview({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen17AlbumPreview> createState() => _Screen17AlbumPreviewState();
}

class _Screen17AlbumPreviewState extends State<Screen17AlbumPreview> {
  late final _title = TextEditingController(
    text: widget.state.albumDraft?.title ?? '',
  );

  /// 처음 받은 AI 추천 카테고리 (사용자가 바꿔도 표시용으로 유지)
  late final String? _aiCategory = widget.state.albumDraft?.category;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = context.sc;
    final draft = s.albumDraft;
    if (draft == null) {
      return Column(
        children: [
          SnapbackTopBar(
            title: '앨범 미리보기',
            onBack: () => s.go(s.albumDraftReturn),
          ),
          const SnapEmpty(icon: 'stack', text: '미리볼 앨범이 없어요'),
        ],
      );
    }
    final byId = {for (final d in s.db) d.id: d};
    final photos = [
      for (final id in draft.photoIds)
        if (byId[id] != null) byId[id]!,
    ];
    final sel = s.albumDraftSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SnapbackTopBar(
          title: '앨범 미리보기',
          onBack: () => s.go(s.albumDraftReturn),
          trailing: Text('${photos.length}장'),
        ),
        const SnapH3('앨범 이름', small: true),
        SnapSearchBar(
          controller: _title,
          showIcon: false,
          hint: '앨범 이름',
          buttonIcon: 'check',
          onSubmit: () => FocusScope.of(context).unfocus(),
        ),
        const SnapH3('카테고리', small: true),
        CategoryChips(
          state: s,
          selected: draft.category,
          aiId: _aiCategory,
          onSelect: s.setDraftCategory,
        ),
        if (_aiCategory != null)
          SnapNote(
            "AI 추천: '${s.categoryById(_aiCategory)?.label ?? ''}' · 눌러서 바꿀 수 있어요",
            top: 8,
          ),
        // 기본은 모두 선택. 빼고 싶은 사진을 눌러 선택 해제
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SnapSub(
                  sel.isEmpty
                      ? 'AI가 고른 사진 ${photos.length}장이 모두 선택돼 있어요. 빼고 싶은 사진을 눌러 선택을 해제하세요.'
                      : '${photos.length}장 중 ${photos.length - sel.length}장 선택됨',
                ),
              ),
              const SizedBox(width: 10),
              Pressable(
                onTap: () => s.setAllDraftPhotos(sel.isNotEmpty),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    sel.isEmpty ? '전체 해제' : '전체 선택',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.pk,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
          itemCount: photos.length,
          itemBuilder: (_, i) {
            final d = photos[i];
            final on = !sel.contains(d.id); // 선택됨 = 앨범에 들어감
            return GestureDetector(
              onTap: () => s.toggleDraftPhoto(d.id),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 선택 해제된 사진은 흐리게
                  Opacity(
                    opacity: on ? 1 : 0.4,
                    child: PhotoTile(item: d),
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
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: on ? c.pri : const Color(0x99FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
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
        SnapButton(
          label: photos.length - sel.length <= 0
              ? '앨범에 넣을 사진을 골라 주세요'
              : '앨범 만들기 (${photos.length - sel.length}장)',
          onTap: photos.length - sel.length <= 0
              ? null
              : () => s.confirmAlbumDraft(_title.text),
        ),
        const SnapNote('만들기 전까지는 저장되지 않아요'),
      ],
    );
  }
}





/// 앨범 상세 (Flutter 추가)
class Screen16AlbumDetail extends StatefulWidget {
  const Screen16AlbumDetail({super.key, required this.state});
  final SnapbackState state;

  @override
  State<Screen16AlbumDetail> createState() => _Screen16AlbumDetailState();
}

class _Screen16AlbumDetailState extends State<Screen16AlbumDetail> {
  bool _editing = false;
  final _name = TextEditingController();
  final _nameFocus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _startEdit(String title) {
    _name.text = title;
    _name.selection = TextSelection(baseOffset: 0, extentOffset: title.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _nameFocus.requestFocus(),
    );
  }

  void _finishEdit(int albumId) {
    if (!_editing) return;
    widget.state.renameAlbum(albumId, _name.text);
    setState(() => _editing = false);
  }

  /// 삭제 확인 팝업
  Future<void> _toggleLock(PhotoAlbum album) async {
    final s = widget.state;
    if (album.locked) {
      final ok = await showSnapConfirm(
        context,
        title: '잠금을 풀까요?',
        message: "'${album.title}' 앨범을 비밀번호 없이\n볼 수 있게 돼요.",
        confirmLabel: '잠금 풀기',
        destructive: false,
      );
      if (ok) s.removeAlbumLock(album.id);
      return;
    }
    final pin = await showPinSetup(context);
    if (pin != null) s.lockAlbum(album.id, pin);
  }

  Future<void> _confirmForgot(int albumId, String title) async {
    final ok = await showSnapConfirm(
      context,
      title: '비밀번호를 잊으셨나요?',
      message: '비밀번호는 찾을 수 없어요.\n앨범을 지우면 다시 만들 수 있고,\n사진과 분석 정보는 그대로 남아요.',
      confirmLabel: '앨범 삭제',
    );
    if (ok) {
      widget.state.deleteAlbum(albumId);
      widget.state.go(11);
    }
  }

  Future<void> _confirmDelete(int albumId, String title) async {
    final ok = await showSnapConfirm(
      context,
      title: '앨범을 삭제할까요?',
      message: "'$title' 앨범만 지워지고,\n사진과 분석 정보는 그대로 남아요.",
    );
    if (ok) {
      widget.state.deleteAlbum(albumId);
      widget.state.go(11);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final album = s.albumById(s.activeAlbumId);
    if (album == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapbackTopBar(title: '앨범', onBack: () => s.go(11)),
          const SnapEmpty(icon: 'stack', text: '앨범을 찾을 수 없어요'),
        ],
      );
    }
    // 잠긴 앨범: 비밀번호 4자리를 맞게 입력해야 사진이 보인다
    if (s.isAlbumHidden(album)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SnapbackTopBar(title: album.title, onBack: () => s.go(11)),
          const SizedBox(height: 12),
          PinPad(
            title: '잠긴 앨범',
            message: '비밀번호 4자리를 입력하면 사진을 볼 수 있어요.',
            onComplete: (pin) async => s.unlockAlbum(album.id, pin),
            footer: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Pressable(
                onTap: () => _confirmForgot(album.id, album.title),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '비밀번호를 잊었어요',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.sc.mute,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final photos = s.albumPhotos(album);
    final made = DateTime.fromMillisecondsSinceEpoch(album.createdAtMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 제목을 누르면 그 자리에서 앨범 이름 편집
        SnapbackTopBar(
          title: album.title,
          onBack: () {
            _finishEdit(album.id);
            s.go(11);
          },
          titleWidget: _editing
              ? IntrinsicWidth(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: context.sc.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.sc.pri, width: 1.2),
                    ),
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      textAlign: TextAlign.center,
                      maxLength: 30,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _finishEdit(album.id),
                      onTapOutside: (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        _finishEdit(album.id);
                      },
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        color: context.sc.ink,
                      ),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        counterText: '',
                      ),
                    ),
                  ),
                )
              : Pressable(
                  onTap: () => _startEdit(album.title),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                            color: context.sc.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SnapIcon('pencil', size: 15, color: context.sc.mute),
                    ],
                  ),
                ),
        ),
        SnapSub(
          '사진 ${photos.length}장 · ${made.year}.${made.month}.${made.day} 만듦',
        ),
        const SizedBox(height: 12),
        CategoryChips(
          state: s,
          selected: album.category,
          onSelect: (id) => s.setAlbumCategory(album.id, id),
        ),
        SnapNote(
          album.category == null
              ? '카테고리를 고르면 앨범 탭에서 모아 볼 수 있어요'
              : '고른 카테고리를 한 번 더 누르면 분류가 해제돼요',
          top: 8,
        ),
        const SizedBox(height: 14),
        if (photos.isEmpty)
          const SnapEmpty(icon: 'image', text: '이 앨범의 사진이 삭제되었거나\n숨김 처리되었어요')
        else
          PhotoGrid(items: photos, onTap: (d) => s.openMemory(d.id)),
        SnapButton(
          label: album.locked ? '잠금 풀기' : '앨범 잠그기',
          icon: 'lock',
          ghost: true,
          onTap: () => _toggleLock(album),
        ),
        SnapNote(
          album.locked
              ? '앨범 목록에서는 사진이 가려지고, 열 때마다 비밀번호를 물어요'
              : '잠그면 앨범 목록에서 사진이 가려지고, 비밀번호 4자리로만 열 수 있어요',
        ),
        SnapButton(
          label: '앨범 삭제',
          ghost: true,
          onTap: () => _confirmDelete(album.id, album.title),
        ),
        const SnapNote('앨범을 지워도 사진과 분석 정보는 그대로 남아요'),
      ],
    );
  }
}
