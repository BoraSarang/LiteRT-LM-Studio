# PLAN v82 — 인스펙터 데몬 히어로 카드 완전 삭제 (T-293)

## 1. 목표

* CPU 위 데몬 통계 카드가 양 경로에서 무의미 → route 무관 완전 삭제.
* LIVE 행 + CPU/RAM/GPU 미터만 남김.

## 2. 변경

* `SystemMetersView`: 히어로 VStack(39~77행)·`daemonChart`·`nativeDaemonCaption` 삭제.
  파일 독 주석의 "데몬 히어로 유지" 문구 수정.
* `SystemMonitor` 샘플링 유지 (`E-MAC-NET-0010` 진단 로그가 `daemonPidCount` 기반).
* 테스트: `testNativeDaemonCaption` 삭제. `daemonCPUPercent` 군 유지.

## 3. 검증

* unit 전체 + lint 신규 0 + `build macos` + DebugPanel ERROR 0.
* 눈확인: 양 경로 카드 소실, CPU/RAM/GPU 정상, 서버 중지 시 E-MAC-NET-0010 로그 유지.
