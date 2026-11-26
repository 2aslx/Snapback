# Snapback 기술 문서

흐릿한 기억을 문장으로 말하면 AI가 갤러리에서 사진을 찾아 주는 스마트 갤러리 앱의 기술 구조를 정리한 문서입니다.
기능 설명은 [README.md](../README.md)와 [FEATURES.md](../FEATURES.md)를 참고하세요.

| 항목 | 내용 |
|---|---|
| 클라이언트 | Flutter 3.50 (iOS 앱이 메인, 같은 코드로 웹도 빌드) |
| 서버 | Node.js (로컬: `server.js`, 배포: Vercel Functions `api/*.js`) |
| AI | OpenAI Chat Completions API, 모델 `gpt-4o-mini` |
| 지도·주소 | OpenStreetMap (Nominatim 역지오코딩, 지도 타일) / Google Geocoding (키가 있을 때) |
| 배포 | https://snapback-virid.vercel.app (`meisteryi/Snapback`의 `main` push 시 자동 배포) |

---

## 1. 전체 구조

```
┌─────────────── Flutter 앱 (iOS / 웹) ───────────────┐
│  화면(screens) ← 상태(SnapbackState) → 서비스(services) │
│  · 사진 보관함 읽기 (iOS: photo_manager / 웹: 파일 선택)  │
│  · 사진을 512px로 줄여 서버로 전송                       │
│  · 분석 결과·앨범·기록은 기기에만 저장                    │
└──────────────────────┬──────────────────────────────┘
                       │ HTTPS (JSON)
┌──────────────────────▼──────────────────────────────┐
│  서버 api/_core.js  (로컬 server.js / Vercel 함수 공용) │
│  · OpenAI API 키는 서버 환경변수에만 있음                │
│  · 요청 크기·횟수 제한, 응답 정리, 개인정보 제거           │
└───────┬──────────────────────────────┬──────────────┘
        ▼                              ▼
  OpenAI gpt-4o-mini           OSM Nominatim / Google Geocoding
  (분석·검색·앨범·기록·제안)      (GPS → 시·구·동 주소)
```

핵심 원칙
- **API 키는 프런트엔드에 절대 넣지 않는다.** 앱 → 우리 서버 → OpenAI 순서로만 호출한다.
- **사진 원본은 서버에 저장하지 않는다.** 분석할 때 축소본을 보내고, 결과(텍스트)만 기기에 저장한다.
- OpenAI 요청에는 `store: false`를 넣어 요청·응답이 OpenAI 쪽에 저장되지 않게 한다.

---

## 2. 저장소 구성

```
Snapback/
├─ api/
│  ├─ _core.js        # 요청 처리만 (라우팅·요청 제한·본문 읽기·오류 응답)
│  ├─ _lib/           # 기능별 서버 로직 ('_' 폴더는 Vercel 함수로 배포되지 않음)
│  │  ├─ config.js · openai.js (Chat·Embeddings) · pii.js (개인정보 제거)
│  │  ├─ analyze.js (분석·/api/embed) · photos.js (사진 정보 다듬기·300장 고르기)
│  │  └─ search.js · album.js (앨범·제안) · place.js · record.js · recall.js
│  └─ analyze.js, search.js, album.js, place.js, record.js, suggest.js, recall.js, embed.js, health.js
│                     # Vercel 함수 래퍼: handleApi(req, res, '<route>') 호출만 함
├─ test/core.test.mjs # 서버 단위 테스트 (npm test)
├─ server.js          # 로컬 개발 서버 (/api/* → _core.js, 나머지는 flutter_app/build/web 정적 파일)
├─ vercel.json        # Vercel 설정 (빌드 스크립트, 출력 폴더, 함수 최대 60초)
├─ scripts/vercel-build.sh  # Vercel에서 Flutter SDK를 받아 웹 빌드
├─ flutter_app/
│  ├─ lib/
│  │  ├─ main.dart            # 앱 셸: 화면 전환, 하단 탭, 진행 카드, 시작 화면
│  │  ├─ state/app_state.dart # SnapbackState: 상태 값·시작 처리·공용 도우미
│  │  ├─ state/parts/         # 기능별 메서드 (extension): storage · places · records · memories ·
│  │  │                       #   search · embeddings · library · analysis · albums · album_lock
│  │  ├─ models/              # PhotoItem, PhotoAlbum, PhotoRecord
│  │  ├─ screens/             # onboarding · record 화면, main_screens.dart + main/*.dart
│  │  │                       #   (홈 · 사진 상세 · 기억 · 앨범 · 설정 · 검색)
│  │  ├─ services/            # API 호출, 이미지 처리, 미리보기·임베딩 저장소, 하이브리드 선별,
│  │  │                       #   월간 리캡 계산, Live Activity
│  │  ├─ widgets/             # 공통 위젯, 지도 팝업, 공유, 아이콘 경로
│  │  └─ theme/app_theme.dart
│  ├─ ios/                    # Runner + SnapbackLiveActivity(위젯 확장)
│  └─ web/                    # index.html, manifest, 아이콘, 시작 화면
├─ README.md, FEATURES.md
└─ docs/
```

---

## 3. 서버 (`api/_core.js`)

### 3.1 라우트

| 라우트 | 메서드 | 하는 일 |
|---|---|---|
| `/api/health` | GET | 서버 상태, 키 설정 여부, 모델 이름, 지도 키 여부 |
| `/api/analyze` | POST | 사진 1장 분석 → 구조화된 사진 정보 |
| `/api/search` | POST | 기억 문장 + 대화 기록으로 사진 순위 매기기, 필요하면 추가 질문 1개 |
| `/api/album` | POST | 자연어 요청으로 앨범에 넣을 사진 고르기 |
| `/api/place` | POST | GPS 좌표 → 시·구·동 주소 |
| `/api/record` | POST | '기록으로 남기기' 초안 (추억/장소/문서 기록) |
| `/api/suggest` | POST | '흩어진 순간 모으기' 앨범 제안 문장 3개 |

### 3.2 공통 처리
- **OpenAI 호출** `ask(content, { temperature })`
  - Chat Completions, `response_format: json_object`(JSON으로만 답하게), `store: false`, 시간 제한 60초.
  - `temperature`를 넘기면 `seed: 7`도 함께 보낸다(앨범 만들기에서 사용).
- **요청 제한**
  - IP별 1분당: `analyze` 120회, 나머지 30회. 넘으면 `429 rate_limited`.
  - 요청 본문 최대 6MB (`too_big`).
  - 검색·앨범·제안은 사진 DB 최대 300장.
- **사진 정보 축소** `slimPhoto`
  - AI에 보낼 때 썸네일·이모지·구조화 정보를 빼고, 글자(150자)·요약(160자)·키워드(8개)를 자른다.
  - 앱은 GPS 좌표 대신 시·구·동 주소(`addr`)를 보낸다.
- **오류 코드** `openai_401/403/404/429/500/503`, `openai_unreachable`, `timeout`, `bad_ai_json`, `bad_image`, `too_big`, `bad_request`, `server_error`
  - 앱의 `ApiException`이 사용자용 한국어 문구로 바꿔 보여 준다.

### 3.3 사진 분석 (`analyze`)
- 프롬프트: `ANALYZE` 상수 (분석 v2).
  - 4가지 관점: 시각 / 의미(유형·카테고리·주제·요약) / 정보 추출(글자·구조화 정보) / 라이프로깅(저장 목적·검색 키워드·어울리는 기록 종류).
  - 규칙
    - 스크린샷의 UI 요소는 무시한다.
    - 보이지 않는 가격·브랜드는 지어내지 않는다.
    - 의학적 판단을 하지 않는다.
    - 개인 식별 정보를 쓰지 않는다.
    - 사람은 "주인공 / 배경"으로 나눠 쓴다.
    - 모르는 항목은 빈 값으로 둔다.
- **해상도 2단계**
  1. 기본: 앱이 긴 변 **512px**로 줄여 `detail: low`로 분석한다(빠르고 저렴).
  2. 글자가 많은 유형(`TEXT_DENSE`: screenshot, document, receipt, menu, chat 등)이거나 사용자가 '다시 분석하기'를 누르면, **1280px + `detail: high`**로 한 번 더 분석한다.
  - 사진은 자르지 않고 원본 비율을 유지한 채 해상도만 낮춘다.
- **응답 정리** `normalizeAnalysis`
  - 필드별 길이를 자른다.
  - 캡션·요약·추출 글자에서 개인정보(전화번호·이메일·주민번호·계좌번호 등)를 지운다(`scrubPII`).
  - 구조화 정보는 개인정보 키를 지우고 1,500자 안으로 줄인다.
  - 플랫폼·문서 이미지는 `place`를 비운다.
  - `analysis_version: 2`, `text_dense` 표시를 붙인다.

### 3.4 검색 (`search`)
- 사진 DB(축소본)와 대화 기록(최근 12개)을 보내면 AI가 사진마다 점수·맞은 단서·확인 안 된 단서를 준다.
- 후보를 가를 질문도 하나 만든다.
- 이미 한 질문과 같은 질문이 나오면 다시 요청하고, 기본 질문은 최대 5번까지다.
- '질문 한 번 더하기'(`wantQuestion`)를 누르면 반드시 질문을 만든다.

### 3.5 앨범 만들기 (`album`), 3단계 파이프라인
1. **조건 해석** (AI, temperature 0)
   - 요청을 `place.terms`, `time.from/to`, `kind`(object|mood), `topic`, `topic_terms`, `mood_cues`, `exclude`, `exclude_terms`, `category`로 바꾼다.
2. **장소·시간 거르기** (서버가 직접)
   - 주소·장소·캡션에 지명이 있는지 본다. '성수동' ↔ '성수2가3동'처럼 동 번호가 붙어도 맞도록 지명 줄기로도 비교한다.
   - 날짜 범위로 거른다.
3. **주제 판정** (AI, temperature 0, 25장씩)
   - `topic_terms`가 사진 정보에 그대로 있으면 확실한 사진이다. 분위기 요청은 이 자동 포함을 하지 않는다.
   - 나머지는 AI가 `yes/maybe/no`와 근거 낱말을 준다. **`yes`이고 근거 낱말이 실제 그 사진 정보에 있을 때만** 넣는다. 지어낸 근거는 걸러진다.
   - 분위기 요청은 스크린샷·문서 같은 정보 이미지를 뺀다.
- **결과 고정**: 응답에 `plan`(해석한 조건 + 사진별 판정 `seen`)을 함께 돌려준다.
  - 앱은 요청 문장별로 저장해 두었다가 다음에 같은 요청이면 다시 보낸다.
  - 같은 요청은 같은 결과가 나오고, 새로 추가했거나 정보가 바뀐 사진만 다시 판정한다(사진 정보 지문으로 비교).
  - 날짜 표현이 있는 요청은 날짜가 바뀌면 새로 해석한다.

### 3.6 주소 변환 (`place`)
- `GOOGLE_MAPS_API_KEY`가 있으면 Google Geocoding, 없으면 OSM Nominatim을 쓴다. Nominatim은 사용 정책에 따라 1.1초 간격으로 호출한다.
- 결과 예: `서울특별시 마포구 서교동`
- 앱은 좌표를 소수 3자리로 묶어 캐시해서 같은 동네를 반복해서 묻지 않는다.

### 3.7 기록 초안 (`record`) · 제안 (`suggest`)
- `record`
  - 사진 분석 정보(최대 2,000자)와 촬영 위치를 보낸다. 문서 사진이면 고해상도 이미지도 함께 보낸다.
  - 기록 종류(moment/place/document), 제목, 날짜, 장소, 내용 줄, 요약, 민감정보 종류(건강/금융/신분)를 받는다.
- `suggest`: 사진 DB를 보고 앨범 요청 문장 3개를 만든다. 앱을 켤 때마다 새로 만든다.

---

## 4. 클라이언트 (Flutter)

### 4.1 주요 패키지
| 패키지 | 용도 |
|---|---|
| `material_ui` | UI 위젯 (material.dart 대신) |
| `photo_manager`, `photo_manager_image_provider` | iOS 사진 보관함 앨범·사진 읽기, 썸네일 |
| `image`, `exif` | 이미지 축소·인코딩, 촬영 날짜·GPS 읽기 |
| `http` | 서버 API 호출 |
| `shared_preferences` | 기기 저장 (iOS) |
| `idb_shim`, `web` | 웹: IndexedDB 저장, 브라우저 API(이미지 디코딩) |
| `flutter_map`, `latlong2` | 촬영 위치 지도 팝업 (OSM 타일) |
| `share_plus` | 공유 시트 (카카오톡 등) |
| `flutter_svg` | 아이콘 |

글꼴: Inter(영문) + SnapbackKR(Pretendard에서 KS X 1001 한글 2,350자만 뽑은 것, OFL 라이선스에 따라 이름 변경).

### 4.2 상태 관리 (`state/app_state.dart`)
`SnapbackState`(ChangeNotifier) 하나가 앱 전체 상태를 가진다.
- **사진 DB**: `List<PhotoItem>`
  - iOS는 `shared_preferences`, 웹은 IndexedDB(`db:main`)에 저장한다.
  - 저장 요청은 2초마다 한 번으로 묶어서 쓴다.
- **분석 대기열**
  - 동시에 여러 장을 분석한다(iOS 5장, 웹 2장). 실패는 따로 센다.
  - 이미 분석한 사진은 다시 분석하지 않는다.
  - 분석 순서를 고를 수 있다(오래된 순 / 지정 연도 우선).
- 그 밖의 상태
  - 앨범·카테고리, 기록(즐겨찾기·정렬), 찾은 사진(기억 탭)
  - 주소 캐시, 앨범 조건 캐시(최근 50개)
- **앱 초기화**: 서버 주소 설정만 남기고 모두 지운다. 사진 앱의 원본은 건드리지 않는다.

### 4.3 이미지 처리 (`services/image_processor.dart`)
- 분석용: 긴 변 **512px** JPEG. 글자 많은 사진은 **1280px**.
- 웹
  - 브라우저 내장 디코더(`createImageBitmap` + `OffscreenCanvas`)로 줄인다.
  - HEIC는 `heic2any`를 필요할 때만 불러와 변환한다.
  - 지원하지 않는 형식은 건너뛰고 안내한다.
- 미리보기(`preview_store`): 웹은 IndexedDB, 메모리에는 최근 24장만 둔다.

### 4.4 화면 구성
- 하단 탭: **사진 · 기억 · 기록 · 앨범**
- 흐름
  - 온보딩: 시작 → 사진 접근 범위(실제 보관함 앨범) → 직접 고르기(날짜 스크롤바) → 분석 순서 → 분석 진행
  - 사진 탭: 모든 사진(월별) / 최근 사진, 편집(선택·전체 선택·앱에서만 삭제)
  - 검색: 1순위 사진 크게 표시 → '맞아요' / '질문 한 번 더하기' → 사진 상세
  - 사진 상세: 같은 날 사진, 비슷한 분위기(같은 주제끼리만), 사진 정보(유형별 카드), 지도, 공유, 다시 분석하기, 기록으로 남기기
  - 앨범: 카테고리(추억/취향/작업 + 사용자 추가), AI 앨범 만들기 → 미리보기(전부 선택된 상태에서 뺄 사진만 해제)
  - 기록: 추억/장소/문서 기록, 즐겨찾기 상단 고정, 정렬 기준 6가지
- 뒤로 가기: 화면이 오른쪽으로 밀리는 전환.

### 4.5 iOS 전용
- **Live Activity**: 잠금화면·다이내믹 아일랜드에 분석 진행률을 보여 준다.
  - 위젯 확장: `ios/SnapbackLiveActivity`
  - 앱과의 연결: `MethodChannel('snapback/live_activity')` (`update/end/cancel`), `LiveActivityBridge.swift`
  - 앱이 백그라운드로 가도 약 30초 동안 분석을 이어 간다(background task).
- **충전 중 장기 백그라운드 분석 (BGProcessingTask)**
  - 작업 id `com.snapback.snapbackApp.analysis` (`Info.plist` 의 `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes: processing`).
  - `AppDelegate.swift` 의 `BackgroundAnalysisBridge` ↔ Flutter `services/background_analysis.dart` (MethodChannel `snapback/background`).
  - 앱 → iOS: `setPending`(분석할 사진이 남았는지, 대기열 저장·삭제 때) · `ready`(대기열 복원 후). 남은 채로 백그라운드로 가면 `requiresExternalPower`·`requiresNetworkConnectivity` 로 예약.
  - iOS → 앱: `run`(남은 분석 이어 하기, 끝나면 true) · `expire`(시간 끝 → 지금 사진까지 마치고 멈춤·저장). 남았으면 다시 예약.
  - 실기기에서 바로 시험: 앱을 백그라운드로 보낸 뒤 Xcode 디버거에서
    `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.snapback.snapbackApp.analysis"]`
- 앱 이름 `Snapback`, 앱 아이콘·시작 화면은 캐릭터 이미지를 쓴다.

---

## 5. 개인정보·보안

| 항목 | 처리 |
|---|---|
| API 키 | 서버 환경변수(`.env` / Vercel)에만 둔다. `.env`는 커밋 금지. |
| 사진 원본 | 서버에 저장하지 않는다. 분석 때 축소본만 전송한다. |
| OpenAI 저장 | `store: false` |
| 개인 식별 정보 | 프롬프트로 금지하고, 서버에서 정규식으로 한 번 더 지운다. 최상위 `이름/name` 키도 지운다. |
| 위치 | AI에는 좌표 대신 시·구·동 주소만 보낸다. |
| 민감 기록 | 건강·금융·신분 정보가 담긴 기록은 저장 전에 동의를 받는다. |
| 앱 삭제 기능 | 앱 데이터에서만 지우고, 사진 보관함 원본은 그대로 둔다. |

---

## 6. 개발·배포

### 환경변수 (`.env`, 커밋 금지)
```
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini
PORT=3000
# 선택: GOOGLE_MAPS_API_KEY=...
```

### 로컬 실행
```bash
npm start                      # node --env-file=.env server.js → http://localhost:3000
cd flutter_app
flutter run -d ios --dart-define=SNAPBACK_API_URL=http://localhost:3000
```
- iOS 앱의 기본 서버는 `https://snapback-virid.vercel.app`이다.
- 웹은 같은 도메인의 `/api`를 쓴다.

### 검증 순서
```bash
npm test                       # 서버 단위 테스트 (test/core.test.mjs, OpenAI 는 가짜 응답)
cd flutter_app
flutter analyze && flutter test  # 모델(test/models_test.dart)·화면 동작(test/app_flows_test.dart) 테스트
flutter build web --release
flutter build ios --simulator --no-codesign
```

- push·PR 마다 GitHub Actions(`.github/workflows/test.yml`)가 위 테스트를 자동으로 돌린다.

### 배포
- **웹·서버**: `meisteryi/Snapback`의 `main`에 push하면 Vercel이 자동 배포한다.
  - Vercel이 `scripts/vercel-build.sh`를 실행한다(Flutter 3.50.0 SDK를 받아 웹 빌드).
  - 결과물은 `flutter_app/build/web`이고, `api/*.js`는 서버 함수로 배포된다(함수 최대 60초).
- **iOS 테스트 빌드**: `flutter build ipa --release --export-method development --build-number N`
  - GitHub Release에 `Snapback-1.0.0-buildN.ipa`로 올린다.
  - 무료 개인 개발자 서명이라 등록된 기기 1대에서만 설치되고, 7일 뒤 만료된다.

### 저장소
| 원격 | 주소 | 용도 |
|---|---|---|
| `origin` | github.com/meisteryi/Snapback | 개인 포크, Vercel 배포 연결 |
| `upstream` | github.com/2aslx/Snapback | 팀 원본 저장소 (`meisteryi/record-flow` 브랜치 → PR로 `main`에 머지) |
