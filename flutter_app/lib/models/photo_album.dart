/// 검색 결과 제안으로 사용자가 만든 앨범 (기기 로컬 저장).
class PhotoAlbum {
  PhotoAlbum({
    required this.id,
    required this.title,
    required this.emoji,
    required this.photoIds,
    required this.createdAtMs,
  });

  final int id;
  final String title;
  final String emoji;
  final List<int> photoIds;
  final int createdAtMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'photoIds': photoIds,
        'createdAtMs': createdAtMs,
      };

  factory PhotoAlbum.fromJson(Map<String, dynamic> j) => PhotoAlbum(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? '앨범',
        emoji: j['emoji'] as String? ?? '🗂️',
        photoIds: ((j['photoIds'] as List?) ?? const [])
            .whereType<num>()
            .map((e) => e.toInt())
            .toList(),
        createdAtMs: (j['createdAtMs'] as num?)?.toInt() ?? 0,
      );
}

/// 검색 직후 "이런 앨범으로 만들어 드릴까요?" 제안 내용.
class AlbumSuggestion {
  const AlbumSuggestion({
    required this.title,
    required this.emoji,
    required this.photoIds,
  });

  final String title;
  final String emoji;
  final List<int> photoIds;
}
