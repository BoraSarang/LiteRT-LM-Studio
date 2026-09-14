# PLAN v1 — LiteRTLM-Manager (macOS)

> 플랫폼: macOS (SwiftUI만) · 번들 `com.borasarang.litertlm-manager` · 문서 우선 순서 준수

## 1. 목표

`uv`로 설치된 `litert-lm`을 SwiftUI 맥 앱에서 관리: 현재 상태 표시 → 데몬(`serve :9379`) 시작/중지/로그 → OpenAI 호환 채팅(스트리밍) → 모델 관리(`list/import/delete`) → 풀 기능(benchmark·Vision/Audio·GPU/MTP).

## 2. 검증 완료 (Phase 0 스파이크, 2026-09-13 실측)

* `uv 0.11.29`, `litert-lm v0.17.0`, 모델 `gemma4-12b` (list 표기 6.4GB / 실제 12G 캐시 포함).
* `config.json` 없음 = 기본값 동작.
* `litert-lm serve --host 127.0.0.1 --port 9379` 기동 → `GET /v1/models`에 `gemma4-12b` 확인.
* `POST /v1/chat/completions` 일반 응답 성공 (서울=대한민국 수도).
* `stream:true` SSE 청크 수신 성공 (`1, 2, ...`).
* `describe gemma4-12b`: Function Call NO / Thinking NO / Speculative YES / Text+Vision+Audio.
* 스파이크 데몬 종료, 포트 반납 확인.

## 3. 아키텍처 (1단계 데몬 래퍼, 2단계 네이티브)

* `UvManager`: `/opt/homebrew/bin/uv` 절대경로, `uv tool list/upgrade` 실행, PATH 미의존.
* `ModelStore`: `litert-lm list/describe/import/delete/rename` 파싱 + `du` 실제 용량 병기.
* `DaemonManager`: `Process(/usr/bin/env litert-lm serve --host 127.0.0.1 --port 9379)` 관리, `/v1/models` 폴링 헬스체크, 로그 파이프, 포트 충돌·좀비 처리.
* `ChatStore`: `/v1/chat/completions` SSE 스트리밍, 중단 지원, `[PERF]` TTFT·tok/s 기록.
* `DebugLogger` 경유 필수. 진입점 `[INFO] [FEATURE]`, 실패 `[ERROR] E-MAC-*`, 성능 `[PERF]`, 캐시 `[CACHE]`.

## 4. 단계

* Phase 1: 스캐폴딩 (Xcode+build_and_run.sh+DebugLogger+error_message_ko).
* Phase 2: MVP (상태 화면+데몬+채팅+모델 목록+3분할 UI).
* Phase 3: 풀 기능 (benchmark, Vision/Audio 첨부, GPU/MTP, Thinking/Tool은 미지원 모델에서 비활성화).
* Phase 4: 네이티브 SPM Engine 옵션 (2단계).
* Phase 5: 게이트 (xcodebuild+swiftlint+smoke, ~/Applications 복사).

## 5. 성능 예산

Cold Start ≤1.5s, 60fps, 앱 셸 ≤300MB (데몬·모델 별도 표기), 캐시 히트 ≥70%.

## 7. 속도 이슈 처방 (2026-09-13 실측)

* 원인: `config.json` 없음 → 엔진 기본값 CPU 추론. 텍스트 콜드 43.9s, Vision 웜 141.4s.
* 처방: `~/.litert-lm/config.json` 생성 (`backend=gpu`, `vision_backend=gpu`, `gemma4-12b speculative_decoding=true`).
* 결과: 텍스트 콜드 5.4s (약 8배). Vision GPU 측정 중.
* 앱 반영: ConfigStore(config 읽기/쓰기+.bak 백업·재시작 필요 표시), 외부 데몬 attach,
  첫 토큰 전 “엔진 준비 중” 표시+TTFT 로그, 이미지 첨부 시 최대 768px JPEG 다운스케일.

## 6. 리스크

* serve의 Thinking/Tool 미노출 (현 모델도 미지원) → UI 비활성화로 대응, 지원 모델 import 시 활성화.
* 12B 상주 메모리 압박 → 데몬 시작/중지 명시적 제어, 중복 기동 가드.
* 스트림 중단 시 BrokenPipe 로그 → 정상 종료로 처리.
