// 사진 임베딩(256차원 Float32) 기기 저장소 — 검색 1차 선별용.
// 웹: IndexedDB, iOS 등: 앱 지원 폴더의 바이너리 파일. SharedPreferences(웹 localStorage 약 5MB)에는 넣지 않는다.
export 'embedding_store_io.dart'
    if (dart.library.js_interop) 'embedding_store_web.dart';
