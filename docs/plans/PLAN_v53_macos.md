# PLAN v53 — 온보딩 게이트 랜딩 (macOS, T-257)

## 1. 목표

* 첫 실행 랜딩에서 uv·litert-lm 설치 확인 후 시작 (명세서 §3).
* 자동 설치는 후속 (수동 안내+복사+재확인 우선, §6).

## 2. 변경

* `Core/OnboardingGate.swift` 신규: 버전 파싱·최소버전 비교 순수함수.
  최소버전 0.14.0, 미달은 경고만 (차단 아님).
* `LandingView.swift` 신규: uv·litert-lm 행(✓/✗+버전), 미설치 안내
  (`uv tool install litert-lm`+복사)+재확인, 시작하기(둘 다 ✓일 때만).
* `LiteRTLMStudioApp`: `onboardingDone` AppStorage 분기 (랜딩/메인).
  ContentView 복원 시 uv 없으면 게이트로 복귀.
* 회귀: 버전 파싱·최소비교 2건.

## 3. 검증

* unit + lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: 게이트 표시·재확인·시작 활성·재실행 스킵·uv 삭제 시 복귀.
