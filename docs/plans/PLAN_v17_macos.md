# PLAN v17 — 네이티브 모드 데몬 표시 + 입력 게이팅 (macOS, T-146)

## 1. 목표

네이티브 모드에서 데몬 CPU 0% 오해 해소 + 데몬 없이 입력 가능.

## 2. 분석

* 측정값 정상: 네이티브 추론·벤치마크는 프로세스 내 (`usesNative`, `nativeBenchmark`).
  `:9379` 데몬은 우회되어 유휴 0%·0.03GB가 맞고, 모델은 앱 상주(4.61GB)에 있음.
* 표시: 히어로 "데몬 CPU 0%"가 주인공이라 오해 (T-133 앱 상주 행은 조연).
* 게이팅: 입력 3곳이 데몬 필수라 네이티브 준비 상태でも 데몬 끄면 입력 불가.

## 3. 변경

1. `SystemMonitorView.swift`: 네이티브면 히어로 "네이티브 (프로세스 내)+앱 상주",
   데몬은 캡션급 "대기 중/없음" (`nativeDaemonCaption` 순수 헬퍼). CLI 분기 불변. 차트 유지.
2. `ChatStore+Native.swift`: `sendAllowed(streaming:daemonRunning:nativeReady:)` 순수 헬퍼.
3. `ChatInputBar.swift`: `canSend` 계산 속성으로 3곳 교체. CLI는 기존과 동일 조건.
4. 테스트: `testSendAllowed` 5항 + `testNativeDaemonCaption` 2항 (86종 목표).
5. 문서: TODO T-146 + CHANGELOG 0.7.93 + 본 PLAN.

## 4. 검증

* unit + lint 신규 0 + `build macos` 설치.
* 눈확인: 네이티브+데몬 on (히어로·대기 표기), 네이티브+데몬 off (입력·전송 동작),
  CLI (기존 동일).
