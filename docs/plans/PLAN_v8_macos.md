# PLAN v8 — 재시도·복원 스크롤 2건 (macOS, T-134~T-135, 3분 초안)

## 1. 현상 (사용자 보고)

1. 재실행 시 마지막 대화로 가지 않음.
2. 재시도 전송 시 질문행으로 이동하나 준비중 표시가 폴드 아래에 가려짐. 토큰이 와야 자동 스크롤됨.

## 2. 원인

* T-134: `ChatStore+Session.load()`가 `sessions.first` (생성순 선두) 선택.
  `touchSession()`은 `updatedAt`을 갱신하지만 복원 시 무시됨. 목록 정렬(`sortedSessions` 최근순)과 불일치.
* T-135: `sendJump()`가 질문행을 뷰포트 상단에 고정. 준비중 버블은 텍스트 증가가 없어
  T-106 추종 조건(`textGrew`)을 만족하지 못해 첫 토큰까지 화면이 멈춤.

## 3. 수정

* T-134: 복원 대상을 `updatedAt` 최대 세션으로. 순수 `mostRecentSessionID` + 회귀 테스트.
* T-135: 0.5초 재확인 블록을 보정 점프로 교체 — preparing이면 `jumpToBottom()` (그 사이 휠 입력 시 취소),
  스트리밍 중이면 추종에 맡기고 손대지 않음, 그 외에만 질문행 재앵커.
  즉시 이동(질문행 상단)은 유지 — 새 레이아웃 확정 후 0.5초 보정이 stale 오버슛 없이 안전.

## 4. 검증

* unit 추가 2종 + 전체 + lint + build. 버전 0.7.79.

## 5. 후속 T-136 (복원 확정)

* `updatedAt`만으로는 "보기만 한 방" 복원이 안 됨 (전송 시에만 갱신).
* 전환 때마다 현재 방 ID를 UserDefaults(`currentSessionID`)에 저장, 복원 시 우선 선택.
* 테스트는 defaults 주입(`saveCurrentID`/`loadCurrentID`)으로 격리. 0.7.80에 포함.
