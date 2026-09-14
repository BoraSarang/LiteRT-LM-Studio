#!/bin/zsh
# build_and_run.sh — LiteRT-LM Studio (macOS)
# 서브커맨드: build {macos} / test {macos} {smoke|unit|full} / e2e (미해당, serve 스파이크는 수동)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJ="$ROOT/LiteRTLMStudio.xcodeproj"
SCHEME="LiteRTLMStudio"
DEST="platform=macOS"

cmd="${1:-build}"; target="${2:-macos}"; level="${3:-unit}"
APP_NAME="LiteRTLMStudio"
APP_DIR="LiteRT-LM Studio"
APP_BUNDLE_ID="com.borasarang.litert-lm-studio"
OLD_APP_NAME="LiteRTLM-Manager"

if [[ "$target" != "macos" ]]; then echo "지원 대상: macos (입력: $target)"; exit 2; fi

quit_app() {
  # 구 이름 프로세스도 함께 종료 (T-060 개명 이행).
  for name in "$APP_NAME" "$OLD_APP_NAME"; do
    if pgrep -xq "$name"; then
      echo "실행 중인 $name 종료 중…"
      osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || \
        osascript -e "tell application \"$name\" to quit" >/dev/null 2>&1 || true
      for _ in $(seq 1 20); do
        pgrep -xq "$name" || break
        sleep 0.5
      done
      pgrep -xq "$name" && { echo "정상 종료 실패 → 강제 종료"; pkill -x "$name" || true; sleep 1; }
    fi
  done
  pgrep -xq "$APP_NAME" || echo "앱 종료됨"
}

find_app() {
  find ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-* -name "$APP_NAME.app" -maxdepth 5 2>/dev/null | head -n 1
}

install_app() {
  local src="$1"
  # 구 이름 잔재 제거 (T-060 개명 이행).
  [[ -d ~/Applications/$OLD_APP_NAME.app ]] && rm -rf ~/Applications/$OLD_APP_NAME.app
  [[ -d ~/Applications/$APP_NAME.app ]] && rm -rf ~/Applications/$APP_NAME.app
  # Finder 표시 규칙: 번들 폴더명 = CFBundleDisplayName (T-061).
  [[ -d ~/Applications/"$APP_DIR".app ]] && rm -rf ~/Applications/"$APP_DIR".app
  cp -R "$src" ~/Applications/"$APP_DIR".app
  echo "설치됨: ~/Applications/$APP_DIR.app"
}

case "$cmd" in
  build)
    quit_app
    # set -e: 빌드 실패 시 여기서 중단, 앱 실행 안 함
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -destination "$DEST" build
    APP="$(find_app)"
    [[ -z "$APP" ]] && { echo "빌드 결과물을 찾을 수 없음"; exit 1; }
    install_app "$APP"
    echo "앱 실행 중…"
    open ~/Applications/"$APP_DIR".app
    ;;
  test)
    case "$level" in
      smoke)
        xcodebuild test -project "$PROJ" -scheme "$SCHEME" -destination "$DEST" -only-testing:LiteRTLMStudioTests/LiteRTLMStudioTests/testDaemonDefaults
        ;;
      unit|full)
        xcodebuild test -project "$PROJ" -scheme "$SCHEME" -destination "$DEST"
        ;;
      *) echo "레벨: smoke|unit|full"; exit 2;;
    esac
    if command -v swiftlint >/dev/null 2>&1; then swiftlint --quiet "$ROOT/LiteRTLMStudio" || true
    else echo "[WARN] swiftlint 없음 — 건너뜀"; fi
    ;;
  install)
    APP="$(find_app)"
    [[ -z "$APP" ]] && { echo "빌드 결과물을 찾을 수 없음. 먼저 ./build_and_run.sh build macos"; exit 1; }
    install_app "$APP"
    ;;
  *) echo "사용법: $0 {build|test|install} macos [smoke|unit|full]"; exit 2;;
esac
