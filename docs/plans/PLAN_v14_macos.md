# PLAN v14 — NSWindow.title 직접 동기화로 좌측 타이틀 표시 (macOS, T-142)

## 1. 목표

T-141 기각: 0.7.84 실측에서 사이드바 `.navigationTitle`이 툴바에 무반영.
좌측 "LiteRT-LM Studio"는 `Window(...)` 타이틀 문자열임을 확인 → NSWindow.title 직접 갱신.

## 2. 변경

1. `LiteRTLMStudioApp.swift`: `WindowTitleSync` 신규 (WindowAccessor T-092 선례, 변경 때만 title 갱신).
2. `ContentView.swift`: 루트 Group에 `.background { WindowTitleSync(title: roomTitle) }`.
   무효한 사이드바 `.navigationTitle` 2곳 제거. 중앙 principal은 모델 정보 유지.
3. 문서: TODO T-142 + CHANGELOG 0.7.85 + 본 PLAN. T-141 기각 기록.

## 3. 검증

* unit + lint 신규 0 + `build macos` 설치. 눈확인: 좌측이 방 전환·이름 변경·드래프트 따라 변경.
