import AppKit
import XCTest
@testable import LiteRTLMStudio

/// 로직 테스트군 (T-060 파일 분리).
final class LiteRTLMStudioLogicTests: XCTestCase {
    /// 별칭: 자동 예쁘게 + 사용자 별칭 우선 + 빈 값은 해제.
    func testModelAlias() {
        XCTAssertEqual(ModelAlias.pretty(id: "gemma4-12b"), "Gemma 4 · 12B")
        XCTAssertEqual(ModelAlias.pretty(id: "odd_name"), "odd_name")
        ModelAlias.setAlias(id: "test-model-x", name: "내 모델")
        XCTAssertEqual(ModelAlias.display(id: "test-model-x"), "내 모델")
        ModelAlias.setAlias(id: "test-model-x", name: "   ")
        XCTAssertEqual(ModelAlias.display(id: "test-model-x"), ModelAlias.pretty(id: "test-model-x"))
    }

    /// 초안/적용/취소: 임시 경로로 실제 디스크 왕복 (실제 config 불변).
    @MainActor
    func testConfigDraftApplyRevert() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("litert-test-\(UUID().uuidString).json")
        let store = ConfigStore(configURL: tmp)
        XCTAssertFalse(store.hasChanges)
        store.draftBackend = "cpu"
        XCTAssertTrue(store.hasChanges)
        XCTAssertTrue(store.diffSummary.contains("cpu"))
        XCTAssertTrue(store.apply(modelID: "m1"))
        XCTAssertFalse(store.hasChanges)
        XCTAssertEqual(store.appliedBackend, "cpu")
        let reloaded = ConfigStore(configURL: tmp)
        reloaded.load(modelID: "m1")
        XCTAssertEqual(reloaded.appliedBackend, "cpu")
        store.draftVision = "cpu"
        store.revert()
        XCTAssertFalse(store.hasChanges)
        XCTAssertEqual(store.draftVision, "gpu")
        try? FileManager.default.removeItem(at: tmp)
    }

    /// 실행 설정 확장 (T-175): 숫자 파싱·예산·신규 키 왕복.
    @MainActor
    func testConfigExtendedKeys() async throws {
        XCTAssertEqual(ConfigStore.intOrNil("", min: 1), nil)
        XCTAssertEqual(ConfigStore.intOrNil("abc", min: 1), nil)
        XCTAssertEqual(ConfigStore.intOrNil("0", min: 1), nil)
        XCTAssertEqual(ConfigStore.intOrNil("16", min: 1), 16)
        XCTAssertEqual(ConfigStore.budgetOrUnlimited(""), -1)
        XCTAssertEqual(ConfigStore.budgetOrUnlimited("4096"), 4096)
        XCTAssertEqual(ConfigStore.budgetOrUnlimited("-9"), -1)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("litert-test-\(UUID().uuidString).json")
        let store = ConfigStore(configURL: tmp)
        store.draftAudio = "gpu"
        store.draftThreads = "8"
        store.draftCache = "memory"
        store.draftKV = "10000"
        store.draftThinking = true
        store.draftBudget = "4096"
        XCTAssertTrue(store.hasChanges)
        XCTAssertTrue(store.diffSummary.contains("Audio"))
        XCTAssertTrue(store.apply(modelID: "m1"))
        let reloaded = ConfigStore(configURL: tmp)
        reloaded.load(modelID: "m1")
        XCTAssertEqual(reloaded.appliedAudio, "gpu")
        XCTAssertEqual(reloaded.appliedThreads, "8")
        XCTAssertEqual(reloaded.appliedCache, "memory")
        XCTAssertEqual(reloaded.appliedKV, "10000")
        XCTAssertTrue(reloaded.appliedThinking)
        XCTAssertEqual(reloaded.appliedBudget, "4096")
        // 빈칸이면 키 삭제 (엔진 기본 복귀).
        reloaded.draftThreads = ""
        reloaded.draftKV = ""
        reloaded.draftBudget = ""
        XCTAssertTrue(reloaded.apply(modelID: "m1"))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: tmp)) as? [String: Any]
        let def = json?["default"] as? [String: Any]
        XCTAssertNil(def?["cpu_thread_count"])
        XCTAssertNil(def?["max_num_tokens"])
        let one = (json?["models"] as? [String: Any])?["m1"] as? [String: Any]
        XCTAssertEqual(one?["thinking_budget"] as? Int, -1)
        try? FileManager.default.removeItem(at: tmp)
    }

    /// 메뉴바 상태 색 매핑.
    func testMenuStatusKeys() {
        XCTAssertEqual(MenuStatus.dotKey(for: .running), "green")
        XCTAssertEqual(MenuStatus.dotKey(for: .starting), "orange")
        XCTAssertEqual(MenuStatus.dotKey(for: .failed), "red")
        XCTAssertEqual(MenuStatus.dotKey(for: .stopped), "gray")
    }

    /// 실효 scheme: 시스템 모드는 환경 다크 여부를 명시로 풂 (T-042).
    func testEffectiveScheme() {
        XCTAssertEqual(AppearanceMode.effectiveScheme(mode: .system, systemDark: true), .dark)
        XCTAssertEqual(AppearanceMode.effectiveScheme(mode: .system, systemDark: false), .light)
        XCTAssertEqual(AppearanceMode.effectiveScheme(mode: .light, systemDark: true), .light)
        XCTAssertEqual(AppearanceMode.effectiveScheme(mode: .dark, systemDark: false), .dark)
    }

    /// 스트리밍 전환 동등성: 종료 시 텍스트 같아도 갱신 (finalize용, T-050).
    func testMarkdownEquatable() {
        XCTAssertEqual(MarkdownView(text: "a"), MarkdownView(text: "a"))
        XCTAssertNotEqual(MarkdownView(text: "a"), MarkdownView(text: "b"))
        XCTAssertNotEqual(MarkdownView(text: "a", scheme: .light),
                          MarkdownView(text: "a", scheme: .dark))
        XCTAssertNotEqual(MarkdownView(text: "a", isStreaming: true),
                          MarkdownView(text: "a", isStreaming: false))
    }

    /// 추종 게이트: 고정+간격+휠정지일 때만 발사 (T-044).
    func testShouldFollow() {
        let now = Date()
        XCTAssertTrue(ContentView.shouldFollow(pinned: true, now: now,
                                               lastFollow: now.addingTimeInterval(-1),
                                               lastWheel: now.addingTimeInterval(-1)))
        XCTAssertFalse(ContentView.shouldFollow(pinned: false, now: now,
                                                lastFollow: .distantPast,
                                                lastWheel: .distantPast))
        XCTAssertFalse(ContentView.shouldFollow(pinned: true, now: now,
                                                lastFollow: now.addingTimeInterval(-0.1),
                                                lastWheel: .distantPast))
        XCTAssertFalse(ContentView.shouldFollow(pinned: true, now: now,
                                                lastFollow: .distantPast,
                                                lastWheel: now.addingTimeInterval(-0.1)))
    }

    /// 내용 증가 판정: 0.5pt 초과 성장일 때만 (T-048).
    func testContentGrew() {
        XCTAssertTrue(ContentView.contentGrew(current: 101, last: 100))
        XCTAssertFalse(ContentView.contentGrew(current: 100.4, last: 100))
        XCTAssertFalse(ContentView.contentGrew(current: 90, last: 100))
        XCTAssertFalse(ContentView.contentGrew(current: 0, last: 0))
    }

    /// 내용 축소 판정: 40pt 초과 축소(재시도 삭제급)만 리셋 대상 (T-106).
    func testContentShrank() {
        XCTAssertTrue(ContentView.contentShrank(current: 900, last: 1000))
        XCTAssertFalse(ContentView.contentShrank(current: 970, last: 1000))
        XCTAssertFalse(ContentView.contentShrank(current: 1010, last: 1000))
        XCTAssertFalse(ContentView.contentShrank(current: 0, last: 0))
    }

    /// 빈 영역 판정 (T-198): 문서 밖 오프셋만 보정, 정상 위치는 제외.
    func testBlankOffset() {
        // 긴 방 잔재 오프셋으로 짧은 방 진입 → 보정 대상.
        XCTAssertTrue(ContentView.blankOffset(cur: 5000, docHeight: 600, clipHeight: 800))
        // 하단·읽는 중(중간)·짧은 문서 정상 → 제외.
        XCTAssertFalse(ContentView.blankOffset(cur: 0, docHeight: 600, clipHeight: 800))
        XCTAssertFalse(ContentView.blankOffset(cur: 300, docHeight: 2000, clipHeight: 800))
        XCTAssertFalse(ContentView.blankOffset(cur: 0, docHeight: 0, clipHeight: 800))
    }

    /// 위 고착 판정 (T-202): 여지 있는데 상단이면 보정, 하단·짧은 문서는 제외.
    func testTopStuck() {
        XCTAssertTrue(ContentView.topStuck(offset: 0, docHeight: 2000, clipHeight: 800))
        XCTAssertFalse(ContentView.topStuck(offset: 1150, docHeight: 2000, clipHeight: 800))
        XCTAssertFalse(ContentView.topStuck(offset: 0, docHeight: 600, clipHeight: 800))
    }

    /// 삭제 액션 중복 발사 가드 (T-113): 동일 ID 1초 내 재호출만 무시.
    func testAllowDelete() {
        let id = UUID()
        XCTAssertTrue(SessionListView.allowDelete(id: id, lastID: nil, lastAt: .distantPast,
                                                  now: Date()))
        XCTAssertTrue(SessionListView.allowDelete(id: UUID(), lastID: id,
                                                  lastAt: Date(), now: Date()))
        XCTAssertFalse(SessionListView.allowDelete(id: id, lastID: id,
                                                   lastAt: Date(), now: Date()))
        XCTAssertTrue(SessionListView.allowDelete(id: id, lastID: id,
                                                  lastAt: Date().addingTimeInterval(-2),
                                                  now: Date()))
    }

    /// 빈 화면 문구 2종 (T-143): 실행 중=환영형, 그 외=서버 시작 안내.
    func testEmptyStateCopy() {
        let running = ContentView.emptyStateCopy(isRunning: true)
        XCTAssertEqual(running.title, "무엇을 도와드릴까요?")
        XCTAssertEqual(running.message, "아래에 질문을 입력하세요")
        let stopped = ContentView.emptyStateCopy(isRunning: false)
        XCTAssertEqual(stopped.title, "서버를 시작하고 채팅해 보세요")
        XCTAssertTrue(stopped.message.contains("⌘R"))
    }

    /// 전송 가능 판정 (T-146): 스트리밍 제외, 데몬 또는 네이티브 준비.
    func testSendAllowed() {
        typealias C = ChatStore
        XCTAssertFalse(C.sendAllowed(streaming: true, daemonRunning: true, nativeReady: true))
        XCTAssertTrue(C.sendAllowed(streaming: false, daemonRunning: true, nativeReady: false))
        XCTAssertTrue(C.sendAllowed(streaming: false, daemonRunning: false, nativeReady: true))
        XCTAssertFalse(C.sendAllowed(streaming: false, daemonRunning: false, nativeReady: false))
        XCTAssertTrue(C.sendAllowed(streaming: false, daemonRunning: true, nativeReady: true))
    }

    /// 네이티브 모드 데몬 캡션 (T-146): pid 없으면 없음, 있으면 대기 표기.
    func testNativeDaemonCaption() {
        XCTAssertEqual(SystemMetersView.nativeDaemonCaption(cpu: 0, rssGB: 0, pidCount: 0), "데몬 없음")
        XCTAssertEqual(SystemMetersView.nativeDaemonCaption(cpu: 0, rssGB: 0.03, pidCount: 2),
                       "데몬 대기 중 · CPU 0% · 0.03GB")
    }

    /// 스트리밍 화면 묶음 갱신 판정 (T-148): 0.1초 간격.
    func testShouldFlushText() {
        typealias C = ChatStore
        let base = Date()
        XCTAssertFalse(C.shouldFlushText(now: base, lastFlush: base))
        XCTAssertFalse(C.shouldFlushText(now: base.addingTimeInterval(0.05), lastFlush: base))
        XCTAssertTrue(C.shouldFlushText(now: base.addingTimeInterval(0.11), lastFlush: base))
    }

    /// SSE 한 줄 적용 (T-148): DONE·무의미줄 종료, 데이터 누적+반영.
    @MainActor
    func testApplySSELine() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-sseline-\(UUID().uuidString).json")
        let store = ChatStore(storageURL: url)
        store.messages.append(ChatStore.Message(role: "assistant", text: ""))
        var st = ChatStore.SSEStreamState(lastFlush: .distantPast)
        let started = Date()
        XCTAssertTrue(store.applySSELine("data: [DONE]", state: &st, idx: 0, started: started))
        XCTAssertFalse(store.applySSELine("", state: &st, idx: 0, started: started))
        XCTAssertEqual(st.acc, "")
        let data = "data: {\"choices\":[{\"delta\":{\"content\":\"안녕\"}}]}"
        XCTAssertFalse(store.applySSELine(data, state: &st, idx: 0, started: started))
        XCTAssertEqual(st.acc, "안녕")
        XCTAssertEqual(store.messages[0].text, "안녕")
        XCTAssertNotNil(st.firstTokenAt)
        try? FileManager.default.removeItem(at: url)
    }

    /// 전송 히스토리 윈도우 (T-149): 0 이하면 전량, 양수면 뒤 2N개.
    func testWindowedHistory() {
        typealias M = ChatStore.Message
        let msgs = (0..<10).map { M(role: $0 % 2 == 0 ? "user" : "assistant", text: "m\($0)") }
        XCTAssertEqual(ChatStore.windowedHistory([], turns: 20).count, 0)
        XCTAssertEqual(ChatStore.windowedHistory(msgs, turns: 0).count, 10)
        XCTAssertEqual(ChatStore.windowedHistory(msgs, turns: -1).count, 10)
        XCTAssertEqual(ChatStore.windowedHistory(msgs, turns: 20).count, 10)
        let cut = ChatStore.windowedHistory(msgs, turns: 2)
        XCTAssertEqual(cut.count, 4)
        XCTAssertEqual(cut.first?.text, "m6")
        XCTAssertEqual(cut.last?.text, "m9")
    }

    /// 클램프 목표: [0, 최대] 구간 제한 (T-054).
    func testClampedTargetY() {
        XCTAssertEqual(ContentView.clampedTargetY(target: 400, docHeight: 1000, clipHeight: 600), 400)
        XCTAssertEqual(ContentView.clampedTargetY(target: 900, docHeight: 1000, clipHeight: 600), 400)
        XCTAssertEqual(ContentView.clampedTargetY(target: -50, docHeight: 1000, clipHeight: 600), 0)
        XCTAssertEqual(ContentView.clampedTargetY(target: 100, docHeight: 400, clipHeight: 600), 0)
    }

    /// 절대 점프 목표·하단 판정 (T-047).
    func testBottomJumpMath() {
        XCTAssertEqual(ContentView.bottomTargetY(docHeight: 1000, clipHeight: 600), 400)
        XCTAssertEqual(ContentView.bottomTargetY(docHeight: 400, clipHeight: 600), 0)
        XCTAssertTrue(ContentView.isAtBottomOffset(offset: 400, content: 1000, container: 600))
        XCTAssertTrue(ContentView.isAtBottomOffset(offset: 350, content: 1000, container: 600))
        XCTAssertFalse(ContentView.isAtBottomOffset(offset: 300, content: 1000, container: 600))
        XCTAssertTrue(ContentView.isAtBottomOffset(offset: 0, content: 400, container: 600))
    }

    /// 디버그 패널 빈 상태 구분 (T-055).
    func testDebugPanelEmptyKind() {
        XCTAssertEqual(DebugPanelView.emptyKind(entryCount: 5, rowCount: 3), .none)
        XCTAssertEqual(DebugPanelView.emptyKind(entryCount: 0, rowCount: 0), .noLogs)
        XCTAssertEqual(DebugPanelView.emptyKind(entryCount: 5, rowCount: 0), .noMatch)
    }

    /// 디버그 패널 검색·시간 (T-053/T-057): 밀리초 형식+일치+레벨AND검색.
    func testDebugPanelSearch() {
        XCTAssertEqual(DebugPanelView.timeString(Date(timeIntervalSince1970: 0)).count, 12)
        let err = DebugLogger.Entry(level: .error, feature: "마크다운", message: "렌더 실패")
        let info = DebugLogger.Entry(level: .info, feature: "앱시작", message: "상태 복원 완료")
        XCTAssertTrue(DebugPanelView.matches(err, query: ""))
        XCTAssertTrue(DebugPanelView.matches(err, query: "렌더"))
        XCTAssertTrue(DebugPanelView.matches(err, query: "ERROR"))
        XCTAssertTrue(DebugPanelView.matches(err, query: "마크다운"))
        XCTAssertFalse(DebugPanelView.matches(info, query: "렌더"))
        let rows = DebugPanelView.filteredRows([err, info], level: .error, query: "렌더")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.level, .error)
        XCTAssertEqual(DebugPanelView.filteredRows([err, info], level: nil, query: "").count, 2)
    }

    /// 수동 외관 매핑: scheme+NSAppearance (T-041).
    func testAppearanceMapping() {
        XCTAssertEqual(AppearanceMode.system.markdownScheme, .auto)
        XCTAssertEqual(AppearanceMode.light.markdownScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.markdownScheme, .dark)
        XCTAssertNil(AppearanceMode.system.nsAppearance)
        XCTAssertNotNil(AppearanceMode.light.nsAppearance)
        XCTAssertNotNil(AppearanceMode.dark.nsAppearance)
    }

    /// 데몬 상태 전이표.
    func testDaemonTransition() {        typealias T = DaemonManager
        // 외부 기동 감지 → 연결
        var next = T.transition(status: .stopped, external: false, muted: false, healthy: true, streak: 0)
        XCTAssertEqual(next.status, .running)
        XCTAssertTrue(next.external)
        // mute면 재연결 억제
        next = T.transition(status: .stopped, external: false, muted: true, healthy: true, streak: 0)
        XCTAssertEqual(next.status, .stopped)
        // 시작 중은 폴러가 건드리지 않음
        next = T.transition(status: .starting, external: false, muted: false, healthy: true, streak: 0)
        XCTAssertEqual(next.status, .starting)
        // 3회 연속 불량 → 실패 확정
        next = T.transition(status: .running, external: true, muted: false, healthy: false, streak: 0)
        XCTAssertEqual(next.status, .running)
        XCTAssertEqual(next.streak, 1)
        next = T.transition(status: .running, external: true, muted: false, healthy: false, streak: 2)
        XCTAssertEqual(next.status, .failed)
        XCTAssertFalse(next.external)
    }

    /// 미연결 외부 실행 판정 (T-179): mute+healthy일 때만 true.
    func testUnlinkedRunning() {
        typealias T = DaemonManager
        XCTAssertTrue(T.unlinkedRunning(muted: true, healthy: true))
        XCTAssertFalse(T.unlinkedRunning(muted: false, healthy: true))
        XCTAssertFalse(T.unlinkedRunning(muted: true, healthy: false))
        XCTAssertFalse(T.unlinkedRunning(muted: false, healthy: false))
    }

    /// 대화 재사용 키 (T-191): 저장분이 현재 앞부분+동일 모델·옵션이면 KV 이어쓰기.
    func testConvKeyReuses() {
        typealias K = NativeEngine.ConvKey
        let opts = GenerationOptions()
        let stored = K(modelID: "m", history: ["user\nhi"], options: opts)
        // 이어진 대화 → 재사용
        XCTAssertTrue(K.reuses(stored: stored, modelID: "m",
                               history: ["user\nhi", "assistant\nhello", "user\nmore"], options: opts))
        // 동일 길이 동일 내용 → 재사용
        XCTAssertTrue(K.reuses(stored: stored, modelID: "m",
                               history: ["user\nhi"], options: opts))
        // 재시도(축소)·모델 변경·옵션 변경 → 재생성
        XCTAssertFalse(K.reuses(stored: stored, modelID: "m", history: [], options: opts))
        XCTAssertFalse(K.reuses(stored: stored, modelID: "other",
                                history: ["user\nhi"], options: opts))
        var other = opts
        other.temperature = 0.1
        XCTAssertFalse(K.reuses(stored: stored, modelID: "m",
                                history: ["user\nhi"], options: other))
        // 앞부분 불일치 → 재생성
        XCTAssertFalse(K.reuses(stored: stored, modelID: "m",
                                history: ["user\nother"], options: opts))
        // 항목 결합 형식
        XCTAssertEqual(K.entries([(role: "user", text: "hi")]), ["user\nhi"])
    }

    /// Ollama식 통합 상태 (T-183): 대화 가능 = 데몬 실행 중 OR 네이티브 준비됨.
    func testUnifiedStatus() {
        typealias U = UnifiedStatus
        // 네이티브 준비 + 데몬 중지 → 대화 가능 (현재 사용자 케이스)
        var s = U.resolve(daemonRunning: false, unlinkedRunning: false,
                          engineMode: .native, preparedLabel: "Gemma 4 · 12B")
        XCTAssertEqual(s.title, "대화 가능")
        XCTAssertTrue(s.live)
        XCTAssertFalse(s.unlinked)
        // 둘 다 없음 → 중지됨
        s = U.resolve(daemonRunning: false, unlinkedRunning: false,
                      engineMode: .native, preparedLabel: nil)
        XCTAssertEqual(s.title, "중지됨")
        XCTAssertFalse(s.live)
        // 데몬 실행 중 → 대화 가능
        s = U.resolve(daemonRunning: true, unlinkedRunning: false,
                      engineMode: .cli, preparedLabel: nil)
        XCTAssertEqual(s.title, "대화 가능")
        XCTAssertTrue(s.live)
        // 둘 다 → 데몬+네이티브 표기
        s = U.resolve(daemonRunning: true, unlinkedRunning: false,
                      engineMode: .native, preparedLabel: "Gemma 4 · 12B")
        XCTAssertTrue(s.detail.contains("데몬+네이티브"))
        // 미연결 → 주황 유지 (T-179 계승)
        s = U.resolve(daemonRunning: false, unlinkedRunning: true,
                      engineMode: .native, preparedLabel: "Gemma 4 · 12B")
        XCTAssertTrue(s.unlinked)
        XCTAssertFalse(s.live)
    }

    /// 전송 보정 판정 (T-135): 준비중→하단, 스트리밍→방치, 그 외→재앵커.
    func testSendCorrectAction() {
        typealias A = ContentView.SendCorrectAction
        XCTAssertEqual(ContentView.sendCorrectAction(preparing: true, streaming: false), .jumpBottom)
        XCTAssertEqual(ContentView.sendCorrectAction(preparing: true, streaming: true), .jumpBottom)
        XCTAssertEqual(ContentView.sendCorrectAction(preparing: false, streaming: true), .none)
        XCTAssertEqual(ContentView.sendCorrectAction(preparing: false, streaming: false), .reanchor)
    }
}
