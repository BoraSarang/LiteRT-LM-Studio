# Session 2026-09-18 (macos)

- 무엇을: T-301 세션 제거 먼저 커밋 완료 후, "리팩토링 정밀 감사 2라운드" 지시에 따라 1차(A→D1~D3)·2차(R2-15/17) 결함 수정.
- 플랫폼: macOS (SwiftUI·xcodebuild·swiftlint).
- 빌드+PERF+CACHE: unit 247/247 통과, build+~/Applications 설치 OK, lint 신규 0 (파일길이 400 임계 유지).
- 남은 TODO: T-302 첫터치 프리필 예열안 정책 결정 대기 (기본 OFF 토글 vs 전원연결 자동).
- 전달로그: D1 editMessage KV 오염→evictNativeSession, D2 cancel 풀 정리(+Events 이동), D3 후속질문 조기중단 cancel, prepare 실패 .failed 확정(markInitFailed), dropModel .idle 갱신.
- 문서갱신: PLAN_v86 신규+검증 기록, TODO T-303~305, CHANGELOG Unreleased, 벤치 분석 안전성 문서화.
- 큐상태: 코드+문서 미커밋 → feat/docs 2커밋 예정, 푸시 보류.
- E2E: 형상 단위 게이트로 대체 (앱내벤치·후속질문 실측은 데픈로그 기대값 유지).
- 후속(T-302): 사용자 확정 "기본 OFF 토글" → PLAN_v87 수립 후 구현. 방 열람(warmupForNextSend, currentSessionID didSet) 시 prepare 선행, 설정→채팅 토글, 재진입·스트리밍 가드, 실패 로그만. tb unit 252/252·lint 신규 0·build OK → feat/docs 커밋 (48e7a02/552b230). 남은: T-302 실측 대조는 사용자 측정 필요.

## 후속 — 응답중 멈춤·wigolo 실패 수정 (T-310/T-311, PLAN_v90)

- 무엇을: ① 채팅 첫 토큰(TTFT) 후 무한 "응답중" (두 모델 모두 FC 미지원) → 빈 도구 + `enableToolCallStreaming:true` 조합의 C++ 디코드 스톨로 판정, `!tools.isEmpty` 제한. 방어용 60초 진행 워치독(`StreamProgressGate`+`stallWatch`)으로 무한 대기 대신 E-MAC-ENG-0005 실패 확정. ② `wigolo serve`가 `env: node` 즉시 실패 — GUI PATH 축약이 원인. `nodeForWigolo`/`wigoloCommand`로 같은 디렉터리 node 직접 실행 + PATH 주입 (serve·init·doctor·--version·npm). ③ 문의 답변만: 첫터치 프리필=방 열람 예열(T-302), 이미지 에러=qwen vision init 실패→폴백으로 이미지 미지원 (모델 응답).
- 플랫폼: macOS (SwiftUI·xcodebuild·swiftlint).
- 빌드+PERF+CACHE: unit 257/257, lint 신규 0 (NativeEngine 400줄 임계 유지 위해 준비 블록 압축), build+~/Applications 설치+실행 OK.
- 남은 TODO: T-302 실측 (사용자 측정), 채팅 재전송 눈확인 (스톨 픽스 실증은 사용자 테스트 필요).
- 전달로그: StreamProgressGate(final class)·stallWatch·handleNativeError·EngineError.timeout(E-MAC-ENG-0005), runServe node 경유, runStreaming environment 선택 파라미터, wigoloCommand 경유 doctor/fetchVersion.
- 문서갱신: PLAN_v90 작성, TODO T-310/T-311 [x], CHANGELOG Unreleased 2줄, error_message_ko.json E-MAC-ENG-0005.
- 큐상태: 코드+문서 미커밋 → feat/docs 2커밋 예정.
- E2E: 형상 단위 게이트로 대체. 실전 확인 항목: 채팅 재전송 완료 로그 + 설정 도구 탭 로그 보기에 `node ... wigolo serve` 정상 출력.

## 후속2 — 스톨 강제 마무리·날짜 주입·FC 조사 (T-311/T-312, PLAN_v90)

- 무엇을: ① T-311 워치독 강화 — C++ 스트림이 cancel에 종료 콜백을 안 주는 경우까지 대비해 `OnceMarker`(1회 보장)·`ProgressCell`(누적 관측) 추가, 워치독이 직접 실패 전환·플래그 해제·저장(`endRun`). `[디코드] chars=… elapsed=…` 2초 로그로 "느림 vs 멈춤" 구분. ② 원인 조사: CLI·Python(동일 config·앱 GPU 캐시·`max_output_tokens=8192`·vision 실패→폴백 시퀀스 포함) 모두 정상 완료 → 앱 전용 `Metal residency=true`가 유력(미확정). ③ `litert-lm describe`: gemma4-12b·qwen3_4b_mixed_int4 **둘 다 Supports Function Call NO** → 웹 검색·도구·`get_time` 전부 불가(모델 한계). ④ T-312 오늘 날짜를 시스템 프롬프트에 자동 주입(네이티브·serve 양쪽), 시각 제외(KV 재사용 보존).
- 플랫폼: macOS (SwiftUI·xcodebuild·swiftlint).
- 빌드+PERF+CACHE: unit 259/259 (T-312 테스트 추가·Refactor `testChatRequest` 기대값 갱신), lint 신규 0 (ChatStore+Generation 무경고), build+~/Applications 설치+실행 OK.
- 남은 TODO: 레지던시 끄고 앱 재실행 후 재전송 실증(사용자 조작 필요). 검색·도구는 FC 지원 모델(FunctionGemma/Gemma4 E2B·E4B) 다운로드 동의 필요.
- 전달로그: `ChatStore.currentDateBlock(now:timeZone:)`(순수)·`chatRequest`/`generationOptions` 주입, `OnceMarker`·`ProgressCell`·`endRun`·`logDecodeProgress`.
- 문서갱신: TODO T-312 [x], CHANGELOG Unreleased T-312 1줄.
- 큐상태: 코드+문서 미커밋.
- E2E: 형상 단위 게이트. 실전 항목: 날짜 질문 응답, 스톨 시 60초 내 E-MAC-ENG-0005 확정.
## 후속3 — 스톨 원인 추적 계측·GPU 배제 (T-311, PLAN_v90)

- 무엇을: ① 원인 후보 추가 배제 — 레지던시 OFF에서도 스톨(원인 아님), 앱·CLI 동일 v0.17.0(버전 갭 아님), Python(GPU·filter_channel_content_from_kv_cache=true·max_output_tokens=8192·vision/audio=None) 재현이 동일 장문 프롬프트에서 90초간 157K자·4680청크 무정지 → GPU/필터/토큰한도 배제, **Swift 경로 전용 문제**로 좁힘. ② 계측 추가: `streamEvents` 소비 루프가 마지막 청크에 도달하면 `[앱내엔진] 엔진 스트림 정상 종료(마지막 청크 도달)`, 실패 시 `E-MAC-ENG-0006 엔진 스트림 오류: …`, `runNative` 소비 루프 종료 시 이벤트 수·글자 수 로그(`NativeStreamState.eventCount`).
- 플랫폼: macOS (SwiftUI·xcodebuild·swiftlint).
- 빌드+PERF+CACHE: unit 259/259, lint 신규 0 (NativeEngine+Events 복잡도 11·본문 56은 HEAD부터 있던 기존 경고 — 신규 아님), build+~/Applications 설치+실행 OK.
- 남은 TODO: 사용자 재현 1회 — 스톨 시 **모델 전환 없이 70초 이상 대기** 후 DebugPanel에서 `스트림 정상 종료`/`E-MAC-ENG-0006`/`E-MAC-ENG-0005` 유무 확인. 정상 종료 로그 없음 = C++ 콜백 미도착(제작사 측), 있음 = 앱 마무리 버그.
- 전달로그: `NativeEngine.logStreamDone()`·`logStreamError(_:)`, `NativeStreamState.eventCount`, error_message_ko.json E-MAC-ENG-0006.
- 문서갱신: CHANGELOG Unreleased T-311 후속3 1건(배제 결과 포함).
- 큐상태: 코드+문서 미커밋 (feat/docs 2커밋 예정, 푸시 보류).
- E2E: 형상 단위 게이트. 실전 항목: 스톨 재현 시 종료 계측 3종 로그 대조.

## 후속4 — 스톨 근본원인 확정·수정 (T-311, PLAN_v90)

- 무엇을: 사용자 재현 로그로 원인 확정 — `[앱내엔진] 엔진 스트림 정상 종료(마지막 청크 도달)`는 찍히나 `소비 루프 종료`가 없음. 즉 **`NativeEngine.streamEvents` 정상 완료 경로가 `continuation.finish()`를 호출하지 않아** `AsyncThrowingStream`이 종료되지 않고 `runNative`의 `for try await`가 영원히 대기 → 텍스트는 나오지만 "응답중"이 안 풀림. `continuation.finish()` 추가로 수정. 다른 브리지(`NativeEngine.stream`, `InferenceEngine` 기본 `streamEvents`)는 정상 finish 확인.
- 플랫폼: macOS (SwiftUI·xcodebuild·swiftlint).
- 빌드+PERF+CACHE: unit 259/259, lint 신규 0 (`streamEvents` 복잡도 11·본문 57은 HEAD 기존 경고), build+~/Applications 설치+실행 OK.
- 남은 TODO: 사용자 재확인 — 응답 완료 시 "응답중" 해제 + `소비 루프 종료 (이벤트 N건…)` 로그 확인. 확인되면 feat/docs 커밋.
- 전달로그: `NativeEngine+Events.swift` 완료 경로 `continuation.finish()` (근본 픽스), 계측 `logStreamDone()`·`logStreamError(_:)`.
- 문서갱신: CHANGELOG Unreleased 근본원인 수정 1건(기존 배제 결과 포함).
- 큐상태: 코드+문서 미커밋 (feat/docs 2커밋 예정, 푸시 보류).
- E2E: 형상 단위 게이트. 실전 항목: 채팅 완료 시 응답중 해제·후속질문 정상·재전송 반복.

## 후속5 — 후속 질문 로딩 애니메이션 (T-313, PLAN_v91)

- 무엇을: 후속 질문 생성 3~4초 동안 정적 스켈레톤이 "멍때리는" 문제 → 심머(밝은 그라데이션이 좌→우 1.2s 루프) 추가, 완료 시 칩 크로스페이드(0.25s). 스켈레톤 바를 칩과 동일 `Capsule`(높이 28, 폭 148/120/164)로 정렬, `동작 줄이기` 시 정적. 초고속 응답 깜빡임 방지용 최소 노출 0.4s(`FollowUpStore.request` sleep, 순수 `minDisplayRemainder`).
- 플랫폼: macOS (SwiftUI·xcodebuild·swiftlint).
- 빌드+PERF+CACHE: unit 260/260(`testFollowUpMinDisplayRemainder` 추가), lint 신규 0 (FollowUpSuggest·ChatPaneView 무경고), build+~/Applications 설치+실행 OK.
- 남은 TODO: 사용자 눈확인(심머·크로스페이드·동작 줄이기 정적). 확인되면 T-311/T-313 일괄 커밋.
- 전달로그: `SkeletonBar`(private)·`FollowUpSkeletonView` Capsule 심머, `FollowUpChipsView`/스켈레톤 `.transition(.opacity)`, `FollowUpSuggest.minLoadingSeconds`·`minDisplayRemainder`, `followUpArea` `.animation`.
- 문서갱신: PLAN_v91 작성, TODO T-313 [x]·T-311 설명 정정(finish 누락), CHANGELOG Unreleased T-313 1건.
- 큐상태: 코드+문서 미커밋 (feat/docs 커밋 예정).
- E2E: 형상 단위 게이트. 실전 항목: 후속 대기 심머·완료 전환·재전송.

## 후속6 — 앱 데이터 홈 통합·스킬 임포트 (T-314/T-315, PLAN_v92)

- 무엇을: ① `StudioPaths`(단일 홈 `~/.litert-lm-studio`, `studioHome` 재지정) 신설 → 경로 9곳(ChatStore·MCPStore·SkillsStore·BenchmarkHistory·ReleaseNotes·NativeEngine.engineCacheDir·ShellTools.workspaceRoot·ModelStoreStaging) 수렴. ② `StudioMigrator` 1회 이사(소형 JSON·스킬=복사→원본 백업, 엔진 캐시·스테이징=이동) + `LiteRTLMStudioApp.init` 훅. ③ `SkillsStore` 멀티 루트(`skillRoots`)·자동 탐색 4곳·`SkillsImportSheet`(설정 스킬 탭).
- 플랫폼: macOS (SwiftUI·xcodebuild·swiftlint).
- 빌드+PERF+CACHE: unit 272/272(신규 12: StudioPaths·Migrator·스킬 임포트), lint 신규 0(SkillsStore 3-tuple→SkillEntry 구조체, SkillsImportSheet를 SettingsView로 이동해 파일 400줄 유지), build+~/Applications 설치+실행 OK.
- 실홈 이사 검증: `~/.litert-lm-studio/{chats,mcp,benchmarks,release-notes.json,engine-cache,staging,workspace}` 생성, `~/Documents/.LiteRT-LM`은 `.DS_Store`만 남음(staging·workspace 이동), 구 App Support JSON·Skills는 백업으로 유지, `studioHomeMigrated=1`.
- 남은 TODO: 설정에서 외부 스킬 폴더 추가·가져오기 눈확인(사용자), studioHome 재지정 실험(선택).
- 전달로그: `StudioPaths`·`StudioMigrator.Summary{failed}`(실패 시 플래그 미설정=재시도), `SkillsStore.scanRoot/SkillEntry/knownExternalRoots/importCandidates/importSkill`, `ErrorCode` E-MAC-STOR-0013/0014.
- 문서갱신: PLAN_v92, TODO T-314/T-315 [x], DESIGN·사용설명서·AGENTS.local 현행화, CHANGELOG Unreleased 2건, error_message_ko.json 2건.
- 큐상태: 코드+문서 미커밋 (feat/docs 커밋 예정, 푸시 보류).
- E2E: 형상 단위 게이트. 실전 항목: 설정→스킬 외부 추가·가져오기, 이사 후 기존 대화·MCP·벤치 기록 정상 로드.

## 후속7 — 스킬 가져오기 UI 강화 (T-315, PLAN_v93)

- 무엇을: AIModelTalk(SkillSettingsView·SkillPickerPopover) 패턴 적용 — `SkillsImportSheet`에 검색(이름·설명 실시간 필터), 출처 캡슐 뱃지(opencode/claude/agents), 헤더 카운트(총/검색/설치됨), 일괄 선택/해제/새로고침 버튼 추가. `SkillsStore`에 `SkillSource` enum(우선순위: opencode > claude > agents > 기타) 신설, 동일 이름 중복 시 높은 우선순위 승. `skillsTab` 행에도 출처 뱃지 표시(기존 "외부" 텍스트 대체).
- 플랫폼: macOS (SwiftUI·xcodebuild·swiftlint).
- 빌드+PERF+CACHE: unit 272/272, swiftlint 신규 0, `build_and_run.sh build macos` OK(설치·실행).
- 남은 TODO: 사용자 실사용 확인(검색·뱃지·일괄 선택 동작), 필요 시 추가 루트(예: `.config/opencode/skill` 단수형) 스캔 대상 추가.
- 전달로그: `SkillSource` enum·`ImportCandidate.source`·`knownExternalRootsWithSource` 우선순위 튜플·`sourceForRoot` 매핑, `SkillsImportSheet` 검색·헤더·액션 버튼, skillsTab 출처 뱃지.
- 문서갱신: PLAN_v93, TODO T-315 갱신, CHANGELOG Unreleased T-315 1건, DESIGN 스킬 섹션 현행화.
- 큐상태: 코드+문서 미커밋 (feat/docs 커밋 예정, 푸시 보류).
- E2E: 형상 단위 게이트. 실전 항목: 설정→스킬 탭→가져오기 시 검색·뱃지·모두선택·새로고침, skillsTab 행 뱃지 확인.
