# PLAN v55 — 수동 스크롤 핀 해제 (macOS, T-260)

## 1. 목표

* 수동 휠 스크롤 시 맨 아래로 버튼이 안 뜨던 문제 수정.
* 원인: 휠 핸들러가 시각만 기록, 핀 해제는 앵커 관측자에만 의존 (stale).

## 2. 변경

* `ChatScrollActions.installWheelMonitor`: 스탬프 발생 시 `reconcilePin()` 실측 1회 +
  해제 로그 1줄. 기존 순수함수 재사용, 회귀 추가 없음.
* TODO·CHANGELOG·session 기록.

## 3. 검증

* unit 유지 + lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: 수동 상승→버튼→클릭 복귀→소멸, 목차 점프 회귀.
