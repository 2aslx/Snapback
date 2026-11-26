// 월간 리캡 계산 단위 테스트
import 'package:flutter_test/flutter_test.dart';
import 'package:snapback_app/models/photo_item.dart';
import 'package:snapback_app/services/recap.dart';

PhotoItem p(int id, String date, {String place = '', List<String> food = const [], List<String> kw = const [], String time = ''}) =>
    PhotoItem(id: id, date: date, place: place, food: food, searchKeywords: kw, time: time);

void main() {
  test('neighborhoodOf: 주소에서 동네 이름', () {
    expect(neighborhoodOf('서울특별시 마포구 서교동'), '서교동');
    expect(neighborhoodOf('서울특별시 성동구 성수2가3동'), '성수2가3동');
    expect(neighborhoodOf(null), isNull);
    expect(neighborhoodOf(''), isNull);
  });

  test('가장 최근 달: 자주 간 동네·음식·분위기, 자동 앨범 후보', () {
    final photos = [
      p(1, '2026-10-30', food: ['라멘']), // 지난달 → 제외
      p(2, '2026-11-01', place: '카페', food: ['케이크'], kw: ['감성', '디저트'], time: '저녁'),
      p(3, '2026-11-03', place: '카페', food: ['케이크', '라떼'], kw: ['감성'], time: '저녁'),
      p(4, '2026-11-05', place: '식당', food: ['파스타'], kw: ['데이트']),
      p(5, '2026-11-09', place: '공원', kw: ['산책', '사진']), // '사진'은 너무 일반적
    ];
    final r = buildMonthlyRecap(photos, addr: {2: '서울특별시 마포구 서교동', 3: '서울특별시 마포구 서교동', 4: '서울특별시 마포구 연남동'})!;
    expect((r.year, r.month), (2026, 11));
    expect(r.photoIds, [2, 3, 4, 5]);
    expect(r.places.first, ('서교동', 2));
    expect(r.places.map((e) => e.$1), containsAll(['연남동', '공원']), reason: '주소가 없으면 장소 유형');
    expect(r.foods.first, ('케이크', 2));
    expect(r.moods.map((e) => e.$1), containsAll(['감성', '저녁']), reason: '두 번 이상 나온 분위기만');
    expect(r.moods.map((e) => e.$1), isNot(contains('사진')));
    expect(r.placePhotoIds, [2, 3]);
    expect(r.foodPhotoIds, [2, 3]);
    expect(r.coverId, 3);
  });

  test('특정 달 지정, 사진이 너무 적으면 null', () {
    final photos = [for (var i = 0; i < 3; i++) p(i, '2026-10-0${i + 1}'), p(9, '2026-11-01')];
    expect(buildMonthlyRecap(photos), isNull, reason: '최근 달(11월)은 1장뿐');
    expect(buildMonthlyRecap(photos, year: 2026, month: 10)!.photoIds.length, 3);
    expect(buildMonthlyRecap(const []), isNull);
  });
}
