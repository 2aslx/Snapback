// 하이브리드 검색 1차 선별 · 사진 임베딩 저장소 단위 테스트
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapback_app/models/photo_item.dart';
import 'package:snapback_app/services/embedding_store.dart';
import 'package:snapback_app/services/hybrid_search.dart';

/// 축 [axis] 방향 단위 벡터 + 약간의 [mix] 방향 성분
Float32List vec(int axis, {int? mix, double w = 0}) {
  final v = Float32List(kEmbeddingDim);
  v[axis] = 1;
  if (mix != null) v[mix] = w;
  return v;
}

PhotoItem photo(int id, {String caption = '', String date = '2025-01-01', List<String> kw = const [], List<String> rk = const []}) =>
    PhotoItem(id: id, date: date, place: '', caption: caption, searchKeywords: kw, recallKeywords: rk);

void main() {
  group('cosine', () {
    test('같은 방향 1, 직교 0, 반대 -1, 0 벡터·길이 다름은 0', () {
      expect(cosine(vec(0), vec(0)), closeTo(1, 1e-6));
      expect(cosine(vec(0), vec(1)), closeTo(0, 1e-6));
      final neg = Float32List(kEmbeddingDim)..[0] = -1;
      expect(cosine(vec(0), neg), closeTo(-1, 1e-6));
      expect(cosine(vec(0), Float32List(kEmbeddingDim)), 0);
      expect(cosine(vec(0), Float32List(3)), 0);
    });

    test('크기와 상관없이 방향만 봄', () {
      final a = Float32List.fromList([for (var i = 0; i < kEmbeddingDim; i++) math.sin(i.toDouble())]);
      final b = Float32List.fromList([for (final x in a) x * 7]);
      expect(cosine(a, b), closeTo(1, 1e-5));
    });

    test('toVector: 256개 숫자만 벡터로', () {
      expect(toVector(List.filled(256, 0.5))!.length, 256);
      expect(toVector(List.filled(10, 0.5)), isNull);
      expect(toVector([...List.filled(255, 0.1), 'x']), isNull);
      expect(toVector(null), isNull);
    });
  });

  group('검색어 낱말·날짜 보너스', () {
    test('queryWords: 조사를 뗀 형태도, 일반 낱말은 빼고', () {
      final w = queryWords('카페에서 먹은 케이크 사진');
      expect(w, containsAll(['카페', '케이크']));
      expect(w, isNot(contains('먹은')));
      expect(w, isNot(contains('사진')));
    });

    test('dateBonus: 연도·작년·월·계절', () {
      final now = DateTime(2026, 11, 1);
      expect(dateBonus('2024년 사진', '2024-05-01', now: now), greaterThan(0));
      expect(dateBonus('2024년 사진', '2025-05-01', now: now), 0);
      expect(dateBonus('작년 바다', '2025-08-01', now: now), greaterThan(0));
      expect(dateBonus('3월에 찍은', '2025-03-10', now: now), greaterThan(0));
      expect(dateBonus('여름 바다', '2023-07-10', now: now), greaterThan(0));
      expect(dateBonus('여름 바다', '2023-12-10', now: now), 0);
      expect(dateBonus('카페', '2023-12-10', now: now), 0);
    });
  });

  group('hybridSelect', () {
    test('사진이 80장 이하면 전부', () {
      final photos = [for (var i = 0; i < kHybridThreshold; i++) photo(i)];
      expect(hybridSelect(photos: photos, query: '카페', vectorOf: (_) => null).length, kHybridThreshold);
    });

    test('동의어: 글자가 안 겹쳐도 임베딩이 가까우면 뽑힘 ("디저트" ↔ "마카롱")', () {
      // 관련 없는 사진 300장은 각자 다른 축, 마카롱 사진은 검색어(축 0)와 거의 같은 방향
      final photos = [
        for (var i = 1; i <= 300; i++) photo(i, caption: '공원 산책 $i'),
        photo(999, caption: '분홍 마카롱 세 개', date: '2019-01-01'),
      ];
      final vectors = {for (var i = 1; i <= 300; i++) i: vec(1 + i % 200), 999: vec(0, mix: 5, w: 0.2)};
      final ids = hybridSelect(photos: photos, query: '디저트', queryVec: vec(0), vectorOf: (id) => vectors[id]);
      expect(ids.first, 999);
      expect(ids.length, lessThanOrEqualTo(kHybridLimit + kHybridRecentExtra));
    });

    test('임베딩 없는 사진: 키워드가 맞는 사진과 최신 사진은 함께 넣어 누락 방지', () {
      final photos = [
        for (var i = 1; i <= 200; i++) photo(i, caption: '공원', date: '2024-01-01'),
        photo(501, caption: '마카롱 디저트', date: '2020-01-01'), // 임베딩 없음 + 키워드 맞음
        photo(502, caption: '거리', date: '2026-10-01'), // 임베딩 없음 + 가장 최신
        photo(503, caption: '거리', date: '2018-01-01'), // 임베딩 없음 + 오래되고 안 맞음
      ];
      // 공원 사진 200장은 모두 검색어와 어느 정도 가까움 → 상위 90장을 다 차지
      final vectors = {for (var i = 1; i <= 200; i++) i: vec(0, mix: 1 + i % 50, w: 0.5)};
      final ids = hybridSelect(photos: photos, query: '디저트', queryVec: vec(0), vectorOf: (id) => vectors[id]);
      expect(ids, contains(501));
      expect(ids, contains(502));
      expect(ids.where((id) => id <= 200).length, kHybridLimit - 0, reason: '상위 90장은 유사도 순');
    });

    test('검색어 임베딩 실패(null): 키워드·주소·찾은 기억·날짜 점수로 고름', () {
      final photos = [
        for (var i = 1; i <= 150; i++) photo(i, caption: '공원'),
        photo(301, caption: '거리', rk: ['생일']), // 확정된 찾은 기억 키워드
        photo(302, caption: '카페 케이크'),
        photo(303, caption: '식당'), // 주소로 맞음
      ];
      final ids = hybridSelect(
        photos: photos,
        query: '연남동 카페 생일',
        vectorOf: (_) => null,
        addr: {303: '서울특별시 마포구 연남동'},
      );
      expect(ids.take(3), containsAll([301, 302, 303]));
      expect(ids.length, lessThanOrEqualTo(kHybridLimit + kHybridRecentExtra));
    });

    test('제외 조건 감지', () {
      expect(hasExcludeCondition('홍대 사진 중 음식은 빼고'), true);
      expect(hasExcludeCondition('사람 없는 풍경'), true);
      expect(hasExcludeCondition('신촌에서 먹은 음식'), false);
    });

    test('embedTextFor: 분석 텍스트 + 구조화 정보 + 주소 + 확정 키워드, "알 수 없음" 은 제외', () {
      final d = PhotoItem(
        id: 1,
        date: '2025-01-01',
        place: '카페',
        caption: '라떼',
        weather: '알 수 없음',
        structuredData: const {'메뉴': ['바닐라 라떼']},
        recallKeywords: const ['생일'],
      );
      final t = embedTextFor(d, addr: '서울특별시 마포구 연남동');
      for (final w in ['라떼', '카페', '바닐라 라떼', '연남동', '생일']) {
        expect(t, contains(w));
      }
      expect(t, isNot(contains('알 수 없음')));
    });
  });

  group('EmbeddingStore (파일)', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('snapback_embed_test');
      EmbeddingStore.debugDirectory = dir;
      EmbeddingStore.debugReset();
    });
    tearDown(() async {
      EmbeddingStore.debugReset();
      EmbeddingStore.debugDirectory = null;
      await dir.delete(recursive: true);
    });

    test('저장 → 파일에 쓰고 → 다시 읽으면 같은 벡터, 삭제·초기화', () async {
      await EmbeddingStore.load();
      await EmbeddingStore.putAll({1: vec(3), 2: vec(4, mix: 7, w: 0.25)});
      await EmbeddingStore.put(3, Float32List(5)); // 차원이 다르면 무시
      await EmbeddingStore.flush();
      final file = File('${dir.path}/embeddings.bin');
      expect(await file.length(), 2 * (4 + 256 * 4), reason: '장당 약 1KB');

      EmbeddingStore.debugReset();
      expect(EmbeddingStore.count, 0);
      await EmbeddingStore.load();
      expect(EmbeddingStore.count, 2);
      expect(EmbeddingStore.get(2)![7], closeTo(0.25, 1e-6));
      expect(EmbeddingStore.has(3), false);

      await EmbeddingStore.remove([1]);
      await EmbeddingStore.flush();
      EmbeddingStore.debugReset();
      await EmbeddingStore.load();
      expect(EmbeddingStore.has(1), false);
      expect(EmbeddingStore.has(2), true);

      await EmbeddingStore.clear();
      expect(EmbeddingStore.count, 0);
      expect(await file.exists(), false);
    });
  });
}
