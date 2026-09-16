# PLAN v59 — 한글 검색 강화: 초성 + 띄어쓰기 무시 (macOS, T-264)

## 1. 목표

* 초성(`ㅁㅅㅈ`→"무슨지")·혼용(`ㄹ테일`)·띄어쓰기 무시(`리테일전략`↔`리테일 전략`).
* 외부 라이브러리 없음, 오프라인 안전. 채팅 검색에만 적용.

## 2. 변경

* `Core/ChatSearch.swift`: `KoreanMatch` 순수 묶음 (초성 추출+슬라이딩 자소 비교+
  매칭 범위) + `search`·`contextPreview` 내부 교체. 정렬·cap 유지.
* `PaletteViews.swift`: 플레이스홀더 문구 1줄.

## 3. 검증

* unit 6건+기존 유지, lint 신규 0, `build macos` 2회, DebugPanel ERROR 0.
* 눈확인: ⌘K 초성·혼용·붙여쓰기 검색+미리보기.
