// 웹: 브라우저 내장 기능으로 사진을 해독·축소. 그 외 플랫폼: 사용 안 함.
export 'browser_image_stub.dart'
    if (dart.library.js_interop) 'browser_image_web.dart';
