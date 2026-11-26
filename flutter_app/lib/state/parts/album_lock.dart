part of '../app_state.dart';

/// 앨범 잠금 (비밀번호 4자리)
extension SnapbackAlbumLock on SnapbackState {
  bool isAlbumHidden(PhotoAlbum a) => a.locked && unlockedAlbumId != a.id;

  /// 지금 잠겨 있는 앨범들에 포함된 사진 id 전체 (홈·검색·기억·기록 등에서 자물쇠로 가림)
  Set<int> get lockedPhotoIds {
    final out = <int>{};
    for (final a in albums) {
      if (isAlbumHidden(a)) out.addAll(a.photoIds);
    }
    return out;
  }

  /// 이 사진이 잠겨 있는 앨범에 들어 있으면 그 앨범을 돌려준다
  PhotoAlbum? lockedAlbumForPhoto(int photoId) {
    for (final a in albums) {
      if (isAlbumHidden(a) && a.photoIds.contains(photoId)) return a;
    }
    return null;
  }

  bool isPhotoLocked(int photoId) => lockedAlbumForPhoto(photoId) != null;

  void lockAlbum(int id, String pin) {
    final a = albumById(id);
    if (a == null || !RegExp(r'^\d{4}$').hasMatch(pin)) return;
    final rnd = math.Random.secure();
    final salt = List.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    a
      ..lockSalt = salt
      ..lockHash = SnapbackState._pinHash(salt, pin);
    unlockedAlbumId = id; // 방금 잠근 사람은 계속 보고 있음
    touch();
    _saveAlbums();
  }

  /// 비밀번호 확인. 맞으면 null, 틀리면 안내 문구. 5번 틀리면 30초 동안 막는다.
  String? unlockAlbum(int id, String pin) {
    final a = albumById(id);
    if (a == null || !a.locked) return null;
    final until = _unlockBlockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final sec = until.difference(DateTime.now()).inSeconds + 1;
      return '$sec초 뒤에 다시 시도하세요';
    }
    if (SnapbackState._pinHash(a.lockSalt!, pin) != a.lockHash) {
      _unlockFails++;
      if (_unlockFails >= 5) {
        _unlockFails = 0;
        _unlockBlockedUntil = DateTime.now().add(const Duration(seconds: 30));
        return '5번 틀렸어요. 30초 뒤에 다시 시도하세요';
      }
      return '비밀번호가 맞지 않아요 ($_unlockFails/5)';
    }
    _unlockFails = 0;
    _unlockBlockedUntil = null;
    unlockedAlbumId = id;
    touch();
    return null;
  }

  /// 잠금 풀기 (앨범을 연 상태에서만)
  void removeAlbumLock(int id) {
    final a = albumById(id);
    if (a == null || isAlbumHidden(a)) return;
    a
      ..lockSalt = null
      ..lockHash = null;
    touch();
    _saveAlbums();
  }
}
