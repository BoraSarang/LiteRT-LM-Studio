# PLAN v31 — 종료 후 고착 보정 (오프셋 이동량 가드) (macOS)

## 1. 목표

잔여 빈 방 해소. 수렴 종료 후 오프셋이 허공(문서 안 빈 공간)에 고착.
스크린샷 확증: 하단 버튼 보임(앵커 아래 존재)+타임라인 전체 백지+스크롤 무반응.
T-204 1건.

## 2. 근거

* 동일 방 문서 높이 널뜀 (14183→9611, 18416 잔재) = Lazy 추정치 팽창·붕괴.
* 휠 개입 로그 없음인데도 보정 미발사 = 사용자가 헛스크롤 시도 → lastWheel 오염 →
  전부 스킵 (가드 자체가 함정).
* 처방: 휠 시각 대신 오프셋 이동량으로 판정. 가만히 있으면 하단 보장,
  멀리 움직였으면(의도적 읽기) 손대지 않음.

## 3. 변경 (T-204)

* `FollowGate.finishDocH/finishOffset`: 종료(정상+상한) 시점 기록, 진입 시작 시 리셋.
* `ScrollMath.docCollapsed(finish:current:threshold: = 200)` +
  `stuckBottom(offset:finishOffset:docHeight:clipHeight:)` 순수 판정+회귀.
* 지연 works(1.5/3/5초): clampToDocument + clampTopStuck (기존) +
  correctCollapsedBottom + correctStuckBottom (신규, 이동량 가드).
* 5초 works: reseatBottomViaProxy (앵커 스크롤 후 0.15초 절대 점프, 실측 강제).
  스트리밍·준비 중·핀ON·이동 큼이면 스킵.
* 버전 0.7.139.

## 4. 검증

* full 111/111 + lint 신규 0 + build 설치. 눈확인: 이솝·오른쪽·난감하네 방 왕복.
* PERF/CACHE 영향 없음.

## 5. 위험

* 프록시 재착지는 T-167 금지 패턴의 제한적 부활. 5초·고착 조건+확정 점프로 제한.
  과민 시 임계 상향·재착지 제거 순으로 후퇴.
