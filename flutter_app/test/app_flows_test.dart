// 화면 동작 테스트: 검색 결과 표시·후보·뒤로가기·답할 때 제외, 사진 정렬, 앨범 잠금
// 서버는 부르지 않는다 (검색 결과는 상태에 직접 넣거나, 저장된 검색 결과 캐시로 대신한다).
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snapback_app/main.dart';
import 'package:snapback_app/models/photo_item.dart';
import 'package:snapback_app/screens/main_screens.dart';
import 'package:snapback_app/services/embedding_store.dart';
import 'package:snapback_app/services/snapback_api.dart';
import 'package:snapback_app/state/app_state.dart';
import 'package:snapback_app/widgets/common_widgets.dart';
import 'package:snapback_app/widgets/pin_pad.dart';

SearchRankedItem r(int id, int score) =>
    SearchRankedItem(id: id, score: score, matched: const ['카페'], missing: const []);

List<Map<String, Object>> photos(int n) => [
  for (var i = 12; i < 12 + n; i++)
    {'id': i, 'date': '2026-01-${(i - 11).toString().padLeft(2, '0')}', 'place': '카페$i'},
];

/// 글자 찾기 (한글 단어 단위 줄바꿈 문자 U+2060 은 무시)
Finder txt(String t) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').replaceAll('⁠', '') == t,
);

Future<SnapbackState> startApp(WidgetTester tester, Map<String, Object> prefs) async {
  EmbeddingStore.debugMemoryOnly = true; // 위젯 테스트: 임베딩은 메모리에만
  EmbeddingStore.debugReset(); // 테스트마다 새로 (앞 테스트의 읽기 작업을 이어 쓰지 않음)
  await tester.binding.setSurfaceSize(const Size(400, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({'snapback_onboarded': true, ...prefs});
  await tester.pumpWidget(const SnapbackApp());
  await tester.pump(const Duration(milliseconds: 600));
  return tester.widget<Screen5Home>(find.byType(Screen5Home)).state;
}

List<int> gridIds(WidgetTester tester) => tester
    .widgetList<PhotoGrid>(find.byType(PhotoGrid))
    .expand((g) => g.items.map((d) => d.id))
    .toList();

void main() {
  group('검색 결과', () {
    testWidgets('일치 확률은 표시하지 않고, 60% 이상 후보만 일치도 순으로 바둑판에', (tester) async {
      final s = await startApp(tester, {'snapback_db': jsonEncode(photos(6))});
      s.searchHistory..clear()..add('카페');
      s.searchResults = [r(15, 62), r(12, 92), r(13, 84), r(14, 59), r(16, 70)];
      s.go(13);
      await tester.pump(const Duration(milliseconds: 800));
      expect(txt('카페12 · 2026-01-01'), findsOneWidget); // 1순위 크게
      expect(gridIds(tester), [13, 16, 15]); // 84·70·62, 59 는 숨김
      final shown = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '');
      expect(shown.any((t) => t.contains('%') || t.contains('일치')), false);
    });

    testWidgets('후보를 크게 본 뒤 뒤로가기는 바로 전 사진 → 1순위 → 홈 순서', (tester) async {
      final s = await startApp(tester, {'snapback_db': jsonEncode(photos(4))});
      s.searchHistory..clear()..add('카페');
      s.searchResults = [r(12, 90), r(13, 80), r(14, 70)];
      s.go(13);
      await tester.pump(const Duration(milliseconds: 800));
      Finder tile(int id) => find.descendant(
        of: find.byType(PhotoGrid),
        matching: find.byWidgetPredicate((w) => w is PhotoTile && w.item.id == id),
      );
      Future<void> back() async {
        await tester.tap(
          find.descendant(of: find.byType(SnapbackTopBar), matching: find.byType(Pressable)).first,
        );
        await tester.pump(const Duration(milliseconds: 800));
      }

      await tester.tap(tile(13));
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.pinnedResultId, 13);
      await tester.tap(tile(14));
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.pinnedResultId, 14);
      await back();
      expect((s.screen, s.pinnedResultId), (13, 13));
      await back();
      expect((s.screen, s.pinnedResultId), (13, null));
      await back();
      await tester.pump(const Duration(milliseconds: 800));
      expect(s.screen, 5);
    });

    testWidgets('질문에 답하면 보고 있던 사진을 빼고 남은 후보 안에서 다시 찾음', (tester) async {
      final db = photos(6);
      final hist = ['카페', 'Q: 날씨? / A: 비'];
      // 13 을 뺀 후보(12·14·15)로 보낸 검색의 결과만 미리 저장해 둔다 → 캐시에 맞으면 13 이 빠진 것
      final sent = [for (final j in db) PhotoItem.fromJson(j)].where((d) => [12, 14, 15].contains(d.id)).toList();
      final key = SnapbackApi.searchKey(sent, hist);
      final s = await startApp(tester, {
        'snapback_db': jsonEncode(db),
        'snapback_search_cache': jsonEncode({key: SearchResponse(ranked: [r(14, 90)]).toJson()}),
      });
      s.searchHistory..clear()..add('카페');
      s.searchPool..clear()..addAll([12, 13, 14, 15]);
      s.searchResults = [r(12, 70), r(13, 80), r(14, 65)];
      expect(s.shownResultId, 13);
      s.currentQuestionText = '날씨?';
      s.serverConnected = true;
      await s.answerFollowUp('비');
      expect(s.searchExcluded, {13});
      expect(s.searchError, isNull);
      expect(s.searchResults.map((x) => x.id), [14]);
      s.resetSearch();
      expect(s.searchExcluded, isEmpty);
    });
  });

  group('검색 이전 단계로 되돌리기', () {
    /// 답(비)을 하면 13 을 뺀 후보로 검색 → 캐시에 [ranked] 를 미리 넣어 둔다
    Future<SnapbackState> answered(WidgetTester tester, List<SearchRankedItem> ranked) async {
      final db = photos(6);
      final sent = [for (final j in db) PhotoItem.fromJson(j)].where((d) => [12, 14, 15].contains(d.id)).toList();
      final key = SnapbackApi.searchKey(sent, ['카페', 'Q: 날씨? / A: 비']);
      final s = await startApp(tester, {
        'snapback_db': jsonEncode(db),
        'snapback_search_cache': jsonEncode({key: SearchResponse(ranked: ranked).toJson()}),
      });
      s.searchHistory..clear()..add('카페');
      s.searchPool..clear()..addAll([12, 13, 14, 15]);
      s.searchResults = [r(13, 80), r(12, 70), r(14, 65)];
      s.activeQuestion = SearchQuestion(text: '날씨?', options: const ['비', '맑음']);
      s.currentQuestionText = '날씨?';
      s.questionShown = true;
      s.serverConnected = true;
      s.go(13);
      await tester.pump(const Duration(milliseconds: 800));
      expect(s.canUndoSearch, false);
      await s.answerFollowUp('비');
      await tester.pump(const Duration(milliseconds: 600));
      return s;
    }

    testWidgets('답한 뒤 되돌리기: 직전 질문·후보·제외 상태로 (다시 검색하지 않음)', (tester) async {
      final s = await answered(tester, [r(14, 90)]);
      expect(s.searchResults.map((x) => x.id), [14]);
      expect(s.searchExcluded, {13});
      expect(txt('이전 단계로 되돌리기'), findsOneWidget);
      await tester.tap(txt('이전 단계로 되돌리기'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(s.searchHistory, ['카페']);
      expect(s.searchExcluded, isEmpty);
      expect(s.searchResults.map((x) => x.id), [13, 12, 14]);
      expect(s.activeQuestion?.text, '날씨?');
      expect(s.questionShown, true);
      expect(s.canUndoSearch, false);
      expect(txt('이전 단계로 되돌리기'), findsNothing);
    });

    testWidgets('남은 후보가 0장이어도 되돌리기 버튼으로 이전 후보로', (tester) async {
      final s = await answered(tester, const []);
      expect(s.searchResults, isEmpty);
      expect(find.textContaining('남은 후보 중에 맞는 사진이 없어요'), findsOneWidget);
      await tester.tap(txt('이전 단계로 되돌리기'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(s.searchResults.map((x) => x.id), [13, 12, 14]);
      expect(s.searchExcluded, isEmpty);
    });

    testWidgets('새 검색을 시작하면 되돌리기 기록은 지워짐', (tester) async {
      final s = await answered(tester, [r(14, 90)]);
      expect(s.canUndoSearch, true);
      s.resetSearch();
      expect(s.canUndoSearch, false);
    });
  });

  testWidgets('narrowForAi: 80장 이하면 그대로, 넘으면 1차 선별 (서버 없이 키워드로 폴백)', (tester) async {
    final db = [
      for (var i = 12; i < 132; i++) {'id': i, 'date': '2025-01-01', 'place': '공원', 'caption': '공원 산책'},
      {'id': 500, 'date': '2019-01-01', 'place': '카페', 'caption': '마카롱 디저트'},
    ];
    final s = await startApp(tester, {'snapback_db': jsonEncode(db)});
    s.serverConnected = false; // 검색어 임베딩을 못 받는 상황
    final few = s.visiblePhotos.take(80).toList();
    expect((await s.narrowForAi(few, '디저트')).length, 80);
    final picked = await s.narrowForAi(s.visiblePhotos, '마카롱 디저트');
    expect(picked.length, lessThan(s.visiblePhotos.length));
    expect(picked.map((d) => d.id), contains(500));
    final ids = picked.map((d) => d.id).toList();
    expect(ids, [...ids]..sort(), reason: '같은 입력이면 같은 목록 (id 순)');
    final wide = await s.narrowForAi(s.visiblePhotos, '공원 사진 중 음식은 빼고', wide: true);
    expect(wide.length, s.visiblePhotos.length, reason: '제외 조건이면 넉넉히 (121장 < 300장)');
  });

  testWidgets('로딩 바: 검색 등을 기다리는 동안만 맨 아래 얇게', (tester) async {
    final s = await startApp(tester, {'snapback_db': jsonEncode(photos(1))});
    expect(find.byType(LinearProgressIndicator), findsNothing);
    s.searchBusy = true;
    s.touch();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    s.searchBusy = false;
    s.touch();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('사진 정보: 눌렀을 때 스르륵 펼쳐짐 (처음엔 접힘)', (tester) async {
    final s = await startApp(tester, {
      'snapback_db': jsonEncode([
        {'id': 12, 'date': '2026-01-01', 'place': '카페', 'caption': '라떼', 'kw': ['라떼아트']},
      ]),
    });
    s.openMemory(12);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('#라떼아트'), findsNothing);
    await tester.tap(txt('사진 정보').last);
    await tester.pump(const Duration(milliseconds: 40));
    final early = tester.widget<Opacity>(find.ancestor(of: find.text('#라떼아트'), matching: find.byType(Opacity)).first).opacity;
    expect(early, lessThan(1), reason: '바로 툭 나오지 않고 서서히');
    await tester.pump(const Duration(milliseconds: 500));
    final done = tester.widget<Opacity>(find.ancestor(of: find.text('#라떼아트'), matching: find.byType(Opacity)).first).opacity;
    expect(done, 1);
  });

  testWidgets('월간 리캡 카드: 요약을 보여 주고 자동 앨범은 미리보기로', (tester) async {
    final s = await startApp(tester, {
      'snapback_db': jsonEncode([
        for (var i = 12; i < 16; i++)
          {'id': i, 'date': '2026-11-0${i - 11}', 'place': '카페', 'food': ['케이크'], 'kw': ['감성']},
      ]),
    });
    expect(txt('11월의 나'), findsOneWidget);
    expect(txt('사진 4장'), findsOneWidget);
    await tester.tap(txt('케이크 모음'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(s.screen, 17);
    expect(s.albumDraft!.photoIds, [12, 13, 14, 15]);
    expect(s.albumDraft!.title, '11월의 케이크');
  });

  testWidgets('촬영 장소: 위치 정보가 있으면 시·구·동 주소로, 못 받으면 안내 ("위치 정보 있음" 아님)', (tester) async {
    final s = await startApp(tester, {
      'snapback_db': jsonEncode([
        {'id': 12, 'date': '2026-01-01', 'place': '카페', 'caption': '라떼', 'gps': [37.5563, 126.9220]},
        {'id': 13, 'date': '2026-01-02', 'place': '', 'caption': '거리', 'gps': [35.1587, 129.1604]},
      ]),
      'snapback_place_names': jsonEncode({'37.556,126.922': '서울특별시 마포구 동교동'}),
    });
    Future<String> placeRow(int id) async {
      s.openMemory(id);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(txt('사진 정보').last);
      await tester.pump(const Duration(milliseconds: 600));
      final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').replaceAll('⁠', ''));
      expect(texts.any((t) => t.contains('위치 정보 있음')), false);
      return texts.firstWhere((t) => t.contains('동교동') || t.contains('주소'), orElse: () => '');
    }

    expect(await placeRow(12), '카페 · 서울특별시 마포구 동교동');
    s.go(5);
    await tester.pump(const Duration(milliseconds: 600));
    s.serverConnected = false; // 주소를 받을 수 없는 상황
    expect(await placeRow(13), contains('주소를 불러오지 못했어요'));
  });

  testWidgets('사진 탭 정렬: 시간순(월별) ↔ 추가순, 고른 기준은 저장', (tester) async {
    final s = await startApp(tester, {
      'snapback_db': jsonEncode([
        {'id': 12, 'date': '2026-03-01', 'place': 'a'},
        {'id': 13, 'date': '2024-01-01', 'place': 'b'}, // 나중에 추가했지만 오래된 사진
        {'id': 14, 'date': '2025-06-01', 'place': 'c'},
      ]),
    });
    expect(txt('시간순'), findsOneWidget);
    expect(gridIds(tester), [12, 14, 13]);
    expect(txt('2026년 3월'), findsOneWidget);
    await tester.tap(txt('시간순'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(txt('추가순'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(gridIds(tester), [14, 13, 12]);
    expect(txt('2026년 3월'), findsNothing);
    expect(s.photoSort, 'added');
    expect((await SharedPreferences.getInstance()).getString('snapback_photo_sort'), 'added');
  });

  testWidgets('앨범 잠금: 목록에서 가리고, 비밀번호가 맞아야 열림, 다시 들어오면 잠김', (tester) async {
    const salt = 'abcd';
    final hash = sha256.convert(utf8.encode('$salt:1234')).toString();
    await startApp(tester, {
      'snapback_db': jsonEncode(photos(1)),
      'snapback_albums': jsonEncode([
        {'id': 1, 'title': '비밀 앨범', 'emoji': '🗂️', 'photoIds': [12], 'createdAtMs': 0, 'lockSalt': salt, 'lockHash': hash},
        {'id': 2, 'title': '열린 앨범', 'emoji': '🗂️', 'photoIds': [12], 'createdAtMs': 0},
      ]),
    });
    Future<void> enter(String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.descendant(of: find.byType(PinPad), matching: txt(d)).first);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 200));
    }

    await tester.tap(txt('앨범').last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(txt('잠긴 앨범'), findsOneWidget);
    expect(txt('사진 1장'), findsOneWidget); // 열린 앨범만 장수 표시
    await tester.tap(txt('비밀 앨범'));
    await tester.pump(const Duration(milliseconds: 600));
    final s = tester.widget<Screen16AlbumDetail>(find.byType(Screen16AlbumDetail)).state;
    expect(find.byType(PinPad), findsOneWidget);
    await enter('0000');
    expect(txt('비밀번호가 맞지 않아요 (1/5)'), findsOneWidget);
    expect(s.unlockedAlbumId, isNull);
    await enter('1234');
    expect(find.byType(PinPad), findsNothing);
    expect(s.unlockedAlbumId, 1);
    s.openAlbum(1);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PinPad), findsOneWidget);

    // 잠그기·풀기, 비밀번호 자체는 저장하지 않음, 5번 틀리면 잠시 막힘
    s.lockAlbum(2, '5678');
    expect(s.albumById(2)!.locked, true);
    expect(jsonEncode(s.albumById(2)!.toJson()).contains('5678'), false);
    s.unlockedAlbumId = null;
    expect(s.unlockAlbum(2, '5678'), isNull);
    s.removeAlbumLock(2);
    expect(s.albumById(2)!.locked, false);
    for (var i = 0; i < 4; i++) {
      s.unlockAlbum(1, '9999');
    }
    expect(s.unlockAlbum(1, '9999'), contains('30초'));
    expect(s.unlockAlbum(1, '1234'), contains('초 뒤에'));
  });
}
