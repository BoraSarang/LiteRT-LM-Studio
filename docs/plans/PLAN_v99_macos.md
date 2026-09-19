# PLAN_v99 — 2차 UI 버그픽스 (T-325, macOS)

> UI 텍스트/레이아웃/툴팁만. 로직 동결. 사용자 결정: 현 파일 직접 수정 /
> 반복 페널티 제외 / 시맨틱 토큰 대체 / 인스펙터 탭 DSSegmented 교체.
> "종지" 0건 스킵. RightPanel.swift 없음 → InspectorView.swift 등 현 파일 수정.

## P0

* 환경 단축: `uv 0.11.29 (Homebrew)` → UI `uv 0.11.29` + 툴팁 전체
  (순수 헬퍼, `parseVersion` 활용, unit). litert-lm 동일.
* 세션 제목·벤치 행: `.help(전체)` 추가 (1줄 유지).
* 웰컴 하단: bottom inset 보강 (48).
* 필터 `전체`→`전체 기록` (tag·기본값·`filtered` 센티널·test).
* `powerLine`: `MTP 켬 · 배터리 충전 중 (95%)` 형식 + ⓘ 툴팁
  "배터리 절약 모드에서는 추측적 디코딩(MTP) 가속이 제한됩니다" (test 갱신).
* `tok/s`→`토큰/초` 전수 (`summary`·`perfLine`·test).

## P1

* GPU 문구→ⓘ 아이콘, CPU Legend (파랑=사용자·빨강=시스템).
* KV 캡션 교체, MTP ⓘ (실행/설정), 외관→테마 모드, 전송경로·턴 툴팁,
  채팅/도구 탭 ScrollView + bottom 32.

## 인스펙터

* 탭 → DSSegmented + 아이콘 (100%×32). AGENTS.local 예외 갱신.
* Sticky 하단 적용바: `변경 사항이 있습니다` + [취소|적용] (기존 인라인 바 이동).

## 검증

* unit 갱신 + 회귀, lint 신규 0, build, 눈확인 4화면.
