# PLAN v90 — 응답중 멈춤 픽스 + wigolo node PATH (macOS, T-310/T-311)

> 사용자 보고: ① 채팅이 첫 토큰(TTFT) 후 "응답중"에서 영원히 멈춤(재발).
> ② 서브 로그 뷰에서 `wigolo serve`가 `env: node: No such file or directory`로 즉시 실패.
> ③ `첫터치 프리필`·이미지 에러("this model does not support image input") 문의.

## 1) wigolo `env: node` 실패 (T-310, 원인 확정)

- wigolo는 Node 스크립트(shebang `#!/usr/bin/env node`). GUI 앱의 PATH는 축약되어
  (`/usr/bin:/bin:/usr/sbin:/sbin`) nvm bin이 없어 `env node`가 실패.
- 바이너리는 `~/.nvm/versions/node/v22.23.1/bin/wigolo` — 같은 디렉터리에 `node` 존재 확인.

변경:
1. `WigoloSupport.swift`: `nodeForWigolo(bin:)`(형제 node 탐색) +
   `wigoloCommand(bin:args:)`(node 경유 실행 커맨드) + `nodePathDirs(home:)` +
   `processEnvironment(addingPathDirs:)`(PATH 확장, 테스트 가능).
2. `WigoloSupport.runServe`: node 경유 실행 + 환경 PATH 주입 + 로그 커맨드 갱신.
3. `WigoloManager.runStreaming`: 선택 `environment` 파라미터 추가
   (npm은 shebang 발동 위해 PATH 필요).
4. `install·init`, `doctor()`, `fetchVersion()`: `wigoloCommand` 경유로 실행.

## 2) 응답중 멈춤 (T-311)

실측: 첫 턴·히스토리 0개·36자 프롬프트에서 TTFT 1.7s → 이후 이벤트 0건·에러 0건·완료 로그 없음.
두 모델(gemma4-12b·qwen3_4b_mixed_int4) 모두 **FC 미지원** 모델.

유력 원인: `preparedStream`이 도구 없음(`tools=[]`)에도 `enableToolCallStreaming: true`로
대화를 생성 → C++ 대화가 도구 호출 스트림 상태를 기다리며 디코드 스톨.

변경 1 (근본): `enableToolCallStreaming: !tools.isEmpty` — 도구가 있을 때만 활성화.
변경 2 (방어): `ChatStore.runNative`에 진행 워치독 도입 —
토큰마다 시계 리셋, 60초 무진행 시 엔진 `cancel()` → 스트림이 CancellationError로
전파 → `E-MAC-ENG-0005` "응답 생성이 멈춰 중지했습니다"로 확정 (무한 "응답중" 방지).

- `InferenceEngine.EngineError.timeout` 추가 (E-MAC-ENG-0005).
- `error_message_ko.json`에 E-MAC-ENG-0005 추가.
- `nativeFailed`에 timeout 분기.

## 3) 문의 답변 (코드 변경 없음)

- **첫터치 프리필(첫터치 프리필 토글, T-302)**: "방 열람 시점에 엔진 준비를 미리 돌려 첫
  전송 성능을 올리는 예열" (기본 OFF). 이번 실측에선 엔진이 이미 캐시 히트 상태여서
  준비 완료 0.1s — 정상 동작.
- **이미지 에러**: qwen3_4b_mixed_int4가 vision 백엔드 포함 init에서 실패(E-MAC-ENG-0001) →
  `vision·audio 제외 폴백`으로 기동되어 사실상 Vision 비활성 → 첨부 이미지를 모델이 못 읽고
  "Cannot read image.png (this model does not support image input)" 형태의 응답을 생성한 것.

## 검증

- 단위: `nodeForWigolo`/`wigoloCommand`/`nodePathDirs`/`StreamProgressGate` + 기존 253.
- unit + lint 신규 0 + build 1회. 실측: 재전송 시 완료 로그·첫터치·서브 확인.