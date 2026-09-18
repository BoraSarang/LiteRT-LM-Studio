# PLAN_v95 — 웹 도구 칩 표시 개편 (T-317, macOS)

> `ToolCallChipView` (`MessageBubbles.swift`) 전용. 발췌 URL이 항상 펼쳐져
> 대화를 밀어내던 문제. 기본 접힘 + 한글 명칭.

## 변경

* 표시명 매핑 (순수, `ToolCallRecord.displayTitle`):
  `web_search`→"웹 검색", `web_fetch`→"웹 가져오기", 그 외 원문 이름 유지.
* 대표 인자 (순수, `displayArg`): `argumentsJSON`에서 `query`/`url` 값만 추출
  표시. 파싱 실패 시 기존 `summary`(80자) 폴백.
* 접기/펼치기: 결과 본문 기본 숨김, 헤더 탭으로 토글
  (`ThinkingBlockView` 동일 패턴, `@State open=false`).
* `web_fetch` 한정 외부열기 버튼 (`arrow.up.right`, http(s)만,
  `NSWorkspace.shared.open` — 비(非)뷰 API라 AGENTS.local 예외 범위).

## 비목표

*他 도구 칩 레이아웃 변경 없음 (타이틀 매핑만 공유, 접힘은 결과 있을 때만 적용).
* 상태 아이콘·문구 변경 없음.

## 검증

* 신규 unit 3건 (displayTitle/displayArg/URL 가드) + 기존 회귀.
* 눈확인: 접힘 기본·펼침·외부열기 (사용자).
