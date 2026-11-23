class PhotoItem {
  PhotoItem({
    required this.id,
    this.fileKey,
    required this.date,
    required this.place,
    this.food = const [],
    this.people = '',
    this.background = '',
    this.weather = '알 수 없음',
    this.time = '알 수 없음',
    this.caption = '',
    this.emoji = '🖼️',
    this.gps,
    this.exif = false,
    this.thumbDataUrl,
    this.hidden = false,
    this.assetId,
    this.assetW,
    this.assetH,
    this.previewKey,
    this.takenAtMs,
  });

  final int id;
  final String? fileKey;
  final String date;
  final String place;
  final List<String> food;
  final String people;
  final String background;
  final String weather;
  final String time;
  final String caption;
  final String emoji;

  /// 디자인(index.html)의 라인 아이콘 이름. 데모 사진은 emoji 에 대응, 업로드 사진은 'image'.
  String get icon => const {
        '🍰': 'cake',
        '🥐': 'bread',
        '🍓': 'bowl',
        '🍵': 'cup',
        '🌸': 'flower',
        '🍝': 'bowl',
        '🎄': 'tree',
        '🌅': 'sunset',
        '🧱': 'building',
        '☕': 'cup',
        '🛍️': 'bag',
      }[emoji] ??
      'image';
  final List<double>? gps;
  final bool exif;
  final String? thumbDataUrl;
  bool hidden;

  /// iOS 사진 보관함 원본 ID (PHAsset.localIdentifier) — 화면 표시 때 원본에서 불러옴
  final String? assetId;
  final int? assetW;
  final int? assetH;

  /// 웹: IndexedDB 에 저장한 1080px 미리보기 키
  final String? previewKey;

  /// 촬영 시각 (ms). '그날의 사진' 대표사진(가장 가까운 시각) 계산용. 기존 데이터에는 없을 수 있음.
  final int? takenAtMs;

  Map<String, dynamic> toJson({bool includeThumb = true}) => {
        'id': id,
        if (fileKey != null) 'key': fileKey,
        'date': date,
        'place': place,
        'food': food,
        'people': people,
        'background': background,
        'weather': weather,
        'time': time,
        if (caption.isNotEmpty) 'caption': caption,
        'e': emoji,
        if (gps != null) 'gps': gps,
        'exif': exif,
        if (includeThumb && thumbDataUrl != null) 'thumb': thumbDataUrl,
        if (hidden) 'hidden': true,
        // 기기 저장용 필드 (AI 요청에는 보내지 않음)
        if (includeThumb && assetId != null) 'asset': assetId,
        if (includeThumb && assetW != null) 'aw': assetW,
        if (includeThumb && assetH != null) 'ah': assetH,
        if (includeThumb && previewKey != null) 'pv': previewKey,
        if (includeThumb && takenAtMs != null) 'ts': takenAtMs,
      };

  factory PhotoItem.fromJson(Map<String, dynamic> j) {
    final rawFood = j['food'];
    final foodList = rawFood is List
        ? rawFood.map((e) => e.toString()).toList()
        : (rawFood is String && rawFood.isNotEmpty ? [rawFood] : <String>[]);
    final rawGps = j['gps'];
    List<double>? gpsList;
    if (rawGps is List && rawGps.length >= 2) {
      gpsList = [
        (rawGps[0] as num).toDouble(),
        (rawGps[1] as num).toDouble(),
      ];
    }
    return PhotoItem(
      id: (j['id'] as num).toInt(),
      fileKey: j['key'] as String?,
      date: (j['date'] ?? '').toString(),
      place: (j['place'] ?? '알 수 없음').toString(),
      food: foodList,
      people: (j['people'] ?? '').toString(),
      background: (j['background'] ?? '').toString(),
      weather: (j['weather'] ?? '알 수 없음').toString(),
      time: (j['time'] ?? '알 수 없음').toString(),
      caption: (j['caption'] ?? '').toString(),
      emoji: (j['e'] ?? '🖼️').toString(),
      gps: gpsList,
      exif: j['exif'] == true,
      thumbDataUrl: j['thumb'] as String?,
      hidden: j['hidden'] == true,
      assetId: j['asset'] as String?,
      assetW: (j['aw'] as num?)?.toInt(),
      assetH: (j['ah'] as num?)?.toInt(),
      previewKey: j['pv'] as String?,
      takenAtMs: (j['ts'] as num?)?.toInt(),
    );
  }
}

class SearchRankedItem {
  SearchRankedItem({
    required this.id,
    required this.score,
    required this.matched,
    required this.missing,
  });

  final int id;
  final int score;
  final List<String> matched;
  final List<String> missing;

  factory SearchRankedItem.fromJson(Map<String, dynamic> j) => SearchRankedItem(
        id: (j['id'] as num).toInt(),
        score: (j['score'] as num?)?.toInt() ?? 0,
        matched: (j['matched'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        missing: (j['missing'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

class SearchQuestion {
  SearchQuestion({required this.text, required this.options});

  final String text;
  final List<String> options;

  factory SearchQuestion.fromJson(Map<String, dynamic> j) => SearchQuestion(
        text: (j['text'] ?? '').toString(),
        options: (j['options'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

class UsabilityLogEntry {
  UsabilityLogEntry({
    required this.id,
    required this.ms,
    required this.questions,
    required this.firstRank,
    required this.hit,
  });

  final int id;
  final int ms;
  final int questions;
  final int firstRank;
  final bool hit;
}

List<PhotoItem> buildSeedPhotos() => [
      PhotoItem(
        id: 1,
        date: '2026-10-15',
        place: '카페(성수동)',
        food: ['딸기 케이크'],
        people: '2명, 니트',
        background: '큰 창 밖으로 비',
        weather: '비',
        time: '낮',
        emoji: '🍰',
        gps: [37.544, 127.056],
      ),
      PhotoItem(
        id: 2,
        date: '2026-07-02',
        place: '베이커리(합정)',
        food: ['크루아상'],
        people: '혼자',
        background: '창가 자리, 햇살',
        weather: '맑음',
        time: '낮',
        emoji: '🥐',
        gps: [37.549, 126.914],
      ),
      PhotoItem(
        id: 3,
        date: '2025-06-21',
        place: '카페(연남동)',
        food: ['딸기 빙수'],
        people: '3명, 여름 옷',
        background: '실내',
        weather: '맑음',
        time: '저녁',
        emoji: '🍓',
        gps: [37.562, 126.925],
      ),
      PhotoItem(
        id: 4,
        date: '2025-04-09',
        place: '찻집(서촌)',
        food: ['말차 라떼'],
        people: '혼자',
        background: '한옥 창가',
        weather: '흐림',
        time: '낮',
        emoji: '🍵',
        gps: [37.58, 126.97],
      ),
      PhotoItem(
        id: 5,
        date: '2024-08-14',
        place: '교토 거리',
        people: '2명, 여행 복장',
        background: '벚꽃, 탑',
        weather: '맑음',
        time: '낮',
        emoji: '🌸',
        gps: [35.011, 135.768],
      ),
      PhotoItem(
        id: 6,
        date: '2026-03-02',
        place: '식당(홍대)',
        food: ['파스타'],
        people: '4명',
        background: '어두운 조명',
        emoji: '🍝',
        time: '저녁',
        gps: [37.556, 126.924],
      ),
      PhotoItem(
        id: 7,
        date: '2025-12-24',
        place: '집(실내)',
        food: ['홈파티 음식'],
        people: '3명',
        background: '트리, 조명',
        time: '밤',
        emoji: '🎄',
      ),
      PhotoItem(
        id: 8,
        date: '2026-09-20',
        place: '한강공원',
        people: '혼자',
        background: '노을, 강',
        weather: '맑음',
        time: '저녁',
        emoji: '🌅',
        gps: [37.528, 126.933],
      ),
      PhotoItem(
        id: 9,
        date: '2026-10-15',
        place: '성수동 거리',
        people: '2명',
        background: '벽돌 건물, 비',
        weather: '비',
        time: '낮',
        emoji: '🧱',
        gps: [37.545, 127.057],
      ),
      PhotoItem(
        id: 10,
        date: '2026-10-15',
        place: '카페(성수동)',
        food: ['아이스 커피'],
        people: '2명',
        background: '큰 창, 식물',
        weather: '비',
        time: '낮',
        emoji: '☕',
        gps: [37.544, 127.055],
      ),
      PhotoItem(
        id: 11,
        date: '2026-10-15',
        place: '성수동 소품샵',
        people: '혼자',
        background: '조명, 실내',
        weather: '비',
        time: '저녁',
        emoji: '🛍️',
        gps: [37.546, 127.058],
      ),
    ];

/// 사진 정보에서 '감지 안 됨'을 뜻하는 조각인지 (예: '알 수 없음', '특정 복장 없음', '인원수 확인 불가', '0명')
bool isUnknownInfo(String x) => RegExp(
      r'(알\s*수\s*없|없음|없다|모름|불명|미상|확인\s*(불가|안\s*됨|되지\s*않)|보이지\s*않|해당\s*없|^0\s*명$|^n/?a$|^unknown|^none$|^null$|^-$)',
      caseSensitive: false,
    ).hasMatch(x.trim());
