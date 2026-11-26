part of '../app_state.dart';

/// 촬영 장소 주소 (구글 지도 또는 OpenStreetMap, 기기에 캐시)
extension SnapbackPlaces on SnapbackState {
  /// 예전(소수 4자리) 캐시도 읽는다
  String? _cachedPlace(PhotoItem d) {
    final k = SnapbackState._placeKey(d);
    if (k == null) return null;
    final g = d.gps!;
    return placeNames[k] ??
        placeNames['${g[0].toStringAsFixed(4)},${g[1].toStringAsFixed(4)}'];
  }

  /// AI 에 보낼 사진별 주소 (주소를 아는 사진만)
  Map<int, String> get addressById => {
    for (final d in db) d.id: ?_cachedPlace(d),
  };

  /// 주소를 미리 받아 둔다. [wait] 만큼만 기다리고 나머지는 계속 뒤에서 받는다.
  Future<void> prefetchAddresses({Duration wait = Duration.zero}) async {
    _addrJob ??= _runAddressJob().whenComplete(() => _addrJob = null);
    if (wait > Duration.zero) {
      await Future.any([_addrJob!, Future<void>.delayed(wait)]);
    }
  }

  Future<void> _runAddressJob() async {
    var changed = 0;
    while (serverConnected) {
      final d = visiblePhotos
          .where((x) => x.gps != null && _cachedPlace(x) == null)
          .where((x) => !_placeAsked.contains(SnapbackState._placeKey(x)))
          .firstOrNull;
      if (d == null) break;
      final k = SnapbackState._placeKey(d)!;
      _placeAsked.add(k);
      try {
        final name = await api.placeName(d.gps![0], d.gps![1]);
        if (name != null) {
          placeNames[k] = name;
          changed++;
          if (changed % 5 == 0) touch(); // 받는 대로 화면에도 반영
        } else {
          _placeFailed(k);
        }
      } on ApiException catch (e) {
        _placeFailed(k, retryable: true);
        if (e.code == 'rate_limited') {
          // 요청이 너무 많으면 잠시 쉬었다가 이어서 받는다
          Future<void>.delayed(const Duration(seconds: 30), prefetchAddresses);
          break;
        }
      } catch (_) {
        _placeFailed(k, retryable: true);
      }
      if (changed > 0 && changed % 10 == 0) await _savePlaceNames();
    }
    if (changed > 0) {
      await _savePlaceNames();
      touch();
    }
  }

  Future<void> _savePlaceNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SnapbackState._placeNamesKey, jsonEncode(placeNames));
    } catch (_) {}
  }

  /// 저장된 지역명. 없으면 서버에 한 번만 물어보고(앱 실행 중) 받아오면 다시 그린다.
  String? placeNameFor(PhotoItem d) {
    final k = SnapbackState._placeKey(d);
    if (k == null) return null;
    final hit = _cachedPlace(d);
    if (hit != null) return hit;
    if (serverConnected && _placeAsked.add(k)) {
      api
          .placeName(d.gps![0], d.gps![1])
          .then((name) async {
            if (name == null) {
              _placeFailed(k);
              touch();
              return;
            }
            placeNames[k] = name;
            touch();
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(SnapbackState._placeNamesKey, jsonEncode(placeNames));
            } catch (_) {}
          })
          .catchError((_) {
            _placeFailed(k, retryable: true); // 다음에 다시 시도 (최대 3번)
            touch();
          });
    }
    return null;
  }

  /// 주소 받기 실패 기록. [retryable] 이면 '요청함' 표시를 지워 다음에 다시 시도한다 (최대 3번).
  void _placeFailed(String k, {bool retryable = false}) {
    final n = (_placeFails[k] ?? 0) + 1;
    _placeFails[k] = n;
    if (retryable && n < 3) _placeAsked.remove(k);
  }

  /// 위치 정보는 있는데 주소를 끝내 받지 못했는지 (3번 실패 · 주소 없음 · 서버 연결 안 됨)
  /// (다시 시도할 수 있는 실패는 '요청함' 표시를 지워 두므로, 실패 기록이 있는데 아직 '요청함'이면 다시 묻지 않는 실패)
  bool placeLookupFailed(PhotoItem d) {
    final k = SnapbackState._placeKey(d);
    if (k == null || _cachedPlace(d) != null) return false;
    final fails = _placeFails[k] ?? 0;
    return !serverConnected || fails >= 3 || (fails > 0 && _placeAsked.contains(k));
  }
}
