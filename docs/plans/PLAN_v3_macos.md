# PLAN v3 — 채팅 다듬기 (macOS)

> 기준: `/Users/lee/Documents/Apps/AIModelTalk` 채팅 방식 이식. 문서 우선 순서 준수.
> AGENTS.local 예외 승인: T-029 마크다운용 WKWebView(NSViewRepresentable) 1건 (읽기 전용 렌더, 뷰 직접 조작 없음).

## 1. 목표

현재 단색 카드+`TextField` 단발+매 토큰 강제 점프(`ContentView.swift:245-301`)를
AIModelTalk식으로: 좌우 버블+푸터 액션 → WKWebView 마크다운 → 멀티라인 입력바 → Sticky-Pin 스크롤 → 세션/영속.

## 2. 현 상태 (2026-09-14)

* `ChatStore`: 단일 `messages` 배열, `role/text/perf` 3필드 (`Core/ChatStore.swift:6-16`).
* 버블: 역할 라벨+단색 카드, 복사/재시도 없음 (`ContentView.swift:552-579`).
* 입력: `TextField`+`onSubmit`, 스트리밍 중 비활성 (`:289-298`).
* 스크롤: 매 토큰 `proxy.scrollTo` 강제 (`:268-270`) — 위로 올린 채로 읽을 때 끌려내려감.
* 세션 없음: 새 채팅=전체 삭제.

## 3. 단계

* T-028 말풍선: `UserBubble(우측)`/`AssistantBubble(좌측)` 분리 + 복사/재시도 푸터 + 에러 테두리. PERF 뱃지 유지.
* T-029 마크다운: WKWebView 높이피팅 + 스트리밍 `appendChunk` + 완료 시 전체 리로드. AGENTS.local 예외 1줄 추가.
* T-030 입력바: `TextEditor` 멀티라인 + Return 전송/Shift 줄바꿈/Cmd+. 중단 + 첨부 썸네일 유지 + 전송/중단 버튼.
* T-031 스크롤: Sticky-Pin (하단 고정 시만 추종, 위로 올리면 해제). NSScrollView 절대좌표.
* T-032 세션/영속: 세션 목록 + JSON 파일 영속 (SwiftData 미도입, 경량). 새 채팅=세션 생성.

## 4. 검증

* 각 단계: `./build_and_run.sh test macos unit` + `build macos` + 눈 확인.
* 회귀 테스트: 복사/재시도 등 순수 로직 위주 (렌더·스크롤은 눈 확인).

## 5. 성능 예산

* PLAN v1 §5 유지: Cold Start ≤1.5s, 60fps, 앱 셸 ≤300MB, 캐시 히트 ≥70%.
* 마크다운 WebView는 메시지당 1개, 스트리밍 중 전체 리로드 금지 (appendChunk만).
