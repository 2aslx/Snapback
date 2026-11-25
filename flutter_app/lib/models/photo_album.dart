/// 앨범 분류. 기본 3개 + 사용자가 추가한 것.
class AlbumCategory {
  const AlbumCategory({
    required this.id,
    required this.label,
    this.hint = '',
    this.builtIn = false,
  });

  final String id;
  final String label;

  /// AI 분류 기준 설명 (기본 카테고리만)
  final String hint;
  final bool builtIn;

  Map<String, dynamic> toJson() => {'id': id, 'label': label};

  factory AlbumCategory.fromJson(Map<String, dynamic> j) => AlbumCategory(
        id: (j['id'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
      );
}

const kBuiltInCategories = [
  AlbumCategory(
    id: 'memories',
    label: '추억',
    hint: '여행, 가족, 친구, 일상, 기념일',
    builtIn: true,
  ),
  AlbumCategory(
    id: 'inspiration',
    label: '취향',
    hint: '네일, 패션, 쇼핑, 위시리스트, 개인적인 디자인 레퍼런스',
    builtIn: true,
  ),
  AlbumCategory(
    id: 'projects',
    label: '작업',
    hint: '업무 자료, 과제, 디자인 및 프로젝트 레퍼런스',
    builtIn: true,
  ),
];

/// 사용자가 만든 앨범 (기기 로컬 저장).
class PhotoAlbum {
  PhotoAlbum({
    required this.id,
    required this.title,
    required this.emoji,
    required this.photoIds,
    required this.createdAtMs,
    this.category,
    this.lockSalt,
    this.lockHash,
  });

  final int id;
  String title; // 앨범 상세에서 이름을 바로 바꿀 수 있음
  final String emoji;
  final List<int> photoIds;
  final int createdAtMs;

  /// [AlbumCategory.id]. 예전에 만든 앨범은 null → '전체'에서만 보인다.
  String? category;

  /// 앨범 잠금: 비밀번호 4자리는 저장하지 않고 salt + SHA-256 해시만 기기에 저장한다.
  String? lockSalt;
  String? lockHash;
  bool get locked => lockHash != null && lockSalt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'photoIds': photoIds,
        'createdAtMs': createdAtMs,
        if (category != null) 'category': category,
        if (locked) 'lockSalt': lockSalt,
        if (locked) 'lockHash': lockHash,
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
        category: j['category'] as String?,
        lockSalt: j['lockSalt'] as String?,
        lockHash: j['lockHash'] as String?,
      );
}

/// AI 가 만든 앨범 초안 (미리보기에서 확인 후 저장).
class AlbumSuggestion {
  const AlbumSuggestion({
    required this.title,
    required this.emoji,
    required this.photoIds,
    this.category,
  });

  final String title;
  final String emoji;
  final List<int> photoIds;

  /// AI 가 추천한 카테고리 (미리보기에서 바꿀 수 있음)
  final String? category;
}
