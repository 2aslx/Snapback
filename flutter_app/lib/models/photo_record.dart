/// '기록으로 남기기'로 저장한 사진 기록 (기기 로컬 저장).
/// 사진 1장을 기준으로, AI 가 만든 초안을 사용자가 확인·수정해서 저장한다.
class RecordType {
  const RecordType(this.id, this.label, this.icon, this.desc);
  final String id;
  final String label;
  final String icon;
  final String desc;
}

/// 기록 종류 (화면에 이 순서로 보임). id 'moment' 는 예전 저장 데이터와 호환되도록 그대로 둔다.
const kRecordTypes = [
  RecordType('moment', '추억 기록', 'heart', '그날의 추억과 느낌을\n짧은 메모로 남겨요.'),
  RecordType('place', '장소 기록', 'pin', '방문한 장소를 기록하고,\n나만의 맛집·카페 리스트로 모아보세요.'),
  RecordType(
    'document',
    '문서 기록',
    'doc',
    '문서의 내용을 추출해 정리하고,\n필요한 정보를 기록으로 남겨요.',
  ),
];

RecordType recordTypeOf(String id) => kRecordTypes.firstWhere(
  (t) => t.id == id,
  orElse: () => kRecordTypes.first,
);

/// 장소 유형 (장소 기록)
const kPlaceKinds = [
  ('카페', 'cup'),
  ('음식점', 'bowl'),
  ('여행지', 'compass'),
  ('공원·자연', 'tree'),
  ('전시·공연', 'palette'),
  ('쇼핑', 'bag'),
  ('기타', 'pin'),
];

String placeKindIcon(String kind) => kPlaceKinds
    .firstWhere((k) => k.$1 == kind, orElse: () => kPlaceKinds.last)
    .$2;

class PhotoRecord {
  PhotoRecord({
    required this.id,
    required this.photoId,
    required this.type,
    required this.title,
    this.location = '',
    this.date = '',
    this.kind = '',
    this.lines = const [],
    this.summary = '',
    this.memo = '',
    this.favorite = false,
    this.sensitiveType,
    this.consentAtMs,
    this.linkedPhotoIds = const [],
    required this.createdAtMs,
  });

  final int id;
  final int photoId;
  String type; // place | document | moment
  String title;
  String location;
  String date;
  String kind; // 장소 유형
  List<String> lines; // 문서에서 추출한 주요 텍스트
  String summary; // 문서 핵심 요약
  String memo;
  bool favorite;

  /// 민감정보 종류 (건강정보·금융정보·신분정보). 있으면 저장 전 동의가 필요.
  String? sensitiveType;
  int? consentAtMs;

  /// 함께 보여줄 사진 (같은 날 · 같은 장소)
  List<int> linkedPhotoIds;
  final int createdAtMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'photo': photoId,
    'type': type,
    'title': title,
    if (location.isNotEmpty) 'loc': location,
    if (date.isNotEmpty) 'date': date,
    if (kind.isNotEmpty) 'kind': kind,
    if (lines.isNotEmpty) 'lines': lines,
    if (summary.isNotEmpty) 'sum': summary,
    if (memo.isNotEmpty) 'memo': memo,
    if (favorite) 'fav': true,
    if (sensitiveType != null) 'sens': sensitiveType,
    if (consentAtMs != null) 'consent': consentAtMs,
    if (linkedPhotoIds.isNotEmpty) 'linked': linkedPhotoIds,
    'at': createdAtMs,
  };

  factory PhotoRecord.fromJson(Map<String, dynamic> j) => PhotoRecord(
    id: (j['id'] as num).toInt(),
    photoId: (j['photo'] as num).toInt(),
    type: (j['type'] ?? 'moment').toString(),
    title: (j['title'] ?? '').toString(),
    location: (j['loc'] ?? '').toString(),
    date: (j['date'] ?? '').toString(),
    kind: (j['kind'] ?? '').toString(),
    lines: ((j['lines'] as List?) ?? const []).map((e) => '$e').toList(),
    summary: (j['sum'] ?? '').toString(),
    memo: (j['memo'] ?? '').toString(),
    favorite: j['fav'] == true,
    sensitiveType: j['sens'] as String?,
    consentAtMs: (j['consent'] as num?)?.toInt(),
    linkedPhotoIds: ((j['linked'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList(),
    createdAtMs: (j['at'] as num?)?.toInt() ?? 0,
  );
}
