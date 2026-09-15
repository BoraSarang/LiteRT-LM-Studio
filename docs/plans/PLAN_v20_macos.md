# PLAN v20 — 채팅 마크다운 네이티브 전환 (macOS, T-150)

## 1. 목표

행당 WKWebView + JS 높이 push 구조를 제거하고 네이티브 텍스트 렌더로 교체.
마지막줄 미추종·빈방 노출·출렁의 공통 분모(높이 비동기 + 점프 3경로 경쟁) 원천 해소.

## 2. 근거 4종 (읽기 전용 실측)

* fazm (`mediar-ai/fazm`): `MarkdownUI Markdown(text)` + `AttributedString(markdown:)` + `Highlightr(atom-one-dark)`, 리스트 `ScrollView+VStack`, 추종 `onChange(count)→scrollTo(bottom)`. WKWebView 없음.
* osaurus (`osaurus-ai/osaurus`): `NativeMarkdownView`(AppKit TextView, `usedRect` 실측) + `NSTableView + DiffableSnapshot` + `ScrollAnchorManager`. 본문 웹뷰 없음(차트만 예외).
* cherry-studio (`CherryHQ/cherry-studio`): `streamdown + StreamingMarkdown(parseIncompleteMarkdown)` + `virtua Virtualizer` + `useAutoStickToBottom`. `react-markdown` 없음.
* gallery (`google-ai-edge/gallery`, Android만 공개): `MarkdownText/BufferedFadingMarkdownText` 네이티브, 웹뷰는 `ChatMessageWebView` 전용. 맥/iOS 소스 미공개(dmg·App Store 바이너리), 루트에 `Android/`만 존재.

## 3. 변경 (B안)

1. `MarkdownView/WebView/Coordinator/Page` 웹뷰 경로를 `MarkdownUI + AttributedString + Highlightr`로 교체.
2. 높이 JS push·`heightCacheAgnostic`·`prewarmPane`·`NoScrollWKWebView` 휠 포워딩 삭제. SwiftUI 자동 높이로 진입 `scrollTo(bottom)` 1회 확정.
3. `AGENTS.local.md` T-029 WKWebView 예외 1줄 회수.
4. 선행 스파이크(동등성 4종): 표·코드강조·한글볼드(T-066)·줌(T-070). 미달 시 본전환 보류.
5. 테스트: 스파이크 판정 4항 + 추종 1회·빈방 무복귀 회귀 (90종대 목표).

## 4. 비범위

* C안(NSTableView + diffable)은 보류. 수백 메시지 성능 문제 확인 시 재검토.
* A안(점진)은 스파이크 미달 시 폴백.

## 5. 검증

* unit + lint 신규 0 + `build macos` 설치.
* 눈확인: 마지막줄 추종·빈방 미노출·긴 방 출렁 해소, 표/코드/볼드/줌 동등.
