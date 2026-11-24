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


/// 사진 정보에서 '감지 안 됨'을 뜻하는 조각인지 (예: '알 수 없음', '특정 복장 없음', '인원수 확인 불가', '0명')
bool isUnknownInfo(String x) => RegExp(
      r'(알\s*수\s*없|없음|없다|모름|불명|미상|확인\s*(불가|안\s*됨|되지\s*않)|보이지\s*않|해당\s*없|^0\s*명$|^n/?a$|^unknown|^none$|^null$|^-$)',
      caseSensitive: false,
    ).hasMatch(x.trim());
