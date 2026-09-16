# PLAN v32 — 앵커 실측 재수렴 (macOS)

## 1. 목표

핀ON 허공 고착 해소. AppKit 문서 높이(추정 팽창)와 SwiftUI 앵커(실측)가 어긋나
offset이 실측 끝을 초과해도 전부 스킵되던 사각지대. T-206 1건.

## 2. 근거

* 0.7.140 로그: 수렴 종료+위고착 1회 후 3/5초 무음, 화면 백지 지속.
* 핀ON(앵커가 뷰포트 위=끝을 지남) + AppKit상 하단 = 상충. 앵커가 진실.
* 자: 실측끝 = anchorMaxY + offset - clipH (스크롤 공간은 내용과 함께 안 움직임,
  핀 판정이 동작하는 근거와 동일).

## 3. 변경 (T-206)

* `FollowGate.anchorMaxY`: 하단 앵커 onChange에서 기록 (@State 아님, 재렌더 방지).
* `ScrollMath.anchorTrueMaxY + pastTrueEnd` 순수 함수+회귀.
* `recoverPastTrueEnd`: !스트리밍·준비 + 기준>0 + 앵커>0 + 미이동 + 실측 초과면
  실측 끝으로 직접 복귀 (jumpToBottom 경유 금지=AppKit 높이 오염).
  지연 works에 추가 (핀 가드 없음, 핀ON 사각지대 담당).
* 버전 0.7.141.

## 4. 검증

* full 112/112 + lint 신규 0 + build 설치. 눈확인: 난감하네 방.
* PERF/CACHE 영향 없음 (지연 works 내 판정 추가뿐, anchor 저장은 기존 콜백 1줄).

## 5. 위험

* 앵커 stale (레이아웃-판정 시차): 이동량 가드(60) + 8pt 톨러로 완화.
  과민 시 앵커 신선도(기록 시각) 가드 추가.
