import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/photo_item.dart';

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
  SearchResponse({required this.ranked, this.question});
  final List<SearchRankedItem> ranked;
  final SearchQuestion? question;
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
      final code = data['error']?.toString() ??
          (res.statusCode == 429 ? 'rate_limited' : 'http_${res.statusCode}');
      throw ApiException(code);
    }
    return data;
  }

  Future<Map<String, dynamic>> analyzeImage(String imageDataUrl) {
    return _post('/api/analyze', {'image': imageDataUrl});
  }

  Future<SearchResponse> searchMemory(
    List<PhotoItem> db,
    List<String> hist,
  ) async {
    final data = await _post('/api/search', {
      'db': db.map((d) => d.toJson(includeThumb: false)).toList(),
      'hist': hist,
    });
    final ranked = (data['ranked'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SearchRankedItem.fromJson)
        .toList();
    final qRaw = data['question'];
    final question = qRaw is Map<String, dynamic> &&
            (qRaw['options'] as List?)?.isNotEmpty == true
        ? SearchQuestion.fromJson(qRaw)
        : null;
    return SearchResponse(ranked: ranked, question: question);
  }
}
