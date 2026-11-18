// 웹: 고화질 미리보기(1080px)를 IndexedDB 에 저장. 그 외 플랫폼: 사용 안 함(iOS 는 원본 에셋에서 직접 로드).
export 'preview_store_stub.dart'
    if (dart.library.js_interop) 'preview_store_web.dart';
