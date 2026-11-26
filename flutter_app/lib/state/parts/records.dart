part of '../app_state.dart';

/// 기록으로 남기기 (기록 다듬기 · 나의 기록 · 기록 탭)
extension SnapbackRecords on SnapbackState {
  void setRecordsView(String v) {
    recordsView = v;
    touch();
  }

  PhotoRecord? recordForPhoto(int photoId) =>
      records.where((r) => r.photoId == photoId).firstOrNull;

  PhotoRecord? recordById(int? id) =>
      records.where((r) => r.id == id).firstOrNull;

  /// 사진 상세의 '기록으로 남기기' → 기록 다듬기.
  /// 분석 v2 에서 이미 추출한 structuredData 가 있으면 재사용해 바로 채우고(불필요한 API 호출 생략),
  /// 없거나 장소·추억 기록이면 AI 가 초안을 만들어 채운다.
  Future<void> startRecord(int photoId) async {
    final photo = photoById(photoId);
    if (photo == null) return;
    final loc = placeNameFor(photo) ?? '';
    final hasPlace = photo.place.isNotEmpty && photo.place != '알 수 없음';
    final initialType = switch (photo.suggestedRecordType) {
      'place' => 'place',
      'document' || 'shopping' || 'info' => 'document',
      'moment' || 'taste' => 'moment',
      _ => photo.isInfoImage
          ? 'document'
          : (hasPlace || photo.gps != null ? 'place' : 'moment'),
    };
    final preLines = structuredRecordLines(photo.structuredData);
    String? inferredSensitive;
    final sensText =
        '${photo.imageType} ${photo.mainTopic} ${photo.contentSummary} ${photo.extractedText}';
    if (photo.imageType == 'health_report' ||
        RegExp(r'건강검진|진단서|처방전|혈액검사|혈압|콜레스테롤').hasMatch(sensText)) {
      inferredSensitive = '건강정보';
    } else if (RegExp(r'계좌번호|통장|카드번호|대출|증권').hasMatch(sensText)) {
      inferredSensitive = '금융정보';
    } else if (RegExp(r'주민등록증|운전면허증|여권번호|신분증').hasMatch(sensText)) {
      inferredSensitive = '신분정보';
    }

    final reuseV2 =
        photo.analysisVersion >= 2 &&
        initialType == 'document' &&
        preLines.isNotEmpty;

    recordDraft = PhotoRecord(
      id: 0,
      photoId: photoId,
      type: initialType,
      title: photo.mainTopic.isNotEmpty
          ? photo.mainTopic
          : (hasPlace ? photo.place : ''),
      location: loc.isNotEmpty ? loc : (hasPlace ? photo.place : ''),
      date: photo.date,
      kind: '기타',
      lines: preLines,
      summary: photo.contentSummary,
      sensitiveType: inferredSensitive,
      createdAtMs: 0,
    );
    recordConsent = false;
    recordError = null;
    recordBusy = !reuseV2 && serverConnected;
    recordDraftVersion++;
    go(20);
    if (reuseV2) return;
    if (!serverConnected) {
      recordError = 'AI 서버에 연결되지 않아 직접 입력해 주세요';
      touch();
      return;
    }
    try {
      final image = await recordImageDataUrl(photo);
      final r = await api.draftRecord(photo, image: image, location: loc);
      final d = recordDraft;
      if (d == null || d.photoId != photoId || d.id != 0) return; // 그사이 나감
      final place = r['place'] is Map ? r['place'] as Map : const {};
      d.type = (r['type'] ?? d.type).toString();
      final title = (r['title'] ?? '').toString();
      final placeName = (place['name'] ?? '').toString();
      d.title = d.type == 'place' && placeName.isNotEmpty
          ? placeName
          : (title.isNotEmpty ? title : d.title);
      if (r['date'] is String) d.date = r['date'] as String;
      d.kind = (place['kind'] ?? '기타').toString();
      if (d.location.isEmpty && placeName.isNotEmpty) d.location = placeName;
      final apiLines =
          ((r['lines'] as List?) ?? const []).map((e) => '$e').toList();
      if (apiLines.isNotEmpty) d.lines = apiLines;
      final apiSummary = (r['summary'] ?? '').toString();
      if (apiSummary.isNotEmpty) d.summary = apiSummary;
      d.sensitiveType = (r['sensitiveType'] as String?) ?? d.sensitiveType;
    } on ApiException catch (e) {
      recordError = '${e.userMessage} · 직접 입력해 주세요';
    } catch (e) {
      recordError = 'AI 초안을 만들지 못했어요 · 직접 입력해 주세요';
    } finally {
      recordBusy = false;
      recordDraftVersion++;
      touch();
    }
  }

  /// 저장된 기록 수정
  void editRecord(int id) {
    final r = recordById(id);
    if (r == null) return;
    recordDraft = PhotoRecord.fromJson(r.toJson());
    recordConsent = r.consentAtMs != null;
    recordError = null;
    recordBusy = false;
    recordDraftVersion++;
    go(20);
  }

  void setRecordType(String type) {
    recordDraft?.type = type;
    touch();
  }

  void setRecordConsent(bool v) {
    recordConsent = v;
    touch();
  }

  /// 민감정보면 동의해야 저장 가능
  bool get canSaveRecord {
    final d = recordDraft;
    if (d == null || recordBusy) return false;
    return d.sensitiveType == null || recordConsent;
  }

  /// 같은 날 · 가까운 곳(1.5km)에서 찍은 사진을 '연결된 사진'으로
  List<int> _linkedFor(PhotoItem p) {
    final list =
        visiblePhotos
            .where(
              (x) =>
                  x.id != p.id &&
                  (x.date == p.date || SnapbackState._distanceKm(p.gps, x.gps) < 1.5),
            )
            .toList()
          ..sort(
            (a, b) => (a.takenAtMs ?? a.id).compareTo(b.takenAtMs ?? b.id),
          );
    return list.take(12).map((x) => x.id).toList();
  }

  /// 기록 저장 → 나의 기록으로
  void saveRecordDraft() {
    final d = recordDraft;
    if (d == null || !canSaveRecord) return;
    if (d.title.trim().isEmpty) d.title = recordTypeOf(d.type).label;
    if (d.sensitiveType != null) {
      d.consentAtMs ??= DateTime.now().millisecondsSinceEpoch;
    }
    final photo = photoById(d.photoId);
    if (d.id == 0) {
      final id = records.fold<int>(0, (m, r) => r.id > m ? r.id : m) + 1;
      final rec = PhotoRecord.fromJson({
        ...d.toJson(),
        'id': id,
        'at': DateTime.now().millisecondsSinceEpoch,
        if (photo != null) 'linked': _linkedFor(photo),
      });
      records.insert(0, rec);
      activeRecordId = id;
    } else {
      final i = records.indexWhere((r) => r.id == d.id);
      if (i >= 0) records[i] = PhotoRecord.fromJson(d.toJson());
      activeRecordId = d.id;
    }
    recordDraft = null;
    recordReturn = 10;
    _saveRecords();
    go(21);
  }

  /// 기록 다듬기 취소: 새 기록이면 사진 상세로, 수정 중이면 나의 기록으로
  void cancelRecordDraft() {
    final d = recordDraft;
    recordDraft = null;
    recordBusy = false;
    if (d != null && d.id != 0) {
      activeRecordId = d.id;
      go(21);
    } else {
      go(10);
    }
  }

  void openRecord(int id) {
    activeRecordId = id;
    recordReturn = screen == 21 ? recordReturn : screen;
    go(21);
  }

  void toggleRecordFavorite(int id) {
    final r = recordById(id);
    if (r == null) return;
    r.favorite = !r.favorite;
    touch();
    _saveRecords();
  }

  /// 문서·쇼핑 리스트 기록의 개별 항목 체크 토글 (앱 재실행 후에도 유지)
  void toggleRecordLine(int id, int lineIndex) {
    final r = recordById(id);
    if (r == null || lineIndex < 0 || lineIndex >= r.lines.length) return;
    final next = List<int>.from(r.checkedLines);
    if (next.contains(lineIndex)) {
      next.remove(lineIndex);
    } else {
      next.add(lineIndex);
    }
    r.checkedLines = next;
    touch();
    _saveRecords();
  }

  void deleteRecord(int id) {
    records.removeWhere((r) => r.id == id);
    if (activeRecordId == id) activeRecordId = null;
    touch();
    _saveRecords();
  }

  Future<void> _saveRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SnapbackState._recordsKey,
        jsonEncode(records.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}
  }
}
