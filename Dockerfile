# 1) Flutter Web 빌드
FROM ghcr.io/cirruslabs/flutter:stable AS web
WORKDIR /app/flutter_app
COPY flutter_app/pubspec.yaml flutter_app/pubspec.lock ./
RUN flutter pub get
COPY flutter_app/ ./
RUN flutter build web --release

# 2) Node 서버 (외부 npm 패키지 없음)
FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json server.js ./
COPY public/ ./public/
COPY --from=web /app/flutter_app/build/web ./flutter_app/build/web
# OPENAI_API_KEY / OPENAI_MODEL / PORT 는 호스팅 환경변수로 주입 (.env 사용 안 함)
CMD ["node", "server.js"]
