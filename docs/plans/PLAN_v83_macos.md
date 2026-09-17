# PLAN v83 — 새소식 앱 저장소 합류 (T-294)

## 1. 목표

* 새소식 피드에 `BoraSarang/LiteRT-LM-Studio` 합류 + 웰컴 추천 링크 추가.
* 현재 앱 릴리즈 `[]` 확인됨 → 빈 결과·조회 실패는 조용히 스킵.

## 2. 변경

* `AppRelease.source` (`.engine`/`.app`) 추가, `id`=source+tag.
  디코딩·생성자 기본값 `.engine` (구 캐시·기존 테스트 무수정).
* `ReleaseNotes`: URL 2개 순차 조회→source 태깅→`merge()`.
  앱 쪽 빈·실패·비200은 info 로그만. `E-MAC-NET-0014`는 양쪽 실패 시만.
* `merge()` 중복 키 tag → source+tag. cap 20 합산 유지.
* 업데이트 판정 (`newerStable`·`latestStable`) → 엔진만 (버전 체계 충돌 방지).
  `featured` 3건은 양쪽 합류.
* `WelcomeLink.all` 앱 저장소 1행 ("LiteRT-LM Studio", 앱 소스·이슈, 지정 URL).

## 3. 검증

* unit: source 기본값·cross-source 병합·newerStable 앱 무시·빈 merge 4건 + 기존 유지.
* lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: 엔진 3건 정상 표시·에러 없음, 링크 클릭 → 지정 주소.
