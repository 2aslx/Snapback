// 하이브리드 검색 1차 선별 (기기 안에서, AI 호출 없이)
// 사진이 많을 때(80장 초과) 검색어 임베딩과 사진 임베딩의 코사인 유사도 + 키워드·주소·찾은 기억·날짜 보너스로
// 상위 후보만 골라 LLM(/api/search, /api/album)에 보낸다. "디저트" ↔ "마카롱"처럼 글자가 안 겹쳐도
// 임베딩으로 잡히고, 아직 임베딩이 없는 사진은 키워드 점수와 최신순으로 함께 넣어 누락을 막는다.
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/photo_item.dart';

/// 사진이 이 수 이하면 1차 선별 없이 전체를 LLM 에 보낸다 (빠르고 누락 없음)
const kHybridThreshold = 80;

/// 1차 선별로 LLM 에 보내는 사진 수
const kHybridLimit = 90;

/// 임베딩이 아직 없는 사진 중 최신 사진을 이만큼 더 넣는다 (누락 방지)
const kHybridRecentExtra = 10;

/// 제외 조건("~빼고")이 있는 앨범 요청은 넉넉히 (실제 제외 판정은 서버·LLM 이 한다)
const kHybridLimitWide = 300;

const kEmbeddingDim = 256;

/// 코사인 유사도 (-1~1). 길이가 다르거나 0 벡터면 0.
double cosine(Float32List a, Float32List b) {
  if (a.length != b.length || a.isEmpty) return 0;
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// 서버 응답의 숫자 배열 → 256차원 벡터 (형식이 다르면 null)
Float32List? toVector(Object? v) {
  if (v is! List || v.length != kEmbeddingDim) return null;
  final out = Float32List(kEmbeddingDim);
  for (var i = 0; i < kEmbeddingDim; i++) {
    final x = v[i];
    if (x is! num) return null;
    out[i] = x.toDouble();
  }
  return out;
}

/// 사진 1장을 임베딩할 검색용 텍스트 (분석 텍스트 + 시·구·동 주소 + 확정된 찾은 기억 키워드)
String embedTextFor(PhotoItem d, {String? addr}) => [
  d.caption,
  d.mainTopic,
  d.contentSummary,
  d.place,
  ...d.food,
  d.background,
  d.weather,
  d.time,
  ...d.searchKeywords,
  ...d.semanticCategory,
  structuredSearchText(d.structuredData),
  ?addr,
  ...d.recallKeywords,
].where((x) => x.trim().isNotEmpty && x != '알 수 없음').join(' · ');

const _josa =
    r'(에서|에게|으로|이랑|하고|까지|부터|처럼|이나|에|로|을|를|이|가|은|는|와|과|랑|의|도|만)$';
const _stopWords = {
  '그', '날', '때', '것', '거', '좀', '사진', '그때', '그날', '있던', '했던', '먹은',
  '찍은', '같은', '모아줘', '보여줘', '찾아줘', '빼고',
};

/// 검색어 낱말 (조사를 뗀 형태도 함께, 일반 낱말 제외)
List<String> queryWords(String q) {
  final out = <String>{};
  final josa = RegExp(_josa);
  for (final w in q.toLowerCase().split(RegExp(r'''[\s,.!?~"'()/:·→]+'''))) {
    for (final v in [w, w.replaceAll(josa, '')]) {
      final hangul1 = RegExp(r'^[가-힣]$').hasMatch(v);
      if (v.isNotEmpty && !_stopWords.contains(v) && (v.length >= 2 || hangul1)) {
        out.add(v);
      }
    }
  }
  return out.toList();
}

String _searchText(PhotoItem d, String? addr) => [
  d.caption,
  d.mainTopic,
  d.contentSummary,
  d.place,
  ...d.food,
  d.background,
  d.weather,
  d.time,
  d.people,
  ...d.searchKeywords,
  ...d.semanticCategory,
  structuredSearchText(d.structuredData),
  d.extractedText,
  ?addr,
  ...d.recallKeywords,
].join(' ').toLowerCase();

const _seasons = {
  '봄': [3, 4, 5],
  '여름': [6, 7, 8],
  '가을': [9, 10, 11],
  '겨울': [12, 1, 2],
};

/// 검색어에 연도·월·계절이 있으면 촬영 날짜가 맞는 사진에 보너스
double dateBonus(String query, String date, {DateTime? now}) {
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(date);
  if (m == null) return 0;
  final year = int.parse(m.group(1)!), month = int.parse(m.group(2)!);
  final today = now ?? DateTime.now();
  var bonus = 0.0;
  final years = <int>{
    for (final y in RegExp(r'(20\d{2})').allMatches(query)) int.parse(y.group(1)!),
    if (query.contains('작년')) today.year - 1,
    if (query.contains('재작년')) today.year - 2,
    if (query.contains('올해') || query.contains('올여름') || query.contains('올봄') ||
        query.contains('올가을') || query.contains('올겨울'))
      today.year,
  };
  if (years.contains(year)) bonus += 0.15;
  final months = {
    for (final x in RegExp(r'(\d{1,2})\s*월').allMatches(query)) int.parse(x.group(1)!),
  };
  if (months.contains(month)) bonus += 0.1;
  for (final e in _seasons.entries) {
    if (query.contains(e.key) && e.value.contains(month)) {
      bonus += 0.08;
      break;
    }
  }
  return bonus;
}

/// 사진 1장의 1차 선별 점수와 키워드 보너스
({double score, double keyword}) hybridScore(
  PhotoItem d, {
  required List<String> words,
  required String query,
  Float32List? queryVec,
  Float32List? photoVec,
  String? addr,
  DateTime? now,
}) {
  final text = _searchText(d, addr);
  final hits = words.where(text.contains).length;
  final keyword = math.min(0.3, 0.08 * hits);
  final q = query.toLowerCase();
  final rk = d.recallKeywords.where((k) => q.contains(k.toLowerCase())).length;
  final recall = math.min(0.2, 0.1 * rk);
  final sim = queryVec != null && photoVec != null
      ? math.max(0.0, cosine(queryVec, photoVec))
      : 0.0;
  return (
    score: sim + keyword + recall + dateBonus(query, d.date, now: now),
    keyword: keyword + recall,
  );
}

/// 1차 선별: 상위 [limit]장 + (임베딩 없는 사진 중) 키워드가 맞는 사진과 최신 사진 [recentExtra]장.
/// [queryVec] 이 null 이면(검색어 임베딩 실패) 키워드·날짜 점수만으로 고른다.
/// 사진이 [kHybridThreshold] 이하이면 전부 돌려준다. 결과는 점수 높은 순 id.
List<int> hybridSelect({
  required List<PhotoItem> photos,
  required String query,
  Float32List? queryVec,
  required Float32List? Function(int id) vectorOf,
  Map<int, String> addr = const {},
  int limit = kHybridLimit,
  int recentExtra = kHybridRecentExtra,
  DateTime? now,
}) {
  if (photos.length <= kHybridThreshold) return [for (final d in photos) d.id];
  final words = queryWords(query);
  final scored = [
    for (final d in photos)
      (
        d: d,
        hasVec: vectorOf(d.id) != null,
        s: hybridScore(
          d,
          words: words,
          query: query,
          queryVec: queryVec,
          photoVec: vectorOf(d.id),
          addr: addr[d.id],
          now: now,
        ),
      ),
  ];
  int newer(PhotoItem a, PhotoItem b) {
    final c = b.date.compareTo(a.date);
    return c != 0 ? c : b.id.compareTo(a.id);
  }

  scored.sort((a, b) {
    final c = b.s.score.compareTo(a.s.score);
    return c != 0 ? c : newer(a.d, b.d);
  });
  final out = <int>[for (final x in scored.take(limit)) x.d.id];
  final picked = out.toSet();
  // 임베딩이 없는 사진(아직 채우는 중)은 유사도 점수가 0이라 밀리기 쉬움 → 키워드가 맞는 사진과 최신 사진을 더 넣는다
  final noVec = [
    for (final x in scored)
      if (queryVec == null || !x.hasVec) x,
  ];
  if (queryVec != null) {
    for (final x in noVec.where((x) => x.s.keyword > 0).take(limit ~/ 3)) {
      if (picked.add(x.d.id)) out.add(x.d.id);
    }
  }
  final recent = [...noVec]..sort((a, b) => newer(a.d, b.d));
  var added = 0;
  for (final x in recent) {
    if (added >= recentExtra) break;
    if (picked.add(x.d.id)) {
      out.add(x.d.id);
      added++;
    }
  }
  return out;
}

/// "~빼고 / 제외" 같은 제외 조건이 있는 요청인지 (있으면 앨범 1차 선별을 넉넉히)
bool hasExcludeCondition(String request) =>
    RegExp(r'빼고|제외|말고|없는|빼줘|뺀').hasMatch(request);
