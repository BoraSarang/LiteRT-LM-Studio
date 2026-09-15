# PLAN v13 — 사이드바 타이틀에 현재 채팅방 표시 (macOS, T-141)

## 1. 목표

T-140 중앙 표시 위치 정정: 사용자 지정 위치는 좌측 `LiteRT-LM Studio` 자리(사이드바 컬럼 타이틀).
중앙 principal은 모델 정보로 원복, 사이드바 타이틀이 채팅방 이름.

## 2. 변경

1. `ContentView.swift`: `roomTitle` 신규 (현재 세션 displayTitle, 드래프트 "새 채팅").
   `headerTitle`/`headerSubtitle`는 T-140 이전(모델명·스펙)으로 원복.
   양쪽 분기 `sidebar`에 `.navigationTitle(roomTitle)` (기본 Window 타이틀 대체).
2. 문서: TODO T-141 + CHANGELOG 0.7.84 + 본 PLAN.

## 3. 검증

* unit + lint 신규 0 + `build macos` 설치. 눈확인: 좌측 타이틀이 방 전환·이름 변경·드래프트 따라 변경, 중앙은 모델 정보.
