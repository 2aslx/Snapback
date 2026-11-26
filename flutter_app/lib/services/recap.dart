// 월간 리캡: 분석된 라이프로깅 데이터(장소·음식·분위기·취향)를 한 달 단위로 모아
// "이번 달 가장 자주 간 동네·음식·분위기" 요약과 자동 앨범 후보를 만든다. AI 호출 없이 기기 안에서 계산.
import '../models/photo_item.dart';

/// (이름, 장수)
typedef Count = (String, int);

class MonthlyRecap {
  const MonthlyRecap({
    required this.year,
    required this.month,
    required this.photoIds,
    required this.places,
    required this.foods,
    required this.moods,
    required this.coverId,
    required this.placePhotoIds,
    required this.foodPhotoIds,
  });

  final int year;
  final int month;

  /// 그 달 사진 (오래된 순)
  final List<int> photoIds;

  /// 자주 간 동네(주소가 없으면 장소 유형) · 자주 먹은 음식 · 많이 찍은 분위기·취향 키워드 — 많은 순 최대 3개
  final List<Count> places;
  final List<Count> foods;
  final List<Count> moods;

  /// 대표 사진 (가장 자주 간 곳·먹은 음식이 담긴 사진, 없으면 그 달 마지막 사진)
  final int coverId;

  /// 가장 자주 간 곳 / 가장 자주 먹은 음식이 담긴 사진 (자동 앨범용)
  final List<int> placePhotoIds;
  final List<int> foodPhotoIds;

  String get label => '$month월';
}

/// 주소에서 동네 이름 (예: "서울특별시 마포구 서교동" → "서교동")
String? neighborhoodOf(String? addr) {
  if (addr == null || addr.trim().isEmpty) return null;
  final parts = addr.trim().split(RegExp(r'\s+'));
  for (final p in parts.reversed) {
    if (RegExp(r'(동|읍|면|가)$').hasMatch(p) || RegExp(r'\d*가\d*동$').hasMatch(p)) return p;
  }
  return parts.last;
}

const _genericMoods = {
  '사진', '일상', '기록', '이미지', '풍경', '정보', '음식', '스크린샷', '문서', '기타', '알 수 없음',
};

/// 사진이 있는 가장 최근 달(또는 [year]·[month])의 리캡. 그 달 사진이 [minPhotos] 장보다 적으면 null.
MonthlyRecap? buildMonthlyRecap(
  List<PhotoItem> photos, {
  Map<int, String> addr = const {},
  int? year,
  int? month,
  int minPhotos = 3,
}) {
  final dated = [
    for (final d in photos)
      if (RegExp(r'^\d{4}-\d{2}').hasMatch(d.date)) d,
  ];
  if (dated.isEmpty) return null;
  final key = year != null && month != null
      ? '$year-${month.toString().padLeft(2, '0')}'
      : dated.map((d) => d.date.substring(0, 7)).reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
  final inMonth = dated.where((d) => d.date.startsWith(key)).toList()
    ..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  if (inMonth.length < minPhotos) return null;

  final placeOf = <int, String>{};
  final placeCount = <String, int>{};
  final foodCount = <String, int>{};
  final moodCount = <String, int>{};
  for (final d in inMonth) {
    final p = neighborhoodOf(addr[d.id]) ??
        (d.place.trim().isNotEmpty && d.place != '알 수 없음' ? d.place.trim() : null);
    if (p != null) {
      placeOf[d.id] = p;
      placeCount[p] = (placeCount[p] ?? 0) + 1;
    }
    for (final f in d.food.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()) {
      foodCount[f] = (foodCount[f] ?? 0) + 1;
    }
    final foods = d.food.toSet();
    for (final m in {
      ...d.searchKeywords,
      ...d.semanticCategory.skip(1), // 상위 카테고리(정보·일상 등)는 너무 넓음
      if (d.time.isNotEmpty && d.time != '알 수 없음') d.time,
      if (d.weather.isNotEmpty && d.weather != '알 수 없음') d.weather,
    }.map((e) => e.trim())) {
      if (m.isEmpty || _genericMoods.contains(m) || foods.contains(m) || m == p) continue;
      moodCount[m] = (moodCount[m] ?? 0) + 1;
    }
  }
  List<Count> top(Map<String, int> m, {int min = 1}) {
    final list = m.entries.where((e) => e.value >= min).map((e) => (e.key, e.value)).toList()
      ..sort((a, b) {
        final c = b.$2.compareTo(a.$2);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return list.take(3).toList();
  }

  final places = top(placeCount);
  final foods = top(foodCount);
  final moods = top(moodCount, min: 2);
  final topPlace = places.isNotEmpty ? places.first.$1 : null;
  final topFood = foods.isNotEmpty ? foods.first.$1 : null;
  final placeIds = [
    for (final d in inMonth)
      if (topPlace != null && placeOf[d.id] == topPlace) d.id,
  ];
  final foodIds = [
    for (final d in inMonth)
      if (topFood != null && d.food.contains(topFood)) d.id,
  ];
  final cover = foodIds.isNotEmpty
      ? foodIds.last
      : (placeIds.isNotEmpty ? placeIds.last : inMonth.last.id);
  return MonthlyRecap(
    year: int.parse(key.substring(0, 4)),
    month: int.parse(key.substring(5, 7)),
    photoIds: [for (final d in inMonth) d.id],
    places: places,
    foods: foods,
    moods: moods,
    coverId: cover,
    placePhotoIds: placeIds,
    foodPhotoIds: foodIds,
  );
}
