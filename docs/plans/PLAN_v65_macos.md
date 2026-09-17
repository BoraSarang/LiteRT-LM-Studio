# PLAN v65 — 네이티브 초기화 자동 폴백 (T-273)

## 원인

* `prepare()`가 default config의 vision·audio 백엔드를 그대로 전달 →
  인코더 없는 모델은 `engine.initialize()` 실패 (`failedToCreateEngine`).
* 벤치마크 `failNative`가 코드 고정 0002 (init 실패도 0002로 표기).

## 변경

* `boot(modelID:backends:)` 분리 + 실패 시 `modalFallback` (vision·audio 제외) 1회 재시도.
* `failNative`: `(error as? EngineError)?.code` 사용.
* 테스트 3건 + CHANGELOG.
