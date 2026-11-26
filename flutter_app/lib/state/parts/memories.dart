part of '../app_state.dart';

/// 사진 탭 · 기억 탭: 다시 꺼내 볼 기억 · 정렬 · 찾은 사진과 기억 학습 · 관련된 추억
extension SnapbackMemories on SnapbackState {
  void setPhotoSort(String v) {
    if (v != 'time' && v != 'added') return;
    photoSort = v;
    touch();
    SharedPreferences.getInstance()
        .then((p) => p.setString(SnapbackState._photoSortKey, v))
        .ignore();
  }

  /// 오늘 다시 볼 사진 1장과 제목.
  /// 우선순위: 지난해 같은 날 찍은 사진 → 기록으로 남긴 사진 → 검색으로 찾은 사진 → 장소가 있는 사진.
  /// 여러 장이면 날짜마다 돌아가며 보여준다.
  (PhotoItem, String)? resurfaceMemory() {
    final photos = visiblePhotos.toList();
    if (photos.isEmpty) return null;
    final now = DateTime.now();
    final md =
        '-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final byId = {for (final d in photos) d.id: d};
    final tiers = <List<PhotoItem>>[
      photos
          .where(
            (d) => d.date.endsWith(md) && !d.date.startsWith('${now.year}'),
          )
          .toList(),
      [for (final r in records) ?byId[r.photoId]],
      [for (final f in found) ?byId[f.id]],
      photos.where((d) => d.place.isNotEmpty && d.place != '알 수 없음').toList(),
      photos,
    ];
    final pool = tiers.firstWhere((t) => t.isNotEmpty);
    final day = now.difference(DateTime(now.year)).inDays;
    final pick = pool[day % pool.length];
    return (pick, memoryTitle(pick));
  }

  /// 사진 한 장의 짧은 제목: 기록 제목 → '비 오는 날 성수동 카페' 처럼 날씨 + 장소 → 캡션
  String memoryTitle(PhotoItem d) {
    final r = recordForPhoto(d.id);
    if (r != null && r.title.isNotEmpty) return r.title;
    // '카페(성수동)' → '성수동 카페'
    final m = RegExp(r'^(.+?)\((.+)\)$').firstMatch(d.place.trim());
    final place = m != null ? '${m.group(2)} ${m.group(1)}' : d.place.trim();
    final weather = switch (d.weather) {
      '비' => '비 오는 날 ',
      '눈' => '눈 오는 날 ',
      '맑음' => '맑은 날 ',
      _ => d.time == '밤' ? '밤의 ' : '',
    };
    if (place.isNotEmpty && place != '알 수 없음') return '$weather$place';
    return d.caption.isNotEmpty ? d.caption : '그날의 사진';
  }

  /// '맞아요'(또는 후보 선택)로 찾은 사진에 그 기억을 키워드로 붙인다.
  /// 화면은 바로 넘어가고 키워드는 뒤에서 받는다. AI 호출이 실패하면 검색 결과의
  /// '확인 안 된 단서'(missing)와 질문 답을 대신 붙인다.
  /// 처음 나온 낱말은 '대기'(순위에 안 씀), 다른 검색에서 또 나오면 '확정'(순위에 씀) — [PhotoItem.withRecall].
  Future<void> _learnFromFound(int id) async {
    if (searchHistory.isEmpty) return;
    final query = searchHistory.first.trim();
    final qaPattern = RegExp(r'^Q:\s*(.+?)\s*/\s*A:\s*(.+)$');
    final qa = <(String, String)>[
      for (final h in searchHistory.skip(1))
        if (qaPattern.firstMatch(h) case final m?)
          (m.group(1)!.trim(), m.group(2)!.trim()),
    ];
    const vague = {'네', '예', '아니요', '아니오', '모르겠어요', '잘 모르겠어요', '건너뛰기', '상관없어요'};
    final answers = [for (final (q, a) in qa) '$q → $a'];
    final fallback = [
      ...?searchResults.where((r) => r.id == id).firstOrNull?.missing,
      for (final (_, a) in qa)
        if (!vague.contains(a)) a,
    ];
    final photo = db.where((d) => d.id == id).firstOrNull;
    if (query.isEmpty || photo == null) return;
    List<String> keywords;
    try {
      keywords = await api.recallKeywords(photo, query, answers: answers);
    } catch (_) {
      keywords = fallback;
    }
    // 사용자가 실제로 말한 낱말만, 사진 정보에 이미 있는 낱말은 빼고 (대체 키워드에도 같은 기준)
    final said = '$query ${answers.join(' ')}'.toLowerCase();
    final known = jsonEncode(photo.toJson(includeThumb: false)).toLowerCase();
    keywords = [
      for (final k in keywords.map((e) => e.trim()))
        if (k.isNotEmpty &&
            k.length <= 15 &&
            !k.contains('단서') &&
            !k.contains('낱말') &&
            said.contains(k.toLowerCase()) &&
            !known.contains(k.toLowerCase()))
          k,
    ];
    final i = db.indexWhere((d) => d.id == id); // 그사이 지워졌을 수 있음
    if (i < 0) return;
    final before = db[i].recallKeywords.join('|');
    db[i] = db[i].withRecall(keywords, query);
    _saveDbSoon();
    touch();
    // 확정 키워드가 바뀌면 그 사진 임베딩도 조용히 다시 만든다
    if (db[i].recallKeywords.join('|') != before) refreshEmbedding(id).ignore();
  }

  void _rememberFound(int id) {
    _learnFromFound(id).ignore();
    final q = searchHistory.isNotEmpty ? searchHistory.first : '';
    found
      ..removeWhere((f) => f.id == id)
      ..insert(
        0,
        FoundMemory(
          id: id,
          atMs: DateTime.now().millisecondsSinceEpoch,
          query: q,
        ),
      );
    _saveFound();
  }

  /// 기억 탭에 보여줄 사진 (삭제·숨김된 사진 제외)
  List<PhotoItem> get foundPhotos {
    final byId = {for (final d in visiblePhotos) d.id: d};
    return [
      for (final f in found)
        if (byId[f.id] != null) byId[f.id]!,
    ];
  }

  void forgetFound(int id) {
    found.removeWhere((f) => f.id == id);
    touch();
    _saveFound();
  }

  Future<void> _saveFound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SnapbackState._foundKey,
        jsonEncode(found.map((f) => f.toJson()).toList()),
      );
    } catch (_) {}
  }

  void openRelatedAlbum(int kind) {
    _relatedNav.add((10, activeMemoryId, 0));
    relatedAlbumKind = kind;
    relatedBaseId = activeMemoryId;
    go(18);
  }

  /// 관련 앨범 안에서 사진을 눌러 상세로 (뒤로가기 시 앨범으로 돌아옴)
  void openFromRelatedAlbum(int id) {
    _relatedNav.add((18, relatedBaseId, relatedAlbumKind));
    activeMemoryId = id;
    go(10);
  }

  /// 관련 앨범 이동 기록이 있으면 한 단계 되돌아가고 true.
  bool backFromRelated() {
    if (_relatedNav.isEmpty) return false;
    final (scr, base, kind) = _relatedNav.removeLast();
    if (scr == 10) {
      activeMemoryId = base;
    } else {
      relatedBaseId = base;
      relatedAlbumKind = kind;
    }
    go(scr);
    return true;
  }

  RelatedMemories relatedFor(PhotoItem d) {
    final others = visiblePhotos.where((x) => x.id != d.id).toList();
    final sameDay = others.where((x) => x.date == d.date).toList();
    final nearPlace = others
        .where((x) => x.date != d.date && SnapbackState._distanceKm(d.gps, x.gps) < 1.5)
        .toList();
    final baseTokens = SnapbackState._tokens(d);
    final simPairs =
        others
            // 같은 날이 아니고, 카테고리나 키워드가 하나라도 같은 사진만
            .where((x) => x.date != d.date && SnapbackState.sharesTopic(d, x))
            .map((x) => MapEntry(x, SnapbackState._tokens(x).intersection(baseTokens).length))
            .where((e) => e.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final similarMood = simPairs.take(6).map((e) => e.key).toList();
    return RelatedMemories(
      sameDay: sameDay,
      nearPlace: nearPlace,
      similarMood: similarMood,
    );
  }
}
