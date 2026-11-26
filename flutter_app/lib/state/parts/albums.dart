part of '../app_state.dart';

/// 앨범: 자연어 앨범 만들기 · 월간 리캡 · 미리보기 · 카테고리 · 앨범 열기·삭제
extension SnapbackAlbums on SnapbackState {
  /// AI 대화형 앨범: 요청을 보내 후보를 받고 미리보기(17)로 이동. 바로 저장하지 않는다.
  void _rememberAlbumPlan(String key, Map<String, dynamic> plan) {
    _albumPlans.remove(key); // 최근에 쓴 요청을 뒤로 (오래된 것부터 정리)
    _albumPlans[key] = plan;
    while (_albumPlans.length > 50) {
      _albumPlans.remove(_albumPlans.keys.first);
    }
    SharedPreferences.getInstance()
        .then((p) => p.setString(SnapbackState._albumPlansKey, jsonEncode(_albumPlans)))
        .ignore();
  }

  Future<void> composeAlbum(String request) async {
    final q = request.trim();
    if (q.isEmpty || albumBusy) return;
    if (!serverConnected) {
      albumError = ApiException('network').userMessage;
      touch();
      return;
    }
    albumBusy = true;
    albumError = null;
    touch();
    try {
      // 위치로 찾을 수 있게 주소를 잠깐(최대 8초) 더 받아 두고 보낸다
      await prefetchAddresses(wait: const Duration(seconds: 8));
      final planKey = q.replaceAll(RegExp(r'\s+'), ' ');
      // 사진이 많으면 하이브리드 1차 선별 (제외 조건이 있으면 넉넉히 — 실제 제외는 서버·AI 가 판정)
      final candidates = await narrowForAi(
        visiblePhotos,
        q,
        wide: hasExcludeCondition(q),
      );
      final (title, ids, category, reason, plan) = await api.composeAlbum(
        candidates,
        q,
        addr: addressById,
        plan: _albumPlans[planKey],
        categories: [
          for (final c in allCategories)
            {
              'id': c.id,
              'label': c.label,
              if (c.hint.isNotEmpty) 'hint': c.hint,
            },
        ],
      );
      if (plan != null) _rememberAlbumPlan(planKey, plan);
      final byId = {for (final d in db) d.id: d};
      final valid = ids.where(byId.containsKey).toList();
      if (valid.isEmpty) {
        final noLocation = visiblePhotos.every((d) => d.gps == null);
        albumError = [
          '조건에 맞는 사진을 찾지 못했어요.',
          if (reason.isNotEmpty) reason,
          if (noLocation) '위치 정보가 있는 사진이 없어 장소로는 찾기 어려워요.',
        ].join(' ');
      } else {
        albumDraft = AlbumSuggestion(
          title: title.isEmpty ? q : title,
          emoji: byId[valid.first]!.emoji,
          photoIds: valid,
          category: categoryById(category)?.id,
        );
        albumDraftSelected.clear();
        albumDraftReturn = 11;
        screen = 17;
        seamlessSwitch = false;
      }
    } on ApiException catch (e) {
      albumError = e.userMessage;
    } catch (e) {
      albumError = '오류가 났어요 ($e)';
    } finally {
      albumBusy = false;
      touch();
    }
  }

  /// 관련된 추억(그날의 사진 · 비슷한 분위기)의 사진들로 앨범 초안을 만들어 미리보기로.
  /// 기준 사진도 맨 앞에 함께 넣는다.
  /// 월간 리캡 (사진이 있는 가장 최근 달): 자주 간 동네·먹은 음식·분위기 요약과 자동 앨범 후보
  MonthlyRecap? get monthlyRecap =>
      buildMonthlyRecap(visiblePhotos, addr: addressById);

  /// 사진 목록으로 앨범 미리보기 열기 (월간 리캡 자동 앨범 등). 미리보기에서 뺄 사진·이름을 다듬고 저장.
  void draftAlbum(String title, List<int> ids, {int returnTo = 5}) {
    final valid = [
      for (final id in ids)
        if (photoById(id) != null) id,
    ];
    if (valid.isEmpty) return;
    albumDraft = AlbumSuggestion(
      title: title,
      emoji: photoById(valid.first)!.emoji,
      photoIds: valid,
      category: 'memories',
    );
    albumDraftSelected.clear();
    albumDraftReturn = returnTo;
    go(17);
  }

  void draftAlbumFromRelated(
    String title,
    PhotoItem base,
    List<PhotoItem> photos,
  ) {
    final ids = [
      base.id,
      ...photos.map((p) => p.id).where((id) => id != base.id),
    ];
    albumDraft = AlbumSuggestion(
      title: title,
      emoji: base.emoji,
      photoIds: ids,
      category: 'memories',
    );
    albumDraftSelected.clear();
    albumDraftReturn = 18;
    go(17);
  }

  Future<void> loadAlbumSuggestions() async {
    final photos = visiblePhotos.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (!serverConnected || photos.isEmpty || albumSuggestionsLoading) return;
    albumSuggestionsLoading = true;
    touch();
    try {
      albumSuggestions = await api.suggestAlbums(
        photos.take(300).toList(),
        addr: addressById,
      );
    } catch (_) {
      // 실패하면 기본 예시 그대로
    } finally {
      albumSuggestionsLoading = false;
      touch();
    }
  }

  /// 미리보기 사진 전체 선택(=해제 목록 비우기) / 전체 해제
  void setAllDraftPhotos(bool selected) {
    albumDraftSelected.clear();
    if (!selected) albumDraftSelected.addAll(albumDraft?.photoIds ?? const []);
    touch();
  }

  /// 미리보기에서 사진 선택/해제 (albumDraftSelected = 앨범에서 뺄 사진)
  void toggleDraftPhoto(int id) {
    if (!albumDraftSelected.remove(id)) albumDraftSelected.add(id);
    touch();
  }

  /// 미리보기에서 선택한(원하지 않는) 사진을 후보에서 뺀다.
  void excludeSelectedDraftPhotos() {
    final d = albumDraft;
    if (d == null || albumDraftSelected.isEmpty) return;
    albumDraft = AlbumSuggestion(
      title: d.title,
      emoji: d.emoji,
      photoIds: d.photoIds
          .where((id) => !albumDraftSelected.contains(id))
          .toList(),
      category: d.category,
    );
    albumDraftSelected.clear();
    touch();
  }

  /// 최종 확인 → 앨범 저장 후 앨범 상세로.
  /// 앨범 만들기: 미리보기에서 선택 해제한 사진([albumDraftSelected])은 빼고 선택된 사진만 담는다
  void confirmAlbumDraft(String title) {
    final d = albumDraft;
    if (d == null) return;
    final kept = d.photoIds
        .where((id) => !albumDraftSelected.contains(id))
        .toList();
    if (kept.isEmpty) return;
    createAlbumFromSuggestion(
      AlbumSuggestion(
        title: d.title,
        emoji: d.emoji,
        photoIds: kept,
        category: d.category,
      ),
      title,
    );
    albumDraft = null;
    albumDraftSelected.clear();
    openAlbum(lastCreatedAlbumId!);
  }

  void createAlbumFromSuggestion(AlbumSuggestion sug, String title) {
    final t = title.trim().isEmpty ? sug.title : title.trim();
    final id = albums.fold<int>(0, (m, a) => a.id > m ? a.id : m) + 1;
    albums.insert(
      0,
      PhotoAlbum(
        id: id,
        title: t,
        emoji: sug.emoji,
        photoIds: List.of(sug.photoIds),
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        category: sug.category,
      ),
    );
    lastCreatedAlbumId = id;
    touch();
    _saveAlbums();
  }

  PhotoAlbum? albumById(int? id) {
    for (final a in albums) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// 앨범에 담긴 사진 중 아직 DB 에 있고 숨김 처리되지 않은 것.
  List<PhotoItem> albumPhotos(PhotoAlbum album) {
    final byId = {for (final d in visiblePhotos) d.id: d};
    return [
      for (final id in album.photoIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  AlbumCategory? categoryById(String? id) {
    if (id == null) return null;
    for (final c in allCategories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 필터에 맞는 앨범. 카테고리 없는 앨범은 '전체'에서만 보인다.
  List<PhotoAlbum> get filteredAlbums => albumFilter == null
      ? albums
      : albums.where((a) => a.category == albumFilter).toList();

  void setAlbumFilter(String? id) {
    albumFilter = id;
    touch();
  }

  /// 사용자 정의 카테고리 추가. 같은 이름이 있으면 그것을 돌려준다.
  AlbumCategory? addCategory(String label) {
    final t = label.trim();
    if (t.isEmpty) return null;
    final name = t.length > 12 ? t.substring(0, 12) : t;
    for (final c in allCategories) {
      if (c.label == name) return c;
    }
    final c = AlbumCategory(
      id: 'c${DateTime.now().millisecondsSinceEpoch}',
      label: name,
    );
    customCategories.add(c);
    touch();
    _saveCategories();
    return c;
  }

  /// 사용자 정의 카테고리 삭제. 그 카테고리의 앨범은 '분류 없음'으로 돌아간다(앨범은 유지).
  void removeCategory(String id) {
    if (!customCategories.any((c) => c.id == id)) return;
    customCategories.removeWhere((c) => c.id == id);
    for (final a in albums) {
      if (a.category == id) a.category = null;
    }
    if (albumFilter == id) albumFilter = null;
    if (albumDraft?.category == id) setDraftCategory(null);
    touch();
    _saveCategories();
    _saveAlbums();
  }

  /// 앨범 이름 바꾸기 (빈 이름이면 그대로)
  void renameAlbum(int albumId, String title) {
    final a = albumById(albumId);
    final t = title.trim();
    if (a == null || t.isEmpty || t == a.title) return;
    a.title = t.length > 30 ? t.substring(0, 30) : t;
    touch();
    _saveAlbums();
  }

  void setAlbumCategory(int albumId, String? category) {
    final a = albumById(albumId);
    if (a == null) return;
    a.category = category;
    touch();
    _saveAlbums();
  }

  /// 미리보기에서 AI 추천 카테고리를 바꾼다.
  void setDraftCategory(String? category) {
    final d = albumDraft;
    if (d == null) return;
    albumDraft = AlbumSuggestion(
      title: d.title,
      emoji: d.emoji,
      photoIds: d.photoIds,
      category: category,
    );
    touch();
  }

  void openAlbum(int id) {
    activeAlbumId = id;
    unlockedAlbumId = null; // 앨범 목록에서 들어올 때마다 다시 잠김
    go(16);
  }

  void deleteAlbum(int id) {
    albums.removeWhere((a) => a.id == id);
    if (lastCreatedAlbumId == id) lastCreatedAlbumId = null;
    if (activeAlbumId == id) activeAlbumId = null;
    touch();
    _saveAlbums();
  }
}
