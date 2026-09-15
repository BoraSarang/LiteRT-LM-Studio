# PLAN v6 — 구조 리팩토링 (macOS, T-114~T-121)

> 범위: A 파일분리 + B 중복제거 + C 구조개선. 동작 변경 없음이 원칙. 테스트 공개 API 전부 유지.

## 1. 분석 요약 (2026-09-14 실측)

* 총 5740줄·Swift 21파일. God 파일: `ContentView.swift` 999·`ChatBubbles.swift` 696·`MarkdownView.swift` 605·`LiteRTLMStudioTests.swift` 695·`SystemMonitor.swift` 460·`LiteRTLMStudioApp.swift` 334·`ChatStore.swift` 350.
* 미커밋 7건 + `PLAN_v5` untracked. 본 작업은 작업트리 위에서 진행, 커밋은 별도 지시 전까지 금지.
* `DESIGN.md`는 T-100까지만 반영됨. 본 PLAN 후 구조 섹션 갱신.

## 2. 작업 목록

* T-114 B 공통유틸: `Core/PasteboardUtil.swift`·`Core/TimeFormat.swift`·`Core/ImageUtil.swift` 신규. 복사 4곳·시간포맷 2곳·이미지축소 1곳을 호출로 교체. 구 API는 래퍼로 유지.
* T-115 A 앱분리: `LiteRTLMStudioApp.swift` 334 → 본체 + `AppServices.swift` + `MenuBarView.swift` + `SettingsView.swift` + `AppNotifications.swift`(Notification.Name). 타입명·동작 동일.
* T-116 A 채팅분리: `ChatBubbles.swift` 696 → `SessionListView.swift` + `MessageBubbles.swift`(디스패처+유저+어시스턴트+상대시간) + `ChatInputBar.swift` + `BottomPanelView.swift`(+SystemCell). 구조체명 동일.
* T-117 A 콘텐츠분리: `ContentView.swift` 999 → 본체(툴바·task·onChange) + `FollowGate.swift`(게이트+Finder) + `SidebarView.swift` + `InspectorView.swift` + `ChatPaneView.swift` + `ChatScrollActions.swift`(진입·추종·점프 impure) + `PaletteViews.swift`. `ScrollMath.swift` 순수함수는 유지, 테스트 호출 `ContentView.xxx` 그대로.
* T-118 A 마크다운·모니터·스토어분리: `MarkdownWebView.swift`+`MarkdownPage.swift`, `SystemMonitor+Sampling.swift`+`SystemMonitor+Daemon.swift`, `ChatStore+Session.swift`+`ChatStore+SSE.swift`. 타입·함수명 유지.
* T-119 C 구조개선(저위험): Markdown 캐시 NSLock, `DebugLogger` 2000 cap, `ChatStore` SSE Codable 파서+요청빌더 순수추출, `DaemonManager.isHealthy` 5초 타임아웃. 공개 시그니처 불변.
  - 제외 기록: 영속 write 디바운스 제외 (T-108 회귀가 즉시 영속을 요구), lsof 백그라운드화 제외 (5틱 캐시로 충분, 타이밍 위험).
* T-120 테스트분리: `LiteRTLMStudioTests.swift` 695 단일 → 클래스별 3파일. 케이스 내용 불변.
* T-121 검증: `build_and_run.sh test macos unit` + swiftlint + `build macos`는 실행 없이 `xcodebuild build`만(사용자 사용 중 포커스 스틸 금지).

## 3. API 보존 목록 (테스트 직참조, 이름 변경 금지)

* `ContentView.*`: isPinnedToBottom·shouldFollow·switchJumpTarget·clampedZoom·steppedZoom·clampedTargetY·bottomTargetY·isAtBottomOffset·contentGrew·contentShrank·entryConverged·docStable·shouldJump·wheelStamp·anyVisible·columnShown.
* `MarkdownPage.*`: heightKey·widthBucket·cachedHeight·storeHeight·heightKeyAgnostic·cachedHeightAgnostic·storeHeightAgnostic·stableHashPrefix·persistAgnostic·loadPersistedAgnostic·themeName·loadResource·template·resourceCache·heightCache·agnosticPersistKey·lastPaintAt.
* `MarkdownWebView.*`: widthChanged·resolveAction·needsFlush·shouldRetryEmpty·jsLiteral·fittedHeight·fontPx·RenderAction·apply·runJS + `Coordinator`.
* `ChatInputBar.rowsFor`·`editorHeight`, `SessionListView.allowDelete`, `DaemonManager.stampedLines`·`logTimeString`·`transition`, `SystemMonitor` cpuPercent·ramUsedBytes·ramInactiveBytes·daemonCPUPercent·gpuFromStats·clamp100·cpuStacked·ramStacked·xDomain·totalMemoryGB·CPUTicks·cpuSplit·ramComponentBytes·descendants·pids·shouldReportDaemonMismatch·lsofHead, `SystemMetersView` cpuPopoverRows·ramPopoverRows·ramUsedPct, `DebugPanelView` timeString·matches·filteredRows·emptyKind, `AppearanceMode` effectiveScheme·markdownScheme·nsAppearance, `ModelAlias`·`ConfigStore`·`ChatStore.sortedSessions`·`Session`·`AboutLibraries.all`·`MenuStatus.dotKey`·`AppServices.shouldStopDaemon`·전역 `chatRelativeTime`.

## 4. 위험과 가드

* pbxproj 명시 참조라 신규 파일마다 FileReference+BuildFile+Group+Sources 4곳 추가 필요. 파이썬 스크립트로 원자 추가 후 매 배치 `xcodebuild -showBuildSettings` 수준 확인. 실패 시 즉시 revert.
* `rm -rf`·번들ID·포트·모델경로·권한 변경 없음. 파괴적 가드 해당 없음.
* full 스위트·E2E full·k6는 사용자 허락 전 실행 금지. smoke+unit만.

## 5. 검증 게이트

* 배치마다: `xcodebuild test -only-testing` 관련 클래스 → 전체 unit → `swiftlint --quiet` 신규 경고 0 → `xcodebuild build`.
* 사용 중 공존: headless, 병렬 2 이하, `open`·포그라운드 실행 금지.

## 6. 2차 정밀 조사 (T-122~T-127, 2026-09-14 재조사, 린트 41건 기준)

* R-0 린트 정리 (T-122): 미사용 클로저 인자·명시 nil·trailing comma 4·줄길이 4·switch 정렬·파라미터 정렬 5. 동작 무영향.
* R-1 사망코드 제거 (T-123): `ChatHolder`·`checkPortInUse`·`upgradeLitertLM`·`switchJumpTarget`(+테스트 1종, §3 목록에서 제외)·`ChatBubbles` shim(+pbxproj). 미사용 에러코드 2건(E-MAC-STOR-0006·E-MAC-NET-0002)은 json 유지 (외부 문서 참조 가능). git에서 복원 가능.
* R-2 테스트 보강 (T-124): `ChatSSEParser`·`ImageUtil`·`TimeFormat`·로그 cap 회귀. 신규 로직 DoD 준수.
* R-3 토큰/컴포넌트 (T-125): DS 미사용 토큰 정리 + 11pt 21곳 `captionFont` 교체, `CardBox`·`CopyFeedbackButton`·`OnSizeChange` 신규, 차트 4종은 공용 빌더로 (Charts API라 분리 검증).
* R-4 복잡함수 분해 (T-126): `entryPoll`·`updateNSView`·`template`·`send`·`ingest` 순수 추출 + 회귀 테스트. 공개 API 불변.
* R-5 성능/견고성 (T-127): `ModelStore.refresh` TaskGroup 병렬 (순서 보존), `UvManager.run` 타임아웃, `resourceCache` 락, `TimeFormat` 포매터 캐시.
* T-128 결과: unit 68/68, 린트 41→4. 잔여 4건 수용 사유: `transition`·`cpuStacked`/`ramStacked`·`resolveAction`은 테스트 고정 시그니처, `Session.CodingKeys`는 Codable 필수 내장.
