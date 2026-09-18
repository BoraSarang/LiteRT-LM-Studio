# PLAN v91 — 후속 질문 로딩 애니메이션 (macOS, T-313)

> 사용자 요청: 후속 질문이 "멍때리다가" 나타난다 — 지금 형태(스켈레톤 3개)는 유지하되
> 로딩 애니메이션을 보여주고, 칩으로 부드럽게 채워지게.

## 결정 (사용자 선택)
- 스타일: 심머(좌→우 그라데이션 스윕) + 완료 시 칩 크로스페이드.
- 최소 노출 0.4s (초고속 응답 시 깜빡임 방지).

## 변경
1. `FollowUpSuggest.swift`
   - `FollowUpSkeletonView`: 칩과 동일한 `Capsule` 바 3개(폭 변주 148/120/164), 높이 28.
   - `SkeletonBar`: 밝은 그라데이션이 1.2s 루프로 좌→우 이동.
     `accessibilityReduceMotion`이면 정적, 라벨 "후속 질문 생성 중" 유지.
   - `FollowUpChipsView`·`FollowUpSkeletonView`에 `.transition(.opacity)`.
   - `FollowUpSuggest.minLoadingSeconds`(0.4)·`minDisplayRemainder(elapsed:minimum:)`(순수).
   - `FollowUpStore.request`: 결과 수신 후 남은 최소 노출 시간만큼 sleep.
2. `ChatPaneView.swift`: `followUpArea`에 `.animation(.easeInOut 0.25s, value: loading/chips)`.
3. 테스트: `testFollowUpMinDisplayRemainder` 추가.

## 검증
- unit 260/260, lint 신규 0, `./build_and_run.sh build macos`(설치·실행).
- 수동: 대기 중 심머, 완료 크로스페이드, 동작 줄이기 시 정적.
