# PLAN v19 — 전송 히스토리 범위 설정 (macOS, T-149)

## 1. 목표

매 전송 전량 전달을 범위 설정으로 조절: 제한 없음(기본·기존 동일) / 10·20·40턴.

## 2. 변경

1. `InferenceEngine.swift`: `HistoryWindow` (키 "historyTurns", 0=제한 없음, `currentTurns()`).
2. `ChatStore.swift`: 순수 헬퍼 `windowedHistory(_:turns:)` (0 이하면 전량).
3. `chatRequest` + `runNative` 히스토리 조립부에 적용. 방 기록·방 이름·재시도 불변.
4. `SettingsView.swift` 일반 탭 Picker + help + 전환 로그.
5. 테스트: `testWindowedHistory` 7항 (89종 목표).
6. 문서: TODO T-149 + CHANGELOG 0.7.96 + 본 PLAN.

## 3. 검증

* unit + lint 신규 0 + `build macos` 설치.
* 눈확인: 기본 제한 없음(기존 동일), 10턴 전환 시 긴 방 TTFT 단축, 재실행 유지.
