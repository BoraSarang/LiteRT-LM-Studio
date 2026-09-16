# PLAN v54 — 대화 목차 플로팅 (macOS, T-258)

## 1. 목표

* 채팅 우측 중앙 플로팅 목차: 축소 바 3개 → 호버 확장 → 질문 목록 → 클릭 점프+플래시.
* 설정 채팅 탭에 사용 토글 (기본 켬).

## 2. 변경

* `ChatOutlineView.swift` 신규: `ChatOutlineEntry` + 순수 추출(사용자 첫 줄 40자,
  빈값은 이미지 첨부) + 플로팅 본체(호버 확장 애니메이션).
* `ChatPaneView`: 스크롤 오버레이 부착 + 점프(핀 해제+휠 시각 갱신+scrollTo) +
  행 배경 플래시 1.5초.
* `ContentView`: `outlineEnabled` AppStorage + `outlineFlashID` 상태.
* `SettingsView`: 채팅 탭 신설 + 토글.
* 회귀 3건: 첫 줄 추출·빈 목록·이미지 문구.

## 3. 검증

* unit 156+3 + lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: 축소/확장·점프·플래시·토글 off·빈 방 숨김·스트리밍 중.
