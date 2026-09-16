# PLAN v41 — 벤치마크 별도창+히스토리+AI 분석 (macOS)

## 1. 목표

* 별도 윈도우(`Window id:benchmark`) + 사이드바 "벤치마크" 섹션 (최근 3건 + 열기).
* 네이티브/CLI 모드 분리 선택, CLI는 소요·타임아웃 경고 유지.
* 자동 시작 폐지 → 모델 선택 후 [측정 시작]. 예상 소요 + 경과시간 + 단계 정상화.
* 히스토리 통합 보관 + 모델 필터. 보관 수 설정: 10(기본)/50/100/제한없음.
* 리포트 AI 분석: 현재 채팅 모델·route 그대로 사용, 마크다운 렌더.

T-216 창·시작·시간/단계 / T-217 히스토리·설정·사이드바 / T-218 AI 분석 / T-219 검증·문서.

## 2. 현상 근거

* `ContentView.swift:151` `.sheet` + `ChatScrollActions.swift:378` 열자마자 `run()` 자동 시작.
* `BenchmarkStore.swift:88` 네이티브가 `prepare` 구간 구분 없이 `.measure`로 점프, 진행 콜백 없음.
* `cancel:145`가 `running=false`를 직접 내리지 않아 중지 체감 지연.
* 영속·분석 없음 (`Metrics.explanation` 고정 문구만).

## 3. 변경

### T-216 창·시작·시간/단계
* `LiteRTLMStudioApp.swift`: `Window("벤치마크", id:"benchmark")` 추가. `.sheet` 삭제.
* `AppServices`: `bench` + `benchHistory` 상주 (창 닫아도 유지).
* `ContentView`: bench/history를 services에서 주입(`@ObservedObject`). `runBenchmark`는 pending 세팅 + `openWindow(id:"benchmark")` (Notification `.openBenchmark`).
* `InferenceEngine.swift`: `enum BenchmarkPhase { preparing, measuring, summarizing }` + 프로토콜 `benchmark(modelID:onStage:)` 추가 (기본 구현은 기존 `benchmark(modelID:)` 호출, Fake 호환).
* `NativeEngine`: 신 메서드 구현 — 시작 시 `.preparing`, 스트림 시작 시 `.measuring`, `getBenchmarkInfo` 전 `.summarizing`.
* `BenchmarkStore`:
  - `pendingModelID/pendingRoute` + `prepare(modelID:route:)` / `start()` 분리. `run(modelID:)`는 기존 호출 호환용으로 남기되 내부에서 prepare+start 순서로 동작하지 않고, 신규 UI는 prepare→start만 사용 (테스트 호환: 기존 `run` + `route` 세팅 경로는 그대로 자동 시작 유지).
  - `startedAt/elapsed` (0.5초 틱 Task), `estimateText(route:hasHistory:avg:)` 순수 함수.
  - `cancel()`: 즉시 `running=false` + `logLines += ["— 사용자 중단 —"]` + 상태 `.cancelled` 기록. CLI는 `terminate()` 후 종료 핸들러에서 마무리.
  - `[INFO] [FEATURE] 벤치마크` 진입 로그 1개 이상 유지.

### T-217 히스토리·설정·사이드바
* `BenchmarkRecord(Codable/Identifiable)`: id/date/modelID/route/metrics/durationSec/status(완료/중단/실패).
* `BenchmarkHistoryStore`: JSON `Application Support/LiteRTLMStudio/BenchmarkHistory.json`, 추가 시 cap 적용.
* `BenchmarkRetention`: 10/50/100/무제한, UserDefaults `benchmarkRetention` (기본 10). `SettingsView`에 Picker 추가.
* 사이드바 "벤치마크" 섹션: [벤치마크 열기] + 최근 3건 (시간·모델·decode). 클릭 시 해당 기록을 창 상세에 표시.
* 창 좌측: 전체/모델별 필터 + 삭제. 우측: 새 측정 + 결과.

### T-218 AI 분석
* `BenchmarkAnalyzer.prompt(record:avg:)` 상수 — PLAN_v41 §5 문구 그대로 (4섹션 고정, 과장 금지).
* `BenchmarkStore.analyze(record:avg:chat:)` — `chat.model/route/options` 그대로 사용, 채팅 세션 오염 방지 (임시 전송, `keyHistory=[]`). CLI는 비스트림 `POST /v1/chat/completions`, 네이티브는 `stream` 수집.
* 결과 `analysisMarkdown` + `analyzing` 퍼블리시, `MarkdownView` 렌더 + "프롬프트 보기" Disclosure.
* 실패: `E-MAC-ENG-0002` + 한국어 메시지 (신규 코드 없음, 기존 코드 재사용).

## 4. 소요 예측 문구

*初회: 네이티브 "약 1~3분 (첫 준비 포함)", CLI "약 3~10분 (12B는 워밍업 타임아웃 가능)". 2회부터 히스토리 평균±30% 표시.

## 5. 분석 프롬프트 (코드 상수, 화면에도 공개)

```text
당신은 온디바이스 LLM 성능 분석가입니다. 아래 벤치마크 JSON을 한국어로 분석하세요.
출력은 마크다운, 4섹션 고정.
- ## 요약 (3줄)
- ## 지표 해석 (TTFT·prefill·decode·init 각각 체감 기준)
- ## 이전 기록과 비교 (avg 대비 증감 %, 없으면 단독 평가)
- ## 개선 제안 (구체 3개: 짧게 답 요청, KV 재사용, GPU/CPU 설정 확인).
과장 금지, 숫자는 소수1자리, 불확실하면 "측정 1회라 단정 불가"라고 명시.

[이번 결과]
{이번 JSON}

[최근 같은 모델 평균 (최대 5건)]
{평균 JSON 또는 "없음"}
```

## 6. 검증

* 신규 unit: 예측 문구·cap(10/50/100/무제한)·필터·pending→시작·중단 즉시종료·프롬프트 4섹션. 기존 `LiteRTLMStudioBenchmarkTests` 2건 유지.
* `test macos unit` + swiftlint 신규 0 + `build macos` 설치. DebugPanel ERROR 0.
* PERF 영향: 벤치마크 실행 시에만 동작, 평상시 타이머 없음.

## 7. 위험

* 네이티브 엔진 블로킹 구간에서 중지가 즉시 안 먹을 수 있음 → `cancel()`은 UI 상태를 즉시 내리고, 엔진 `cancel()` 병행 호출로 완화.
* 창·사이드바가 같은 store를 공유해야 함 → AppServices 단일 인스턴스로 해결.
