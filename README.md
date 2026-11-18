# Snapback — 실행 방법
1. Node.js 20.6 이상 설치 (https://nodejs.org)
2. `.env.example` 을 `.env` 로 복사하고 OPENAI_API_KEY, OPENAI_MODEL 입력
3. 터미널에서 이 폴더로 이동 → `npm start`
4. 브라우저에서 http://localhost:3000 → 하단 🔍 검색 탭 (AI 연동 화면)

구조: 브라우저(public/index.html) → server.js(/api/analyze, /api/search) → OpenAI API
- API 키는 서버(.env)에만 있고 브라우저에는 절대 내려가지 않는다. .env 는 Git에 올리지 말 것.
- 배포: Render / Railway / Fly.io 등에 올리고 환경변수에 OPENAI_API_KEY 설정.

## 배포 (Vercel)
- 구조: Flutter Web(정적) + `api/*.js` 서버리스 함수. API 로직은 `api/_core.js` 하나를 로컬 `server.js` 와 Vercel 이 같이 쓴다.
- 최초 1회: vercel.com → GitHub 로그인 → Add New → Project → 이 저장소 Import → Environment Variables 에 `OPENAI_API_KEY` (선택: `OPENAI_MODEL`) 입력 → Deploy. 빌드 설정은 `vercel.json` 이 지정한다.
- 이후 `main` 에 push 하면 자동 배포, 다른 브랜치는 Preview 주소로 배포된다.
- iOS 앱은 배포 주소를 서버로 쓰도록 빌드: `flutter run -d ios --dart-define=SNAPBACK_API_URL=https://<배포주소>` (앱 설정 화면에서도 변경 가능)
