// 데이터 모델 단위 테스트: 예전(v1) 데이터 호환, 저장·복원, AI 로 보내는 필드, 찾은 기억 키워드, 앨범 잠금
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapback_app/models/photo_album.dart';
import 'package:snapback_app/models/photo_item.dart';
import 'package:snapback_app/services/snapback_api.dart';

/// 분석 v1 시절에 저장된 사진 (분석 v2 필드가 전혀 없음)
const legacyV1 = {
  'id': 12,
  'date': '2024-05-01',
  'place': '카페',
  'food': '케이크', // v1 은 문자열 하나로 저장한 경우도 있었음
  'people': '2명',
  'background': '창가',
  'weather': '비',
  'time': '저녁',
  'caption': '창가에서 먹은 케이크',
  'e': '🍰',
  'gps': [37.5, 127.0],
  'exif': true,
  'asset': 'ABC-123',
};

Map<String, dynamic> v2Analysis() => {
  'analysis_version': 2,
  'image_type': 'receipt',
  'source_platform': '',
  'semantic_category': ['정보', '영수증'],
  'main_topic': '카페 영수증',
  'content_summary': '라떼와 케이크 결제 내역',
  'extracted_text': '라떼 5,000원 ' * 30, // 길게
  'structured_data': {
    '항목': [
      {'이름': '라떼', '가격': '5,000원'},
    ],
  },
  'inferred_purpose': '지출 기록',
  'search_keywords': ['영수증', '카페'],
  'suggested_record_type': 'document',
  'caption': '카페 영수증',
  'food': <String>[],
  'place': '',
  'people': '',
  'background': '흰 종이',
  'weather': '',
  'time': '',
};

void main() {
  group('PhotoItem 예전 데이터(v1) 호환', () {
    test('v1 JSON 을 그대로 읽고, v2 필드는 빈 기본값', () {
      final p = PhotoItem.fromJson(legacyV1);
      expect(p.id, 12);
      expect(p.analysisVersion, 1);
      expect(p.food, ['케이크']);
      expect(p.gps, [37.5, 127.0]);
      expect(p.assetId, 'ABC-123');
      expect(p.imageType, '');
      expect(p.searchKeywords, isEmpty);
      expect(p.structuredData, isEmpty);
      expect(p.recallKeywords, isEmpty);
      expect(p.isInfoImage, false);
    });

    test('v1 → 다시 분석(v2): 설명만 바뀌고 id·날짜·위치·원본 연결·찾은 기억은 유지', () {
      final v1 = PhotoItem.fromJson(legacyV1).withRecall(['친구'], '친구랑 간 카페');
      final v2 = v1.withAnalysis(v2Analysis());
      expect(v2.analysisVersion, 2);
      expect(v2.imageType, 'receipt');
      expect(v2.isInfoImage, true);
      expect(v2.caption, '카페 영수증');
      expect(v2.id, 12);
      expect(v2.date, '2024-05-01');
      expect(v2.gps, [37.5, 127.0]);
      expect(v2.assetId, 'ABC-123');
      expect(v2.emoji, '🍰');
      expect(v2.recallPending, ['친구']);
      expect(v2.recallPhrase, '친구랑 간 카페');
      expect(v2.structuredData['항목'], isNotEmpty);
    });

    test('너무 큰 구조화 정보는 기기에 저장하지 않음', () {
      final big = v2Analysis()
        ..['structured_data'] = {'목록': List.generate(200, (i) => '항목 $i 아주 긴 설명')};
      expect(PhotoItem.fromJson(legacyV1).withAnalysis(big).structuredData, isEmpty);
    });
  });

  group('PhotoItem 저장·복원과 AI 로 보내는 필드', () {
    final p = PhotoItem.fromJson(legacyV1).withAnalysis(v2Analysis());

    test('기기 저장 JSON 으로 왕복하면 같은 내용', () {
      final back = PhotoItem.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(jsonEncode(back.toJson()), jsonEncode(p.toJson()));
    });

    test('AI 요청용(includeThumb:false)은 기기 전용 필드를 빼고 글자를 자름', () {
      final ai = p.toJson(includeThumb: false);
      for (final k in ['thumb', 'asset', 'aw', 'ah', 'pv', 'ts', 'purpose', 'rec', 'data', 'rp']) {
        expect(ai.containsKey(k), false, reason: '$k 는 AI 로 보내지 않음');
      }
      // 글자는 잘라서 보냄 (서버 slimPhoto 도 240자로 자름)
      expect((ai['text'] as String).length, lessThan(p.extractedText.length));
      expect((ai['text'] as String).length, lessThanOrEqualTo(240));
      expect(ai['kw'], ['영수증', '카페']);
    });

    test('aiDb: 좌표는 빼고 시·구·동 주소를 붙임', () {
      final db = SnapbackApi.aiDb([p], {12: '서울특별시 마포구 서교동'});
      expect(db.single.containsKey('gps'), false);
      expect(db.single['addr'], '서울특별시 마포구 서교동');
    });

    test('aiDb: 너무 많으면 최근 사진부터 정해진 수만', () {
      final many = [
        for (var i = 0; i < SnapbackApi.maxPhotos + 5; i++)
          PhotoItem(id: i, date: '2020-01-01', place: ''),
        PhotoItem(id: 99999, date: '2026-01-01', place: ''),
      ];
      final db = SnapbackApi.aiDb(many, const {});
      expect(db.length, SnapbackApi.maxPhotos);
      expect(db.first['id'], 99999);
    });
  });

  group('찾은 기억 키워드 (두 번 확인되면 확정)', () {
    test('처음은 대기, 다른 검색에서 또 나오면 확정, 같은 문장 반복은 확정 아님', () {
      var p = PhotoItem(id: 1, date: '2026-01-01', place: '카페');
      p = p.withRecall(['엄마', '모임'], '엄마랑 간 카페');
      expect(p.recallKeywords, isEmpty);
      expect(p.recallPending.toSet(), {'엄마', '모임'});
      expect(p.toJson(includeThumb: false).containsKey('rp'), false);

      p = p.withRecall(['엄마'], '엄마랑  간 카페'); // 같은 문장 (띄어쓰기만 다름)
      expect(p.recallKeywords, isEmpty);

      p = p.withRecall(['친구', '모임'], '친구랑 모임 했던 날');
      expect(p.recallKeywords, ['모임']);
      expect(p.recallPending.toSet(), containsAll(['엄마', '친구']));
      expect(p.toJson(includeThumb: false)['rk'], ['모임']);
      expect(p.recallPhrase, '친구랑 모임 했던 날');
    });

    test('확정 최대 12개, 대기 최대 20개', () {
      var p = PhotoItem(id: 1, date: '', place: '');
      p = p.withRecall([for (var i = 0; i < 30; i++) 'k$i'], 'a');
      expect(p.recallPending.length, 20);
      p = p.withRecall([for (var i = 0; i < 20; i++) 'k$i'], 'b');
      expect(p.recallKeywords.length, lessThanOrEqualTo(12));
    });
  });

  group('검색 응답', () {
    test('SearchResponse 왕복, pool 이 없으면 순위 id 로 대신', () {
      final r = SearchResponse.fromJson({
        'ranked': [
          {'id': 3, 'score': 90, 'matched': ['카페'], 'missing': <String>[]},
        ],
        'question': {'text': '날씨는?', 'options': ['비', '맑음']},
      });
      expect(r.pool, [3]);
      expect(r.question!.options, ['비', '맑음']);
      final back = SearchResponse.fromJson(jsonDecode(jsonEncode(r.toJson())));
      expect(back.ranked.single.score, 90);
      expect(back.question!.text, '날씨는?');
    });

    test('보기가 없는 질문은 질문으로 보지 않음', () {
      final r = SearchResponse.fromJson({
        'ranked': <Object>[],
        'question': {'text': '?', 'options': <String>[]},
      });
      expect(r.question, isNull);
    });

    test('searchKey: 같은 입력이면 같고, 사진·대화가 바뀌면 다름', () {
      final a = [PhotoItem(id: 1, date: '2026-01-01', place: '카페')];
      final k1 = SnapbackApi.searchKey(a, ['카페']);
      expect(SnapbackApi.searchKey(a, ['카페']), k1);
      expect(SnapbackApi.searchKey(a, ['카페', 'Q: x / A: y']), isNot(k1));
      expect(SnapbackApi.searchKey([...a, PhotoItem(id: 2, date: '', place: '')], ['카페']), isNot(k1));
      expect(SnapbackApi.searchKey(a, ['카페'], wantQuestion: true), isNot(k1));
    });
  });

  group('PhotoAlbum 잠금', () {
    test('잠금 정보 왕복, 비밀번호 자체는 저장하지 않음', () {
      final a = PhotoAlbum(id: 1, title: '비밀', emoji: '🗂️', photoIds: [1, 2], createdAtMs: 0)
        ..lockSalt = 'abcd'
        ..lockHash = 'hash';
      final back = PhotoAlbum.fromJson(jsonDecode(jsonEncode(a.toJson())));
      expect(back.locked, true);
      expect(back.photoIds, [1, 2]);
      final open = PhotoAlbum.fromJson({'id': 2, 'title': 't', 'photoIds': <int>[], 'createdAtMs': 0});
      expect(open.locked, false);
      expect(open.toJson().containsKey('lockHash'), false);
    });
  });
}
