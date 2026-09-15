# PLAN v7 — T-010 SPM LiteRTLM 네이티브 Engine 옵션 (macOS)

> 전역 설정 · 1차 범위 텍스트+Vision+벤치마크. CLI가 기본값, 네이티브는 opt-in.

## 1. 타당성 (S-0 전제)

* 공식 Swift API Early Preview (macOS v0.13+), SPM `https://github.com/google-ai-edge/LiteRT-LM`.
* `~/.litert-lm/models/<id>/model.litertlm` 직접 참조 (AGENTS.local .litertlm 번들 금지와 충돌 없음).

## 2. 대응표

* 데몬 serve+헬스 → Engine lazy init (모델당 1개, 첫 초기화 수 분, 준비중 UX 재사용).
* SSE → `sendMessageStream` 매핑 (TTFT·tok/s·preparing 그대로).
* JPEG Data → temp 기록 후 `Content.imageFile`, 전송 후 삭제.
* temperature → `SamplerConfig` (topK/topP 고정). Thinking/Tool은 capability 있을 때만 주입 (`describe` CLI 유지).
* `benchmark` → `BenchmarkInfo` (S-0에서 존재 확인, 없으면 CLI 폴백).
* list/describe/delete/du/config.json은 CLI 유지.

## 3. 설계

* `Core/NativeEngine.swift`: 생명주기 (모델별 lazy init + LRU 1개 + 명시 해제).
* `Core/NativeChatAdapter.swift`: Conversation ↔ ChatStore 토큰 흐름.
* `ChatStore`는 `engineMode` 분기만 추가. 세션·영속·UI 불변.
* Settings 전역 토글 (기본 CLI). 사이드바에 네이티브 상태 표시, 시작/중지는 엔진 초기화/해제.
* 에러코드 `E-MAC-ENG-0001/0002` + `error_message_ko.json` 등록.
* Metal 컴파일 캐시는 Application Support/Caches 고정.

## 4. 마일스톤

* T-129 S-0 스파이크: resolve + init 시간·스트리밍·Vision·BenchmarkInfo·히스토리 주입 5종 실측. 실패 시 T-010 보류.
* T-130 S-1 텍스트 패리티: 어댑터+토글+에러코드+가짜 엔진 테스트. 68종 전부 + 양 모드 smoke.
  - 완료 (0.7.77): EngineVendor 로컬 래퍼로 확정 (직접 SPM 핀은 모든 빌드 stall로 원복).
    vendored Swift 모듈의 explicit-module 호환 실패 → 앱 타깃 직접 포함으로 피벗.
    dylib 링크·임베드는 SPM이 자동 처리, modulemap은 OTHER_SWIFT_FLAGS로 노출.
    테스트 75/75 (Fake 7종). 네이티브 실전송 눈확인 완료 (초기화 13.9초·TTFT 17.4초→11.8초).
* T-131 S-2 결정 (로그 실측 반영): Vision은 imageData 직접 전달로 temp 불필요.
  capability 소스는 양 모드 CLI describe 유지 (NativeEngine은 MTP 판정에만 Capabilities 사용).
  Thinking/Tool 기능 배선은 별도 과제 (현 토글은 표시 전용).
* T-131 S-2 Vision+게이팅: temp 경로+capability 회귀.
* T-132 S-3 벤치마크 패리티: 동등성 확인, 불일치 시 CLI 폴백.
  - 판정 (0.7.78): CLI `benchmark gemma4-12b`(256/256)는 워밍업 10분 타임아웃으로 실패 (CLI 자체 한계).
    네이티브 고정 프롬프트 1턴 실측 확정 (prefill 약 16.5·decode 약 17.0 tok/s, TTFT 약 1.2초).
    네이티브가 주 경로, CLI 폴백 유지. 작은 모델에서는 CLI 비교 가능.
* T-133 S-4 폴리시: 캐시·메모리 표시·문서·CHANGELOG. 버전 0.7.77+.
  - 완료 (0.7.78에 포함, 별도 범프 없음): SystemMonitor.appRSSGB 1Hz + 인스펙터 네이티브 행.
    캐시는 prepared 모델 표시로 갈음 (별도 캐시 UI 없음).

## 6. S-0 실측 결과 (2026-09-15, gemma4-12b, v0.17.0, 판정: GO)

* 스크래치: `/tmp/opencode/EngineSpike` (앱 무접촉). 바이너리 ZIP 직접 47MB (사용자 다운로드 규칙 이전 수신분).
* caps: thinking=false fn=false spec=true text/vision/audio=true vbudget=1120 (CLI describe와 일치).
* init 14.1초 (GPU, 캐시 warm). 스트리밍 TTFT 2.8초, 청크 누적 패턴 유효.
* Vision 응답 (적색 사각형, 에러 없음). BenchmarkInfo 6종 전부 흐름 (init·TTFT·prefill·decode).
* initialMessages 히스토리 주입 동작 (세션 복원 리플레이 불필요).
* Xcode SPM resolve는 거대 repo clone에서 10분 무진전 → S-1은 exact 핀 재시도 후 막히면 로컬 래퍼 패키지 (binaryTarget URL+Swift 소스 13종 벤더)로 폴백.

## 5. 가드

* SPM fetch 전 별도 승인 (진행해 승인됨). 버전 exact 핀 (S-0 확정). LFS resolve 불안정(#2407) 시 보류.
* 12B 상주 메모리: 엔진 RSS 별도 표기, 경고 시 LRU 해제. CLI 기본값이라 기존 게이트 전부 통과가 DoD.
