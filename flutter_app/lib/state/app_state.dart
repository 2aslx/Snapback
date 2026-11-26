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
import '../services/background_analysis.dart';
import '../services/embedding_store.dart';
import '../services/hybrid_search.dart';
import '../services/image_processor.dart';
import '../services/live_activity.dart';
import '../services/preview_store.dart';
import '../services/recap.dart';
import '../services/snapback_api.dart';

// 기능별 메서드는 state/parts/*.dart 의 extension (같은 라이브러리의 part — 비공개 필드를 그대로 쓴다).
part 'parts/storage.dart';
part 'parts/places.dart';
part 'parts/records.dart';
part 'parts/memories.dart';
part 'parts/search.dart';
part 'parts/embeddings.dart';
part 'parts/library.dart';
part 'parts/analysis.dart';
part 'parts/albums.dart';
part 'parts/album_lock.dart';

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

  /// 사용자가 결과를 기다리는 작업이 진행 중인지 (화면 맨 아래 얇은 진행 바). 사진 분석은 진행 카드가 따로 있다.
  bool get isLoading =>
      searchBusy ||
      albumBusy ||
      recordBusy ||
      reanalyzingId != null ||
      pickerLoading ||
      libraryAlbumsLoading;
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
    // iOS 충전 중 백그라운드 분석: 남은 대기열을 복원한 뒤에 연결 (iOS 가 작업을 시작하면 이어서 분석)
    BackgroundAnalysis.attach(
      run: runQueuedAnalysisInBackground,
      expire: pauseForBackgroundExpiry,
    );
    BackgroundAnalysis.setPending(pickQueue.any((e) => e.asset != null));
    EmbeddingStore.load().ignore(); // 검색 1차 선별용 사진 임베딩 — 화면을 막지 않고 뒤에서 읽는다
    ready = true;
    notifyListeners();
    await refreshHealth();
    loadAlbumSuggestions(); // 앱을 켤 때마다 앨범 제안을 새로 만든다
    prefetchAddresses(); // 위치 정보가 있는 사진의 주소를 뒤에서 미리 받아 둔다
    backfillEmbeddings(); // 임베딩이 없는 예전 사진은 분석 텍스트로 뒤에서 채운다
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

  static const _webDbKey = 'db:main';
  Timer? _saveTimer;

  // ── 촬영 장소 주소 (구글 지도 또는 OpenStreetMap, 기기에 캐시) ─────────────
  /// 좌표(소수 3자리 ≈ 110m, 가까운 사진끼리 같은 주소를 나눠 씀) → 지역명
  final Map<String, String> placeNames = {};
  final Set<String> _placeAsked = {};

  /// 주소 받기에 실패한 횟수 (좌표 키별). 3번까지 다시 시도한다.
  final Map<String, int> _placeFails = {};

  static String? _placeKey(PhotoItem d) {
    final g = d.gps;
    if (g == null || g.length < 2) return null;
    return '${g[0].toStringAsFixed(3)},${g[1].toStringAsFixed(3)}';
  }

  // 위치 정보가 있는 사진의 주소를 한 장씩 미리 받아 둔다 (앨범·검색에서 '신촌' 같은 지명으로 찾기 위해)
  Future<void>? _addrJob;

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

  /// 사진 탭 정렬: 'time' 촬영 시간순(월별) / 'added' 앱에 추가한 순(최근 추가가 먼저)
  String photoSort = 'time';

  PhotoItem? photoById(int id) => db.where((d) => d.id == id).firstOrNull;

  // ── 홈 '다시 꺼내 볼 기억' 카드 ─────────────────────────────

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
    // 앨범 상세·사진 상세 흐름을 벗어나면(홈·검색·앨범 목록·기억·기록 등) 잠긴 앨범을 다시 잠근다
    if (!const {10, 16, 18, 20, 21}.contains(idx)) unlockedAlbumId = null;
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
  /// 검색 결과에서 크게 본 사진의 이전 단계 (뒤로가기로 바로 전 사진으로 돌아가기)
  final List<int?> _pinBack = [];

  // ── 하이브리드 검색 1차 선별 · 사진 임베딩 ─────────────────────
  /// 검색어 임베딩 캐시 (같은 검색어는 다시 요청하지 않음, 최근 30개)
  final Map<String, Float32List?> _queryVectors = {};
  int _backfillRun = 0;
  bool _backfilling = false;

  // ── 검색 '이전 단계로 되돌리기' ─────────────────────────────
  final List<_SearchSnapshot> _searchUndo = [];

  /// 홈 검색창의 위치 (홈 스크롤 0 기준, 전역 y). 검색에서 뒤로 올 때 목표 지점.
  double? homeSearchBoxTop;
  bool _homeReturn = false;

  /// 사진 상세에서 '뒤로'로 돌아갈 화면 (들어온 곳)
  int detailReturn = 5;

  // ── 기억 탭: 검색으로 최종 찾은 사진 기록 ─────────────────────
  /// 최근에 찾은 순서. 검색 결과에서 사진을 열면(맞아요 · 후보 선택) 기록된다.
  List<FoundMemory> found = [];

  /// 월간 리캡 상세(화면 24)에서 보는 달 (연, 월)
  (int, int)? recapMonth;

  // ── 사진 상세의 '관련된 추억' 가상 앨범 (화면 18) ─────────────────
  // 실제 갤러리에 앨범을 만들지 않고, 앱 안에서 관련 사진을 묶어 보여준다.
  /// 0 = 그날의 사진, 1 = 비슷한 분위기
  int relatedAlbumKind = 0;

  /// 어느 사진 상세에서 연 앨범인지
  int relatedBaseId = 1;

  /// 상세 ↔ 관련 앨범 사이 뒤로가기 기록: (화면, 기준 사진 id, 앨범 종류)
  final List<(int, int, int)> _relatedNav = [];

  // ── iOS 사진 보관함 (photo_manager) ─────────────────────────────
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

  /// 권한 요청 + 전체 사진 수 / 앨범 목록 불러오기.
  bool _libLoading = false;
  bool pickerLoading = false;

  /// 사진 접근 범위(화면 1)에서 '뒤로' 갈 화면: 처음 설정이면 시작 안내(0), 홈 ＋로 왔으면 홈(5)
  int scopeReturn = 0;

  /// 사진 1장: 줄이기 → AI 분석 → DB 저장 (실패하면 기록만 남기고 넘어감)
  /// 동시에 분석할 사진 수: 웹은 큰 사진을 브라우저 메모리에서 풀어야 해서 2장, 앱은 5장
  static int get _concurrency => kIsWeb ? 2 : kAnalyzeConcurrency;

  /// 이번 분석에서 실패한 사진 수 (형식을 읽을 수 없음·서버 오류 등). 하단 진행 카드와 홈 알림에 표시
  int analysisFailed = 0;
  final Set<String> _failedKeys = {};

  /// 사진을 고를 때 건너뛴 이유 안내 (예: 이미 분석한 사진)
  String pickNotice = '';

  /// 지금 분석 요청 중인 사진 (일시정지 후 바로 다시 시작해도 같은 사진을 두 번 보내지 않게)
  final Set<String> _inFlight = {};

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

  // ── 사진 상세 > 이 사진만 다시 분석하기 (고해상도 정밀 분석) ────────────
  /// 지금 다시 분석 중인 사진 id
  int? reanalyzingId;
  String? reanalyzeError;

  /// 앨범 미리보기(17)에서 '뒤로' 갈 화면 (AI 앨범 = 앨범 탭, 관련된 추억 = 그 앨범 화면)
  int albumDraftReturn = 11;

  /// '흩어진 순간 모으기' 제안 (앱 실행 시 GPT 로 생성). 비어 있으면 화면은 기본 예시를 쓴다.
  List<String> albumSuggestions = [];
  bool albumSuggestionsLoading = false;

  // ── 앨범 카테고리 ─────────────────────────────────────────

  // ── 앨범 잠금 (비밀번호 4자리) ─────────────────────────────
  /// 지금 열어 둔 잠긴 앨범 (앨범 안에서 사진을 봤다 돌아와도 열린 채, 목록에서 다시 들어오면 잠김)
  int? unlockedAlbumId;
  int _unlockFails = 0;
  DateTime? _unlockBlockedUntil;

  static String _pinHash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

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

}

/// 질문에 답하기 직전의 검색 상태 ('이전 단계로 되돌리기'용)
class _SearchSnapshot {
  _SearchSnapshot.of(SnapbackState s)
    : history = [...s.searchHistory],
      excluded = {...s.searchExcluded},
      results = [...s.searchResults],
      question = s.activeQuestion,
      questionText = s.currentQuestionText,
      questionShown = s.questionShown,
      completed = s.searchCompleted,
      pinned = s.pinnedResultId;

  final List<String> history;
  final Set<int> excluded;
  final List<SearchRankedItem> results;
  final SearchQuestion? question;
  final String questionText;
  final bool questionShown;
  final bool completed;
  final int? pinned;

  void restore(SnapbackState s) {
    s.searchHistory
      ..clear()
      ..addAll(history);
    s.searchExcluded
      ..clear()
      ..addAll(excluded);
    s.searchResults = [...results];
    s.activeQuestion = question;
    s.currentQuestionText = questionText;
    s.questionShown = questionShown;
    s.searchCompleted = completed;
    s.pinnedResultId = pinned;
  }
}
