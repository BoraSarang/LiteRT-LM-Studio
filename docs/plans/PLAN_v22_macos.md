# PLAN v22 — 설정 전부 때려박기 + 서버 상태 + 빌드 정리 (macOS)

## 1. 목표

실행 설정에 litert-lm 실제 옵션 전부 노출 (기본값 내장). 서버 미연결 외부 실행 표시.
빌드 중복 등록 제거. Temperature 기본 1.0.

## 2. 확정 기본값 (Gallery·describe 대조)

* Temperature 1.0 (0.7→변경, 신규 설치만) · TopK 64 · TopP 0.95 (describe 실측, 하드코딩 40 수정).
* Max 출력 빈칸=무제한 · Seed 빈칸=랜덤 · KV 빈칸=모델 기본(힌트 10000).
* Audio cpu · CPU 스레드 빈칸=자동(CPU 모드만 표시) · cache disk · Metal residency 켬.
* Visual 1120(상한) · Thinking 지원 모델만 (현 12b 비활성 유지) · 정밀도 모델 내장 · `npu` UI 미노출.

## 3. 변경

* T-175 실행 설정: ConfigStore 6종(audio·스레드·cache·KV·thinking/budget) + BackendSectionView 행. 적용·재시작 패턴 유지.
* T-176 생성 설정: ChatStore topK/topP/maxTokens/seed/systemPrompt + serve 요청 전송 + NativeEngine Sampler/Thinking/시스템 연결. 미지원 비활성 기존 패턴.
* T-177 고급 접기: residency+visual+정밀도만. vision `.cpu()` 고정 → config 추종 수정 포함.
* T-178 빌드 정리: AppNotifications 컴파일 중복 1건 제거 (완료).
* T-179 서버 상태: `unlinkedRunning`(muted+healthy) + 사이드바 주황 표시 + 시작 버튼 재연결. 전이표 불변.

## 4. 비범위

* repetition/noRepeatNgram 패널티 UI, LoRA, ringbuffers, gpu_decode_steps (수요 시).
* serve 요청 top_k (OpenAI 비표준, config 기본으로만).

## 5. 검증

* T별 unit + lint 신규 0 + `test macos unit` + `build macos` 설치·눈확인 (0.7.116~).
* serve 무시 버전 대비: T-176 때 curl 로그 대조, 무시되면 config 폴백.
