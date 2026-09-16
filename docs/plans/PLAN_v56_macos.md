# PLAN v56 — 후속질문 칩 (macOS, T-261)

## 1. 목표

* 응답 완료 후 해당 응답 기반 후속질문 3~4개를 어시스턴트 버블 직하·우측 정렬 칩으로 표시.
* 설정 > 채팅 탭에 `후속 질문 사용` 토글 (기본 켜짐).
* 추가 LLM 호출 없음 (로컬 휴리스틱, 토큰·지연 0).

## 2. 변경

* `FollowUpSuggest.swift` (신규): `suggestFollowUps(for:max:)` 순수함수.
  빈/짧은 응답→고정 4종, 긴 응답→키워드 2개+템플릿 조합 3~4개, 중복 제거·30자 절단.
* `FollowUpChipsView` (신규, `MessageBubbles.swift` 하단 또는 별도): 우측 정렬 캡슐 칩 행.
  `HStack { Spacer(minLength:60); chips }`, accent 틴트, 클릭 즉시 `chat.send`.
* `ChatPaneView.messageRow()`: 마지막 어시스턴트(`m.id == messages.last?.id`) 아래에만 조건부 삽입.
  조건: 토글 ON + 완료(`!streaming && !preparing`) + 비어있지 않음 + `!isError`.
* `ContentView`: `@AppStorage("followUpEnabled")` 선언, messageRow 전달.
* `SettingsView` 채팅 탭: Toggle 1건 + DebugLogger 로그.
* 클릭 로그: `[INFO] [후속질문] 전송` 1줄. 에러코드 없음.

## 3. 검증

* unit: 빈/짧음/김/중복/길이 5건 + 기존 유지.
* lint 신규 0 + `build macos` + DebugPanel ERROR 0.
* 눈확인: 완료→칩 우측 표시→클릭 전송→스트리밍 숨김→OFF 숨김→에러 미표시.
