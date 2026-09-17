# PLAN v80 — 후속질문 칩 LLM 호출 전환 (T-291)

## 1. 목표

* 키워드 빈도 휴리스틱(`suggestFollowUps`) → 응답 완료 후 LLM 1회 호출로 맥락 있는 후속질문 3개.
* 칩 자리 lazy 호출 (로딩 스켈레톤→도착 시 교체), 현재 채팅 경로 그대로, 실패 시 기존 휴리스틱 조용히 폴백.

## 2. 변경

* `FollowUpSuggest.swift`: `prompt(question:answer:)` (Q/A 각 2000자 절단) + `parseFollowUps(from:max:)` 순수 파서 (번호/불릿/따옴표/JSON 배열 수용, 빈 제거·중복 제거·30자 절단) + `@MainActor FollowUpStore` (messageID·loading·chips, 중복 가드·취소·적용 가드).
* 서버 route: `POST v1/chat/completions` (`stream:false`, `max_tokens:150`, `temperature:0.7`, tools/extras 제외, 타임아웃 30초). 컨텍스트는 마지막 Q/A 1턴만.
* 앱 내 엔진 route: `engine.stream` 1회성 호출 (history 없음, 고유 keyHistory로 재사용 강제 회피, 도구 미등록 옵션) + 호출 전후 `activeConversation`/`activeKey` 스냅샷 복원 (본 대화 KV 보존). 파싱 0건·실패는 휴리스틱 폴백.
* `ContentView`: `@StateObject followUps` 1줄. `ChatPaneView.messageRow`: 로딩=스켈레톤, 완료=LLM 칩, 실패·미요청=휴리스틱. `onAppear` 1회 요청 (마지막 완료 응답만, 기존 `shouldShowFollowUp` 게이트 재사용).
* 로그: `[INFO] [후속질문] 요청/완료(개수·소요ms)/실패(사유)`. 에러코드 신규 없음 (사용자 노출 실패 없음).

## 3. 검증

* unit: 파서 7건 (번호/불릿/JSON/빈/따옴표/초과·30자/중복) + 프롬프트 절단 1건 + 기존 유지.
* lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: 완료→스켈레톤→칩 3개→클릭 전송→스트리밍 숨김→실패 시 휴리스틱→방 전환 시 이전 요청 미표시.
