part of '../app_state.dart';

/// 사진 분석: 실행 · 일시정지 · 취소 · 전체 다시 분석 · 한 장 다시 분석 · 연도별 진행
extension SnapbackAnalysis on SnapbackState {
  Future<void> startAnalysis() async {
    final myRun = ++_runId;
    // 지난 분석이 끝난 뒤의 시작이면 새 묶음 (일시정지 후 이어하기는 같은 묶음)
    final newBatch = analysisFinished || analysisTotal == 0;
    analysisPaused = false;
    analysisRunning = true;
    analysisFinished = false;

    final analyzed = {for (final d in db) d.fileKey, ...removedKeys};
    // 지난 분석이 끝났으면 새 묶음: 끝난 사진(분석됨·지움·실패)을 대기열에서 빼고 이번에 올린 사진만 센다
    if (newBatch) {
      pickQueue.removeWhere(
        (e) =>
            (analyzed.contains(e.key) || _failedKeys.contains(e.key)) &&
            !_inFlight.contains(e.key),
      );
      _failedKeys.clear();
    }
    analysisFinished = false;
    final pending = pickQueue
        .where(
          (p) =>
              !analyzed.contains(p.key) &&
              !_inFlight.contains(p.key) &&
              !_failedKeys.contains(p.key),
        )
        .toList();

    pending.sort((a, b) => compareForOrder(a.modified, b.modified));

    analysisTotal = pickQueue.length;
    _recountDone();
    _saveQueue();
    etaMs = 0;
    currentFileDate = pending.isNotEmpty ? pending.first.modified : null;
    if (pending.isEmpty && analysisTotal > 0) {
      analysisFinished = true;
      analysisRunning = false;
      _clearQueue();
    }
    touch();

    if (pending.isEmpty) {
      analysisRunning = false;
      touch();
      return;
    }

    final t0 = DateTime.now().millisecondsSinceEpoch;
    var processedCount = 0;
    var next = 0;

    // 여러 장 동시에 분석: 일꾼(worker) N개가 대기열에서 한 장씩 가져간다
    Future<void> worker() async {
      while (true) {
        if (myRun != _runId || analysisPaused) return;
        if (next >= pending.length) return;
        final entry = pending[next++];
        currentFileDate = entry.modified;
        touch();
        await _analyzeOne(entry);
        _recountDone(); // 완료 수는 실제 상태(분석됨·실패)로 다시 센다
        if (myRun != _runId) {
          touch();
          return; // 그사이 새 분석이 시작됨
        }
        processedCount++;
        final elapsed = DateTime.now().millisecondsSinceEpoch - t0;
        final remaining = analysisTotal - analysisDone;
        // 동시에 처리하므로 실제 흐른 시간 기준으로 남은 시간 계산
        etaMs = remaining > 0
            ? ((elapsed / processedCount) * remaining).round()
            : 0;
        touch();
      }
    }

    await Future.wait([
      for (var w = 0; w < math.min(SnapbackState._concurrency, pending.length); w++) worker(),
    ]);

    if (myRun != _runId || analysisPaused) {
      analysisRunning = false;
      touch();
      return;
    }

    if (myRun == _runId) {
      await _saveDb(); // 묶어 두던 저장을 바로 마무리
      prefetchAddresses(); // 새로 분석한 사진의 주소도 받아 둔다
      backfillEmbeddings(); // 임베딩이 빠진 사진이 있으면 채운다
      analysisRunning = false;
      analysisFinished = true;
      etaMs = 0;
      _clearQueue();
      touch();
    }
  }

  /// 이번 묶음에서 끝난 사진 수 = 분석됨·지움·실패
  void _recountDone() {
    final analyzed = {for (final d in db) d.fileKey, ...removedKeys};
    analysisDone = pickQueue
        .where((e) => analyzed.contains(e.key) || _failedKeys.contains(e.key))
        .length;
    analysisFailed = _failedKeys.length;
  }

  Future<void> _analyzeOne(PickedFileEntry entry) async {
    _inFlight.add(entry.key);
    try {
      final processed = entry.asset != null
          ? await ImageProcessor.processAsset(entry.asset!)
          : await ImageProcessor.process(entry.file!, entry.modified);
      String? previewKey;
      if (processed.previewBytes != null && PreviewStore.enabled) {
        // 저장에 실패하면(사생활 보호 모드 등) 미리보기 없이 작은 썸네일로 보여 준다
        if (await PreviewStore.put(
          'pv:${entry.key}',
          processed.previewBytes!,
        )) {
          previewKey = 'pv:${entry.key}';
        }
      }
      var ai = await api.analyzeImage(processed.analyzeDataUrl);
      // 스크린샷·문서처럼 글자가 많은 이미지면 1280px + 고해상도로 한 번 더 정밀 분석
      if (ai['text_dense'] == true) {
        final hi = entry.asset != null
            ? await hiResDataUrlForAsset(entry.asset!)
            : (processed.previewBytes != null
                  ? 'data:image/jpeg;base64,${base64Encode(processed.previewBytes!)}'
                  : null);
        if (hi != null) {
          try {
            ai = await api.analyzeImage(hi, detail: 'high');
          } catch (_) {
            // 정밀 분석이 실패하면 1차 결과를 그대로 쓴다
          }
        }
      }

      final item = PhotoItem(
        id: _nextId++,
        fileKey: entry.key,
        date: processed.dateStr,
        place: '',
        gps: processed.gps,
        exif: processed.hasExifDate,
        thumbDataUrl: processed.thumbDataUrl,
        assetId: entry.asset?.id,
        assetW: entry.asset?.width,
        assetH: entry.asset?.height,
        previewKey: previewKey,
        takenAtMs: processed.takenAt?.millisecondsSinceEpoch,
      ).withAnalysis(ai);
      if (db.any((d) => d.fileKey == entry.key)) return; // 이미 저장됨 (중복 방지)
      db.add(item);
      // 분석 응답에 함께 온 임베딩을 기기에 저장 (없으면 나중에 backfillEmbeddings 가 채움)
      if (toVector(ai['embedding']) case final v?) EmbeddingStore.put(item.id, v).ignore();
      _saveDbSoon();
      analysisLogs.insert(
        0,
        AnalysisLogEntry(
          isError: false,
          text: '#${item.id} ${item.caption}',
          subtext: '${item.place} · ${item.date}',
          thumbDataUrl: item.thumbDataUrl,
        ),
      );
    } on ApiException catch (e) {
      _failedKeys.add(entry.key);
      analysisFailed = _failedKeys.length;
      aiStatusText = e.userMessage;
      analysisLogs.insert(
        0,
        AnalysisLogEntry(
          isError: true,
          text: '⚠️ ${entry.label} — ${e.userMessage}',
        ),
      );
    } catch (e) {
      _failedKeys.add(entry.key);
      analysisFailed = _failedKeys.length;
      analysisLogs.insert(
        0,
        AnalysisLogEntry(isError: true, text: '⚠️ ${entry.label} — 오류 ($e)'),
      );
    } finally {
      _inFlight.remove(entry.key);
    }
  }

  /// 분석 취소: 진행을 멈추고 남은 대기열을 비운다. 이미 분석한 사진(DB)은 그대로 둔다.
  void cancelAnalysis() {
    _runId++; // 돌고 있는 분석 루프 중단 (요청 중인 1장은 끝나면 저장만 됨)
    pickQueue.clear();
    pickedAssetIds.clear();
    _failedKeys.clear();
    analysisFailed = 0;
    pickNotice = '';
    analysisRunning = false;
    analysisPaused = false;
    analysisFinished = false;
    analysisTotal = 0;
    analysisDone = 0;
    etaMs = 0;
    currentFileDate = null;
    _clearQueue();
    _liveActivity.cancel();
    go(5);
  }

  /// 다시 분석할 수 있는 사진 (데모 사진 제외)
  List<PhotoItem> get relabelTargets => db.where((d) => d.id > 11).toList();

  Future<void> relabelAll() async {
    if (relabelRunning || analysisRunning) return;
    if (!serverConnected) {
      relabelFinished = false;
      aiStatusText = ApiException('network').userMessage;
      touch();
      return;
    }
    final targets = relabelTargets;
    final run = ++_relabelRun;
    relabelRunning = true;
    relabelFinished = false;
    relabelTotal = targets.length;
    relabelDone = relabelSkipped = relabelFailed = 0;
    touch();
    var next = 0;
    Future<void> worker() async {
      while (run == _relabelRun && next < targets.length) {
        final d = targets[next++];
        final url = await ImageProcessor.analyzeUrlFor(d);
        if (run != _relabelRun) return;
        if (url == null) {
          relabelSkipped++;
        } else {
          try {
            final ai = await api.analyzeImage(url);
            if (run != _relabelRun) return;
            final i = db.indexWhere((x) => x.id == d.id);
            if (i >= 0) {
              db[i] = _relabeled(db[i], ai);
              await _saveDb();
              _storeEmbedding(d.id, ai);
            }
          } catch (_) {
            relabelFailed++;
          }
        }
        relabelDone++;
        touch();
      }
    }

    await Future.wait([
      for (var w = 0; w < math.min(SnapbackState._concurrency, targets.length); w++) worker(),
    ]);
    if (run != _relabelRun) return;
    relabelRunning = false;
    relabelFinished = true;
    touch();
  }

  /// 진행 표시(하단 카드·잠금화면)를 다시 분석 쪽으로 보여줄지: 다시 분석 중이거나 방금 끝났고, 일반 분석은 쉬는 중
  bool get relabelActiveForProgress =>
      relabelRunning ||
      (relabelFinished &&
          !analysisRunning &&
          !analysisPaused &&
          pickQueue.isEmpty);

  Future<void> reanalyzePhoto(int id) async {
    final d = photoById(id);
    if (d == null || reanalyzingId != null) return;
    if (!serverConnected) {
      reanalyzeError = ApiException('network').userMessage;
      touch();
      return;
    }
    reanalyzingId = id;
    reanalyzeError = null;
    touch();
    try {
      // 원본에서 1280px(웹은 1080px 미리보기)를 만들어 detail:'high' 로 분석
      final hi = await recordImageDataUrl(d);
      final url = hi ?? await ImageProcessor.analyzeUrlFor(d);
      if (url == null) {
        reanalyzeError = '원본 사진을 찾을 수 없어 다시 분석할 수 없어요';
      } else {
        final ai = await api.analyzeImage(
          url,
          detail: hi != null ? 'high' : 'low',
        );
        final i = db.indexWhere((x) => x.id == id);
        if (i >= 0) {
          db[i] = db[i].withAnalysis(ai);
          await _saveDb();
          _storeEmbedding(id, ai);
        }
      }
    } on ApiException catch (e) {
      reanalyzeError = e.userMessage;
    } catch (e) {
      reanalyzeError = '다시 분석하지 못했어요 ($e)';
    } finally {
      reanalyzingId = null;
      touch();
    }
  }

  void cancelRelabel() {
    _liveActivity.cancel();
    _relabelRun++;
    relabelRunning = false;
    relabelFinished = false;
    touch();
  }

  /// 새 AI 분석으로 설명만 바꾼 사진 (나머지 필드는 그대로)
  PhotoItem _relabeled(PhotoItem d, Map<String, dynamic> ai) =>
      d.withAnalysis(ai);

  void togglePauseAnalysis() {
    analysisPaused = !analysisPaused;
    if (!analysisPaused && pickQueue.isNotEmpty) {
      startAnalysis();
    } else {
      analysisRunning = false;
      touch();
    }
  }

  Map<String, List<int>> yearProgress() {
    final map = <String, List<int>>{};
    for (final p in pickQueue) {
      final y = p.modified.year.toString();
      final pair = map.putIfAbsent(y, () => [0, 0]);
      pair[1]++;
      if (db.any((d) => d.fileKey == p.key)) pair[0]++;
    }
    return map;
  }

  void toggleYearVisibility(String year) {
    final currentlyHidden = db.any((d) => d.date.startsWith(year) && d.hidden);
    final nextHidden = !currentlyHidden;
    var count = 0;
    for (final d in db) {
      if (d.date.startsWith(year)) {
        d.hidden = nextHidden;
        count++;
      }
    }
    hiddenWarning = nextHidden ? '$year년 사진 $count장과 분석 정보가 검색에서 제외됩니다.' : '';
    touch();
  }
}
