part of '../app_state.dart';

/// 하이브리드 검색 1차 선별 · 사진 임베딩 저장·갱신·백필
extension SnapbackEmbeddings on SnapbackState {
  /// 사진이 [kHybridThreshold] 장을 넘으면 검색어 임베딩 + 사진 임베딩 코사인 유사도 + 키워드·주소·날짜 보너스로
  /// 상위 후보만 골라 돌려준다 (기기 안에서, 검색어 1문장만 서버로). 검색어 임베딩이 실패하면 키워드 점수로 고른다.
  /// 결과는 id 순으로 정렬해 같은 입력이면 같은 목록 (검색·앨범 결과 캐시 키가 일정하게).
  Future<List<PhotoItem>> narrowForAi(
    List<PhotoItem> photos,
    String query, {
    bool wide = false,
  }) async {
    if (photos.length <= kHybridThreshold) return photos;
    await EmbeddingStore.load();
    final key = query.trim();
    Float32List? qv;
    if (_queryVectors.containsKey(key)) {
      qv = _queryVectors[key];
    } else if (serverConnected) {
      qv = await api.embedQuery(key);
      if (qv != null) {
        _queryVectors[key] = qv;
        while (_queryVectors.length > 30) {
          _queryVectors.remove(_queryVectors.keys.first);
        }
      }
    }
    final ids = hybridSelect(
      photos: photos,
      query: key,
      queryVec: qv,
      vectorOf: EmbeddingStore.get,
      addr: addressById,
      limit: wide ? kHybridLimitWide : kHybridLimit,
    ).toSet();
    return [
      for (final d in photos)
        if (ids.contains(d.id)) d,
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  /// 다시 분석한 사진: 응답에 임베딩이 있으면 저장, 없으면 분석 텍스트로 새로 만든다
  void _storeEmbedding(int id, Map<String, dynamic> ai) {
    if (toVector(ai['embedding']) case final v?) {
      EmbeddingStore.put(id, v).ignore();
    } else {
      refreshEmbedding(id).ignore();
    }
  }

  /// 사진 1장의 임베딩을 지금 분석 텍스트·주소·확정 키워드로 다시 만든다 (실패해도 조용히 넘어감)
  Future<void> refreshEmbedding(int id) async {
    final d = photoById(id);
    if (d == null || !serverConnected) return;
    try {
      final v = (await api.embedTexts([embedTextFor(d, addr: addressById[id])])).first;
      if (v != null && photoById(id) != null) await EmbeddingStore.put(id, v);
    } catch (_) {}
  }

  /// 임베딩이 없는 사진을 50장씩 뒤에서 채운다 (이미지는 다시 분석하지 않고, 저장된 분석 텍스트 + 주소만 보냄)
  Future<void> backfillEmbeddings() async {
    if (_backfilling || !serverConnected) return;
    _backfilling = true;
    final run = _backfillRun;
    try {
      await EmbeddingStore.load(); // 저장된 임베딩을 다 읽은 뒤에 빠진 것만 채운다
      while (run == _backfillRun) {
        final missing = [
          for (final d in db)
            if (!EmbeddingStore.has(d.id)) d,
        ].take(50).toList();
        if (missing.isEmpty) break;
        final vs = await api.embedTexts([
          for (final d in missing) embedTextFor(d, addr: addressById[d.id]),
        ]);
        if (run != _backfillRun) break;
        final got = <int, Float32List>{
          for (var i = 0; i < missing.length; i++)
            if (vs[i] != null && photoById(missing[i].id) != null) missing[i].id: vs[i]!,
        };
        if (got.isEmpty) break; // 서버가 못 만들어 주면 다음 실행 때 다시
        await EmbeddingStore.putAll(got);
      }
    } catch (_) {
      // 서버 오류·오프라인 — 다음 실행이나 다음 분석 뒤에 다시 시도
    } finally {
      _backfilling = false;
    }
  }
}
