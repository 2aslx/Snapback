part of '../app_state.dart';

/// 사진 가져오기: iOS 사진 보관함 · 사진 직접 고르기 · 웹 파일 선택 · 분석 대기열 만들기
extension SnapbackLibrary on SnapbackState {
  /// iOS 앱은 사진 보관함을 직접 읽는다. 웹은 파일 선택.
  bool get useLibrary => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get libraryDenied =>
      libraryPermission != null && !libraryPermission!.hasAccess;

  /// 화면이 처음 그려질 때 한 번만 사진 보관함 정보를 불러온다.
  void ensureLibraryOnce() {
    if (!useLibrary || _libLoading || libraryPermission != null) return;
    _libLoading = true;
    Future.microtask(() async {
      await ensureLibrary();
      _libLoading = false;
    });
  }

  Future<bool> ensureLibrary() async {
    if (!useLibrary) return false;
    libraryPermission = await PhotoManager.requestPermissionExtend();
    if (!libraryPermission!.hasAccess) {
      touch();
      return false;
    }
    final paths = await PhotoManager.getAssetPathList(type: RequestType.image);
    _allPath = paths.where((p) => p.isAll).firstOrNull ?? paths.firstOrNull;
    libraryCount = await _allPath?.assetCountAsync ?? 0;
    libraryAlbumsLoading = true;
    touch();
    final albums = <LibraryAlbum>[];
    for (final p in paths.where((p) => !p.isAll)) {
      final n = await p.assetCountAsync;
      if (n == 0) continue; // 빈 앨범(빈 스마트 앨범 등)은 숨김
      final cover = (await p.getAssetListRange(start: 0, end: 1)).firstOrNull;
      albums.add(LibraryAlbum(p, n, cover));
    }
    libraryAlbums = albums;
    // 사라진 앨범은 선택에서 뺀다
    selectedAlbumIds.retainAll(albums.map((a) => a.path.id));
    libraryAlbumsLoading = false;
    touch();
    return true;
  }

  void toggleLibraryAlbum(String id) {
    if (!selectedAlbumIds.remove(id)) selectedAlbumIds.add(id);
    touch();
  }

  /// 고른 앨범들의 사진 수 합 (앨범끼리 겹치는 사진은 분석할 때 한 번만 들어감)
  int get selectedAlbumPhotoCount => libraryAlbums
      .where((a) => selectedAlbumIds.contains(a.path.id))
      .fold(0, (n, a) => n + a.count);

  Future<void> openLibrarySettings() => PhotoManager.openSetting();

  /// '사진 직접 고르기' 그리드용 — 최근 사진부터 120장씩.
  Future<void> loadPickerAssets({bool more = false}) async {
    if (_allPath == null && !await ensureLibrary()) return;
    final path = _allPath;
    if (path == null) return;
    if (pickerLoading) return;
    pickerLoading = true;
    touch();
    final start = more ? pickerAssets.length : 0;
    final page = await path.getAssetListRange(start: start, end: start + 120);
    pickerAssets = more ? [...pickerAssets, ...page] : page;
    pickerHasMore = pickerAssets.length < libraryCount;
    pickerLoading = false;
    touch();
  }

  void togglePickAsset(String id) {
    if (!pickedAssetIds.remove(id)) pickedAssetIds.add(id);
    touch();
  }

  void _enqueueAssets(Iterable<AssetEntity> assets) {
    final seen = pickQueue.map((e) => e.key).toSet();
    for (final a in assets) {
      final k = 'asset:${a.id}';
      if (seen.add(k)) {
        pickQueue.add(
          PickedFileEntry(asset: a, key: k, modified: a.createDateTime),
        );
      }
    }
  }

  /// 지난 분석이 끝났으면 새 묶음을 시작: 끝난 사진(분석됨·지움·실패)을 대기열에서 빼서
  /// 다음에 올린 사진만 센다. 분석이 아직 진행 중이면 그 묶음에 더해진다.
  void prepareNewBatch() {
    if (!analysisFinished) return;
    final done = {for (final d in db) d.fileKey, ...removedKeys};
    pickQueue.removeWhere(
      (e) =>
          (done.contains(e.key) || _failedKeys.contains(e.key)) &&
          !_inFlight.contains(e.key),
    );
    _failedKeys.clear();
    analysisFailed = 0;
    analysisFinished = false;
    analysisTotal = 0;
    analysisDone = 0;
  }

  String _skipNotice(int picked, int added, int already, int dup) {
    if (already == 0 && dup == 0) return '';
    return [
      '고른 사진 $picked장 중 $added장을 분석해요',
      if (already > 0) '이미 분석한 사진 $already장은 건너뛰었어요',
      if (dup > 0) '이미 대기 중인 사진 $dup장은 한 번만 분석해요',
    ].join(' · ');
  }

  /// '직접 고르기'에서 고른 사진을 대기열에 넣고 (홈 ＋로 왔으면 바로 분석 시작) 돌아간다.
  void confirmPickedAssets() {
    prepareNewBatch();
    final chosen = pickerAssets
        .where((a) => pickedAssetIds.contains(a.id))
        .toList();
    final analyzed = {for (final d in db) d.fileKey, ...removedKeys};
    final already = chosen
        .where((a) => analyzed.contains('asset:${a.id}'))
        .length;
    pickNotice = _skipNotice(
      chosen.length,
      chosen.length - already,
      already,
      0,
    );
    _enqueueAssets(chosen);
    pickedAssetIds.clear();
    if (_startAfterPick) {
      _startAfterPick = false;
      go(5);
      startAnalysis();
    } else {
      go(3);
    }
  }

  /// '사진 접근 범위' + '분석 순서' 기준으로 사진 보관함에서 분석할 사진을 고른다.
  Future<int> queueFromLibrary() async {
    if (!await ensureLibrary()) return 0;
    prepareNewBatch();
    if (scopeSelection == 2) return pickQueue.length; // 직접 고른 사진 그대로
    // 메타데이터만 읽으므로 가볍다. 순서 기준으로 정렬한 뒤 상한만큼 담는다.
    var list = <AssetEntity>[];
    if (scopeSelection == 1) {
      // 고른 앨범들을 합치고, 여러 앨범에 같은 사진이 있으면 한 번만
      final seen = <String>{};
      for (final a in libraryAlbums.where(
        (a) => selectedAlbumIds.contains(a.path.id),
      )) {
        final page = await a.path.getAssetListRange(
          start: 0,
          end: math.min(a.count, 3000),
        );
        list.addAll(page.where((x) => seen.add(x.id)));
      }
      if (list.isEmpty) return 0;
    } else {
      final path = _allPath;
      if (path == null) return 0;
      final total = await path.assetCountAsync;
      list = await path.getAssetListRange(start: 0, end: math.min(total, 3000));
    }
    if (scopeSelection == 3) {
      list = list
          .where((a) => !a.createDateTime.isBefore(DateTime(2022)))
          .toList();
    }
    list.sort((a, b) => compareForOrder(a.createDateTime, b.createDateTime));
    // 이미 분석한 사진은 빼고 상한만큼 담는다 (분석한 사진이 자리를 차지하지 않게)
    final analyzed = {for (final d in db) d.fileKey, ...removedKeys};
    _enqueueAssets(
      list
          .where((a) => !analyzed.contains('asset:${a.id}'))
          .take(kMaxLibraryQueue),
    );
    touch();
    return pickQueue.length;
  }

  /// 홈 ＋: iOS 는 사진 접근 범위 → (직접 고르기) → 분석 순서 → 분석 시작 흐름으로.
  /// 웹은 사진 보관함이 없어 바로 파일 선택.
  void openAddPhotos() {
    if (!useLibrary) {
      pickPhotosFromGallery(startImmediately: true);
      return;
    }
    _startAfterPick = false;
    scopeReturn = 5;
    go(1);
  }

  Future<int> pickPhotosFromGallery({bool startImmediately = false}) async {
    if (useLibrary) {
      // iOS: 사진 보관함 그리드에서 직접 고르기 (② 사진 직접 고르기)
      _startAfterPick = startImmediately;
      scopeSelection = 2;
      go(2);
      await loadPickerAssets();
      return 0;
    }
    pickNotice = ''; // 이전 안내는 지움
    List<XFile> files;
    try {
      files = await _picker.pickMultiImage();
    } catch (e) {
      // 앱 안 브라우저(카카오톡·인스타그램 등)나 브라우저 설정 때문에 파일 선택이 막힌 경우
      pickNotice = '사진을 불러오지 못했어요. Safari·Chrome 같은 기본 브라우저에서 다시 시도해 주세요.';
      touch();
      return 0;
    }
    if (files.isEmpty) return 0;
    // 분석이 끝난 묶음이면 먼저 비워서, 이번에 올린 사진만 세게 한다
    prepareNewBatch();
    final seen = pickQueue.map((e) => e.key).toSet();
    final analyzed = {for (final d in db) d.fileKey, ...removedKeys};
    var added = 0, already = 0, dup = 0;
    for (final f in files) {
      final len = await f.length();
      final mod = await f.lastModified();
      final k = '${f.name}$len${mod.millisecondsSinceEpoch}';
      if (analyzed.contains(k)) {
        already++;
      } else if (seen.contains(k)) {
        dup++;
      } else {
        pickQueue.add(PickedFileEntry(file: f, key: k, modified: mod));
        seen.add(k);
        added++;
      }
    }
    pickNotice = _skipNotice(files.length, added, already, dup);
    touch();
    if (startImmediately) {
      startAnalysis();
    }
    return added;
  }
}
