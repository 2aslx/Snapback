# Snapback — 실행 방법
1. Node.js 20.6 이상 설치 (https://nodejs.org)
2. `.env.example` 을 `.env` 로 복사하고 OPENAI_API_KEY, OPENAI_MODEL 입력
3. 터미널에서 이 폴더로 이동 → `npm start`
4. 브라우저에서 http://localhost:3000 → 하단 🔍 검색 탭 (AI 연동 화면)

구조: 브라우저(public/index.html) → server.js(/api/analyze, /api/search) → OpenAI API
- API 키는 서버(.env)에만 있고 브라우저에는 절대 내려가지 않는다. .env 는 Git에 올리지 말 것.
- 배포(Render): 대시보드 → New → Blueprint → 이 저장소 선택 → `render.yaml` 인식 → OPENAI_API_KEY 입력. Dockerfile이 Flutter Web을 빌드해 server.js와 함께 실행한다.
