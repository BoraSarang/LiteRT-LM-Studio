# PLAN v57 — 메인 웰컴 페이지 (macOS, T-262)

## 1. 목표

* 빈 채팅 화면을 웰컴(환영+새소식+업데이트+추천 링크)으로 교체.
* 새소식: GitHub Releases 라이브 조회+JSON 누적 캐시 (오프라인 폴백).
* 업데이트: 신버전 감지 시 `uv tool upgrade litert-lm` 확인 팝업 후 실행.

## 2. 변경

* `Core/ReleaseNotes.swift` (신규): `AppRelease` 모델+`parseReleases`·`summaryLines`·
  `compareVersions` 순수함수+`ReleaseNotes` 스토어 (페치·6시간 가드·20건 cap·원자 저장).
* `WelcomeView.swift` (신규): 환영+환경 1줄+새소식 3건+업데이트 행+링크 4행+축소 안내.
* `ChatPaneView`: 빈 화면 분기 → `WelcomeView`.
* `AppServices`+`ContentView`+`LiteRTLMStudioApp`: `releases` 공유 인스턴스 전달.
* `error_message_ko.json`: `E-MAC-NET-0014` (소식 조회 실패), `E-MAC-ENG-0003` (업데이트 실패).

## 3. 검증

* unit 6건 (파서·요약·버전비교·신버전 판정) + 기존 유지.
* lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: 웰컴→새소식→업데이트 팝업→외부 링크→오프라인 캐시→채팅 후 소멸.
