# PLAN v29 — 스트리밍 미완성 마커 숨김 + full + 병합 (macOS)

## 1. 목표

잔여 4건 일괄: T-194 마커 깜빡임, full 스위트, 브랜치 병합, 첫 전송 8초 점검.

## 2. 변경

* T-194: `NativeMarkdown.hidePendingStrong` (순수): 홀수 `**`면 마지막 마커만
  표시 제외 (내용은 평문 유지). `proseBody`에서 isStreaming일 때 적용.
  코드 블록(펜스 분리済)은 제외.
* full: `test macos full` 실행 (E2E는 미해당).
* 병합: `chore/macos-commit-0.7.115-0.7.129` → main (fast-forward 가능 시).
* 첫 전송 8초: 추가 코드 변경 없이 원인 명시 (방당 1회 풀 프리필).
  축소 수단은 전송 범위 설정(사용자 값)이라 기본값 변경은 하지 않음.

## 3. 검증

* unit 103+α + lint 신규 0 + `build macos` 설치·눈확인(스트리밍 볼드).
