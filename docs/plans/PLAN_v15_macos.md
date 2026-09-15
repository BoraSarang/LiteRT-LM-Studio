# PLAN v15 — 빈 화면 서버 상태별 2종 문구 (macOS, T-143)

## 1. 목표

빈 방 진입 시 서버 상태에 따라 문구 분리: 중지=서버 시작 안내(기존), 실행 중=환영형.

## 2. 변경

1. `ChatPaneView.swift`: 순수 헬퍼 `emptyStateCopy(isRunning:)` + `chatPane` 빈 분기에서
   `daemon.status == .running`으로 선택 (ContentView가 daemon 관찰 중이라 자동 갱신).
2. 테스트: `testEmptyStateCopy` 2종 회귀 (84종 목표).
3. 문서: TODO T-143 + CHANGELOG 0.7.86 + 본 PLAN.

## 3. 검증

* unit + lint 신규 0 + `build macos` 설치. 눈확인: 서버 중지/실행 각 빈 방 문구 + 전환 시 자동 변경.
