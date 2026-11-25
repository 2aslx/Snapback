import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/photo_album.dart';
import '../models/photo_item.dart';
import '../models/photo_record.dart';
import '../services/image_processor.dart';
import '../services/live_activity.dart';
import '../services/preview_store.dart';
import '../services/snapback_api.dart';

/// 분석 대기열 항목 — 웹은 고른 파일([file]), iOS 는 사진 보관함 에셋([asset]).
class PickedFileEntry {
  PickedFileEntry({
    this.file,
    this.asset,
    required this.key,
    required this.modified,
  });

  final XFile? file;
  final AssetEntity? asset;
  final String key;
  final DateTime modified;

  String get label => file?.name ?? asset?.title ?? key;
}

/// 서버 검색이 한 번에 받는 사진 수(300)에 맞춘 분석 상한
const int kMaxLibraryQueue = 300;

class AnalysisLogEntry {
  AnalysisLogEntry({
    required this.isError,
    required this.text,
    this.subtext = '',
    this.thumbDataUrl,
  });

  final bool isError;
  final String text;
  final String subtext;
  final String? thumbDataUrl;
}

class RelatedMemories {
  RelatedMemories({
    required this.sameDay,
    required this.nearPlace,
    required this.similarMood,
  });

  final List<PhotoItem> sameDay;
  final List<PhotoItem> nearPlace;
  final List<PhotoItem> similarMood;
}

/// 검색으로 찾은 사진 기록 (기억 탭)
class FoundMemory {
  FoundMemory({required this.id, required this.atMs, this.query = ''});
  final int id;
  final int atMs;

  /// 찾을 때 처음 입력한 기억 문장
  final String query;

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': atMs,
    if (query.isNotEmpty) 'q': query,
  };
  factory FoundMemory.fromJson(Map<String, dynamic> j) => FoundMemory(
    id: (j['id'] as num).toInt(),
    atMs: (j['at'] as num?)?.toInt() ?? 0,
    query: (j['q'] ?? '').toString(),
  );
}

/// 사진 보관함 앨범 + 사진 수 + 대표사진(가장 최근 1장)
class LibraryAlbum {
  LibraryAlbum(this.path, this.count, this.cover);
  final AssetPathEntity path;
  final int count;
  final AssetEntity? cover;
}

class ActiveTestSession {
  ActiveTestSession({required this.targetId, required this.startedAtMs});
  final int targetId;
  final int startedAtMs;
  int questions = 0;
  int? firstRank;
}

/// 사진 분석 동시 처리 수 (서버 분석 요청 제한 분당 120회 안에서)
const kAnalyzeConcurrency = 5;

class SnapbackState extends ChangeNotifier {
  SnapbackState() {
    _init();
  }

  static const _dbKey = 'snapback_db';
  static const _urlKey = 'snapback_server_url';
  static const _albumsKey = 'snapback_albums';
  static const _categoriesKey = 'snapback_album_categories';
  static const _placeNamesKey = 'snapback_place_names';
  static const _foundKey = 'snapback_found';
  static const _recordsKey = 'snapback_records';
  static const _onboardedKey = 'snapback_onboarded';
  static const _queueKey = 'snapback_queue';
  static const _removedKey = 'snapback_removed';
  static const _albumPlansKey = 'snapback_album_plans';
  static const _photoSortKey = 'snapback_photo_sort';
  static const _searchCacheKey = 'snapback_search_cache';

  /// 같은 검색(같은 대화 기록 + 같은 사진 정보)은 저장해 둔 결과를 그대로 보여 준다 (최근 30개).
  final Map<String, Map<String, dynamic>> _searchCache = {};

  /// 앨범 요청 문장 → 서버가 해석한 조건. 같은 요청은 같은 조건으로 다시 찾아 결과가 매번 같게 한다.
  final Map<String, Map<String, dynamic>> _albumPlans = {};

  /// 사용자가 앱에서 지운 사진 (fileKey 또는 데모 사진 'seed:id').
  /// 다시 분석 대기열에 넣지 않고, 다음 실행 때도 목록에서 빼 둔다. 사진 앱 원본은 건드리지 않는다.
  final Set<String> removedKeys = {};
  static String _removalKey(PhotoItem d) => d.fileKey ?? 'seed:${d.id}';

  /// 저장된 데이터를 다 읽었는지 (그 전에는 화면을 그리지 않아 시작 화면이 깜빡이지 않게)
  bool ready = false;

  final SnapbackApi api = SnapbackApi();
  final ImagePicker _picker = ImagePicker();

  int screen = 0;
  bool serverConnected = false;

  /// 서버·AI 문제가 있을 때만 경고 문구 (정상이면 빈 문자열 → 화면에 표시 안 함)
  String aiStatusText = '';

  // Onboarding selections
  int scopeSelection = 0; // 0: 전체, 1: 앨범, 2: 직접, 3: 기간
  int orderSelection = 1; // 0: 최근, 1: 오래된(기본), 2: 지정 기간 우선
  String priorityYear = '${DateTime.now().year}';

  /// '지정 기간 우선'에서 고를 수 있는 연도 (고른 범위의 사진에 실제로 있는 연도, 최신순)
  List<String> availableYears = [];
  bool yearsLoading = false;

  /// 분석 순서 비교: 최근 / 오래된 / 지정 연도 먼저 → 나머지는 오래된 순
  int compareForOrder(DateTime a, DateTime b) {
    if (orderSelection == 0) return b.compareTo(a);
    if (orderSelection == 2) {
      final py = int.tryParse(priorityYear);
      final am = a.year == py ? 0 : 1, bm = b.year == py ? 0 : 1;
      if (am != bm) return am - bm;
    }
    return a.compareTo(b);
  }

  /// 고른 접근 범위(전체 · 앨범 · 직접 고르기 · 기간)의 사진에 들어 있는 연도를 모은다.
  Future<void> loadAvailableYears() async {
    if (yearsLoading) return;
    yearsLoading = true;
    notifyListeners();
    final years = <int>{};
    try {
      if (scopeSelection == 2 || !useLibrary) {
        years.addAll(pickQueue.map((e) => e.modified.year));
      } else if (await ensureLibrary()) {
        final paths = scopeSelection == 1
            ? libraryAlbums
                  .where((a) => selectedAlbumIds.contains(a.path.id))
                  .map((a) => a.path)
            : [?_allPath];
        for (final p in paths) {
          final n = await p.assetCountAsync;
          final list = await p.getAssetListRange(
            start: 0,
            end: math.min(n, 3000),
          );
          years.addAll(list.map((a) => a.createDateTime.year));
        }
        if (scopeSelection == 3) years.removeWhere((y) => y < 2022);
      }
    } catch (_) {}
    availableYears = (years.toList()..sort((a, b) => b - a))
        .map((y) => '$y')
        .toList();
    if (availableYears.isNotEmpty && !availableYears.contains(priorityYear)) {
      priorityYear = availableYears.first;
    }
    yearsLoading = false;
    notifyListeners();
  }

  // Photos & DB
  /// 분석한 사진 DB (데모 사진 없이 사용자의 사진만). id 1~11 은 예전 데모 사진 자리라 비워 둔다.
  List<PhotoItem> db = [];
  int _nextId = 12;

  // Analysis queue & progress
  final List<PickedFileEntry> pickQueue = [];
  int _runId = 0;
  bool analysisPaused = false;
  bool analysisRunning = false;
  int analysisDone = 0;
  int analysisTotal = 0;
  int etaMs = 0;
  bool analysisFinished = false;
  DateTime? currentFileDate;
  final List<AnalysisLogEntry> analysisLogs = [];

  // Search (Screen 13)
  final List<String> searchHistory = [];

  /// 처음 검색의 상위 30개 후보 id. 질문에 답한 뒤에는 이 후보 안에서만 다시 찾는다.
  final List<int> searchPool = [];

  /// 질문에 답할 때 크게 보고 있던 사진 (맞다고 하지 않았으므로 다음 검색에서 제외, 답할수록 쌓임)
  final Set<int> searchExcluded = {};

  /// 지금 검색 화면에서 크게 보여 주는 사진: 고른 후보, 없으면 일치도 1순위
  int? get shownResultId {
    if (pinnedResultId != null) return pinnedResultId;
    if (searchResults.isEmpty) return null;
    return searchResults.reduce((a, b) => b.score > a.score ? b : a).id;
  }
  String currentQuestionText = '';
  List<SearchRankedItem> searchResults = [];

  /// 검색 일치도 기준 (점수는 화면에 보여 주지 않고 이 기준에만 쓴다)
  /// 1순위 아래 '다른 후보'에 [kMinScore] 이상인 연관 사진을 모두 보여 준다.
  static const kMinScore = 60;
  SearchQuestion? activeQuestion;
  bool searchCompleted = false;
  bool searchBusy = false;
  String? searchError;

  /// '질문 한 번 더하기'를 눌러 질문이 보이는 상태 (검색 직후에는 맨 위 사진 + 버튼만)
  bool questionShown = false;

  // AI 대화형 앨범 (Screen 11 → 17 미리보기)
  bool albumBusy = false;
  String? albumError;
  AlbumSuggestion? albumDraft;
  final Set<int> albumDraftSelected = {};

  // Memory detail (Screen 10)
  int activeMemoryId = 1;

  // Settings (Screen 12)
  bool backgroundAnalysis = true;
  String hiddenWarning = '';

  // Albums (Screen 11, 16) — 미리 정한 카테고리 없이, 검색 결과 제안으로만 만든다.
  List<PhotoAlbum> albums = [];
  int? activeAlbumId;
  int? lastCreatedAlbumId; // 이번 검색에서 만든 앨범 (완료 안내용)

  // 앨범 카테고리: 기본 3개(추억·취향·작업) + 사용자 정의
  List<AlbumCategory> customCategories = [];
  List<AlbumCategory> get allCategories => [
    ...kBuiltInCategories,
    ...customCategories,
  ];

  /// 앨범 탭 필터. null = 전체
  String? albumFilter;

  // Usability test (Screen 14)
  ActiveTestSession? testSession;
  final List<UsabilityLogEntry> testLogs = [];

  List<PhotoItem> get visiblePhotos =>
      db.where((d) => !d.hidden).toList(growable: false);

  String get serverUrl => api.baseUrl;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString(_urlKey);
    if (customUrl != null && customUrl.isNotEmpty) {
      api.baseUrl = customUrl;
    }
    final rawAlbums = prefs.getString(_albumsKey);
    if (rawAlbums != null && rawAlbums.isNotEmpty) {
      try {
        albums = (jsonDecode(rawAlbums) as List)
            .whereType<Map<String, dynamic>>()
            .map(PhotoAlbum.fromJson)
            .toList();
      } catch (_) {}
    }
    final rawRecords = prefs.getString(_recordsKey);
    if (rawRecords != null && rawRecords.isNotEmpty) {
      try {
        records = (jsonDecode(rawRecords) as List)
            .whereType<Map<String, dynamic>>()
            .map(PhotoRecord.fromJson)
            .toList();
      } catch (_) {}
    }
    final rawFound = prefs.getString(_foundKey);
    if (rawFound != null && rawFound.isNotEmpty) {
      try {
        found = (jsonDecode(rawFound) as List)
            .whereType<Map<String, dynamic>>()
            .map(FoundMemory.fromJson)
            .toList();
      } catch (_) {}
    }
    final rawSearch = prefs.getString(_searchCacheKey);
    if (rawSearch != null && rawSearch.isNotEmpty) {
      try {
        (jsonDecode(rawSearch) as Map).forEach((k, v) {
          if (v is Map<String, dynamic>) _searchCache['$k'] = v;
        });
      } catch (_) {}
    }
    if (prefs.getString(_photoSortKey) case final v?) photoSort = v;
    final rawPlans = prefs.getString(_albumPlansKey);
    if (rawPlans != null && rawPlans.isNotEmpty) {
      try {
        (jsonDecode(rawPlans) as Map).forEach((k, v) {
          if (v is Map<String, dynamic>) _albumPlans['$k'] = v;
        });
      } catch (_) {}
    }
    final rawPlaces = prefs.getString(_placeNamesKey);
    if (rawPlaces != null && rawPlaces.isNotEmpty) {
      try {
        placeNames.addAll(
          (jsonDecode(rawPlaces) as Map).map((k, v) => MapEntry('$k', '$v')),
        );
      } catch (_) {}
    }
    final rawCats = prefs.getString(_categoriesKey);
    if (rawCats != null && rawCats.isNotEmpty) {
      try {
        customCategories = (jsonDecode(rawCats) as List)
            .whereType<Map<String, dynamic>>()
            .map(AlbumCategory.fromJson)
            .where((c) => c.id.isNotEmpty && c.label.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    // 웹은 IndexedDB(용량 넉넉) 에 저장, 예전 localStorage 데이터는 그대로 읽어 옮긴다
    String? raw;
    if (kIsWeb && PreviewStore.enabled) {
      final bytes = await PreviewStore.get(_webDbKey);
      if (bytes != null) raw = utf8.decode(bytes);
    }
    raw ??= prefs.getString(_dbKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .whereType<Map<String, dynamic>>()
            .map(PhotoItem.fromJson)
            .toList();
        db = list.where((d) => d.id > 11).toList();
        final maxId = db.fold<int>(11, (prev, e) => e.id > prev ? e.id : prev);
        _nextId = maxId + 1;
      } catch (_) {}
    }
    removedKeys.addAll(prefs.getStringList(_removedKey) ?? const []);
    db.removeWhere((d) => removedKeys.contains(_removalKey(d)));
    // 초기 설정을 마쳤거나 이미 분석한 사진이 있으면 홈에서 시작 (분석 결과는 기기에 저장돼 있어 다시 분석하지 않음)
    final onboarded =
        (prefs.getBool(_onboardedKey) ?? false) || db.any((d) => d.id > 11);
    if (onboarded && screen == 0) screen = 5;
    await _restoreQueue(prefs);
    ready = true;
    notifyListeners();
    await refreshHealth();
    loadAlbumSuggestions(); // 앱을 켤 때마다 앨범 제안을 새로 만든다
    prefetchAddresses(); // 위치 정보가 있는 사진의 주소를 뒤에서 미리 받아 둔다
  }

  Future<void> refreshHealth() async {
    final res = await api.checkHealth();
    serverConnected = res.ok;
    if (!res.ok) {
      aiStatusText = '⚠️ 서버 연결 안 됨';
    } else if (res.keyOk) {
      aiStatusText = '';
    } else {
      aiStatusText = '⚠️ API 키 확인 필요';
    }
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    api.baseUrl = clean.isEmpty ? kDefaultApiUrl : clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, clean);
    await refreshHealth();
  }

  // ── 분석 대기열 저장/복원: 분석 도중 앱을 껐다 켜도 남은 사진만 이어서 ─────────
  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardedKey, true);
      // 사진 보관함 사진만 다시 찾을 수 있다 (웹 파일은 다시 읽을 수 없음)
      await prefs.setStringList(_queueKey, [
        for (final e in pickQueue)
          if (e.asset != null) e.key,
      ]);
    } catch (_) {}
  }

  Future<void> _clearQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_queueKey);
    } catch (_) {}
  }

  /// 지난번에 끝나지 않은 대기열을 '일시정지됨'으로 복원한다. 자동으로 다시 분석하지는 않는다(▶로 이어서).
  Future<void> _restoreQueue(SharedPreferences prefs) async {
    final keys = prefs.getStringList(_queueKey);
    if (!useLibrary || keys == null || keys.isEmpty) return;
    try {
      final perm = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );
      if (!perm.hasAccess) return;
      final analyzed = {for (final d in db) d.fileKey, ...removedKeys};
      if (keys.every(analyzed.contains)) {
        await prefs.remove(_queueKey);
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
    albums = [];
    unlockedAlbumId = null;
    customCategories = [];
    records = [];
    found = [];
    placeNames.clear();
    _placeAsked.clear();
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
    albumFilter = null;
    recordsView = 'default';
    photoSort = 'time';
    scopeReturn = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [
        _dbKey,
        _albumsKey,
        _categoriesKey,
        _recordsKey,
        _foundKey,
        _placeNamesKey,
        _queueKey,
        _removedKey,
        _onboardedKey,
        _albumPlansKey,
        _photoSortKey,
        _searchCacheKey,
      ]) {
        await prefs.remove(k);
      }
    } catch (_) {}
    await PreviewStore.clear(); // 웹: 미리보기·DB
    go(0);
  }

  /// 앱에서 사진 지우기 (분석 정보·썸네일·앨범/기록/찾은 사진 연결만 삭제, 원본은 그대로)
  void removePhotos(Set<int> ids) {
    if (ids.isEmpty) return;
    for (final d in db.where((d) => ids.contains(d.id))) {
      removedKeys.add(_removalKey(d));
    }
    db.removeWhere((d) => ids.contains(d.id));
    for (final a in albums) {
      a.photoIds.removeWhere(ids.contains);
    }
    records.removeWhere((r) => ids.contains(r.photoId));
    for (final r in records) {
      r.linkedPhotoIds.removeWhere(ids.contains);
    }
    found.removeWhere((f) => ids.contains(f.id));
    searchResults = searchResults.where((x) => !ids.contains(x.id)).toList();
    notifyListeners();
    _saveDb();
    _saveAlbums();
    _saveRecords();
    _saveFound();
    SharedPreferences.getInstance()
        .then((p) => p.setStringList(_removedKey, removedKeys.toList()))
        .catchError((_) => true);
  }

  static const _webDbKey = 'db:main';
  Timer? _saveTimer;

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
            _webDbKey,
            Uint8List.fromList(utf8.encode(json)),
          )) {
        await prefs.remove(_dbKey); // localStorage 비워 앨범·기록 저장 공간 확보
        return;
      }
      await prefs.setString(_dbKey, json);
    } catch (_) {}
  }

  Future<void> _saveAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _albumsKey,
        jsonEncode(albums.map((a) => a.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _saveCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _categoriesKey,
        jsonEncode(customCategories.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}
  }

  // ── 촬영 장소 주소 (구글 지도 또는 OpenStreetMap, 기기에 캐시) ─────────────
  /// 좌표(소수 3자리 ≈ 110m, 가까운 사진끼리 같은 주소를 나눠 씀) → 지역명
  final Map<String, String> placeNames = {};
  final Set<String> _placeAsked = {};

  static String? _placeKey(PhotoItem d) {
    final g = d.gps;
    if (g == null || g.length < 2) return null;
    return '${g[0].toStringAsFixed(3)},${g[1].toStringAsFixed(3)}';
  }

  /// 예전(소수 4자리) 캐시도 읽는다
  String? _cachedPlace(PhotoItem d) {
    final k = _placeKey(d);
    if (k == null) return null;
    final g = d.gps!;
    return placeNames[k] ??
        placeNames['${g[0].toStringAsFixed(4)},${g[1].toStringAsFixed(4)}'];
  }

  /// AI 에 보낼 사진별 주소 (주소를 아는 사진만)
  Map<int, String> get addressById => {
    for (final d in db) d.id: ?_cachedPlace(d),
  };

  // 위치 정보가 있는 사진의 주소를 한 장씩 미리 받아 둔다 (앨범·검색에서 '신촌' 같은 지명으로 찾기 위해)
  Future<void>? _addrJob;

  /// 주소를 미리 받아 둔다. [wait] 만큼만 기다리고 나머지는 계속 뒤에서 받는다.
  Future<void> prefetchAddresses({Duration wait = Duration.zero}) async {
    _addrJob ??= _runAddressJob().whenComplete(() => _addrJob = null);
    if (wait > Duration.zero) {
      await Future.any([_addrJob!, Future<void>.delayed(wait)]);
    }
  }

  Future<void> _runAddressJob() async {
    var changed = 0;
    while (serverConnected) {
      final d = visiblePhotos
          .where((x) => x.gps != null && _cachedPlace(x) == null)
          .where((x) => !_placeAsked.contains(_placeKey(x)))
          .firstOrNull;
      if (d == null) break;
      final k = _placeKey(d)!;
      _placeAsked.add(k);
      try {
        final name = await api.placeName(d.gps![0], d.gps![1]);
        if (name != null) {
          placeNames[k] = name;
          changed++;
        }
      } catch (_) {}
      if (changed > 0 && changed % 10 == 0) await _savePlaceNames();
    }
    if (changed > 0) {
      await _savePlaceNames();
      notifyListeners();
    }
  }

  Future<void> _savePlaceNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_placeNamesKey, jsonEncode(placeNames));
    } catch (_) {}
  }

  /// 저장된 지역명. 없으면 서버에 한 번만 물어보고(앱 실행 중) 받아오면 다시 그린다.
  String? placeNameFor(PhotoItem d) {
    final k = _placeKey(d);
    if (k == null) return null;
    final hit = _cachedPlace(d);
    if (hit != null) return hit;
    if (serverConnected && _placeAsked.add(k)) {
      api
          .placeName(d.gps![0], d.gps![1])
          .then((name) async {
            if (name == null) return;
            placeNames[k] = name;
            notifyListeners();
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_placeNamesKey, jsonEncode(placeNames));
            } catch (_) {}
          })
          .catchError((_) {}); // 지도 키 없음 등 → 좌표 그대로 표시
    }
    return null;
  }

  // ── 기록으로 남기기 (화면 20 기록 다듬기 · 21 나의 기록) ─────────────
  List<PhotoRecord> records = [];

  /// 지금 다듬는 기록 (새 기록이면 id 0)
  PhotoRecord? recordDraft;
  bool recordBusy = false;
  String? recordError;

  /// AI 초안이 도착할 때마다 증가 → 입력칸을 새 값으로 다시 채움
  int recordDraftVersion = 0;

  /// 민감정보 저장 동의 체크
  bool recordConsent = false;
  int? activeRecordId;

  /// 나의 기록에서 '뒤로' 갈 화면
  int recordReturn = 19;

  /// 기록 탭 보기 방식: default(기본: 즐겨찾기 위) · genre(장르별) · fav(즐겨찾기만) · moment/place/document(그 종류만)
  String recordsView = 'default';

  void setRecordsView(String v) {
    recordsView = v;
    notifyListeners();
  }

  /// 사진 탭 정렬: 'time' 촬영 시간순(월별) / 'added' 앱에 추가한 순(최근 추가가 먼저)
  String photoSort = 'time';

  void setPhotoSort(String v) {
    if (v != 'time' && v != 'added') return;
    photoSort = v;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_photoSortKey, v))
        .ignore();
  }

  PhotoRecord? recordForPhoto(int photoId) =>
      records.where((r) => r.photoId == photoId).firstOrNull;
  PhotoRecord? recordById(int? id) =>
      records.where((r) => r.id == id).firstOrNull;
  PhotoItem? photoById(int id) => db.where((d) => d.id == id).firstOrNull;

  /// 사진 상세의 '기록으로 남기기' → 기록 다듬기. AI 가 초안을 만들어 채운다.
  Future<void> startRecord(int photoId) async {
    final photo = photoById(photoId);
    if (photo == null) return;
    final loc = placeNameFor(photo) ?? '';
    final hasPlace = photo.place.isNotEmpty && photo.place != '알 수 없음';
    recordDraft = PhotoRecord(
      id: 0,
      photoId: photoId,
      type: switch (photo.suggestedRecordType) {
        'place' => 'place',
        'document' || 'shopping' || 'info' => 'document',
        'moment' || 'taste' => 'moment',
        _ => hasPlace || photo.gps != null ? 'place' : 'moment',
      },
      title: hasPlace ? photo.place : '',
      location: loc.isNotEmpty ? loc : (hasPlace ? photo.place : ''),
      date: photo.date,
      kind: '기타',
      createdAtMs: 0,
    );
    recordConsent = false;
    recordError = null;
    recordBusy = serverConnected;
    recordDraftVersion++;
    go(20);
    if (!serverConnected) {
      recordError = 'AI 서버에 연결되지 않아 직접 입력해 주세요';
      notifyListeners();
      return;
    }
    try {
      final image = await recordImageDataUrl(photo);
      final r = await api.draftRecord(photo, image: image, location: loc);
      final d = recordDraft;
      if (d == null || d.photoId != photoId || d.id != 0) return; // 그사이 나감
      final place = r['place'] is Map ? r['place'] as Map : const {};
      d.type = (r['type'] ?? d.type).toString();
      final title = (r['title'] ?? '').toString();
      final placeName = (place['name'] ?? '').toString();
      d.title = d.type == 'place' && placeName.isNotEmpty
          ? placeName
          : (title.isNotEmpty ? title : d.title);
      if (r['date'] is String) d.date = r['date'] as String;
      d.kind = (place['kind'] ?? '기타').toString();
      if (d.location.isEmpty && placeName.isNotEmpty) d.location = placeName;
      d.lines = ((r['lines'] as List?) ?? const []).map((e) => '$e').toList();
      d.summary = (r['summary'] ?? '').toString();
      d.sensitiveType = r['sensitiveType'] as String?;
    } on ApiException catch (e) {
      recordError = '${e.userMessage} · 직접 입력해 주세요';
    } catch (e) {
      recordError = 'AI 초안을 만들지 못했어요 · 직접 입력해 주세요';
    } finally {
      recordBusy = false;
      recordDraftVersion++;
      notifyListeners();
    }
  }

  /// 저장된 기록 수정
  void editRecord(int id) {
    final r = recordById(id);
    if (r == null) return;
    recordDraft = PhotoRecord.fromJson(r.toJson());
    recordConsent = r.consentAtMs != null;
    recordError = null;
    recordBusy = false;
    recordDraftVersion++;
    go(20);
  }

  void setRecordType(String type) {
    recordDraft?.type = type;
    notifyListeners();
  }

  void setRecordConsent(bool v) {
    recordConsent = v;
    notifyListeners();
  }

  /// 민감정보면 동의해야 저장 가능
  bool get canSaveRecord {
    final d = recordDraft;
    if (d == null || recordBusy) return false;
    return d.sensitiveType == null || recordConsent;
  }

  /// 같은 날 · 가까운 곳(1.5km)에서 찍은 사진을 '연결된 사진'으로
  List<int> _linkedFor(PhotoItem p) {
    final list =
        visiblePhotos
            .where(
              (x) =>
                  x.id != p.id &&
                  (x.date == p.date || _distanceKm(p.gps, x.gps) < 1.5),
            )
            .toList()
          ..sort(
            (a, b) => (a.takenAtMs ?? a.id).compareTo(b.takenAtMs ?? b.id),
          );
    return list.take(12).map((x) => x.id).toList();
  }

  /// 기록 저장 → 나의 기록으로
  void saveRecordDraft() {
    final d = recordDraft;
    if (d == null || !canSaveRecord) return;
    if (d.title.trim().isEmpty) d.title = recordTypeOf(d.type).label;
    if (d.sensitiveType != null) {
      d.consentAtMs ??= DateTime.now().millisecondsSinceEpoch;
    }
    final photo = photoById(d.photoId);
    if (d.id == 0) {
      final id = records.fold<int>(0, (m, r) => r.id > m ? r.id : m) + 1;
      final rec = PhotoRecord.fromJson({
        ...d.toJson(),
        'id': id,
        'at': DateTime.now().millisecondsSinceEpoch,
        if (photo != null) 'linked': _linkedFor(photo),
      });
      records.insert(0, rec);
      activeRecordId = id;
    } else {
      final i = records.indexWhere((r) => r.id == d.id);
      if (i >= 0) records[i] = PhotoRecord.fromJson(d.toJson());
      activeRecordId = d.id;
    }
    recordDraft = null;
    recordReturn = 10;
    _saveRecords();
    go(21);
  }

  /// 기록 다듬기 취소: 새 기록이면 사진 상세로, 수정 중이면 나의 기록으로
  void cancelRecordDraft() {
    final d = recordDraft;
    recordDraft = null;
    recordBusy = false;
    if (d != null && d.id != 0) {
      activeRecordId = d.id;
      go(21);
    } else {
      go(10);
    }
  }

  void openRecord(int id) {
    activeRecordId = id;
    recordReturn = screen == 21 ? recordReturn : screen;
    go(21);
  }

  void toggleRecordFavorite(int id) {
    final r = recordById(id);
    if (r == null) return;
    r.favorite = !r.favorite;
    notifyListeners();
    _saveRecords();
  }

  void deleteRecord(int id) {
    records.removeWhere((r) => r.id == id);
    if (activeRecordId == id) activeRecordId = null;
    notifyListeners();
    _saveRecords();
  }

  Future<void> _saveRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _recordsKey,
        jsonEncode(records.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}
  }

  // ── 홈 '다시 꺼내 볼 기억' 카드 ─────────────────────────────
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

  final _liveActivity = LiveActivity();

  /// 상태가 바뀔 때마다 잠금화면 Live Activity 도 같은 진행 상황으로 맞춘다.
  @override
  void notifyListeners() {
    super.notifyListeners();
    final rl = relabelActiveForProgress; // 다시 분석 중이면 그 진행을 잠금화면에
    _liveActivity.sync(
      done: rl ? relabelDone : analysisDone,
      total: rl ? relabelTotal : analysisTotal,
      running: rl ? relabelRunning : analysisRunning,
      paused: rl ? false : analysisPaused,
      finished: rl ? relabelFinished : analysisFinished,
    );
  }

  /// 화면에서 공개 필드(선택값 등)를 직접 바꾼 뒤 다시 그리기.
  void touch() => notifyListeners();

  void go(int idx) {
    // 분석 순서 화면에 들어올 때마다 연도 목록을 지금 고른 범위로 다시 계산
    if (idx == 3 && screen != 3) availableYears = [];
    seamlessSwitch = false;
    screen = idx;
    notifyListeners();
  }

  /// true 면 화면 전환 시 크로스페이드 없이 바로 바꾼다 (검색창이 직접 이어지는 전환용).
  bool seamlessSwitch = false;
  Rect? _searchOrigin;

  /// 홈 검색창([origin] 위치)에서 검색 화면으로: 창이 그 자리에서 내려오도록 위치를 넘긴다.
  /// 새 검색: 이전 검색어·결과·질문을 모두 비운다 (홈·기억 탭에서 검색을 새로 열 때)
  int _searchRunId = 0;

  /// 검색 결과에서 '다른 후보'를 눌러 크게 올려 둔 사진 (맞아요로 확인할 대상). null 이면 1순위
  int? pinnedResultId;

  /// 다른 후보를 크게 보기 → 맞아요 / 질문 한 번 더하기로 확인 (바로 상세로 가지 않음)
  void pinResult(int? id) {
    pinnedResultId = id;
    notifyListeners();
  }

  void resetSearch() {
    pinnedResultId = null;
    _searchRunId++; // 진행 중이던 검색 결과는 무시
    searchHistory.clear();
    searchPool.clear();
    searchExcluded.clear();
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
    notifyListeners();
  }

  /// 홈 검색창의 위치 (홈 스크롤 0 기준, 전역 y). 검색에서 뒤로 올 때 목표 지점.
  double? homeSearchBoxTop;
  bool _homeReturn = false;

  /// 검색창이 홈 자리까지 올라간 뒤 호출: 크로스페이드 없이 홈으로 전환.
  void returnHomeFromSearch() {
    _homeReturn = true;
    screen = 5;
    seamlessSwitch = true;
    notifyListeners();
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
    if (testSession != null && screen == 13) {
      testLogs.add(
        UsabilityLogEntry(
          id: testSession!.targetId,
          ms: DateTime.now().millisecondsSinceEpoch - testSession!.startedAtMs,
          questions: testSession!.questions,
          firstRank: testSession!.firstRank ?? 0,
          hit: id == testSession!.targetId,
        ),
      );
      testSession = null;
      go(14);
      return;
    }
    if (screen == 13) _rememberFound(id);
    if (screen != 10) detailReturn = screen;
    _relatedNav.clear();
    activeMemoryId = id;
    go(10);
  }

  /// 사진 상세에서 '뒤로'로 돌아갈 화면 (들어온 곳)
  int detailReturn = 5;

  // ── 기억 탭: 검색으로 최종 찾은 사진 기록 ─────────────────────
  /// 최근에 찾은 순서. 검색 결과에서 사진을 열면(맞아요 · 후보 선택) 기록된다.
  List<FoundMemory> found = [];

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
    db[i] = db[i].withRecall(keywords, query);
    _saveDbSoon();
    notifyListeners();
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
    notifyListeners();
    _saveFound();
  }

  Future<void> _saveFound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _foundKey,
        jsonEncode(found.map((f) => f.toJson()).toList()),
      );
    } catch (_) {}
  }

  // ── 사진 상세의 '관련된 추억' 가상 앨범 (화면 18) ─────────────────
  // 실제 갤러리에 앨범을 만들지 않고, 앱 안에서 관련 사진을 묶어 보여준다.
  /// 0 = 그날의 사진, 1 = 비슷한 분위기
  int relatedAlbumKind = 0;

  /// 어느 사진 상세에서 연 앨범인지
  int relatedBaseId = 1;

  /// 상세 ↔ 관련 앨범 사이 뒤로가기 기록: (화면, 기준 사진 id, 앨범 종류)
  final List<(int, int, int)> _relatedNav = [];

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

  // ── iOS 사진 보관함 (photo_manager) ─────────────────────────────
  /// iOS 앱은 사진 보관함을 직접 읽는다. 웹은 파일 선택.
  bool get useLibrary => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  PermissionState? libraryPermission;
  int libraryCount = 0;

  /// 기기 사진 보관함의 실제 앨범 (사진이 있는 것만, 개수·대표사진 포함)
  List<LibraryAlbum> libraryAlbums = [];

  /// '앨범 선택'에서 사용자가 고른 앨범 id (여러 개). 처음엔 아무것도 선택 안 됨.
  final Set<String> selectedAlbumIds = {};
  bool libraryAlbumsLoading = false;
  AssetPathEntity? _allPath;
  List<AssetEntity> pickerAssets = [];
  bool pickerHasMore = false;
  final Set<String> pickedAssetIds = {};
  bool _startAfterPick = false;

  bool get libraryDenied =>
      libraryPermission != null && !libraryPermission!.hasAccess;

  /// 권한 요청 + 전체 사진 수 / 앨범 목록 불러오기.
  bool _libLoading = false;
  bool pickerLoading = false;

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
      notifyListeners();
      return false;
    }
    final paths = await PhotoManager.getAssetPathList(type: RequestType.image);
    _allPath = paths.where((p) => p.isAll).firstOrNull ?? paths.firstOrNull;
    libraryCount = await _allPath?.assetCountAsync ?? 0;
    libraryAlbumsLoading = true;
    notifyListeners();
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
    notifyListeners();
    return true;
  }

  void toggleLibraryAlbum(String id) {
    if (!selectedAlbumIds.remove(id)) selectedAlbumIds.add(id);
    notifyListeners();
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
    notifyListeners();
    final start = more ? pickerAssets.length : 0;
    final page = await path.getAssetListRange(start: start, end: start + 120);
    pickerAssets = more ? [...pickerAssets, ...page] : page;
    pickerHasMore = pickerAssets.length < libraryCount;
    pickerLoading = false;
    notifyListeners();
  }

  void togglePickAsset(String id) {
    if (!pickedAssetIds.remove(id)) pickedAssetIds.add(id);
    notifyListeners();
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
    notifyListeners();
    return pickQueue.length;
  }

  /// 사진 접근 범위(화면 1)에서 '뒤로' 갈 화면: 처음 설정이면 시작 안내(0), 홈 ＋로 왔으면 홈(5)
  int scopeReturn = 0;

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
      notifyListeners();
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
    notifyListeners();
    if (startImmediately) {
      startAnalysis();
    }
    return added;
  }

  Future<void> startAnalysis() async {
    final myRun = ++_runId;
    // 지난 분석이 끝난 뒤의 시작이면 새 묶음 (일시정지 후 이어하기는 같은 묶음)
    final newBatch = analysisFinished || analysisTotal == 0;
    analysisPaused = false;
    analysisRunning = true;
    analysisFinished = false;

    final analyzed = {for (final d in db) d.fileKey, ...removedKeys};
    // 지난 분석이 끝났으면 새 묶음: 끝난 사진(분석됨·지움·실패)을 대기열에서 빼고 이번에 올린 사진만 센다
    if (newBatch) {
      pickQueue.removeWhere(
        (e) =>
            (analyzed.contains(e.key) || _failedKeys.contains(e.key)) &&
            !_inFlight.contains(e.key),
      );
      _failedKeys.clear();
    }
    analysisFinished = false;
    final pending = pickQueue
        .where(
          (p) =>
              !analyzed.contains(p.key) &&
              !_inFlight.contains(p.key) &&
              !_failedKeys.contains(p.key),
        )
        .toList();

    pending.sort((a, b) => compareForOrder(a.modified, b.modified));

    analysisTotal = pickQueue.length;
    _recountDone();
    _saveQueue();
    etaMs = 0;
    currentFileDate = pending.isNotEmpty ? pending.first.modified : null;
    if (pending.isEmpty && analysisTotal > 0) {
      analysisFinished = true;
      analysisRunning = false;
      _clearQueue();
    }
    notifyListeners();

    if (pending.isEmpty) {
      analysisRunning = false;
      notifyListeners();
      return;
    }

    final t0 = DateTime.now().millisecondsSinceEpoch;
    var processedCount = 0;
    var next = 0;

    // 여러 장 동시에 분석: 일꾼(worker) N개가 대기열에서 한 장씩 가져간다
    Future<void> worker() async {
      while (true) {
        if (myRun != _runId || analysisPaused) return;
        if (next >= pending.length) return;
        final entry = pending[next++];
        currentFileDate = entry.modified;
        notifyListeners();
        await _analyzeOne(entry);
        _recountDone(); // 완료 수는 실제 상태(분석됨·실패)로 다시 센다
        if (myRun != _runId) {
          notifyListeners();
          return; // 그사이 새 분석이 시작됨
        }
        processedCount++;
        final elapsed = DateTime.now().millisecondsSinceEpoch - t0;
        final remaining = analysisTotal - analysisDone;
        // 동시에 처리하므로 실제 흐른 시간 기준으로 남은 시간 계산
        etaMs = remaining > 0
            ? ((elapsed / processedCount) * remaining).round()
            : 0;
        notifyListeners();
      }
    }

    await Future.wait([
      for (var w = 0; w < math.min(_concurrency, pending.length); w++) worker(),
    ]);

    if (myRun != _runId || analysisPaused) {
      analysisRunning = false;
      notifyListeners();
      return;
    }

    if (myRun == _runId) {
      await _saveDb(); // 묶어 두던 저장을 바로 마무리
      prefetchAddresses(); // 새로 분석한 사진의 주소도 받아 둔다
      analysisRunning = false;
      analysisFinished = true;
      etaMs = 0;
      _clearQueue();
      notifyListeners();
    }
  }

  /// 사진 1장: 줄이기 → AI 분석 → DB 저장 (실패하면 기록만 남기고 넘어감)
  /// 동시에 분석할 사진 수: 웹은 큰 사진을 브라우저 메모리에서 풀어야 해서 2장, 앱은 5장
  static int get _concurrency => kIsWeb ? 2 : kAnalyzeConcurrency;

  /// 이번 분석에서 실패한 사진 수 (형식을 읽을 수 없음·서버 오류 등). 하단 진행 카드와 홈 알림에 표시
  int analysisFailed = 0;
  final Set<String> _failedKeys = {};

  /// 사진을 고를 때 건너뛴 이유 안내 (예: 이미 분석한 사진)
  String pickNotice = '';

  /// 이번 묶음에서 끝난 사진 수 = 분석됨·지움·실패
  void _recountDone() {
    final analyzed = {for (final d in db) d.fileKey, ...removedKeys};
    analysisDone = pickQueue
        .where((e) => analyzed.contains(e.key) || _failedKeys.contains(e.key))
        .length;
    analysisFailed = _failedKeys.length;
  }

  /// 지금 분석 요청 중인 사진 (일시정지 후 바로 다시 시작해도 같은 사진을 두 번 보내지 않게)
  final Set<String> _inFlight = {};

  Future<void> _analyzeOne(PickedFileEntry entry) async {
    _inFlight.add(entry.key);
    try {
      final processed = entry.asset != null
          ? await ImageProcessor.processAsset(entry.asset!)
          : await ImageProcessor.process(entry.file!, entry.modified);
      String? previewKey;
      if (processed.previewBytes != null && PreviewStore.enabled) {
        // 저장에 실패하면(사생활 보호 모드 등) 미리보기 없이 작은 썸네일로 보여 준다
        if (await PreviewStore.put(
          'pv:${entry.key}',
          processed.previewBytes!,
        )) {
          previewKey = 'pv:${entry.key}';
        }
      }
      var ai = await api.analyzeImage(processed.analyzeDataUrl);
      // 스크린샷·문서처럼 글자가 많은 이미지면 1280px + 고해상도로 한 번 더 정밀 분석
      if (ai['text_dense'] == true) {
        final hi = entry.asset != null
            ? await hiResDataUrlForAsset(entry.asset!)
            : (processed.previewBytes != null
                  ? 'data:image/jpeg;base64,${base64Encode(processed.previewBytes!)}'
                  : null);
        if (hi != null) {
          try {
            ai = await api.analyzeImage(hi, detail: 'high');
          } catch (_) {
            // 정밀 분석이 실패하면 1차 결과를 그대로 쓴다
          }
        }
      }

      final item = PhotoItem(
        id: _nextId++,
        fileKey: entry.key,
        date: processed.dateStr,
        place: '',
        gps: processed.gps,
        exif: processed.hasExifDate,
        thumbDataUrl: processed.thumbDataUrl,
        assetId: entry.asset?.id,
        assetW: entry.asset?.width,
        assetH: entry.asset?.height,
        previewKey: previewKey,
        takenAtMs: processed.takenAt?.millisecondsSinceEpoch,
      ).withAnalysis(ai);
      if (db.any((d) => d.fileKey == entry.key)) return; // 이미 저장됨 (중복 방지)
      db.add(item);
      _saveDbSoon();
      analysisLogs.insert(
        0,
        AnalysisLogEntry(
          isError: false,
          text: '#${item.id} ${item.caption}',
          subtext: '${item.place} · ${item.date}',
          thumbDataUrl: item.thumbDataUrl,
        ),
      );
    } on ApiException catch (e) {
      _failedKeys.add(entry.key);
      analysisFailed = _failedKeys.length;
      aiStatusText = e.userMessage;
      analysisLogs.insert(
        0,
        AnalysisLogEntry(
          isError: true,
          text: '⚠️ ${entry.label} — ${e.userMessage}',
        ),
      );
    } catch (e) {
      _failedKeys.add(entry.key);
      analysisFailed = _failedKeys.length;
      analysisLogs.insert(
        0,
        AnalysisLogEntry(isError: true, text: '⚠️ ${entry.label} — 오류 ($e)'),
      );
    } finally {
      _inFlight.remove(entry.key);
    }
  }

  /// 분석 취소: 진행을 멈추고 남은 대기열을 비운다. 이미 분석한 사진(DB)은 그대로 둔다.
  void cancelAnalysis() {
    _runId++; // 돌고 있는 분석 루프 중단 (요청 중인 1장은 끝나면 저장만 됨)
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
    etaMs = 0;
    currentFileDate = null;
    _clearQueue();
    _liveActivity.cancel();
    go(5);
  }

  // ── 설정 > 사진 다시 분석하기 (재라벨링) ─────────────────────────
  // 이미 분석한 사진의 설명(캡션·장소 유형·인물·배경·날씨·시간대)만 새로 만든다.
  // 사진 id·날짜·위치와 그 사진을 쓰는 앨범·기록·찾은 사진은 그대로.
  bool relabelRunning = false;
  bool relabelFinished = false;
  int relabelTotal = 0;
  int relabelDone = 0;
  int relabelSkipped = 0; // 원본을 다시 읽을 수 없는 사진
  int relabelFailed = 0;
  int _relabelRun = 0;

  /// 다시 분석할 수 있는 사진 (데모 사진 제외)
  List<PhotoItem> get relabelTargets => db.where((d) => d.id > 11).toList();

  Future<void> relabelAll() async {
    if (relabelRunning || analysisRunning) return;
    if (!serverConnected) {
      relabelFinished = false;
      aiStatusText = ApiException('network').userMessage;
      notifyListeners();
      return;
    }
    final targets = relabelTargets;
    final run = ++_relabelRun;
    relabelRunning = true;
    relabelFinished = false;
    relabelTotal = targets.length;
    relabelDone = relabelSkipped = relabelFailed = 0;
    notifyListeners();
    var next = 0;
    Future<void> worker() async {
      while (run == _relabelRun && next < targets.length) {
        final d = targets[next++];
        final url = await ImageProcessor.analyzeUrlFor(d);
        if (run != _relabelRun) return;
        if (url == null) {
          relabelSkipped++;
        } else {
          try {
            final ai = await api.analyzeImage(url);
            if (run != _relabelRun) return;
            final i = db.indexWhere((x) => x.id == d.id);
            if (i >= 0) {
              db[i] = _relabeled(db[i], ai);
              await _saveDb();
            }
          } catch (_) {
            relabelFailed++;
          }
        }
        relabelDone++;
        notifyListeners();
      }
    }

    await Future.wait([
      for (var w = 0; w < math.min(_concurrency, targets.length); w++) worker(),
    ]);
    if (run != _relabelRun) return;
    relabelRunning = false;
    relabelFinished = true;
    notifyListeners();
  }

  /// 진행 표시(하단 카드·잠금화면)를 다시 분석 쪽으로 보여줄지: 다시 분석 중이거나 방금 끝났고, 일반 분석은 쉬는 중
  bool get relabelActiveForProgress =>
      relabelRunning ||
      (relabelFinished &&
          !analysisRunning &&
          !analysisPaused &&
          pickQueue.isEmpty);

  // ── 사진 상세 > 이 사진만 다시 분석하기 (고해상도 정밀 분석) ────────────
  /// 지금 다시 분석 중인 사진 id
  int? reanalyzingId;
  String? reanalyzeError;

  Future<void> reanalyzePhoto(int id) async {
    final d = photoById(id);
    if (d == null || reanalyzingId != null) return;
    if (!serverConnected) {
      reanalyzeError = ApiException('network').userMessage;
      notifyListeners();
      return;
    }
    reanalyzingId = id;
    reanalyzeError = null;
    notifyListeners();
    try {
      // 원본에서 1280px(웹은 1080px 미리보기)를 만들어 detail:'high' 로 분석
      final hi = await recordImageDataUrl(d);
      final url = hi ?? await ImageProcessor.analyzeUrlFor(d);
      if (url == null) {
        reanalyzeError = '원본 사진을 찾을 수 없어 다시 분석할 수 없어요';
      } else {
        final ai = await api.analyzeImage(
          url,
          detail: hi != null ? 'high' : 'low',
        );
        final i = db.indexWhere((x) => x.id == id);
        if (i >= 0) {
          db[i] = db[i].withAnalysis(ai);
          await _saveDb();
        }
      }
    } on ApiException catch (e) {
      reanalyzeError = e.userMessage;
    } catch (e) {
      reanalyzeError = '다시 분석하지 못했어요 ($e)';
    } finally {
      reanalyzingId = null;
      notifyListeners();
    }
  }

  void cancelRelabel() {
    _liveActivity.cancel();
    _relabelRun++;
    relabelRunning = false;
    relabelFinished = false;
    notifyListeners();
  }

  /// 새 AI 분석으로 설명만 바꾼 사진 (나머지 필드는 그대로)
  PhotoItem _relabeled(PhotoItem d, Map<String, dynamic> ai) =>
      d.withAnalysis(ai);

  void togglePauseAnalysis() {
    analysisPaused = !analysisPaused;
    if (!analysisPaused && pickQueue.isNotEmpty) {
      startAnalysis();
    } else {
      analysisRunning = false;
      notifyListeners();
    }
  }

  Map<String, List<int>> yearProgress() {
    final map = <String, List<int>>{};
    for (final p in pickQueue) {
      final y = p.modified.year.toString();
      final pair = map.putIfAbsent(y, () => [0, 0]);
      pair[1]++;
      if (db.any((d) => d.fileKey == p.key)) pair[0]++;
    }
    return map;
  }

  Future<void> startNewSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty || searchBusy) return;
    searchHistory
      ..clear()
      ..add(q);
    searchPool.clear();
    searchExcluded.clear();
    await _runSearch();
  }

  Future<void> answerFollowUp(String answer) async {
    if (searchBusy) return;
    // 답하기 전에 크게 보고 있던 사진은 아니라는 뜻 → 제외하고 나머지 후보에서 찾는다
    if (shownResultId case final id?) searchExcluded.add(id);
    searchHistory.add('Q: $currentQuestionText / A: $answer');
    if (testSession != null) testSession!.questions++;
    await _runSearch(withinPool: true);
  }

  /// '질문 한 번 더하기' — 검색을 처음부터 하지 않고 지금 맥락(searchHistory)에 질문 하나를 더한다.
  Future<void> askMore() async {
    if (searchBusy || searchResults.isEmpty) return;
    if (activeQuestion != null) {
      questionShown = true; // 서버가 이미 만들어 둔 질문이 있으면 바로 보여줌
      notifyListeners();
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
        .then((p) => p.setString(_searchCacheKey, jsonEncode(_searchCache)))
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
      notifyListeners();
      return;
    }
    searchBusy = true;
    searchError = null;
    searchCompleted = false;
    questionShown = false;
    notifyListeners();

    final run = _searchRunId;
    final inPool = withinPool && searchPool.isNotEmpty;
    final pool = searchPool.toSet();
    final photos = [
      for (final d in visiblePhotos)
        if ((!inPool || pool.contains(d.id)) && !searchExcluded.contains(d.id))
          d,
    ];
    try {
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
      if (testSession != null && testSession!.firstRank == null) {
        final idx = searchResults.indexWhere(
          (x) => x.id == testSession!.targetId,
        );
        testSession!.firstRank = idx >= 0 ? idx + 1 : 0;
      }
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
        notifyListeners();
      }
    }
  }

  void toggleYearVisibility(String year) {
    final currentlyHidden = db.any((d) => d.date.startsWith(year) && d.hidden);
    final nextHidden = !currentlyHidden;
    var count = 0;
    for (final d in db) {
      if (d.date.startsWith(year)) {
        d.hidden = nextHidden;
        count++;
      }
    }
    hiddenWarning = nextHidden ? '$year년 사진 $count장과 분석 정보가 검색에서 제외됩니다.' : '';
    notifyListeners();
  }

  /// AI 대화형 앨범: 요청을 보내 후보를 받고 미리보기(17)로 이동. 바로 저장하지 않는다.
  void _rememberAlbumPlan(String key, Map<String, dynamic> plan) {
    _albumPlans.remove(key); // 최근에 쓴 요청을 뒤로 (오래된 것부터 정리)
    _albumPlans[key] = plan;
    while (_albumPlans.length > 50) {
      _albumPlans.remove(_albumPlans.keys.first);
    }
    SharedPreferences.getInstance()
        .then((p) => p.setString(_albumPlansKey, jsonEncode(_albumPlans)))
        .ignore();
  }

  Future<void> composeAlbum(String request) async {
    final q = request.trim();
    if (q.isEmpty || albumBusy) return;
    if (!serverConnected) {
      albumError = ApiException('network').userMessage;
      notifyListeners();
      return;
    }
    albumBusy = true;
    albumError = null;
    notifyListeners();
    try {
      // 위치로 찾을 수 있게 주소를 잠깐(최대 8초) 더 받아 두고 보낸다
      await prefetchAddresses(wait: const Duration(seconds: 8));
      final planKey = q.replaceAll(RegExp(r'\s+'), ' ');
      final (title, ids, category, reason, plan) = await api.composeAlbum(
        visiblePhotos,
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
      notifyListeners();
    }
  }

  /// 앨범 미리보기(17)에서 '뒤로' 갈 화면 (AI 앨범 = 앨범 탭, 관련된 추억 = 그 앨범 화면)
  int albumDraftReturn = 11;

  /// 관련된 추억(그날의 사진 · 비슷한 분위기)의 사진들로 앨범 초안을 만들어 미리보기로.
  /// 기준 사진도 맨 앞에 함께 넣는다.
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

  /// '흩어진 순간 모으기' 제안 (앱 실행 시 GPT 로 생성). 비어 있으면 화면은 기본 예시를 쓴다.
  List<String> albumSuggestions = [];
  bool albumSuggestionsLoading = false;

  Future<void> loadAlbumSuggestions() async {
    final photos = visiblePhotos.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (!serverConnected || photos.isEmpty || albumSuggestionsLoading) return;
    albumSuggestionsLoading = true;
    notifyListeners();
    try {
      albumSuggestions = await api.suggestAlbums(
        photos.take(300).toList(),
        addr: addressById,
      );
    } catch (_) {
      // 실패하면 기본 예시 그대로
    } finally {
      albumSuggestionsLoading = false;
      notifyListeners();
    }
  }

  /// 미리보기 사진 전체 선택(=해제 목록 비우기) / 전체 해제
  void setAllDraftPhotos(bool selected) {
    albumDraftSelected.clear();
    if (!selected) albumDraftSelected.addAll(albumDraft?.photoIds ?? const []);
    notifyListeners();
  }

  /// 미리보기에서 사진 선택/해제 (albumDraftSelected = 앨범에서 뺄 사진)
  void toggleDraftPhoto(int id) {
    if (!albumDraftSelected.remove(id)) albumDraftSelected.add(id);
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
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

  // ── 앨범 카테고리 ─────────────────────────────────────────
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
    _saveCategories();
    _saveAlbums();
  }

  /// 앨범 이름 바꾸기 (빈 이름이면 그대로)
  void renameAlbum(int albumId, String title) {
    final a = albumById(albumId);
    final t = title.trim();
    if (a == null || t.isEmpty || t == a.title) return;
    a.title = t.length > 30 ? t.substring(0, 30) : t;
    notifyListeners();
    _saveAlbums();
  }

  void setAlbumCategory(int albumId, String? category) {
    final a = albumById(albumId);
    if (a == null) return;
    a.category = category;
    notifyListeners();
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
    notifyListeners();
  }

  void openAlbum(int id) {
    activeAlbumId = id;
    unlockedAlbumId = null; // 앨범 목록에서 들어올 때마다 다시 잠김
    go(16);
  }

  // ── 앨범 잠금 (비밀번호 4자리) ─────────────────────────────
  /// 지금 열어 둔 잠긴 앨범 (앨범 안에서 사진을 봤다 돌아와도 열린 채, 목록에서 다시 들어오면 잠김)
  int? unlockedAlbumId;
  int _unlockFails = 0;
  DateTime? _unlockBlockedUntil;

  static String _pinHash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  bool isAlbumHidden(PhotoAlbum a) => a.locked && unlockedAlbumId != a.id;

  void lockAlbum(int id, String pin) {
    final a = albumById(id);
    if (a == null || !RegExp(r'^\d{4}$').hasMatch(pin)) return;
    final rnd = math.Random.secure();
    final salt = List.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    a
      ..lockSalt = salt
      ..lockHash = _pinHash(salt, pin);
    unlockedAlbumId = id; // 방금 잠근 사람은 계속 보고 있음
    notifyListeners();
    _saveAlbums();
  }

  /// 비밀번호 확인. 맞으면 null, 틀리면 안내 문구. 5번 틀리면 30초 동안 막는다.
  String? unlockAlbum(int id, String pin) {
    final a = albumById(id);
    if (a == null || !a.locked) return null;
    final until = _unlockBlockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final sec = until.difference(DateTime.now()).inSeconds + 1;
      return '$sec초 뒤에 다시 시도하세요';
    }
    if (_pinHash(a.lockSalt!, pin) != a.lockHash) {
      _unlockFails++;
      if (_unlockFails >= 5) {
        _unlockFails = 0;
        _unlockBlockedUntil = DateTime.now().add(const Duration(seconds: 30));
        return '5번 틀렸어요. 30초 뒤에 다시 시도하세요';
      }
      return '비밀번호가 맞지 않아요 ($_unlockFails/5)';
    }
    _unlockFails = 0;
    _unlockBlockedUntil = null;
    unlockedAlbumId = id;
    notifyListeners();
    return null;
  }

  /// 잠금 풀기 (앨범을 연 상태에서만)
  void removeAlbumLock(int id) {
    final a = albumById(id);
    if (a == null || isAlbumHidden(a)) return;
    a
      ..lockSalt = null
      ..lockHash = null;
    notifyListeners();
    _saveAlbums();
  }

  void deleteAlbum(int id) {
    albums.removeWhere((a) => a.id == id);
    if (lastCreatedAlbumId == id) lastCreatedAlbumId = null;
    if (activeAlbumId == id) activeAlbumId = null;
    notifyListeners();
    _saveAlbums();
  }

  void startUsabilityTest(int targetId) {
    testSession = ActiveTestSession(
      targetId: targetId,
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    searchHistory.clear();
    searchResults = [];
    activeQuestion = null;
    searchCompleted = false;
    searchError = null;
    go(13);
  }

  static double _distanceKm(List<double>? a, List<double>? b) {
    if (a == null || b == null || a.length < 2 || b.length < 2) return 1e9;
    double rad(double x) => x * math.pi / 180.0;
    final dLat = rad(b[0] - a[0]);
    final dLon = rad(b[1] - a[1]);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a[0])) *
            math.cos(rad(b[0])) *
            math.pow(math.sin(dLon / 2), 2);
    return 12742.0 * math.asin(math.sqrt(h));
  }

  static Set<String> _tokens(PhotoItem d) {
    final raw = <String>[
      d.weather,
      d.time,
      ...d.background.split(RegExp(r'[ ,]+')),
      ...d.place.split(RegExp(r'[()\s]+')),
      ...d.food,
      // 분석 v2: 의미 카테고리·검색 키워드도 '비슷한 분위기' 계산에 사용
      ...d.semanticCategory,
      ...d.searchKeywords,
      if (d.imageType.isNotEmpty && d.imageType != 'photo') d.imageType,
    ];
    return raw
        .where((x) => x.isNotEmpty && !{'알', '수', '없음'}.contains(x))
        .toSet();
  }

  /// 큰 분류: 정보(스크린샷·문서) · 음식 · 인물 · 풍경·장소
  static String topicGroup(PhotoItem d) {
    if (d.isInfoImage) return '정보';
    if (d.food.any((f) => !isUnknownInfo(f))) return '음식';
    final people = d.people.trim();
    if (people.isNotEmpty && !isUnknownInfo(people)) return '인물';
    return '풍경·장소';
  }

  // 비교에서 빼는 너무 흔한 말 (날씨·시간대·실내/실외 등은 '비슷함'의 근거로 약함)
  static const _genericWords = {
    '실내',
    '실외',
    '야외',
    '배경',
    '조명',
    '사진',
    '이미지',
    '모습',
    '장면',
    '낮',
    '밤',
    '저녁',
    '아침',
    '오후',
    '맑음',
    '흐림',
    '비',
    '눈',
  };

  /// 주제 비교용 키워드: AI 검색 키워드 · 카테고리 · 음식 · 장소
  static Set<String> topicTokens(PhotoItem d) =>
      {
            ...d.searchKeywords,
            ...d.semanticCategory,
            ...d.food,
            ...d.place.split(RegExp(r'[()\s·,]+')),
          }
          .map((x) => x.trim())
          .where(
            (x) =>
                x.length >= 2 &&
                !_genericWords.contains(x) &&
                !isUnknownInfo(x),
          )
          .toSet();

  /// 최소한 카테고리나 키워드 하나는 같아야 '비슷한 사진'으로 본다
  /// (풍경이면 풍경, 음식이면 음식 · 또는 '카페'처럼 같은 키워드)
  static bool sharesTopic(PhotoItem a, PhotoItem b) {
    if (topicGroup(a) == topicGroup(b)) return true;
    if (a.semanticCategory.isNotEmpty &&
        b.semanticCategory.isNotEmpty &&
        a.semanticCategory.first == b.semanticCategory.first) {
      return true;
    }
    return topicTokens(a).intersection(topicTokens(b)).isNotEmpty;
  }

  static const _timeOrder = {'아침': 0, '낮': 1, '오후': 1, '저녁': 2, '밤': 3};

  /// '그날의 사진' 대표: 기준 사진과 촬영 시각이 가장 가까운 사진.
  /// 시각 정보가 없는 기존 데이터는 시간대(낮/저녁/밤) → 분석 순서가 가까운 순.
  static PhotoItem? closestInTime(PhotoItem base, List<PhotoItem> list) {
    if (list.isEmpty) return null;
    num dist(PhotoItem x) {
      if (base.takenAtMs != null && x.takenAtMs != null) {
        return (x.takenAtMs! - base.takenAtMs!).abs();
      }
      final a = _timeOrder[base.time], b = _timeOrder[x.time];
      final slot = (a != null && b != null) ? (a - b).abs() : 2;
      // 시각이 있는 쪽을 항상 우선
      return 1e13 + slot * 1e6 + (x.id - base.id).abs();
    }

    return list.reduce((m, x) => dist(x) < dist(m) ? x : m);
  }

  RelatedMemories relatedFor(PhotoItem d) {
    final others = visiblePhotos.where((x) => x.id != d.id).toList();
    final sameDay = others.where((x) => x.date == d.date).toList();
    final nearPlace = others
        .where((x) => x.date != d.date && _distanceKm(d.gps, x.gps) < 1.5)
        .toList();
    final baseTokens = _tokens(d);
    final simPairs =
        others
            // 같은 날이 아니고, 카테고리나 키워드가 하나라도 같은 사진만
            .where((x) => x.date != d.date && sharesTopic(d, x))
            .map((x) => MapEntry(x, _tokens(x).intersection(baseTokens).length))
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
