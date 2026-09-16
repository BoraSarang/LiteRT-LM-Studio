# PLAN v42 — MTP 기본 OFF+벤치마크 전원 경고 (macOS)

## 1. 목표

12B+MTP 풀가동 발열·배터리 급감 (실측: 수 분에 5~10%) 대응. T-222 1건.

## 2. 변경

* `ConfigStore`: `appliedMTP/draftMTP` 초기값 true→false. 파일 명시된 모델은 그대로 존중.
  기존 `gemma4-12b`처럼 파일에 `true`가 박힌 모델은 인스펙터에서 수동 끔 필요.
* 벤치마크 창 상태 한 줄: `ConfigStore.savedMTP` 파일 직독 + `pmset -g batt` 배터리.
  MTP 켬 또는 20% 이하 방전 중이면 주황 경고, 아니면 회색 정보.
* `BatteryStatus.parse/powerLine` 순수 분리 + 회귀 테스트.
* `BenchmarkWindowSections.swift` 신규 (창 섹션 분리, 파일 길이 분산) + pbxproj 등록.

## 3. 검증

* full 123/123 + lint 신규 0 + build 설치. 눈확인: 벤치마크 창 상태 줄·MTP 끔 기본.
* PERF/CACHE 영향 없음 (pmset 1회성, 측정 중 폴링 없음).
