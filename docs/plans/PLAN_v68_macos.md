# PLAN v68 — 재사용 시작 실패 재시도 (T-277)

## 원인

* 재사용 대화 핸들에서 C API 스트림 시작 거부 (`failedToStartStream(status: 13)`).
* 재사용은 KV 최적화일 뿐이므로 실패 시 새 대화로 1회 재시도.

## 변경

* `preparedStream`에 `reused` 반환 + `allowReuse` 인자.
* `consumeStream` 분리: 시작 실패+재사용일 때만 무효화 후 1회 재시도.
* `isStartStreamFailure` 순수 판정+테스트.
