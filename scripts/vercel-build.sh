#!/usr/bin/env bash
# Vercel 빌드: Flutter SDK 를 받아 flutter_app 을 웹으로 빌드한다.
# 결과물(flutter_app/build/web)은 vercel.json 의 outputDirectory 로 배포된다.
set -euo pipefail

FLUTTER_VERSION="3.50.0"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if command -v flutter >/dev/null 2>&1; then
  FLUTTER=flutter                       # 로컬처럼 Flutter 가 이미 있으면 그대로 사용
else
  SDK_DIR="${FLUTTER_SDK_DIR:-$HOME/flutter-sdk}"
  if [ ! -x "$SDK_DIR/flutter/bin/flutter" ]; then
    # Flutter 가 웹 엔진 아티팩트를 풀 때 unzip 이 필요하다 (Vercel 빌드 이미지는 dnf 사용 가능)
    command -v unzip >/dev/null 2>&1 || dnf install -y unzip >/dev/null
    mkdir -p "$SDK_DIR"
    echo "Downloading Flutter $FLUTTER_VERSION ..."
    curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      | tar -xJ -C "$SDK_DIR"
  fi
  git config --global --add safe.directory "$SDK_DIR/flutter"
  FLUTTER="$SDK_DIR/flutter/bin/flutter"
fi

cd "$ROOT/flutter_app"
"$FLUTTER" --version
"$FLUTTER" config --no-analytics >/dev/null
"$FLUTTER" pub get
"$FLUTTER" build web --release
