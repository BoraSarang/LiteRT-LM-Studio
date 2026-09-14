import AppKit
import XCTest
@testable import LiteRTLMStudio

/// smoke: 에러 메시지 매핑 무결성 (한국어 분리 파일 로드).
final class LiteRTLMStudioTests: XCTestCase {
    func testErrorMessagesKorean() throws {
        // 번들 리소스에서 로드: 문서 폴더 TCC 접근 회피 (프로젝트가 ~/Documents 하위).
        // error_message_ko.json은 테스트 타깃 Copy Bundle Resources에 포함.
        let bundle = Bundle(for: LiteRTLMStudioTests.self)
        guard let jsonURL = bundle.url(forResource: "error_message_ko", withExtension: "json") else {
            XCTFail("error_message_ko.json이 테스트 번들에 없음 (Copy Bundle Resources 확인)")
            return
        }
        let data = try Data(contentsOf: jsonURL)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertNotNil(dict?["E-MAC-VALID-0001"])
        XCTAssertNotNil(dict?["E-MAC-NET-0002"])
    }

    func testDaemonDefaults() {
        XCTAssertEqual(DaemonManager.host, "127.0.0.1")
        XCTAssertEqual(DaemonManager.port, 9379)
    }

    /// 회귀: list 안내 줄·헤더 행은 모델로 세지 않는다 (“모델 (2)” 버그).
    func testParseListSkipsHeader() {
        let sample = """
        Listing models in: /Users/lee/.litert-lm/models
        ID                          SIZE            MODIFIED
        gemma4-12b                  6.4 GB          2026-09-13 09:58:20
        """
        let models = ModelStore.parseList(sample)
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.id, "gemma4-12b")
        XCTAssertEqual(models.first?.listedSize, "6.4 GB")
        XCTAssertEqual(ModelStore.parseList(""), [])
    }

    /// CPU 델타 계산: 사용 75 + 유휴 25 → 75%.
    func testCpuPercentMath() {
        let pct = SystemMonitor.cpuPercent(used: 175, idle: 125, prevUsed: 100, prevIdle: 100)
        XCTAssertEqual(pct ?? -1, 75.0, accuracy: 0.001)
        XCTAssertNil(SystemMonitor.cpuPercent(used: 100, idle: 100, prevUsed: 100, prevIdle: 100))
    }

    /// RAM 바이트 계산: 활성 상태 보기 정의 (active+wired+compressed, inactive 제외).
    func testRamMath() {
        let bytes = SystemMonitor.ramUsedBytes(active: 100, inactive: 50, wired: 40, compressed: 10, pageSize: 16384)
        XCTAssertEqual(bytes, 150 * 16384)
        XCTAssertEqual(SystemMonitor.ramInactiveBytes(inactive: 50, pageSize: 16384), 50 * 16384)
    }

    /// 데몬 CPU%: 실측 경과초 나눔, 단일코어 기준 (100 초과 허용).
    func testDaemonCPUPercent() {
        XCTAssertEqual(SystemMonitor.daemonCPUPercent(deltaNS: 1_000_000_000, elapsed: 1.0), 100.0, accuracy: 0.001)
        XCTAssertEqual(SystemMonitor.daemonCPUPercent(deltaNS: 1_000_000_000, elapsed: 1.2), 83.333, accuracy: 0.01)
        XCTAssertEqual(SystemMonitor.daemonCPUPercent(deltaNS: 2_000_000_000, elapsed: 1.0), 200.0, accuracy: 0.001)
        XCTAssertEqual(SystemMonitor.daemonCPUPercent(deltaNS: 1_000_000_000, elapsed: 0), 0.0, accuracy: 0.001)
    }

    /// 데몬 불일치 보고 (T-073): 실행 중+0개+미기록일 때만 1회.
    func testDaemonMismatch() {
        XCTAssertTrue(SystemMonitor.shouldReportDaemonMismatch(running: true, pidCount: 0, alreadyLogged: false))
        XCTAssertFalse(SystemMonitor.shouldReportDaemonMismatch(running: true, pidCount: 0, alreadyLogged: true))
        XCTAssertFalse(SystemMonitor.shouldReportDaemonMismatch(running: true, pidCount: 2, alreadyLogged: false))
        XCTAssertFalse(SystemMonitor.shouldReportDaemonMismatch(running: false, pidCount: 0, alreadyLogged: false))
        XCTAssertEqual(SystemMonitor.pids(fromLsof: "85921\n85922\n"), [85921, 85922])
        XCTAssertEqual(SystemMonitor.pids(fromLsof: ""), [])
    }

    /// 팝오버 행 포맷 (T-073): CPU 3행·RAM 4행.
    func testMeterPopoverRows() {
        let cpu = SystemMetersView.cpuPopoverRows(sys: 7, user: 11)
        XCTAssertEqual(cpu.map(\.label), ["시스템", "사용자", "유휴"])
        XCTAssertEqual(cpu.map(\.value), ["7%", "11%", "82%"])
        let ram = SystemMetersView.ramPopoverRows(app: 13.6, wired: 2.1, comp: 0.5, cache: 1.2)
        XCTAssertEqual(ram.map(\.label), ["App", "Wired", "압축", "캐시"])
        XCTAssertEqual(ram.map(\.value), ["13.6GB", "2.1GB", "0.5GB", "1.2GB"])
    }

    /// 타이틀 % (T-074): RAM 사용률.
    func testRamUsedPct() {
        XCTAssertEqual(SystemMetersView.ramUsedPct(usedGB: 16, totalGB: 32), 50.0, accuracy: 0.001)
        XCTAssertEqual(SystemMetersView.ramUsedPct(usedGB: 0, totalGB: 0), 0.0, accuracy: 0.001)
    }

    /// 진입 수렴 판정 (T-079): 스크롤 여지 있을 때만 성공, 미성장 문서는 재시도.
    func testEntryConverged() {
        XCTAssertTrue(ContentView.entryConverged(offsetY: 900, docHeight: 1500, clipHeight: 600))
        XCTAssertTrue(ContentView.entryConverged(offsetY: 850, docHeight: 1500, clipHeight: 600))
        XCTAssertFalse(ContentView.entryConverged(offsetY: 100, docHeight: 1500, clipHeight: 600))
        // 미성장 문서: 맨 위도 성공 아님 (후속탭 차단 금지).
        XCTAssertFalse(ContentView.entryConverged(offsetY: 0, docHeight: 300, clipHeight: 600))
        XCTAssertFalse(ContentView.entryConverged(offsetY: 0, docHeight: 0, clipHeight: 600))
    }

    /// 문서 안정·휠 누적 판정 (T-080).
    func testEntryStability() {
        XCTAssertTrue(ContentView.docStable([100, 100.5, 100]))
        XCTAssertFalse(ContentView.docStable([24, 300, 900]))
        XCTAssertFalse(ContentView.docStable([100]))
        let r1 = ContentView.wheelStamp(accum: 0, delta: 3)
        XCTAssertFalse(r1.stamp)
        let r2 = ContentView.wheelStamp(accum: r1.accum, delta: 6)
        XCTAssertTrue(r2.stamp)
        XCTAssertEqual(r2.accum, 0, accuracy: 0.001)
    }

    /// 점프 데드밴드 (T-087): 4pt 이내는 생략.
    func testShouldJump() {
        XCTAssertFalse(ContentView.shouldJump(cur: 1000, target: 1002))
        XCTAssertTrue(ContentView.shouldJump(cur: 1000, target: 1020))
        XCTAssertTrue(ContentView.shouldJump(cur: 1020, target: 1000))
    }

    /// 높이 캐시 키·저장 (T-083): 동일 입력 동일 키, 스케일 바뀌면 다른 키.
    func testHeightCache() {
        let k1 = MarkdownPage.heightKey(markdown: "hello", scheme: .dark, fontScale: 1.0)
        XCTAssertEqual(k1, MarkdownPage.heightKey(markdown: "hello", scheme: .dark, fontScale: 1.0))
        XCTAssertNotEqual(k1, MarkdownPage.heightKey(markdown: "hello", scheme: .dark, fontScale: 1.5))
        MarkdownPage.storeHeight(300, markdown: "hello", scheme: .dark, fontScale: 1.0)
        XCTAssertEqual(MarkdownPage.cachedHeight(markdown: "hello", scheme: .dark, fontScale: 1.0), 300)
        XCTAssertNil(MarkdownPage.cachedHeight(markdown: "other", scheme: .dark, fontScale: 1.0))
    }

    /// 상대 시간 (T-077): 방금 전·초·분·시간·어제·일·날짜.
    func testChatRelativeTime() {
        let now = Date()
        XCTAssertEqual(chatRelativeTime(from: now, now: now), "방금 전")
        XCTAssertEqual(chatRelativeTime(from: now.addingTimeInterval(-25), now: now), "25초 전")
        XCTAssertEqual(chatRelativeTime(from: now.addingTimeInterval(-180), now: now), "3분 전")
        XCTAssertEqual(chatRelativeTime(from: now.addingTimeInterval(-7200), now: now), "2시간 전")
        let cal = Calendar.current
        let yesterdayNoon = cal.date(byAdding: .day, value: -1,
                                     to: cal.startOfDay(for: now))!.addingTimeInterval(3600 * 12)
        XCTAssertEqual(chatRelativeTime(from: yesterdayNoon, now: now), "어제")
        XCTAssertEqual(chatRelativeTime(from: now.addingTimeInterval(-3 * 86400), now: now), "3일 전")
        XCTAssertTrue(chatRelativeTime(from: now.addingTimeInterval(-10 * 86400), now: now).contains("월"))
    }

    /// CPU 성분 분리: Δuser=50·Δnice=5·Δsys=20·Δidle=25 → 사용자 55%·시스템 20% (T-015 인덱스 회귀).
    func testCpuSplit() {
        let cur = SystemMonitor.CPUTicks(user: 150, sys: 120, nice: 105, idle: 125)
        let prev = SystemMonitor.CPUTicks(user: 100, sys: 100, nice: 100, idle: 100)
        let s = SystemMonitor.cpuSplit(cur: cur, prev: prev)
        XCTAssertEqual(s?.userPct ?? -1, 55.0, accuracy: 0.001)
        XCTAssertEqual(s?.sysPct ?? -1, 20.0, accuracy: 0.001)
        XCTAssertNil(SystemMonitor.cpuSplit(cur: prev, prev: prev))
    }

    /// RAM 성분 분리: App/Wired/Compressed 페이지 단위 (inactive 제외).
    func testRamComponents() {
        let c = SystemMonitor.ramComponentBytes(active: 100, wired: 40, compressed: 10, pageSize: 16384)
        XCTAssertEqual(c.app, 100 * 16384)
        XCTAssertEqual(c.wired, 40 * 16384)
        XCTAssertEqual(c.comp, 10 * 16384)
    }

    /// 차트 클램프 + 절대 틱 X 도메인 (늘어남 방지).
    func testChartHelpers() {
        XCTAssertEqual(SystemMonitor.clamp100(150), 100, accuracy: 0.001)
        XCTAssertEqual(SystemMonitor.clamp100(-5), 0, accuracy: 0.001)
        XCTAssertEqual(SystemMonitor.clamp100(42.5), 42.5, accuracy: 0.001)
        let d = SystemMonitor.xDomain(tick: 70)
        XCTAssertEqual(d.lowerBound, 11)
        XCTAssertEqual(d.upperBound, 70)
    }

    /// 누적 스택: CPU=시스템+합계, RAM=App/App+Wired/합계. 교차 없음 보장.
    func testStackedSeries() {
        let cpu = SystemMonitor.cpuStacked(user: 30, sys: 20)
        XCTAssertEqual(cpu.sys, 20, accuracy: 0.001)
        XCTAssertEqual(cpu.total, 50, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(cpu.total, cpu.sys)
        let ram = SystemMonitor.ramStacked(app: 10, wired: 20, comp: 5)
        XCTAssertEqual(ram.app, 10, accuracy: 0.001)
        XCTAssertEqual(ram.appWired, 30, accuracy: 0.001)
        XCTAssertEqual(ram.total, 35, accuracy: 0.001)
        XCTAssertLessThanOrEqual(ram.app, ram.appWired)
        XCTAssertLessThanOrEqual(ram.appWired, ram.total)
    }

    /// GPU 추정치 파싱: IOKit PerformanceStatistics 키 (실측 fixture).
    func testGpuFromStats() {
        let stats: [String: Any] = ["Device Utilization %": NSNumber(value: 88),
                                    "Renderer Utilization %": NSNumber(value: 88)]
        XCTAssertEqual(SystemMonitor.gpuFromStats(stats) ?? -1, 88.0, accuracy: 0.001)
        XCTAssertNil(SystemMonitor.gpuFromStats([:]))
    }

    /// 회귀: 메뉴바 칩 에셋 해결 (Asset Catalog MenuBarChip).
    func testMenuBarChipResolves() {
        XCTAssertNotNil(NSImage(named: "MenuBarChip"), "MenuBarChip 에셋 확인")
    }

    /// 채팅 재시도 조회: 마지막 user 프롬프트 반환, 없으면 nil (T-028).
    @MainActor
    func testLastUserPrompt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-prompt-\(UUID().uuidString).json")
        let store = ChatStore(storageURL: url)
        XCTAssertNil(store.lastUserPrompt())
        store.messages.append(ChatStore.Message(role: "user", text: "안녕"))
        store.messages.append(ChatStore.Message(role: "assistant", text: "반가워"))
        XCTAssertEqual(store.lastUserPrompt(), "안녕")
        try? FileManager.default.removeItem(at: url)
    }

    /// 종료 정리 판정: 설정ON+앱소유+실행중일 때만 중지 (T-035).
    func testShouldStopDaemon() {
        typealias S = DaemonManager.Status
        XCTAssertTrue(AppServices.shouldStopDaemon(stopOnQuit: true, external: false, status: .running))
        XCTAssertFalse(AppServices.shouldStopDaemon(stopOnQuit: false, external: false, status: .running))
        XCTAssertFalse(AppServices.shouldStopDaemon(stopOnQuit: true, external: true, status: .running))
        XCTAssertFalse(AppServices.shouldStopDaemon(stopOnQuit: true, external: false, status: .stopped))
        XCTAssertFalse(AppServices.shouldStopDaemon(stopOnQuit: true, external: false, status: .starting))
        XCTAssertFalse(AppServices.shouldStopDaemon(stopOnQuit: true, external: false, status: .failed))
    }

    /// 입력창 줄수: 실측 높이→2~8 클램프 (T-034).
    func testInputRows() {
        XCTAssertEqual(ChatInputBar.rowsFor(mirrorHeight: 10, lineHeight: 17), 2)
        XCTAssertEqual(ChatInputBar.rowsFor(mirrorHeight: 17, lineHeight: 17), 2)
        XCTAssertEqual(ChatInputBar.rowsFor(mirrorHeight: 60, lineHeight: 17), 4)
        XCTAssertEqual(ChatInputBar.rowsFor(mirrorHeight: 500, lineHeight: 17), 8)
        XCTAssertGreaterThan(ChatInputBar.editorHeight(rows: 8, lineHeight: 17),
                              ChatInputBar.editorHeight(rows: 2, lineHeight: 17))
    }

    /// 세션 생명주기: 생성·전환·삭제 + 영속 왕복 (T-032).
    @MainActor
    func testChatSessions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-test-\(UUID().uuidString).json")
        let store = ChatStore(storageURL: url)
        XCTAssertEqual(store.sessions.count, 1)
        store.messages.append(ChatStore.Message(role: "user", text: "첫 질문입니다"))
        store.refreshTitle()
        XCTAssertEqual(store.sessions.first?.title, "첫 질문입니다")
        let firstID = store.currentSessionID!
        store.newSession()
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertTrue(store.messages.isEmpty)
        store.selectSession(firstID)
        XCTAssertEqual(store.messages.count, 1)
        let reloaded = ChatStore(storageURL: url)
        XCTAssertEqual(reloaded.sessions.count, 2)
        reloaded.selectSession(firstID)
        XCTAssertEqual(reloaded.messages.first?.text, "첫 질문입니다")
        reloaded.deleteSession(firstID)
        XCTAssertEqual(reloaded.sessions.count, 1)
        try? FileManager.default.removeItem(at: url)
    }

    /// 채팅 정렬: 핀 우선 + 최근/이름/생성 (T-058).
    func testSortedSessions() {
        typealias S = ChatStore.Session
        let old = S(title: "b", updatedAt: Date(timeIntervalSince1970: 100),
                    createdAt: Date(timeIntervalSince1970: 100))
        let new = S(title: "a", updatedAt: Date(timeIntervalSince1970: 200),
                    createdAt: Date(timeIntervalSince1970: 200))
        var pinned = S(title: "z", updatedAt: Date(timeIntervalSince1970: 50),
                       createdAt: Date(timeIntervalSince1970: 50), pinned: true)
        XCTAssertEqual(ChatStore.sortedSessions([old, new], by: .recent).first?.title, "a")
        XCTAssertEqual(ChatStore.sortedSessions([old, new], by: .name).first?.title, "a")
        XCTAssertEqual(ChatStore.sortedSessions([old, new], by: .created).first?.title, "a")
        XCTAssertEqual(ChatStore.sortedSessions([new, pinned], by: .recent).first?.title, "z")
        pinned.pinned = false
        XCTAssertEqual(ChatStore.sortedSessions([old, pinned], by: .recent).first?.title, "b")
    }

    /// 구 JSON 호환: 신필드 없으면 기본값 (T-058).
    func testSessionMigration() throws {
        let id = UUID()
        let json = "{\"id\":\"\(id.uuidString)\",\"title\":\"구대화\",\"updatedAt\":1789000000.0}"
        let s = try JSONDecoder().decode(ChatStore.Session.self, from: Data(json.utf8))
        XCTAssertEqual(s.id, id)
        XCTAssertEqual(s.title, "구대화")
        XCTAssertFalse(s.pinned)
        XCTAssertNil(s.customTitle)
        XCTAssertEqual(s.displayTitle, "구대화")
    }

    /// 이름 변경·고정·자동제목 보호 (T-058).
    @MainActor
    func testRenamePin() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-rename-\(UUID().uuidString).json")
        let store = ChatStore(storageURL: url)
        let id = store.sessions.first!.id
        store.renameSession(id, title: "   ")
        XCTAssertNil(store.sessions.first!.customTitle)
        store.renameSession(id, title: "  회의  ")
        XCTAssertEqual(store.sessions.first!.displayTitle, "회의")
        store.messages.append(ChatStore.Message(role: "user", text: "바뀌면 안됨"))
        store.refreshTitle()
        XCTAssertEqual(store.sessions.first!.displayTitle, "회의")
        store.togglePin(id)
        XCTAssertTrue(store.sessions.first!.pinned)
        store.togglePin(id)
        XCTAssertFalse(store.sessions.first!.pinned)
        try? FileManager.default.removeItem(at: url)
    }

    /// 회귀: 채팅 목록 SF Symbol 실렌더 가능 (T-058).
    func testSessionSymbolsResolve() {
        for name in ["plus", "circle", "pin", "pin.fill", "pin.slash",
                     "pencil", "trash", "ellipsis", "arrow.up.arrow.down"] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(name) 확인")
        }
    }
}

/// 뷰·표시 테스트군 (T-060 파일 분리).
final class LiteRTLMStudioViewTests: XCTestCase {
    /// Sticky-Pin 판정: 앵커가 뷰포트 안이면 고정 (T-031).
    func testPinnedToBottom() {
        XCTAssertTrue(ContentView.isPinnedToBottom(bottomMaxY: 600, viewportHeight: 600))
        XCTAssertTrue(ContentView.isPinnedToBottom(bottomMaxY: 650, viewportHeight: 600))
        XCTAssertFalse(ContentView.isPinnedToBottom(bottomMaxY: 700, viewportHeight: 600))
    }

    /// 마크다운 엔진 부트스트랩: marked+hljs+렌더러+CSS 내장, 외관 매핑 (T-050).
    /// 빈 화면 방지: try/catch 폴백+에러 보고 고리 (T-052).
    func testMarkdownEngineBootstrap() {
        let dark = MarkdownPage.template(scheme: .dark)
        XCTAssertTrue(dark.contains("renderMarkdown"))
        XCTAssertTrue(dark.contains("marked"))
        XCTAssertTrue(dark.contains("copyCode"))
        XCTAssertTrue(dark.contains(".markdown-body"))
        XCTAssertTrue(dark.contains("data-theme=\"dark\""))
        XCTAssertTrue(dark.contains("try {"))
        XCTAssertTrue(dark.contains("window.onerror"))
        XCTAssertTrue(dark.contains("jsError"))
        XCTAssertTrue(dark.contains("verifyRender"))
        XCTAssertTrue(dark.contains("renderState"))
        XCTAssertTrue(dark.contains("koreanStrong")) // T-066 한글 볼드 확장
        XCTAssertTrue(dark.contains("v18.0.13")) // T-067 marked 핀
        XCTAssertTrue(dark.contains("v11.12.0")) // T-067 highlight.js 핀
        XCTAssertTrue(dark.contains(".hljs-keyword")) // T-069 토큰 팔레트
        XCTAssertTrue(dark.contains("--hl-base")) // T-069 테마 변수
        XCTAssertTrue(dark.contains("letter-spacing: 0.015em")) // T-075 본문 자간
        XCTAssertTrue(MarkdownPage.template(scheme: .light).contains("data-theme=\"light\""))
        XCTAssertTrue(MarkdownPage.template(scheme: .auto).contains("data-theme=\"system\""))
        XCTAssertEqual(MarkdownPage.themeName(for: .auto), "system")
    }

    /// JS 문자열 리터럴: 따옴표 포함·내부 이스케이프 (T-050).
    func testJsLiteral() {
        XCTAssertEqual(MarkdownWebView.jsLiteral("a\"b"), "\"a\\\"b\"")
        XCTAssertTrue(MarkdownWebView.jsLiteral("줄\n바꿈")!.contains("\\n"))
    }

    /// 정보 창 라이브러리 목록 무결성 (T-068): 번들 벤더와 버전 핀 일치.
    func testAboutLibraries() {
        XCTAssertEqual(AboutLibraries.all.count, 2)
        let marked = AboutLibraries.all[0]
        XCTAssertEqual(marked.name, "marked")
        XCTAssertEqual(marked.version, "v18.0.13")
        XCTAssertEqual(URL(string: marked.url)?.host, "github.com")
        let hljs = AboutLibraries.all[1]
        XCTAssertEqual(hljs.name, "highlight.js")
        XCTAssertEqual(hljs.version, "v11.12.0")
        XCTAssertEqual(URL(string: hljs.url)?.host, "github.com")
    }

    /// 폰트 줌 스텝·px 매핑 (T-070): 0.7~2.0 클램프, 14px 기준.
    func testChatZoom() {
        XCTAssertEqual(ContentView.steppedZoom(1.0, step: 0.1), 1.1, accuracy: 0.0001)
        XCTAssertEqual(ContentView.steppedZoom(2.0, step: 0.1), 2.0, accuracy: 0.0001)
        XCTAssertEqual(ContentView.steppedZoom(0.7, step: -0.1), 0.7, accuracy: 0.0001)
        XCTAssertEqual(ContentView.steppedZoom(1.0, step: -0.5), 0.7, accuracy: 0.0001)
        XCTAssertEqual(MarkdownWebView.fontPx(1.0), 14.0, accuracy: 0.0001)
        XCTAssertEqual(MarkdownWebView.fontPx(3.0), 28.0, accuracy: 0.0001)
        XCTAssertEqual(MarkdownWebView.fontPx(0.1), 9.8, accuracy: 0.0001)
    }

    /// 인스펙터 섹션 타이틀 (T-072): 3종 고정, 중복 없음.
    func testInspectorTitles() {
        XCTAssertEqual(InspectorTitle.all, ["시스템 현황", "실행 설정", "생성 설정"])
        XCTAssertEqual(Set(InspectorTitle.all).count, 3)
    }

    /// 회귀: 툴바 SF Symbol 실렌더 가능 (외부 link.badge.minus 링 현상 방지).
    func testToolbarSymbolsResolve() {
        for name in ["play.fill", "stop.fill", "terminal", "command", "sidebar.right",
                     "gauge", "server.rack", "wand.and.stars"] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(name) 확인")
        }
    }

    /// 인스펙터 섹션 가시성: 하나라도 켜지면 컬럼 표시, 전체 off면 2분할.
    func testAnySectionVisible() {
        XCTAssertTrue(ContentView.anyVisible(true, false, false))
        XCTAssertTrue(ContentView.anyVisible(false, false, true))
        XCTAssertFalse(ContentView.anyVisible(false, false, false))
    }

    /// 컬럼 표시 결정: 마스터 off면 섹션과 무관하게 숨김.
    func testInspectorColumnShown() {
        XCTAssertTrue(ContentView.columnShown(columnOn: true, sections: true, false, false))
        XCTAssertFalse(ContentView.columnShown(columnOn: true, sections: false, false, false))
        XCTAssertFalse(ContentView.columnShown(columnOn: false, sections: true, true, true))
    }
}

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

    /// 메뉴바 상태 색 매핑.
    func testMenuStatusKeys() {
        XCTAssertEqual(MenuStatus.dotKey(for: .running), "green")
        XCTAssertEqual(MenuStatus.dotKey(for: .starting), "orange")
        XCTAssertEqual(MenuStatus.dotKey(for: .failed), "red")
        XCTAssertEqual(MenuStatus.dotKey(for: .stopped), "gray")
    }

    /// 빈 렌더 재시도 판정: 보고+원문+미재시도일 때만 (T-056).
    func testShouldRetryEmpty() {
        XCTAssertTrue(MarkdownWebView.shouldRetryEmpty(reportedEmpty: true, markdownEmpty: false,
                                                        alreadyRetried: false))
        XCTAssertFalse(MarkdownWebView.shouldRetryEmpty(reportedEmpty: false, markdownEmpty: false,
                                                         alreadyRetried: false))
        XCTAssertFalse(MarkdownWebView.shouldRetryEmpty(reportedEmpty: true, markdownEmpty: true,
                                                         alreadyRetried: false))
        XCTAssertFalse(MarkdownWebView.shouldRetryEmpty(reportedEmpty: true, markdownEmpty: false,
                                                         alreadyRetried: true))
    }

    /// 렌더 상태머신: 종료는 원문 확정, 빈 finalize 없음 (T-051).
    func testResolveAction() {
        typealias R = MarkdownWebView.RenderAction
        XCTAssertEqual(MarkdownWebView.resolveAction(schemeChanged: true, streamingEnded: true,
                                                     isStreaming: true, loaded: true,
                                                     applied: "a", markdown: "b"), R.reload)
        XCTAssertEqual(MarkdownWebView.resolveAction(schemeChanged: false, streamingEnded: true,
                                                     isStreaming: false, loaded: true,
                                                     applied: "a", markdown: "a"), R.finishFull)
        XCTAssertEqual(MarkdownWebView.resolveAction(schemeChanged: false, streamingEnded: false,
                                                     isStreaming: true, loaded: true,
                                                     applied: "a", markdown: "ab"), R.append)
        XCTAssertEqual(MarkdownWebView.resolveAction(schemeChanged: false, streamingEnded: false,
                                                     isStreaming: false, loaded: true,
                                                     applied: "a", markdown: "ab"), R.fullSet)
        XCTAssertEqual(MarkdownWebView.resolveAction(schemeChanged: false, streamingEnded: false,
                                                     isStreaming: false, loaded: true,
                                                     applied: "a", markdown: "a"), R.wait)
        XCTAssertEqual(MarkdownWebView.resolveAction(schemeChanged: false, streamingEnded: false,
                                                     isStreaming: false, loaded: false,
                                                     applied: "", markdown: "a"), R.wait)
    }

    /// 응답 사라짐 방지: 로드 전엔 적용 금지·로드 후 변경분만 적용 (T-038).
    func testMarkdownNeedsFlush() {
        XCTAssertFalse(MarkdownWebView.needsFlush(loaded: false, applied: "", html: "<p>a</p>"))
        XCTAssertFalse(MarkdownWebView.needsFlush(loaded: true, applied: "<p>a</p>", html: "<p>a</p>"))
        XCTAssertTrue(MarkdownWebView.needsFlush(loaded: true, applied: "<p>a</p>", html: "<p>b</p>"))
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

    /// 높이 피팅: 올림+2pt 여유, 0 이하는 0 (T-043/T-049).
    func testFittedHeight() {
        XCTAssertEqual(MarkdownWebView.fittedHeight(100), 102)
        XCTAssertEqual(MarkdownWebView.fittedHeight(100.2), 103)
        XCTAssertEqual(MarkdownWebView.fittedHeight(0), 0)
        XCTAssertEqual(MarkdownWebView.fittedHeight(-5), 0)
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

    /// 세션 전환 점프 대상: 같은 세션+휠 없음+마지막 있음일 때만 (T-046).
    func testSwitchJumpTarget() {
        let a = UUID(), b = UUID(), m = UUID()
        XCTAssertEqual(ContentView.switchJumpTarget(sessionID: a, currentID: a,
                                                    lastMessageID: m, wheeledSinceSwitch: false), m)
        XCTAssertNil(ContentView.switchJumpTarget(sessionID: a, currentID: b,
                                                  lastMessageID: m, wheeledSinceSwitch: false))
        XCTAssertNil(ContentView.switchJumpTarget(sessionID: a, currentID: a,
                                                  lastMessageID: m, wheeledSinceSwitch: true))
        XCTAssertNil(ContentView.switchJumpTarget(sessionID: a, currentID: a,
                                                  lastMessageID: nil, wheeledSinceSwitch: false))
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
}
