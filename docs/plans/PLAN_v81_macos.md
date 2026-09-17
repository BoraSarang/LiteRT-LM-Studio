# PLAN v81 — 후속질문 선행 생성 (T-292, 안전 절충안)

## 1. 배경

* T-291 실측: 후속 생성 6.7~16.5초 (gemma4-12b 네이티브, 로그 확인).
* 스트리밍 중 겹치기(선행 생성) 검토 결과, 네이티브 Engine 동시 추론 지원이
  Swift 소스·C 바이너리 어디에서도 확인 불가 → 본 응답 불안정 위험으로 네이티브 겹치기 기각.

## 2. 처방 (사용자 결정: 안전 절충안)

* 서버 route: 스트리밍 중 선행 호출 (독립 HTTP라 안전). 답변 300자 도달 시 1회,
  완료 시 드리프트 판정 후 유지/재호출.
* 앱 내 엔진 route: 완료 후 즉시 호출 유지 (현행) + 작업 축소로 단축.
* 공통 작업 축소: 프롬프트 Q 2000→1000자·A 2000→800자, maxTokens 150→100.

## 3. 변경

* `FollowUpSuggest.prompt` 절단값 변경 + `needsRefire(snapshot:final:)` 순수 판정
  (final - snapshot > max(300, snapshot/2)면 재호출).
* `FollowUpStore`: `snapshotLen` 추가. `request()` (선행·완료 공용, 중복 가드 유지) +
  `finalize()` (칩 있으면 드리프트 판정 후 유지/재호출). 서버 선행 실패는 완료 시 자연 재시도.
* `ChatPaneView`: 스트리밍 중 마지막 어시스턴트 300자 도달 시 `request()` 1회
  (route==.cli만). 완료 시 `onAppear`는 `request()` → `finalize()`로 교체.
* 로그: `[후속질문] 선행 요청/유지(드리프트 없음)/재호출(드리프트)` 추가. 에러코드 없음.

## 4. 검증

* unit: needsRefire 4건 + prompt 절단 갱신 + finalize 유지/재호출 2건(FakeEngine) + 기존 유지.
* lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인(서버): 스트리밍 중 선행 요청→완료 시 즉시 칩 또는 드리프트 재호출→클릭 전송.
