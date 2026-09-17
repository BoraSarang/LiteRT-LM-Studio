# PLAN v84 — 네이티브 엔진 성능 최적화 (Gallery 수준 응답 속도 달성)

## 1. 문제 정의

**같은 엔진(LiteRT-LM), 같은 GPU(Metal)인데 Google AI Edge Gallery(iOS/macOS 샘플) 대비 응답 속도 현저히 느림.**

원인: Studio는 **엔진/대화 매 요청 재생성 + 3중 스트리밍 래퍼 + 매 턴 설정 파싱**으로 오버헤드 누적.
Gallery 샘플은 **Engine 1개 + Conversation 1개 + 직호출** 최소 경로.

## 2. 목표

- **TTFT(Time To First Token)** 50% 단축 (연속 대화 2턴째부터)
- **모델 전환** 10초 → 0초 (이미 로드된 모델 캐시 히트)
- **토큰당 스트리밍 지연** 2-5ms → 0ms (래퍼 제거)
- **UI 60fps 유지** (백그라운드 액터 분리)

## 3. 변경 계획 (우선순위 순)

### P0: 즉시 효과 - 아키텍처 단순화 (핵심)

| 작업 | 파일 | 설명 |
|------|------|------|
| **P0-1** Engine 캐시 맵 | `NativeEngine.swift` | `engines: [String: Engine]` 모델당 1개 보유, 앱 수명 동안 재사용 |
| **P0-2** Conversation 풀링 | `NativeEngine.swift` | `conversations: [ConvKey: Conversation]` KV 캐시 완전 재사용 |
| **P0-3** 백엔드/플래그 캐싱 | `NativeEngine+Backends.swift`, `NativeEngine.swift` | 최초 1회만 디스크 읽기, 메모리 캐시 + 파일 감시로 갱신 |

### P1: 스트리밍 경로 단축

| 작업 | 파일 | 설명 |
|------|------|------|
| **P1-1** `streamEvents` 제거 | `NativeEngine+Events.swift`, `NativeEngine.swift` | `stream()`에서 `sendMessageStream` 직호출 |
| **P1-2** ChatStore 단순화 | `ChatStore+Native.swift` | `streamEvents` 대신 `stream` 직접 사용 |

### P2: 캐시 디렉토리 최적화

| 작업 | 파일 | 설명 |
|------|------|------|
| **P2-1** `cachesDirectory` 변경 | `NativeEngine.swift:74-81` | 시스템 자동 관리, 초기 로드 속도 향상 |

### P3: 백그라운드 추론 분리

| 작업 | 파일 | 설명 |
|------|------|------|
| **P3-1** `InferenceActor` 도입 | `NativeEngine.swift` (신규 파일) | `@MainActor` 해제, 추론만 백그라운드에서 |
| **P3-2** NativeEngine 프록시 | `NativeEngine.swift` | 메인 액터에서 호출, 실제 추론은 actor 위임 |

## 4. 검증 기준

- **Unit 테스트**: 244/244 통과 + 신규 테스트 추가 (캐시 히트/미스, 풀링 동작)
- **Lint**: 신규 0건 (기준선 3건 유지)
- **Build**: `./build_and_run.sh build macos` 성공
- **실측**: 
  - 모델 전환(동일 모델 재선택) < 100ms
  - 연속 대화 2턴째 TTFT < 1초 (Gallery 근접)
  - DebugPanel `[PERF]` 로그로 확인

## 5. 위험도 및 대응

| 위험 | 대응 |
|------|------|
| Conversation 풀 키 충돌 | `ConvKey`에 `modelID + history prefix + options` 포함으로 유일성 보장 |
| 메모리 누적 (Engine/Conversation 다수) | LRU eviction: 최근 3개 모델만 유지, 대화 20개 초과 시 오래된 것부터 해제 |
| 스레드 안전성 | `Engine`은 `actor`이므로 동시 접근 안전. `Conversation` 풀은 `@MainActor`에서만 접근 |
| 기존 `release()`/`restart()` 호환 | `release()`는 해당 모델만 제거, `restart()`는 캐시 비우고 재생성 |

## 6. 작업 순서

1. **P0-1~3** 동시 진행 (NativeEngine.swift 대폭 리팩토링)
2. **P1-1~2** 스트리밍 경로 단순화
3. **P2-1** 캐시 디렉토리 변경
4. **P3-1~2** 액터 분리 (선택: 성능 측정 후 결정)
5. 전체 테스트 + 빌드 + 실측 검증

---

**예상 소요**: 3-4 세션 (P0-P2 필수, P3는 측정 후)
**DoD**: unit 244+ 통과, lint 신규 0, build 성공, 실측 로그로 TTFT/모델전환 개선 확인