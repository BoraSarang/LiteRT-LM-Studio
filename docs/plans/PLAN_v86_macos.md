# PLAN_v86 — 정밀 재감사 2라운드 (KV 정합·중단·1회성 정리)

> 작업자: BoRaSaRang · 플랫폼: macOS · 날짜: 2026-09-18
> 목표: PLAN_v85 리팩토링 전수 재감사로 남아있는 상태 정합 결함을
> 정밀 추적·수정. 1라운드(분류) → 게이트 → 2라운드(재탐색) 순.

## 컨텍스트
- v85에서 세션키(모델+방ID+옵션) 고정으로 KV 재사용 최적화 완료.
- 재사용은 대신 "끊어진 KV가 그대로 살아나 재생성됨"을 **강조**:
  `initialMessages`는 생성 시 1회만 적용되고 이후 턴은 KV를 그대로 잇는다.
- 같은 방에서 기록이 잘리지 않으면 정상이나, **잘리는 경로** 4종이 남아
  KV가 이전 기록을 오염시킬 수 있음.

## 1라운드 발견 (정밀 재열독)

| # | 결함 | 원인 | 심각도 |
|---|------|------|--------|
| D1 | `editMessage`는 히스토리를 잘라내지만 해당 방 KV를 유지 → 모델이 삭제된 메시지를 "기억" | retry와 동일 원인, retry만 고치고 editMessage 누락 | 높음 |
| D2 | `cancel()`이 풀에서 대화를 제거하지 않음 → 중단 직후 같은 방 재전송 시 끊긴 KV 재사용 | cancel은 activeKey/activeConversation만 nil, 풀 항목 잔존 (T-191 의도 "다음 전송 새로 생성" 미달) | 높음 |
| D3 | 후속질문 조기 중단(`hasEnoughQuestions`) 시 엔진 cancel 없음 → 최대 64토큰 무의미 디코드 지속 | same session이라 `break`만으로 스트림이 안 끝남 | 낮음 |

### 1라운드 수정
1. **D1**: `ChatStore`에 `evictNativeSession()` 헬퍼 추가, `retry()`·`editMessage()` 공용.
2. **D2**: `NativeEngine.cancel()`이 `activeKey` 세션을 풀에서 제거 (의도 복원).
3. **D3**: `FollowUpStore.fetchNative`에서 `hasEnoughQuestions` 조기 중단 시 `engine.cancel()`.

### 1라운드 게이트
- 단위 246/246, lint 신규 0, build+설치.

## 2라운드 (재탐색 후 확정)
- **R2-15**: `EngineConfig`/폴백 실패 시 `state`가 `.preparing`에서 멈춘 결함
  → `markInitFailed()`로 `.failed` 확정.
- **R2-17**: 마지막 엔진 LRU 방출 시 `state=.ready` 잔존 → `.idle` 갱신.
- **R2-기타**: 벤치 분석은 `analyzing` 단일-플라이트+`evictSession("")`로 안전 확인.
  `streamEvents` 모델 재선택 레이스는 단일 창·streaming 가드로 도달 불가 확인(문서화).

## 검증 요약 기록
- 1라운드: unit 247/247 / lint 신규 0 / build OK
- 2라운드: unit 247/247 / lint 신규 0 / build OK
- NativeEngine file_length 임계(400) 유지하며 분리·정리 완료.