import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/photo_item.dart';
import '../services/image_processor.dart';
import '../services/snapback_api.dart';

class PickedFileEntry {
  PickedFileEntry({
    required this.file,
    required this.key,
    required this.modified,
  });

  final XFile file;
  final String key;
  final DateTime modified;
}

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

class ActiveTestSession {
  ActiveTestSession({required this.targetId, required this.startedAtMs});
  final int targetId;
  final int startedAtMs;
  int questions = 0;
  int? firstRank;
}

class SnapbackState extends ChangeNotifier {
  SnapbackState() {
    _init();
  }

  static const _dbKey = 'snapback_db';
  static const _urlKey = 'snapback_server_url';

  final SnapbackApi api = SnapbackApi();
  final ImagePicker _picker = ImagePicker();

  int screen = 0;
  bool serverConnected = false;
  String aiStatusText = '연결 확인 중…';

  // Onboarding selections
  int scopeSelection = 0; // 0: 전체, 1: 앨범, 2: 직접, 3: 기간
  int orderSelection = 0; // 0: 최근, 1: 오래된, 2: 지정 기간
  String priorityYear = '2026';

  // Photos & DB
  List<PhotoItem> db = buildSeedPhotos();
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
  String currentQuestionText = '';
  List<SearchRankedItem> searchResults = [];
  SearchQuestion? activeQuestion;
  bool searchCompleted = false;
  bool searchBusy = false;
  String? searchError;

  // Memory detail (Screen 10)
  int activeMemoryId = 1;

  // Settings (Screen 12)
  bool backgroundAnalysis = true;
  String hiddenWarning = '';

  // Albums (Screen 11)
  final List<Map<String, String>> keywordAlbums = [
    {'emoji': '🐱', 'title': '고양이 · 86'},
    {'emoji': '🌊', 'title': '바다 · 120'},
  ];

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
    final raw = prefs.getString(_dbKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .whereType<Map<String, dynamic>>()
            .map(PhotoItem.fromJson)
            .toList();
        db = [...buildSeedPhotos(), ...list];
        final maxId =
            db.fold<int>(11, (prev, e) => e.id > prev ? e.id : prev);
        _nextId = maxId + 1;
      } catch (_) {}
    }
    notifyListeners();
    await refreshHealth();
  }

  Future<void> refreshHealth() async {
    final res = await api.checkHealth();
    serverConnected = res.ok;
    if (!res.ok) {
      aiStatusText = '⚠️ 서버 연결 안 됨';
    } else if (res.keyOk) {
      aiStatusText = 'AI 연결됨 ✓';
    } else {
      aiStatusText = '⚠️ API 키 확인 필요';
    }
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    api.baseUrl = clean.isEmpty ? (kIsWeb ? '' : 'http://localhost:3000') : clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, clean);
    await refreshHealth();
  }

  Future<void> _saveDb() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uploaded = db.where((d) => d.id > 11).map((d) => d.toJson()).toList();
      await prefs.setString(_dbKey, jsonEncode(uploaded));
    } catch (_) {}
  }

  void go(int idx) {
    screen = idx;
    notifyListeners();
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
    activeMemoryId = id;
    go(10);
  }

  Future<int> pickPhotosFromGallery({bool startImmediately = false}) async {
    final files = await _picker.pickMultiImage();
    if (files.isEmpty) return 0;
    final seen = pickQueue.map((e) => e.key).toSet();
    var added = 0;
    for (final f in files) {
      final len = await f.length();
      final mod = await f.lastModified();
      final k = '${f.name}$len${mod.millisecondsSinceEpoch}';
      if (!seen.contains(k)) {
        pickQueue.add(PickedFileEntry(file: f, key: k, modified: mod));
        seen.add(k);
        added++;
      }
    }
    notifyListeners();
    if (startImmediately) {
      startAnalysis();
    }
    return added;
  }

  Future<void> startAnalysis() async {
    final myRun = ++_runId;
    analysisPaused = false;
    analysisRunning = true;
    analysisFinished = false;

    final pending = pickQueue
        .where((p) => !db.any((d) => d.fileKey == p.key))
        .toList();

    if (orderSelection == 2) {
      final py = int.tryParse(priorityYear) ?? 2026;
      pending.sort((a, b) {
        final am = a.modified.year == py ? 1 : 0;
        final bm = b.modified.year == py ? 1 : 0;
        if (am != bm) return bm - am;
        return b.modified.compareTo(a.modified);
      });
    } else if (orderSelection == 1) {
      pending.sort((a, b) => a.modified.compareTo(b.modified));
    } else {
      pending.sort((a, b) => b.modified.compareTo(a.modified));
    }

    analysisTotal = pickQueue.length;
    analysisDone = analysisTotal - pending.length;
    etaMs = 0;
    currentFileDate = pending.isNotEmpty ? pending.first.modified : null;
    if (pending.isEmpty && analysisTotal > 0) {
      analysisFinished = true;
      analysisRunning = false;
    }
    notifyListeners();

    if (pending.isEmpty) {
      analysisRunning = false;
      notifyListeners();
      return;
    }

    final t0 = DateTime.now().millisecondsSinceEpoch;
    var processedCount = 0;

    for (var i = 0; i < pending.length; i++) {
      if (myRun != _runId || analysisPaused) {
        analysisRunning = false;
        notifyListeners();
        return;
      }
      final entry = pending[i];
      currentFileDate = entry.modified;
      notifyListeners();

      try {
        final processed =
            await ImageProcessor.process(entry.file, entry.modified);
        final ai = await api.analyzeImage(processed.analyzeDataUrl);
        final rawFood = ai['food'];
        final foodList = rawFood is List
            ? rawFood.map((e) => e.toString()).toList()
            : (rawFood is String && rawFood.isNotEmpty ? [rawFood] : <String>[]);

        final item = PhotoItem(
          id: _nextId++,
          fileKey: entry.key,
          date: processed.dateStr,
          place: (ai['place'] ?? '알 수 없음').toString(),
          food: foodList,
          people: (ai['people'] ?? '').toString(),
          background: (ai['background'] ?? '').toString(),
          weather: (ai['weather'] ?? '알 수 없음').toString(),
          time: (ai['time'] ?? '알 수 없음').toString(),
          caption: (ai['caption'] ?? '').toString(),
          gps: processed.gps,
          exif: processed.hasExifDate,
          thumbDataUrl: processed.thumbDataUrl,
        );
        db.add(item);
        await _saveDb();
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
        aiStatusText = e.userMessage;
        analysisLogs.insert(
          0,
          AnalysisLogEntry(
            isError: true,
            text: '⚠️ ${entry.file.name} — ${e.userMessage}',
          ),
        );
      } catch (e) {
        analysisLogs.insert(
          0,
          AnalysisLogEntry(
            isError: true,
            text: '⚠️ ${entry.file.name} — 오류 ($e)',
          ),
        );
      }

      analysisDone++;
      processedCount++;
      final elapsed = DateTime.now().millisecondsSinceEpoch - t0;
      final remaining = analysisTotal - analysisDone;
      etaMs = remaining > 0 ? ((elapsed / processedCount) * remaining).round() : 0;
      currentFileDate =
          i + 1 < pending.length ? pending[i + 1].modified : entry.modified;
      notifyListeners();
    }

    if (myRun == _runId) {
      analysisRunning = false;
      analysisFinished = true;
      etaMs = 0;
      notifyListeners();
    }
  }

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
    await _runSearch();
  }

  Future<void> answerFollowUp(String answer) async {
    if (searchBusy) return;
    searchHistory.add('Q: $currentQuestionText / A: $answer');
    if (testSession != null) testSession!.questions++;
    await _runSearch();
  }

  Future<void> _runSearch() async {
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
    notifyListeners();

    try {
      final res = await api.searchMemory(visiblePhotos, searchHistory);
      searchResults = res.ranked.take(5).toList();
      if (testSession != null && testSession!.firstRank == null) {
        final idx = searchResults.indexWhere((x) => x.id == testSession!.targetId);
        testSession!.firstRank = idx >= 0 ? idx + 1 : 0;
      }
      activeQuestion = res.question;
      if (res.question != null) {
        currentQuestionText = res.question!.text;
        searchCompleted = false;
      } else {
        searchCompleted = true;
      }
    } on ApiException catch (e) {
      searchError = e.userMessage;
    } catch (e) {
      searchError = '오류가 났어요 ($e)';
    } finally {
      searchBusy = false;
      notifyListeners();
    }
  }

  void toggleYearVisibility(String year) {
    final currentlyHidden =
        db.any((d) => d.date.startsWith(year) && d.hidden);
    final nextHidden = !currentlyHidden;
    var count = 0;
    for (final d in db) {
      if (d.date.startsWith(year)) {
        d.hidden = nextHidden;
        count++;
      }
    }
    hiddenWarning =
        nextHidden ? '$year년 사진 $count장과 분석 정보가 검색에서 제외됩니다.' : '';
    notifyListeners();
  }

  void addKeywordAlbum(String keyword) {
    final v = keyword.trim();
    if (v.isEmpty) return;
    keywordAlbums.add({'emoji': '✨', 'title': '$v · 새 앨범'});
    notifyListeners();
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
    final h = math.pow(math.sin(dLat / 2), 2) +
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
    ];
    return raw
        .where((x) => x.isNotEmpty && !{'알', '수', '없음'}.contains(x))
        .toSet();
  }

  RelatedMemories relatedFor(PhotoItem d) {
    final others = visiblePhotos.where((x) => x.id != d.id).toList();
    final sameDay = others.where((x) => x.date == d.date).toList();
    final nearPlace = others
        .where((x) => x.date != d.date && _distanceKm(d.gps, x.gps) < 1.5)
        .toList();
    final baseTokens = _tokens(d);
    final simPairs = others
        .where((x) => x.date != d.date)
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
