# PLAN_v94 — web_search 1위 본문 자동 첨부 (T-316, macOS)

> 3분 초안 (소규모 수정). 실측 계기: 서버 경로 E2B에서 `web_search`는 동작하나,
> 발췌(제목+URL+300자)에 답이 없으면 모델이 `web_fetch` 후속 호출 없이 종료함
> ("직접 방문하세요", 2026-09-18 실측 2건). 작은 모델 follow-through 한계.

## 변경 (1곳)

* `WebSearchTool.run` (`Core/WebSearch.swift`): hits 반환 후 1위 URL 본문을
  자동 fetch해 결과 문자열에 첨부. fetch 실패·빈 본문이면 검색 목록만 반환
  (기존 동작 유지, 2턴 절약이 목적이지 강제 아님).
* `WebSearch.autoFetchCap = 2000` (fetchCap 8192와 분리 — 컨텍스트 절약).
* 순수 합성 함수 `combinedForModel(hits:topBody:)` 분리 → 단위 테스트.

## 비목표

* N위 전체 fetch (토큰·지연 폭증) — 1위만.
* 프롬프트/턴 루프 변경 — S-3 3턴 그대로.
* 네이티브 FC 게이트 변경 — 무관.

## 에러·로그

* 신규 error_code 없음. fetch 실패는 기존 `E-MAC-NET-0015` 로그 후 조용히 생략.
* 칩 표시는 기존 그대로 (detail=질의).

## 검증

* 신규 unit 3건 (본문 있음/없음/cap 절단) + 기존 272건 회귀.
* `build_and_run.sh test macos unit` + swiftlint 신규 0 + `build macos`.
* 실전: "LiteRT-LM 최신 버전" 1턴 답변 확인 (사용자).

## 문서

* TODO T-316, CHANGELOG Unreleased 1건, TOOLCALL_TEST 13번 기대값 ("1위 본문 자동 첨부") 1행.
