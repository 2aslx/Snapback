import 'dart:convert';

class PhotoItem {
  PhotoItem({
    required this.id,
    this.fileKey,
    required this.date,
    required this.place,
    this.food = const [],
    this.people = '',
    this.background = '',
    this.weather = '알 수 없음',
    this.time = '알 수 없음',
    this.caption = '',
    this.emoji = '🖼️',
    this.gps,
    this.exif = false,
    this.thumbDataUrl,
    this.hidden = false,
    this.assetId,
    this.assetW,
    this.assetH,
    this.previewKey,
    this.takenAtMs,
    this.analysisVersion = 1,
    this.imageType = '',
    this.sourcePlatform = '',
    this.semanticCategory = const [],
    this.mainTopic = '',
    this.contentSummary = '',
    this.extractedText = '',
    this.inferredPurpose = '',
    this.searchKeywords = const [],
    this.suggestedRecordType = '',
    this.structuredData = const {},
  });

  final int id;
  final String? fileKey;
  final String date;
  final String place;
  final List<String> food;
  final String people;
  final String background;
  final String weather;
  final String time;
  final String caption;
  final String emoji;

  /// 디자인(index.html)의 라인 아이콘 이름. 데모 사진은 emoji 에 대응, 업로드 사진은 'image'.
  String get icon => const {
        '🍰': 'cake',
        '🥐': 'bread',
        '🍓': 'bowl',
        '🍵': 'cup',
        '🌸': 'flower',
        '🍝': 'bowl',
        '🎄': 'tree',
        '🌅': 'sunset',
        '🧱': 'building',
        '☕': 'cup',
        '🛍️': 'bag',
      }[emoji] ??
      'image';
  final List<double>? gps;
  final bool exif;
  final String? thumbDataUrl;
  bool hidden;

  /// iOS 사진 보관함 원본 ID (PHAsset.localIdentifier) — 화면 표시 때 원본에서 불러옴
  final String? assetId;
  final int? assetW;
  final int? assetH;

  /// 웹: IndexedDB 에 저장한 1080px 미리보기 키
  final String? previewKey;

  /// 촬영 시각 (ms). '그날의 사진' 대표사진(가장 가까운 시각) 계산용. 기존 데이터에는 없을 수 있음.
  final int? takenAtMs;

  // ── 분석 v2 (구버전 데이터는 기본값: analysisVersion 1, 나머지 빈 값) ──
  /// 1 = 기존(캡션·장소·인물 등), 2 = 시각·의미·정보 추출·라이프로깅 분석
  final int analysisVersion;

  /// photo · screenshot · document · shopping_list · recipe · certificate · receipt · health_report …
  final String imageType;

  /// 유튜브 쇼츠, 인스타그램 등 (확인될 때만)
  final String sourcePlatform;
  final List<String> semanticCategory;
  final String mainTopic;
  final String contentSummary;

  /// 핵심 글자 발췌 (기기 저장 최대 600자)
  final String extractedText;

  /// AI 가 추정한 저장 목적 (확정 아님)
  final String inferredPurpose;
  final List<String> searchKeywords;

  /// moment · place · taste · shopping · document · info
  final String suggestedRecordType;

  /// 유형별 구조화 정보 (예: 제품 목록, 시험명·등급, 항목·수치·단위). 기기 저장 최대 약 1.5KB
  final Map<String, dynamic> structuredData;

  /// 글자가 많은 정보성 이미지 (사진 정보 카드를 정보 중심으로 표시)
  bool get isInfoImage => kTextDenseTypes.contains(imageType);

  Map<String, dynamic> toJson({bool includeThumb = true}) => {
        'id': id,
        if (fileKey != null) 'key': fileKey,
        'date': date,
        'place': place,
        'food': food,
        'people': people,
        'background': background,
        'weather': weather,
        'time': time,
        if (caption.isNotEmpty) 'caption': caption,
        'e': emoji,
        if (gps != null) 'gps': gps,
        'exif': exif,
        if (includeThumb && thumbDataUrl != null) 'thumb': thumbDataUrl,
        if (hidden) 'hidden': true,
        // 기기 저장용 필드 (AI 요청에는 보내지 않음)
        if (includeThumb && assetId != null) 'asset': assetId,
        if (includeThumb && assetW != null) 'aw': assetW,
        if (includeThumb && assetH != null) 'ah': assetH,
        if (includeThumb && previewKey != null) 'pv': previewKey,
        if (includeThumb && takenAtMs != null) 'ts': takenAtMs,
        // 분석 v2: 검색·앨범에는 의미 필드(요약된 글자 포함)만, 구조화 정보는 기기에만 저장
        if (analysisVersion > 1) 'v': analysisVersion,
        if (imageType.isNotEmpty) 'type': imageType,
        if (sourcePlatform.isNotEmpty) 'src': sourcePlatform,
        if (semanticCategory.isNotEmpty) 'cat': semanticCategory,
        if (mainTopic.isNotEmpty) 'topic': mainTopic,
        if (contentSummary.isNotEmpty) 'summary': contentSummary,
        if (extractedText.isNotEmpty)
          'text': includeThumb ? extractedText : _cut(extractedText, 150),
        if (searchKeywords.isNotEmpty) 'kw': searchKeywords,
        if (includeThumb && inferredPurpose.isNotEmpty) 'purpose': inferredPurpose,
        if (includeThumb && suggestedRecordType.isNotEmpty) 'rec': suggestedRecordType,
        if (includeThumb && structuredData.isNotEmpty) 'data': structuredData,
      };

  /// AI 분석 결과(서버 /api/analyze 응답)로 설명만 바꾼 사진. id·날짜·위치·원본 연결은 그대로.
  PhotoItem withAnalysis(Map<String, dynamic> ai) {
    String s(String k) => (ai[k] ?? '').toString().trim();
    final data = ai['structured_data'];
    var structured = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    // 기기 저장 용량 보호 (서버도 줄이지만 한 번 더)
    if (jsonEncode(structured).length > 1600) structured = {};
    return PhotoItem(
      id: id,
      fileKey: fileKey,
      date: date,
      place: s('place'),
      food: _strList(ai['food']),
      people: s('people'),
      background: s('background'),
      weather: s('weather'),
      time: s('time'),
      caption: s('caption'),
      emoji: emoji,
      gps: gps,
      exif: exif,
      thumbDataUrl: thumbDataUrl,
      hidden: hidden,
      assetId: assetId,
      assetW: assetW,
      assetH: assetH,
      previewKey: previewKey,
      takenAtMs: takenAtMs,
      analysisVersion: (ai['analysis_version'] as num?)?.toInt() ?? 1,
      imageType: s('image_type'),
      sourcePlatform: s('source_platform'),
      semanticCategory: _strList(ai['semantic_category']),
      mainTopic: s('main_topic'),
      contentSummary: s('content_summary'),
      extractedText: _cut(s('extracted_text'), 600),
      inferredPurpose: s('inferred_purpose'),
      searchKeywords: _strList(ai['search_keywords']),
      suggestedRecordType: s('suggested_record_type'),
      structuredData: structured,
    );
  }

  factory PhotoItem.fromJson(Map<String, dynamic> j) {
    final rawFood = j['food'];
    final foodList = rawFood is List
        ? rawFood.map((e) => e.toString()).toList()
        : (rawFood is String && rawFood.isNotEmpty ? [rawFood] : <String>[]);
    final rawGps = j['gps'];
    List<double>? gpsList;
    if (rawGps is List && rawGps.length >= 2) {
      gpsList = [
        (rawGps[0] as num).toDouble(),
        (rawGps[1] as num).toDouble(),
      ];
    }
    return PhotoItem(
      id: (j['id'] as num).toInt(),
      fileKey: j['key'] as String?,
      date: (j['date'] ?? '').toString(),
      place: (j['place'] ?? '알 수 없음').toString(),
      food: foodList,
      people: (j['people'] ?? '').toString(),
      background: (j['background'] ?? '').toString(),
      weather: (j['weather'] ?? '알 수 없음').toString(),
      time: (j['time'] ?? '알 수 없음').toString(),
      caption: (j['caption'] ?? '').toString(),
      emoji: (j['e'] ?? '🖼️').toString(),
      gps: gpsList,
      exif: j['exif'] == true,
      thumbDataUrl: j['thumb'] as String?,
      hidden: j['hidden'] == true,
      assetId: j['asset'] as String?,
      assetW: (j['aw'] as num?)?.toInt(),
      assetH: (j['ah'] as num?)?.toInt(),
      previewKey: j['pv'] as String?,
      takenAtMs: (j['ts'] as num?)?.toInt(),
      analysisVersion: (j['v'] as num?)?.toInt() ?? 1,
      imageType: (j['type'] ?? '').toString(),
      sourcePlatform: (j['src'] ?? '').toString(),
      semanticCategory: _strList(j['cat']),
      mainTopic: (j['topic'] ?? '').toString(),
      contentSummary: (j['summary'] ?? '').toString(),
      extractedText: (j['text'] ?? '').toString(),
      inferredPurpose: (j['purpose'] ?? '').toString(),
      searchKeywords: _strList(j['kw']),
      suggestedRecordType: (j['rec'] ?? '').toString(),
      structuredData: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : const {},
    );
  }
}

/// 글자가 많은 정보성 이미지 유형 (서버 TEXT_DENSE 와 같음)
const kTextDenseTypes = {
  'screenshot', 'document', 'shopping_list', 'recipe', 'certificate', 'receipt',
  'health_report', 'ticket', 'menu', 'chat', 'note',
};

/// 이미지 유형 한국어 이름
String imageTypeLabel(String t) => const {
      'photo': '사진',
      'screenshot': '스크린샷',
      'document': '문서',
      'shopping_list': '쇼핑 리스트',
      'recipe': '레시피',
      'certificate': '인증서·자격증',
      'receipt': '영수증',
      'health_report': '건강검진표',
      'ticket': '티켓',
      'menu': '메뉴판',
      'chat': '대화 캡처',
      'note': '메모',
      'artwork': '그림·작품',
    }[t] ??
    (t.isEmpty ? '' : t);

/// structured_data 의 핵심 항목을 '키: 값' 줄로 (사진 정보 카드 미리보기, 최대 [max]줄)
List<String> structuredPreview(Map<String, dynamic> m, {int max = 5}) {
  String fmt(Object? v) {
    if (v is List) {
      final items = v.take(3).map((e) {
        if (e is Map) {
          return e.values.where((x) => x is String || x is num).take(2).join(' ');
        }
        return '$e';
      }).where((x) => x.trim().isNotEmpty);
      final more = v.length > 3 ? ' 외 ${v.length - 3}개' : '';
      return items.join(', ') + more;
    }
    if (v is Map) {
      return v.entries.take(3).map((e) => '${e.key} ${fmt(e.value)}').join(', ');
    }
    return v == null ? '' : '$v';
  }

  final out = <String>[];
  for (final e in m.entries) {
    if (out.length >= max) break;
    final t = fmt(e.value).trim();
    if (t.isNotEmpty) out.add('${e.key}: $t');
  }
  return out;
}

List<String> _strList(Object? v) => v is List
    ? v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
    : (v is String && v.trim().isNotEmpty ? [v.trim()] : const <String>[]);

String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

class SearchRankedItem {
  SearchRankedItem({
    required this.id,
    required this.score,
    required this.matched,
    required this.missing,
  });

  final int id;
  final int score;
  final List<String> matched;
  final List<String> missing;

  factory SearchRankedItem.fromJson(Map<String, dynamic> j) => SearchRankedItem(
        id: (j['id'] as num).toInt(),
        score: (j['score'] as num?)?.toInt() ?? 0,
        matched: (j['matched'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        missing: (j['missing'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

class SearchQuestion {
  SearchQuestion({required this.text, required this.options});

  final String text;
  final List<String> options;

  factory SearchQuestion.fromJson(Map<String, dynamic> j) => SearchQuestion(
        text: (j['text'] ?? '').toString(),
        options: (j['options'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

class UsabilityLogEntry {
  UsabilityLogEntry({
    required this.id,
    required this.ms,
    required this.questions,
    required this.firstRank,
    required this.hit,
  });

  final int id;
  final int ms;
  final int questions;
  final int firstRank;
  final bool hit;
}


/// 사진 정보에서 '감지 안 됨'을 뜻하는 조각인지 (예: '알 수 없음', '특정 복장 없음', '인원수 확인 불가', '0명')
bool isUnknownInfo(String x) => RegExp(
      r'(알\s*수\s*없|없음|없다|모름|불명|미상|확인\s*(불가|안\s*됨|되지\s*않)|보이지\s*않|해당\s*없|^0\s*명$|^n/?a$|^unknown|^none$|^null$|^-$)',
      caseSensitive: false,
    ).hasMatch(x.trim());
