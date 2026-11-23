# Snapback

흐릿하게 기억나는 장면을 말로 설명하면 AI가 갤러리에서 그 사진을 찾아 주는 스마트 갤러리입니다.
찾은 사진은 장소·문서·순간 기록으로 남길 수 있습니다.

- **iOS 앱**이 메인이고, 같은 화면을 **웹 앱**으로도 씁니다(테스트·피드백용).
- 웹: https://snapback-virid.vercel.app
- AI: OpenAI `gpt-4o-mini`

## 주요 기능

| 기능 | 설명 |
|---|---|
| 사진 분석 | 사진마다 캡션·장소·인물 특징·배경·날씨·시간대를 뽑아 **기기 안의 텍스트 DB**에 저장. 한 번 분석한 사진은 다시 분석하지 않음 |
| 대화형 검색 | "작년 여름 바닷가"처럼 말하면 가장 가능성 높은 사진을 크게 제시. **맞아요** / **질문 한 번 더하기**로 후보를 좁힘. 보기 대신 직접 답을 입력할 수도 있음 |
| 사진 상세 | 관련된 추억(그날의 사진 · 비슷한 분위기), 사진 정보, 기록으로 남기기 |
| 기록 | AI가 초안을 만들고 사용자가 확인·수정해 저장. 건강·금융·신분 정보는 동의해야 저장 |
| 기억 탭 | 검색으로 찾은 사진과 나의 기록을 모아 봄 |
| AI 앨범 | "올여름 친구들과 함께했던 순간들"처럼 설명하면 사진을 모아 앨범 초안을 만들고, 카테고리(추억·취향·작업·사용자 정의)도 추천 |
| 진행 표시 | 분석 중 하단 진행 바. iOS는 잠금화면·다이내믹 아일랜드(Live Activity)에도 표시 |

## 구조

```
Flutter 앱 (iOS · 웹)  ──▶  API 서버  ──▶  OpenAI
  분석 결과·앨범·기록은       로컬: server.js
  기기에만 저장              배포: Vercel 함수 (api/*.js)
```

- API 로직은 `api/_core.js` 하나를 로컬 `server.js`와 Vercel 함수가 함께 씁니다.
- **API 키는 서버 환경변수에만** 있고 앱·브라우저로는 내려가지 않습니다.
- OpenAI 요청은 `store: false`로 보내 OpenAI에 저장되지 않습니다. 사진 원본은 서버에 저장하지 않습니다.

```
flutter_app/          Flutter 앱 (lib/screens · state · services · widgets)
flutter_app/ios/      iOS 프로젝트 (SnapbackLiveActivity = 잠금화면 위젯)
api/                  서버 API (_core.js + 경로별 Vercel 함수)
server.js             로컬 서버 (웹 빌드 + /api)
scripts/vercel-build.sh  Vercel 빌드 (Flutter 설치 → 웹 빌드)
index.html            UI 디자인 원본 (HTML 프로토타입)
```

## 로컬에서 실행

필요한 것: Node.js 20.6 이상, Flutter 3.50 이상, (iOS) Xcode

1. `.env.example`을 `.env`로 복사하고 키를 넣습니다. **`.env`는 절대 커밋하지 마세요.**

   | 변수 | 필수 | 설명 |
   |---|---|---|
   | `OPENAI_API_KEY` | ✓ | OpenAI API 키 |
   | `OPENAI_MODEL` | | 기본 `gpt-4o-mini` |
   | `PORT` | | 기본 `3000` |
   | `GOOGLE_MAPS_API_KEY` | | 촬영 장소를 지역명으로 표시 (Geocoding API). 없으면 좌표로 표시 |

2. 웹 앱 + 서버

   ```bash
   cd flutter_app && flutter pub get && flutter build web --release && cd ..
   npm start            # http://localhost:3000
   ```

3. iOS 앱 (시뮬레이터 또는 기기)

   ```bash
   cd flutter_app && flutter run -d ios
   ```

   VS Code에서는 F5로 실행됩니다(`.vscode/launch.json`).
   iOS 앱은 기본으로 배포 서버(Vercel)를 씁니다.
   다른 서버를 쓰려면 `--dart-define=SNAPBACK_API_URL=<주소>`를 붙이거나 앱 설정 화면에서 바꿉니다.

## API

| 경로 | 하는 일 |
|---|---|
| `GET /api/health` | 서버·키 연결 확인 |
| `POST /api/analyze` | 사진 1장 분석 (512px, 저해상도 모드) |
| `POST /api/search` | 기억 문장 + 질문·답변 기록 → 후보 순위와 다음 질문 |
| `POST /api/album` | 앨범 요청 → 앨범 이름, 사진 목록, 추천 카테고리 |
| `POST /api/place` | GPS 좌표 → 지역명 (구글 지도 키 필요) |
| `POST /api/record` | 기록 초안 (종류·제목·추출 텍스트·요약·민감정보 여부) |

IP당 분당 요청 제한(사진 분석 120회, 그 밖 30회), 요청 크기 제한, 60초 시간 초과, 로그의 키 가림 처리가 들어 있습니다.

## 배포 (Vercel)

- 처음 한 번: vercel.com에서 이 저장소를 Import → Environment Variables에 `OPENAI_API_KEY`(선택: `OPENAI_MODEL`, `GOOGLE_MAPS_API_KEY`) 입력 → Deploy. 빌드 설정은 `vercel.json`에 있습니다.
- 이후 연결된 저장소의 **`main`에 push하면 자동 배포**되고, 다른 브랜치는 Preview 주소로 배포됩니다.
- 공개 주소라 누구나 AI 기능을 쓸 수 있습니다. OpenAI 사용량을 가끔 확인하세요.

## 개발 규칙

- 작업은 `main`이 아닌 브랜치에서 하고, `main`에는 머지로만 반영합니다.
- 코드를 바꾼 뒤에는 아래를 차례로 확인합니다.

  ```bash
  cd flutter_app
  flutter analyze && flutter test
  flutter build web --release
  flutter run -d ios
  ```
