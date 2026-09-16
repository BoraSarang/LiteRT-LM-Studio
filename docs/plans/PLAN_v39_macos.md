# PLAN v39 — 앵커 초기 보고+진입 완료 게이트 (macOS)

## 1. 목표

"떴다가 사라짐" 해소. 최초 레이아웃 1회는 onChange 미발火라 앵커 영원히 0,
그 사이 폴링 중 보정 캐스케이드가 레이아웃을 박살. T-213 1건.

## 2. 근거 (0.7.147 로그 11:00:33~41)

* 최초 페인트(메시지 보임) → 36.002 점프+36.008 프록시(폴링 중!) → 백지.
* refreshFinishMark가 폴링 중 보정에도 기준을 세워 wake를 정당화 (T-205 부작용).
* 앵커 onChange는 최초값에 미발화라 7초간 0 유지 → wake 4연발로 계속 난사.

## 3. 변경 (T-213)

* 앵커 onChange에 `initial: true` (최초 레이아웃 즉시 보고).
* `FollowGate.entryDone`: schedule에서 false, finish/상한에서 true.
  `refreshFinishMark`는 entryDone일 때만 갱신 (폴링 중 정당화 차단).
  collapse/stuck/recover/wake/final 5종에 entryDone 가드 추가.
  clamp 2종은 기존대로 (위치 위생, 기준과 무관).
* `settleToBottom` 프록시는 앵커 0일 때만 (정상 경로 간섭 제거).
* 버전 0.7.148.

## 4. 검증

* full 112/112 + lint 신규 0 + build 설치. 눈확인: 첫 방 유지+하단.
* PERF/CACHE 영향 없음.

## 5. 위험

* initial:true로 첫 보고 시점에 pinned 정정 → 버튼 1회 깜빡임 가능. 허용.
