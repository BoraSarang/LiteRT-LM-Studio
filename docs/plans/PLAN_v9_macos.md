# PLAN v9 — 새 채팅 드래프트 방식 (macOS, T-137)

## 1. 목표

"새 채팅" 클릭으로는 방을 만들지 않고, 첫 메시지 전송 시점에 방이 생기며
사이드바에 선택 표시됨.

## 2. 상태 모델

* 드래프트 = `currentSessionID == nil` (messages 비어 있음, 영속 안 됨).
* 방이 있으면 실행 시 마지막 방 복원(현행 유지). 방이 0개면 드래프트로 시작.
* 드래프트 중 종료 → 휘발, 재실행 시 마지막 실제 방.

## 3. 동작 명세

* 새 채팅 클릭 (방 있음): 방 생성 없음. 버튼만 틴트, 입력창 키보드 포커스.
* 새 채팅 클릭 (이미 드래프트): 무시.
* 첫 메시지 전송: 그때 방 생성 → 행 등장 + 선택 표시, 버튼 포커스 해제.
* 드래프트 중 기존 방 클릭: 그대로 전환. 전부 삭제: 드래프트로 복귀.
* ⌘N / 팔레트 / 메뉴: 모두 드래프트 시작 + 입력 포커스.

## 4. 비주얼

* 평상시 버튼: fill 제거素 텍스트+plus (`controlColor` 배경 삭제).
* 드래프트 활성: 기존 행과 동일한 틴트 (`accentColor.opacity(0.15)`), 방 0개 실행 직후 포함.

## 5. 파일별 변경

1. `ChatStore+Session.swift`: `startDraft()` 신규. `newSession()` 삭제,
   호출 3곳(`init` 빈 저장소·`deleteSession` 전멸·`clear()`)을 `startDraft()`로 교체.
   `send()` 선두에 `ensureSessionForSend()`.
2. `SessionListView.swift`: 버튼 액션→`chat.startDraft()` + 틴트 조건 `currentSessionID == nil`.
3. 포커스: 신규 `.focusChatInput` Notification. `ContentView`에 `@FocusState`,
   `ChatInputBar`에 바인딩 + `.focused`. 드래프트 시작 3곳에서 발행.
4. `ChatPaneView.swift`: nil 진입 시 `sessionJump` 스킵 (빈 뷰 5초 공회전 방지).
5. 테스트: `testChatSessions` 드래프트 기준 갱신 + 신규 3종.
6. 문서: DESIGN 사이드바 절 → CHANGELOG + 0.7.80.

## 6. 주의·위험

* `send()` 실패 시 생성된 방에 에러 버블 잔류 — 현행과 동일하므로 허용.
* nil 세션 `entryPoll` 통과 가드 존재 → 4번 스킵 가드로 차단.

## 7. 검증

* unit 81→83종 목표, lint 신규 0, `build_and_run.sh build macos`.
* 눈확인: 방 미생성+틴트+포커스 / 첫 전송 행 등장+선택 / 드래프트 종료→마지막 방.
