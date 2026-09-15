# PLAN v12 — 툴바 중앙에 현재 채팅방 표시 (macOS, T-140)

## 1. 목표

현재 채팅방을 사이드바 없이도 확인: 윈도우 타이틀 자리(툴바 principal) 1줄째에 채팅방 이름.

## 2. 배경

* `Window("LiteRT-LM Studio")` + `.unified` 툴바 + principal이 타이틀 슬롯 점유 → 별도 윈도우 타이틀 문자열은 가려짐.
* 따라서 principal 1줄째를 모델명 → 채팅방명으로 교체, 모델 정보는 2줄째로 유지 (가시적 윈도우 타이틀).

## 3. 변경

1. `ContentView.swift`: `headerTitle` = 현재 세션 `displayTitle` (드래프트 "새 채팅").
   `headerSubtitle` = 모델 표시명·용량·모달리티·MTP. 세션 전환·이름 변경 시 자동 갱신 (@StateObject chat 관찰).
2. 문서: TODO T-140 + CHANGELOG 0.7.83 + 본 PLAN.

## 4. 검증

* unit + lint 신규 0 + `build macos` 설치. 눈확인: 방 전환·이름 변경·드래프트 시 1줄째 변경.
