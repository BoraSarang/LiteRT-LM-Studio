# PLAN_v87_macos — 첫터치 프리필 예열 (T-302)

> 플랫폼: macOS · 범위: 앱 내 엔진(native) 준비 예열 · 3분 초안

## 목표
- 첫 메시지 전송 시점의 엔진 init(실측 1~2s)을 방 열람 시점으로 선소비해 TTFT 단축.
- 사용자 확정 정책: **기본 OFF 토글** (설정 → 채팅). 발열·배터리 기본 영향 없음.

## 설계
- 토글 키: `UserDefaults "prefillWarmup"` (기본 false). ChatStore가 `routeDefaults`로 읽고
  저장 (@AppStorage와 동일 .standard 키 공유, unit 테스트는 주입 defaults로 분리).
- 발동 지점: `ChatStore.currentSessionID` `didSet` → `warmupForNextSend()`.
  selectSession·startDraft·앱 시작 복원·첫 전송 방 생성 모두 커버 (단일 진입).
- 예열 동작: `guard` 통과 시 Task로 `engine.prepare(modelID: model)`.
  재진입 가드는 `warmupTask != nil`. 완료·실패 시 nil 복원.
- **범위 한계 (문서화)**: 방 KV 대화 프리필 예열은 제외 — 대화 키(ConvKey)가 전송 옵션
  확정 후에만 결정돼 예열 키 불일치 위험. prepare 선행만으로도 init 구간 제거.
- 실패: 조용히 로그만 (E-MAC-PERF-0001), 사용자 흐름 무방해.

## 파일
- `Core/ChatStore.swift`: 토글 @Published + `warmupTask` + `currentSessionID` didSet (2줄 + α)
- `Core/ChatStore+Native.swift`: `warmupForNextSend()` + 순수 판정 `warmupWanted(...)` (본문 확장 파일 재사용 → pbxproj 불필요)
- `SettingsView.swift`: 채팅 탭 "첫터치 프리필" 토글 (후속 질문 토글 하단)
- `Tests/LiteRTLMStudioRefactorTests.swift`: warmupWanted 순수 + 토글 라운드트립 + didSet 발동 (FakeEngine)

## 테스트
- warmupWanted(enabled, nativeRoute, preparedModel, target, streaming, warming) 판정
- 토글 저장/복원 (주입 defaults) — 기본 OFF 확인
- 예열 실행: FakeEngine.prepareCalls 기록 검증, 재진입, streaming/비native 가드

## 게이트
- unit (247→+) / swiftlint 신규 0 / build+설치 OK
- 진입점 로그 `[INFO] [프리필] 방 열람 예열 시작` + 실패 `[ERROR] E-MAC-PERF-0001`

## 검증 방법
- 설정 켜고 방 전환 → DebugPanel에서 "예열 완료" PERF 로그, 첫 전송 준비 구간 단축 확인.

## 검증 요약 기록
- unit 252/252 (신규 5: 판정·토글라운드트립·발동·기본OFF·스트리밍 가드)
- lint: 변경 파일 신규 0 (function_parameter_count 6→5 파라미터로 정리,
  테스트 신규 클래스 LiteRTLMStudioPrefillTests 분리로 serious 0)
- build+설치 OK. 토글 저장소는 routeDefaults 주입 분리 (테스트 격리)