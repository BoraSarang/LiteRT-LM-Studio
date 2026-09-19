# PLAN_v105 — README 멀티라인 HTML 블록 제거 (T-331, macOS)

> 증상: 모델 설명의 `<svg>` 블록이 파란 링크 텍스트로 렌더됨.
> 원인: `consumeTagLine`은 `<` 시작 줄만 처리, `>` 없이 끝난 줄(블록 시작)과
> 후속 path 줄이 문단으로 흘러 자동 링크화됨.

## 변경 (렌더·표 로직 불변)

* `ProseAccumulator.htmlSkipTag` 추가 + `consumeHtmlBlock` 신규
  (`NativeMarkdownHTML.swift`):
  닫히지 않은 `<태그` 시작 줄 → `</` 포함 줄까지 통째로 스킵.
  `<table>` 누적 중에는 진입 금지, `<br/>`·한 줄 완성 태그는 기존 경로,
  `<3` 같은 비태그는 그대로 두기.
* unit: svg 블록 전체 제거·한 줄 태그 유지·`<3` 보존·표 회귀.

## 검증

* 신규 unit 3건 + 280 회귀, lint 신규 0, build, 눈확인(모델 설명).
