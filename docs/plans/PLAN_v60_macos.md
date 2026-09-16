# PLAN v60 — 팔레트 점프 진입 체인 충돌 수정 (macOS, T-265)

## 1. 원인 (로그 확정)

* 팔레트 검색 이동 → `selectSession` → `sessionJump` 진입 체인 시작 →
  0.15초 후 `jumpToOutline` 휠 스탬프 → `진입 중단: 세션교체·휠`.
* 앵커 실측 0 고착 → 핀 판정 사망 → 전송·재시도 자동 추종 미동작,
  고장 보정 체인이 문서 밖으로 점프 → 빈 대화 영역.

## 2. 변경 (최소 범위)

* `suppressNextSessionJump` 1회성 플래그: 팔레트 전환 시 진입 체인 스킵.
* `jumpToOutline` 분리: 수동 래퍼(휠 스탬프 유지)+`jumpToOutlineCore` (무스탬프).
  팔레트 점프는 코어만 호출.
* 맨 아래로 버튼 미달 치유: `healDirection` 순수 판정 (넘침 8pt·미달 24pt) +
  `jumpToBottom` 지연 치유에 상향 재점프 (핀ON·휠 정지 때만).
  후속질문 칩으로 늦게 늘어난 문서에 착지가 위에서 멈추던 문제 수정.
* 회귀 테스트 3건 + `CHANGELOG`.

## 3. 검증

* unit 유지, lint 신규 0, `build macos` 2회, DebugPanel ERROR 0.
* 눈확인: 팔레트 점프 후 `진입 중단` 없음 → 전송·재시도 추종 정상 → 빈 영역 없음.
