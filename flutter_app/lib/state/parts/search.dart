part of '../app_state.dart';

/// 기억으로 찾기: 검색 · 질문 · 후보 · 되돌리기 · 결과 캐시
extension SnapbackSearch on SnapbackState {
  /// 다른 후보(또는 '1순위 보기')를 크게 보기. 바로 전에 보던 사진을 기록해 둔다.
  void pinResult(int? id) {
    if (id == pinnedResultId) return;
    _pinBack.add(pinnedResultId);
    pinnedResultId = id;
    touch();
  }

  /// 뒤로가기: 바로 전에 크게 보던 사진으로. 돌아갈 단계가 없으면 false.
  bool popPinnedResult() {
    if (_pinBack.isEmpty) return false;
    pinnedResultId = _pinBack.removeLast();
    touch();
    return true;
  }

  /// 질문에 답한 단계가 있어 되돌릴 수 있는지
  bool get canUndoSearch => _searchUndo.isNotEmpty;

  /// 직전 답(질문·제외 상태)만 취소하고 바로 이전 후보 화면으로 (다시 검색하지 않음)
  void undoLastAnswer() {
    if (_searchUndo.isEmpty) return;
    _searchRunId++; // 진행 중이던 검색 결과는 무시
    _searchUndo.removeLast().restore(this);
    searchBusy = false;
    searchError = null;
    _pinBack.clear();
    touch();
  }

  void resetSearch() {
    pinnedResultId = null;
    _pinBack.clear();
    _searchRunId++; // 진행 중이던 검색 결과는 무시
    searchHistory.clear();
    searchPool.clear();
    searchExcluded.clear();
    _searchUndo.clear();
    searchResults = [];
    activeQuestion = null;
    currentQuestionText = '';
    questionShown = false;
    searchCompleted = false;
    searchError = null;
    searchBusy = false;
  }

  /// 홈·기억 탭에서 '새 검색'으로 검색 화면 열기
  void openNewSearch() {
    resetSearch();
    go(13);
  }

  void openSearchFrom(Rect origin) {
    resetSearch();
    _searchOrigin = origin;
    screen = 13;
    seamlessSwitch = true;
    touch();
  }

  /// 검색창이 홈 자리까지 올라간 뒤 호출: 크로스페이드 없이 홈으로 전환.
  void returnHomeFromSearch() {
    _homeReturn = true;
    screen = 5;
    seamlessSwitch = true;
    touch();
  }

  /// 홈이 '검색에서 돌아옴' 여부를 한 번만 가져간다.
  bool takeHomeReturn() {
    final r = _homeReturn;
    _homeReturn = false;
    return r;
  }

  /// 검색 화면이 진입 애니메이션 시작 위치를 한 번만 가져간다.
  Rect? takeSearchOrigin() {
    final r = _searchOrigin;
    _searchOrigin = null;
    return r;
  }

  void openMemory(int id) {
    if (screen == 13) _rememberFound(id);
    if (screen != 10) detailReturn = screen;
    _relatedNav.clear();
    activeMemoryId = id;
    go(10);
  }

  Future<void> startNewSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty || searchBusy) return;
    searchHistory
      ..clear()
      ..add(q);
    searchPool.clear();
    searchExcluded.clear();
    _searchUndo.clear();
    await _runSearch();
  }

  Future<void> answerFollowUp(String answer) async {
    if (searchBusy) return;
    _searchUndo.add(_SearchSnapshot.of(this)); // '이전 단계로 되돌리기'용
    // 답하기 전에 크게 보고 있던 사진은 아니라는 뜻 → 제외하고 나머지 후보에서 찾는다
    if (shownResultId case final id?) searchExcluded.add(id);
    searchHistory.add('Q: $currentQuestionText / A: $answer');
    await _runSearch(withinPool: true);
  }

  /// '질문 한 번 더하기' — 검색을 처음부터 하지 않고 지금 맥락(searchHistory)에 질문 하나를 더한다.
  Future<void> askMore() async {
    if (searchBusy || searchResults.isEmpty) return;
    if (activeQuestion != null) {
      questionShown = true; // 서버가 이미 만들어 둔 질문이 있으면 바로 보여줌
      touch();
      return;
    }
    // 이미 질문에 답했다면 '질문 더하기'도 처음 후보 30개 안에서
    await _runSearch(wantQuestion: true, withinPool: searchHistory.length > 1);
  }

  void _rememberSearch(String key, SearchResponse res) {
    _searchCache.remove(key); // 최근 검색을 뒤로 (오래된 것부터 정리)
    _searchCache[key] = res.toJson();
    while (_searchCache.length > 30) {
      _searchCache.remove(_searchCache.keys.first);
    }
    SharedPreferences.getInstance()
        .then((p) => p.setString(SnapbackState._searchCacheKey, jsonEncode(_searchCache)))
        .ignore();
  }

  /// [withinPool] true 면 처음 검색의 상위 30개 후보([searchPool]) 안에서만 다시 순위를 매긴다.
  Future<void> _runSearch({
    bool wantQuestion = false,
    bool withinPool = false,
  }) async {
    if (!serverConnected) {
      searchError = ApiException('network').userMessage;
      searchResults = [];
      activeQuestion = null;
      searchCompleted = false;
      touch();
      return;
    }
    searchBusy = true;
    searchError = null;
    searchCompleted = false;
    questionShown = false;
    touch();

    final run = _searchRunId;
    final inPool = withinPool && searchPool.isNotEmpty;
    final pool = searchPool.toSet();
    var photos = [
      for (final d in visiblePhotos)
        if ((!inPool || pool.contains(d.id)) && !searchExcluded.contains(d.id))
          d,
    ];
    try {
      // 첫 검색: 사진이 많으면 기기 안에서 하이브리드 1차 선별 (답한 뒤에는 이미 고른 후보 안에서 찾음)
      if (!inPool && searchHistory.isNotEmpty) {
        photos = await narrowForAi(photos, searchHistory.first);
        if (run != _searchRunId) return;
      }
      final key = SnapbackApi.searchKey(
        photos,
        searchHistory,
        wantQuestion: wantQuestion,
        addr: addressById,
      );
      final cached = _searchCache[key];
      final res = cached != null
          ? SearchResponse.fromJson(cached)
          : await api.searchMemory(
              photos,
              searchHistory,
              wantQuestion: wantQuestion,
              addr: addressById,
            );
      if (run != _searchRunId) return; // 그사이 새 검색을 시작함
      if (cached == null) _rememberSearch(key, res);
      // 처음 검색(후보 안에서 다시 찾는 게 아닐 때)의 상위 30개를 후보로 기억
      if (!inPool) {
        searchPool
          ..clear()
          ..addAll(res.pool);
      }
      searchResults = res.ranked.toList();
      pinnedResultId = null; // 순위가 새로 나오면 다시 1순위부터
      _pinBack.clear();
      activeQuestion = res.question;
      if (res.question != null) {
        currentQuestionText = res.question!.text;
        searchCompleted = false;
      } else {
        searchCompleted = true;
      }
      questionShown = wantQuestion;
    } on ApiException catch (e) {
      if (run == _searchRunId) searchError = e.userMessage;
    } catch (e) {
      if (run == _searchRunId) searchError = '오류가 났어요 ($e)';
    } finally {
      // 이미 새 검색이 시작됐다면 그 검색의 상태는 건드리지 않는다
      if (run == _searchRunId) {
        searchBusy = false;
        touch();
      }
    }
  }
}
