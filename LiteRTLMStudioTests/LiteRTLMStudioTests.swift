import AppKit
import XCTest
@testable import LiteRTLMStudio

/// smoke: 에러 메시지 매핑 무결성 (한국어 분리 파일 로드).
final class LiteRTLMStudioTests: LiteRTLMStudioTestCase {
    /// 오류 코드 대조표 (T-366): 코드 전수가 카탈로그에 ko·en으로 존재한다.
    /// 기존 `error_message_ko.json`(한국어 단일 파일)을 카탈로그로 이관한 뒤의 안전망.
    func testErrorCatalogCoversAllCodes() {
        XCTAssertEqual(ErrorCatalog.codes.count, 30)
        XCTAssertEqual(Set(ErrorCatalog.codes).count, 30, "중복 코드")
        for language in [AppLanguage.ko, .en] {
            setAppLanguageForTesting(language)
            for code in ErrorCatalog.codes {
                let message = ErrorCatalog.message(code)
                XCTAssertNotEqual(message, ErrorCatalog.key(code).raw,
                                  "\(language.rawValue) 미해석: \(code)")
                XCTAssertGreaterThan(message.count, 5, "\(language.rawValue) 문구 없음: \(code)")
            }
        }
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

    /// 데몬 로그 타임스탬프 (T-094).
    func testDaemonLogStamp() {
        let lines = DaemonManager.stampedLines("a\nb", time: "12:00:01")
        XCTAssertEqual(lines, ["[12:00:01] a", "[12:00:01] b"])
        XCTAssertEqual(DaemonManager.stampedLines("", time: "12:00:01"), [])
        XCTAssertTrue(DaemonManager.logTimeString(Date()).count == 8)
    }

    /// 상대 시간 (T-077): 방금 전·초·분·시간·어제·일·날짜.
    func testChatRelativeTime() {
        let now = Date()
        XCTAssertEqual(chatRelativeTime(from: now, now: now), "방금 전")
        XCTAssertEqual(chatRelativeTime(from: now.addingTimeInterval(-25), now: now), "25초 전")
        XCTAssertEqual(chatRelativeTime(from: now.addingTimeInterval(-180), now: now), "3분 전")
        XCTAssertEqual(chatRelativeTime(from: now.addingTimeInterval(-7200), now: now), "2시간 전")
        let cal = Calendar.current
        // 자정 경계 플레이크 방지 (T-127): `now`을 오늘 15시로 고정하면 어제 정오는 항상 27시간 전.
        let today3pm = cal.date(bySettingHour: 15, minute: 0, second: 0, of: now)!
        let yesterdayNoon = today3pm.addingTimeInterval(-27 * 3600)
        XCTAssertEqual(chatRelativeTime(from: yesterdayNoon, now: today3pm), "어제")
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

    /// 회귀: 채팅 목록 SF Symbol 실렌더 가능 (T-058).
    func testSessionSymbolsResolve() {
        for name in ["plus", "circle", "pin", "pin.fill", "pin.slash",
                     "pencil", "trash", "ellipsis", "arrow.up.arrow.down"] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(name) 확인")
        }
    }

    /// 자가 footprint (T-133): GB 변환 + 테스트 호스트에서 0 초과.
    func testAppFootprint() {
        XCTAssertEqual(SystemMonitor.bytesToGB(1073741824), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SystemMonitor.bytesToGB(0), 0.0, accuracy: 0.0001)
        XCTAssertGreaterThan(SystemMonitor.appFootprintBytes(), 0)
    }

    /// 대화 목차 추출 (T-258): 사용자 첫 줄 40자.
    func testChatOutlineEntries() {
        let msgs = [
            ChatStore.Message(role: "user", text: "첫 질문입니다\n둘째 줄"),
            ChatStore.Message(role: "assistant", text: "답변"),
            ChatStore.Message(role: "user", text: "두 번째 질문")
        ]
        let entries = ChatOutline.entries(from: msgs)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].preview, "첫 질문입니다")
        XCTAssertEqual(entries[0].id, msgs[0].id)
        XCTAssertEqual(entries[1].preview, "두 번째 질문")
    }

    /// 대화 목차 빈 본문 (T-258): 이미지 첨부 표기.
    func testChatOutlineEmptyBody() {
        let msgs = [ChatStore.Message(role: "user", text: "   ")]
        XCTAssertEqual(ChatOutline.entries(from: msgs).first?.preview, "(이미지 첨부)")
    }

    /// 대화 목차 빈 목록 (T-258): 질문 없으면 빈 배열.
    func testChatOutlineEmpty() {
        XCTAssertTrue(ChatOutline.entries(from: []).isEmpty)
        XCTAssertTrue(ChatOutline.entries(
            from: [ChatStore.Message(role: "assistant", text: "답변")]).isEmpty)
    }

    /// 대화 목차 높이 맞춤 (T-258 후속): 내용만큼, 최대 400 클램프.
    func testChatOutlineCappedHeight() {
        XCTAssertEqual(ChatOutline.cappedHeight(120), 120)
        XCTAssertEqual(ChatOutline.cappedHeight(400), 400)
        XCTAssertEqual(ChatOutline.cappedHeight(1000), 400)
        XCTAssertEqual(ChatOutline.cappedHeight(1000, maxHeight: 250), 250)
        XCTAssertEqual(ChatOutline.cappedHeight(0), 0)
        XCTAssertEqual(ChatOutline.cappedHeight(-5), 0)
    }
}
