# PLAN v85 — 전수 리팩토링: 상태 정합+사각 제거+중복 제거 (T-295~T-300)

## 1. 배경

* 3방향 병렬 진단(사각·중복 / lint·구조 / 아키텍처) + 팩트 대조 완료.
* P0(정확성)만 이번 회차, P1(구조)은 잔여·일부만, P2(대형)는 후속.

## 2. P0 — 정확성 (반드시)

* T-295 상태 정합 (`NativeEngine`):
  `release()` 전체 해제 전환(중지 버튼 no-op 해소),
  `registerEngine` 방출·`releaseModel` 시 대화 풀+`active*` 정리,
  `prepare()` 캐시 히트 시 LRU 터치 (`preparedModelID`==최근 준비 모델 보장),
  `stream()`을 `streamEvents` 위임으로 단일 경로화 (모델 선택 분기 해소).
* T-296 히스토리 정직화: `historyTurns` 미설정 기본 10턴,
  `currentTurns()`는 저장값 그대로 (명시적 0=제한 없음 동작 복원).
* T-297 ConfigStore 단일화: `ContentView`의 `@StateObject` 제거,
  `services.config` 주입 (`App` 호출부 포함). 설정창·사이드바·인스펙터 동일 인스턴스.
* T-299 KV 필드 통일: `draftMaxTokens/appliedMaxTokens` int 필드 제거,
  `draftKV/appliedKV`(Inspector 입력칸) 단일 소스 복원. 빈칸=키 삭제=모델 기본.
  (`max_num_tokens` 인위 상한이 `4115>=4096` 에러 원인 — 벤더 기본값으로 복귀.)

## 3. P1 — 위생 (저위험만)

* T-298 사각 제거: `max_prefix_turns` 읽기·쓰기·필드·summary 전수 삭제
  (쓰기 시 기존 키 1회 정리), `BenchmarkHistory.recent` 삭제,
  미사용 `import UniformTypeIdentifiers` 10건 삭제, trailing 2건 수정.
* T-299 중복 제거: `ConfigStore.jsonDict` 공용 JSON 읽기
  (`load/savedMTP/maxNumTokensValue/resolveBackends` 적용),
  `pastTurns()` (`runNative`+`chatRequest` 윈도우 적용 통일).
  `ToolLedger` 칩 반영 2곳은 의도적 분리 유지 (완료=인덱스 순서,
  서버 재시도=callID 매칭) — 강제 통합 시 오동작 위험으로 기각.

## 4. P2 — 후속 (이번 회차 제외, 기록만)

* 제네릭 `LRUCache`, 스트리밍 소비 루프 통합, 채팅 요청 빌더 통합,
  `LogicTests`(1278줄)·`RefactorTests`(544줄) 분할, `Conversation.swift` 분리 검토.

## 5. 검증

* T-300: unit 244/244 + lint 신규 0 (기준선 3건 유지) + `build macos` 2회.
* 눈확인: 설정 MTP 토글 재실행 유지, 중지 버튼 상태 표시, 제한없음 전송 범위.
