# PLAN v58 — Spotlight식 커맨드 팔레트 + 전체 채팅 검색 (macOS, T-263)

## 1. 목표

* 고정 버튼식 팔레트를 Spotlight식 통합 검색창으로 교체 (명령 필터+전체 채팅 검색).
* 채팅 결과 Enter → 방 전환 후 해당 대화 스크롤+플래시. `⌘K` 실배선.

## 2. 변경

* `Core/ChatSearch.swift` (신규): `ChatSearchHit`+`search` 순수함수
  (대소문자 무시·2자 미만 제외·질문/응답·문맥 20자·방 최신순·8건 cap).
* `PaletteViews.swift` (개조): `PaletteView` → 검색창+명령 섹션+채팅 섹션,
  ↑↓·Enter·Esc, 자동 포커스. `AliasSheetView` 유지.
* `ChatPaneView`: `.sheet` → `mainSplit` 오버레이, `jumpToMessage` 추가
  (전환+0.15초 후 `jumpToOutline` 재사용). 스트리밍 중 이동 불가.
* `ContentView`: 툴바 버튼 `⌘K` 배선.

## 3. 검증

* unit 5건+기존 유지, lint 신규 0, `build macos` 2회, DebugPanel ERROR 0.
* 눈확인: ⌘K→명령 필터→Enter / 검색→전환+스크롤+플래시 / Esc / 스트리밍 가드.
