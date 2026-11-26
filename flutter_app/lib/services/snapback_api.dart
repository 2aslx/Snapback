import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/photo_item.dart';
import 'hybrid_search.dart';

class ApiException implements Exception {
  ApiException(this.code);
  final String code;

  static const Map<String, String> _messages = {
    'openai_401': 'API 키가 올바르지 않아요. .env 의 키를 확인하고 서버를 다시 시작해 주세요',
    'openai_403': '이 API 키로는 해당 모델을 쓸 수 없어요',
    'openai_404': '모델을 찾을 수 없어요. .env 의 OPENAI_MODEL 을 확인해 주세요',
    'openai_400': 'AI가 요청을 거절했어요 (모델이 이미지를 지원하지 않거나 사진 형식 문제)',
    'openai_429': 'OpenAI 사용 한도 초과 또는 크레딧 부족이에요. 결제/잔액을 확인해 주세요',
    'openai_500': 'OpenAI 서버 오류예요. 잠시 후 다시 시도해 주세요',
    'openai_503': 'OpenAI 서버가 바빠요. 잠시 후 다시 시도해 주세요',
    'openai_unreachable': '서버가 OpenAI에 연결하지 못했어요. 인터넷 연결을 확인해 주세요',
    'rate_limited': '요청이 너무 많아요. 1분 뒤 다시 시도해 주세요',
    'timeout': '응답이 너무 오래 걸려요. 다시 시도해 주세요',
    'network': '서버에 연결할 수 없어요. 터미널에서 npm start 가 켜져 있는지 확인해 주세요',
    'bad_ai_json': 'AI 응답 형식이 이상해요. 다시 시도해 주세요',
    'bad_image': '이미지를 읽을 수 없어요',
    'too_big': '사진 용량이 너무 커요',
    'bad_request': '요청 형식 오류예요',
    'server_error': '서버 내부 오류예요. 터미널 메시지를 확인해 주세요',
  };

  String get userMessage => '${_messages[code] ?? '오류가 났어요'} ($code)';

  @override
  String toString() => userMessage;
}

class HealthResult {
  HealthResult({required this.ok, required this.keyOk, required this.model});
  final bool ok;
  final bool keyOk;
  final String model;
}

class SearchResponse {
  SearchResponse({required this.ranked, this.question, this.pool = const []});
  final List<SearchRankedItem> ranked;
  final SearchQuestion? question;

  /// 상위 30개 후보 id — 질문에 답한 뒤에는 이 안에서만 다시 찾는다
  final List<int> pool;

  Map<String, dynamic> toJson() => {
    'ranked': [for (final r in ranked) r.toJson()],
    'question': question?.toJson(),
    'pool': pool,
  };

  factory SearchResponse.fromJson(Map<String, dynamic> data) {
    final ranked = (data['ranked'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SearchRankedItem.fromJson)
        .toList();
    final qRaw = data['question'];
    final question =
        qRaw is Map<String, dynamic> &&
            (qRaw['options'] as List?)?.isNotEmpty == true
        ? SearchQuestion.fromJson(qRaw)
        : null;
    final pool = (data['pool'] as List? ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList();
    return SearchResponse(
      ranked: ranked,
      question: question,
      pool: pool.isNotEmpty ? pool : [for (final r in ranked) r.id],
    );
  }
}

/// 기본 API 서버 주소.
/// 웹은 같은 도메인('')을 쓰고, iOS 는 빌드 시 지정한 주소를 쓴다.
/// 예: flutter run -d ios --dart-define=SNAPBACK_API_URL=http://localhost:3000 (로컬 서버로 테스트할 때)
const String kDefaultApiUrl = kIsWeb
    ? String.fromEnvironment('SNAPBACK_API_URL')
    : String.fromEnvironment(
        'SNAPBACK_API_URL',
        defaultValue: 'https://snapback-virid.vercel.app',
      );

class SnapbackApi {
  SnapbackApi({String? baseUrl}) : baseUrl = baseUrl ?? kDefaultApiUrl;

  String baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<HealthResult> checkHealth() async {
    try {
      final res = await http
          .get(_uri('/api/health'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        return HealthResult(ok: false, keyOk: false, model: '');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return HealthResult(
        ok: data['ok'] == true,
        keyOk: data['key'] == true,
        model: (data['model'] ?? '').toString(),
      );
    } catch (_) {
      return HealthResult(ok: false, keyOk: false, model: '');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    http.Response res;
    try {
      res = await http
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw ApiException('timeout');
    } catch (_) {
      throw ApiException('network');
    }

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final code =
          data['error']?.toString() ??
          (res.statusCode == 429 ? 'rate_limited' : 'http_${res.statusCode}');
      throw ApiException(code);
    }
    return data;
  }

  /// 사진 1장 분석. 서버·OpenAI 가 잠깐 바쁘면(429/5xx/시간초과) 조금 기다렸다 최대 2번 다시 시도.
  /// [detail] 'high' 면 서버가 고해상도로 글자까지 정밀하게 읽는다 (큰 이미지와 함께 보낼 때만).
  Future<Map<String, dynamic>> analyzeImage(
    String imageDataUrl, {
    String detail = 'low',
  }) async {
    const retry = {
      'rate_limited',
      'openai_429',
      'openai_500',
      'openai_503',
      'timeout',
    };
    for (var attempt = 0; ; attempt++) {
      try {
        return await _post('/api/analyze', {
          'image': imageDataUrl,
          if (detail == 'high') 'detail': 'high',
        });
      } on ApiException catch (e) {
        if (attempt >= 2 || !retry.contains(e.code)) rethrow;
        await Future<void>.delayed(Duration(seconds: 3 * (attempt + 1)));
      }
    }
  }

  /// 서버가 한 번에 받는 최대 사진 수 (api/_core.js MAX_DB). 넘으면 최근 사진부터 이만큼만 보낸다.
  static const maxPhotos = 2000;

  /// AI 로 보낼 사진 목록: 썸네일 없이, 촬영 위치는 좌표 대신 시·구·동 주소(addr)로
  static List<Map<String, dynamic>> aiDb(
    List<PhotoItem> db,
    Map<int, String> addr,
  ) => [
    for (final d
        in db.length <= maxPhotos
            ? db
            : ([...db]..sort((a, b) => b.date.compareTo(a.date))).take(
                maxPhotos,
              ))
      {...d.toJson(includeThumb: false)..remove('gps'), 'addr': ?addr[d.id]},
  ];

  /// [wantQuestion] — '질문 한 번 더하기': 서버가 후보를 가를 질문을 반드시 하나 만든다.
  Future<SearchResponse> searchMemory(
    List<PhotoItem> db,
    List<String> hist, {
    bool wantQuestion = false,
    Map<int, String> addr = const {},
  }) async {
    final data = await _post('/api/search', {
      'db': aiDb(db, addr),
      'hist': hist,
      if (wantQuestion) 'wantQuestion': true,
    });
    return SearchResponse.fromJson(data);
  }

  /// 검색 결과 저장용 키: 대화 기록 + '질문 더하기' 여부 + AI 에 보내는 사진 정보 전체의 지문.
  /// 사진을 추가·삭제·다시 분석하거나 주소가 새로 생기면 키가 바뀌어 새로 검색한다.
  static String searchKey(
    List<PhotoItem> db,
    List<String> hist, {
    bool wantQuestion = false,
    Map<int, String> addr = const {},
  }) {
    final text = jsonEncode([hist, wantQuestion, aiDb(db, addr)]);
    // FNV-1a 32bit (실행·플랫폼이 달라도 같은 값)
    var h = 0x811c9dc5;
    for (final c in utf8.encode(text)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return '${h.toRadixString(36)}-${text.length}';
  }

  /// AI 대화형 앨범: 자연어 요청 → (이름, 사진 id 목록, 추천 카테고리 id 또는 null, 못 찾은 이유, 해석한 조건)
  /// [plan] 같은 요청으로 전에 받은 조건. 보내면 서버가 다시 해석하지 않아 매번 같은 결과가 나온다.
  Future<(String, List<int>, String?, String, Map<String, dynamic>?)>
  composeAlbum(
    List<PhotoItem> db,
    String request, {
    List<Map<String, String>> categories = const [],
    Map<int, String> addr = const {},
    Map<String, dynamic>? plan,
  }) async {
    final data = await _post('/api/album', {
      'db': aiDb(db, addr),
      'request': request,
      if (categories.isNotEmpty) 'categories': categories,
      'plan': ?plan,
    });
    final ids = (data['ids'] as List? ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList();
    final cat = data['category'];
    return (
      (data['title'] ?? '').toString(),
      ids,
      cat is String && cat.isNotEmpty ? cat : null,
      (data['reason'] ?? '').toString(),
      data['plan'] is Map<String, dynamic>
          ? data['plan'] as Map<String, dynamic>
          : null,
    );
  }

  /// GPS 좌표 → 시·구·동 주소 (서버가 구글 지도 또는 OpenStreetMap 으로 변환).
  Future<String?> placeName(double lat, double lng) async {
    final data = await _post('/api/place', {'lat': lat, 'lng': lng});
    final n = data['name'];
    return n is String && n.trim().isNotEmpty ? n.trim() : null;
  }

  /// '기록으로 남기기' 초안. [image] 가 있으면 AI 가 사진 속 글자까지 읽는다.
  Future<Map<String, dynamic>> draftRecord(
    PhotoItem photo, {
    String? image,
    String? location,
  }) => _post('/api/record', {
    'photo': photo.toJson(includeThumb: false),
    'image': ?image,
    if (location != null && location.isNotEmpty) 'location': location,
  });

  /// '맞아요'로 찾은 사진에 붙일 키워드 — 기억 문장·질문 답에서 사진 정보가 놓친 새 정보만
  Future<List<String>> recallKeywords(
    PhotoItem photo,
    String query, {
    List<String> answers = const [],
  }) async {
    final data = await _post('/api/recall', {
      'photo': {...photo.toJson(includeThumb: false)}
        ..remove('gps')
        ..remove('rk')
        ..remove('rq'),
      'query': query,
      if (answers.isNotEmpty) 'answers': answers,
    });
    return ((data['keywords'] as List?) ?? const [])
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 글 여러 개(최대 50개) → 256차원 임베딩. 빈 글이나 실패한 항목은 null.
  Future<List<Float32List?>> embedTexts(List<String> texts) async {
    final data = await _post('/api/embed', {'texts': texts});
    final list = (data['embeddings'] as List?) ?? const [];
    return [for (var i = 0; i < texts.length; i++) i < list.length ? toVector(list[i]) : null];
  }

  /// 검색어 한 문장 → 256차원 임베딩 (실패하면 null — 키워드 선별로 대신한다)
  Future<Float32List?> embedQuery(String text) async {
    try {
      final data = await _post('/api/embed', {'text': text});
      return toVector(data['embedding']);
    } catch (_) {
      return null;
    }
  }

  /// '흩어진 순간 모으기' 제안 문장 (사진 분석 DB 기반, 최대 3개)
  Future<List<String>> suggestAlbums(
    List<PhotoItem> db, {
    Map<int, String> addr = const {},
  }) async {
    final data = await _post('/api/suggest', {'db': aiDb(db, addr)});
    return ((data['suggestions'] as List?) ?? const [])
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
