part of '../app_state.dart';

/// 저장·복원 (기기 DB·대기열·앨범·카테고리) · 앱 초기화 · 앱에서 사진 지우기
extension SnapbackStorage on SnapbackState {
  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SnapbackState._onboardedKey, true);
      // 사진 보관함 사진만 다시 찾을 수 있다 (웹 파일은 다시 읽을 수 없음)
      final keys = [
        for (final e in pickQueue)
          if (e.asset != null) e.key,
      ];
      await prefs.setStringList(SnapbackState._queueKey, keys);
      // iOS: 남은 사진이 있으면 충전 중 백그라운드 분석(BGProcessingTask)을 예약할 수 있게 알림
      BackgroundAnalysis.setPending(keys.isNotEmpty);
    } catch (_) {}
  }

  Future<void> _clearQueue() async {
    BackgroundAnalysis.setPending(false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(SnapbackState._queueKey);
    } catch (_) {}
  }

  /// 지난번에 끝나지 않은 대기열을 '일시정지됨'으로 복원한다. 자동으로 다시 분석하지는 않는다(▶로 이어서).
  Future<void> _restoreQueue(SharedPreferences prefs) async {
    final keys = prefs.getStringList(SnapbackState._queueKey);
    if (!useLibrary || keys == null || keys.isEmpty) return;
    try {
      final perm = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );
      if (!perm.hasAccess) return;
      final analyzed = {for (final d in db) d.fileKey, ...removedKeys};
      if (keys.every(analyzed.contains)) {
        await prefs.remove(SnapbackState._queueKey);
        return;
      }
      for (final k in keys) {
        if (!k.startsWith('asset:')) continue;
        final a = await AssetEntity.fromId(k.substring(6));
        if (a == null) continue; // 그사이 지운 사진
        pickQueue.add(
          PickedFileEntry(asset: a, key: k, modified: a.createDateTime),
        );
      }
      if (pickQueue.isEmpty) return;
      analysisTotal = pickQueue.length;
      analysisDone = pickQueue.where((e) => analyzed.contains(e.key)).length;
      analysisPaused = true;
      analysisRunning = false;
      analysisFinished = false;
    } catch (_) {}
  }

  /// 설정 > 앱 초기화: 앱이 저장한 모든 것(분석 정보·앨범·기록·찾은 사진·카테고리·주소 캐시 등)을 지우고
  /// 처음 화면으로. 사진 앱의 원본 사진은 건드리지 않는다. 서버 주소 설정은 남긴다.
  Future<void> resetAll() async {
    _runId++; // 진행 중인 분석 중지
    _relabelRun++;
    _searchRunId++;
    _liveActivity.cancel();
    _saveTimer?.cancel();
    db = [];
    _nextId = 12;
    _backfillRun++;
    _queryVectors.clear();
    _searchUndo.clear();
    albums = [];
    unlockedAlbumId = null;
    customCategories = [];
    records = [];
    found = [];
    placeNames.clear();
    _placeAsked.clear();
    _placeFails.clear();
    _albumPlans.clear();
    _searchCache.clear();
    removedKeys.clear();
    pickQueue.clear();
    pickedAssetIds.clear();
    _failedKeys.clear();
    analysisFailed = 0;
    pickNotice = '';
    analysisRunning = false;
    analysisPaused = false;
    analysisFinished = false;
    analysisTotal = 0;
    analysisDone = 0;
    relabelRunning = false;
    relabelFinished = false;
    albumSuggestions = [];
    albumDraft = null;
    albumDraftSelected.clear();
    recordDraft = null;
    searchHistory.clear();
    searchResults = [];
    activeQuestion = null;
    pinnedResultId = null;
    _pinBack.clear();
    albumFilter = null;
    recordsView = 'default';
    photoSort = 'time';
    scopeReturn = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [
        SnapbackState._dbKey,
        SnapbackState._albumsKey,
        SnapbackState._categoriesKey,
        SnapbackState._recordsKey,
        SnapbackState._foundKey,
        SnapbackState._placeNamesKey,
        SnapbackState._queueKey,
        SnapbackState._removedKey,
        SnapbackState._onboardedKey,
        SnapbackState._albumPlansKey,
        SnapbackState._photoSortKey,
        SnapbackState._searchCacheKey,
      ]) {
        await prefs.remove(k);
      }
    } catch (_) {}
    await PreviewStore.clear(); // 웹: 미리보기·DB
    await EmbeddingStore.clear(); // 사진 임베딩
    go(0);
  }

  /// 앱에서 사진 지우기 (분석 정보·썸네일·앨범/기록/찾은 사진 연결만 삭제, 원본은 그대로)
  void removePhotos(Set<int> ids) {
    if (ids.isEmpty) return;
    for (final d in db.where((d) => ids.contains(d.id))) {
      removedKeys.add(SnapbackState._removalKey(d));
    }
    db.removeWhere((d) => ids.contains(d.id));
    EmbeddingStore.remove(ids).ignore();
    for (final a in albums) {
      a.photoIds.removeWhere(ids.contains);
    }
    records.removeWhere((r) => ids.contains(r.photoId));
    for (final r in records) {
      r.linkedPhotoIds.removeWhere(ids.contains);
    }
    found.removeWhere((f) => ids.contains(f.id));
    searchResults = searchResults.where((x) => !ids.contains(x.id)).toList();
    touch();
    _saveDb();
    _saveAlbums();
    _saveRecords();
    _saveFound();
    SharedPreferences.getInstance()
        .then((p) => p.setStringList(SnapbackState._removedKey, removedKeys.toList()))
        .catchError((_) => true);
  }

  /// 분석 중엔 사진마다 전체 DB 를 쓰지 않고 2초에 한 번으로 묶어 저장 (웹·휴대폰 부담 줄이기)
  void _saveDbSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveDb);
  }

  Future<void> _saveDb() async {
    _saveTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(
        db.where((d) => d.id > 11).map((d) => d.toJson()).toList(),
      );
      // 웹: localStorage 는 약 5MB 라 사진이 많으면 저장이 조용히 실패한다 → IndexedDB 에 저장
      if (kIsWeb &&
          PreviewStore.enabled &&
          await PreviewStore.put(
            SnapbackState._webDbKey,
            Uint8List.fromList(utf8.encode(json)),
          )) {
        await prefs.remove(SnapbackState._dbKey); // localStorage 비워 앨범·기록 저장 공간 확보
        return;
      }
      await prefs.setString(SnapbackState._dbKey, json);
    } catch (_) {}
  }

  Future<void> _saveAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SnapbackState._albumsKey,
        jsonEncode(albums.map((a) => a.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _saveCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SnapbackState._categoriesKey,
        jsonEncode(customCategories.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}
  }
}
