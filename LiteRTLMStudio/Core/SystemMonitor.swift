import Darwin
import Foundation
import IOKit

/// 시스템 사용량 1Hz 샘플러 (CPU/RAM/GPU/데몬). sudo 불필요, 오버헤드 1% 미만.
/// - CPU: host_processor_info 델타, 사용자/시스템 분리 (활성 상태 보기와 동일)
/// - RAM: host_statistics64 + hw.memsize (App/Wired/Compressed 분리, inactive=캐시된 파일)
/// - GPU: IOKit IOAccelerator PerformanceStatistics (순간 busy 추정치, powermetrics급 정밀 아님)
/// - 데몬: :9379 리스너(lsof) + 자식(ppid 워크) CPU/footprint 합산 (단일코어 기준, 실측 경과로 나눔)
@MainActor
final class SystemMonitor: ObservableObject {
    static let historyLength = 60

    @Published var cpuHistory: [Double] = [] // 합계 (호환 유지)
    @Published var cpuUserHistory: [Double] = [] // 사용자 % (nice 포함)
    @Published var cpuSystemHistory: [Double] = [] // 시스템 %
    @Published var gpuHistory: [Double] = []
    @Published var ramHistory: [Double] = [] // 사용률 % (호환 유지)
    @Published var ramAppHistory: [Double] = [] // App % (active)
    @Published var ramWiredHistory: [Double] = [] // Wired %
    @Published var ramCompHistory: [Double] = [] // Compressed %
    @Published var daemonCPUHistory: [Double] = [] // 단일 코어 기준 %, 원값(100 초과 허용)
    @Published var daemonRSSHistory: [Double] = []
    @Published var cpu = 0.0
    @Published var cpuUser = 0.0
    @Published var cpuSystem = 0.0
    @Published var gpu: Double? // 측정 불가 칩 대비 옵셔널
    @Published var ramUsedGB = 0.0
    @Published var ramAppGB = 0.0
    @Published var ramWiredGB = 0.0
    @Published var ramCompGB = 0.0
    @Published var ramInactiveGB = 0.0 // 캐시된 파일, 사용량에서 제외·별도 표기
    @Published var ramTotalGB = 32.0
    @Published var daemonCPU = 0.0 // 단일 코어 기준 %
    @Published var daemonRSSGB = 0.0 // phys_footprint 합산
    @Published var daemonPidCount = 0 // 측정 대상 pid 수 (0이면 미측정)
    @Published var daemonRunning = false // ContentView가 daemon.status로 동기화 (불일치 감지용)
    @Published var appRSSGB = 0.0 // 자가 footprint (T-133, 앱 내 엔진 엔진 상주 확인용)
    @Published var live = false
    @Published var sampleTick = 0 // 절대 틱 인덱스 (X 도메인 고정용, 리셋 없음)

    private var timer: Timer?
    private var prevUserTick: UInt64 = 0
    private var prevSysTick: UInt64 = 0
    private var prevNiceTick: UInt64 = 0
    private var prevIdleTick: UInt64 = 0
    private var prevProc: [pid_t: UInt64] = [:]
    private var lastTick: Date?
    private let logger = DebugLogger.shared

    func start() {
        stop()
        logger.info(feature: "모니터", "시스템 샘플링 시작 (1Hz)")
        ramTotalGB = Self.totalMemoryGB()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.2
        live = true
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        live = false
    }

    /// 데몬 상태 전이(시작/중지/인수) 시 호출: lsof 캐시+CPU 델타 초기화로 스파이크 방지.
    func invalidateDaemonCache() {
        listenerCache = []
        tickCount = 0
        prevProc = [:]
        lastTick = nil
        mismatchLogged = false
        logger.info(feature: "모니터", "데몬 캐시 무효화 (상태 전이)")
    }

    private func tick() {
        let now = Date()
        let elapsed = lastTick.map { now.timeIntervalSince($0) } ?? 1.0
        lastTick = now
        sampleTick += 1
        let dt = min(max(elapsed, 0.2), 5.0) // 타이머 드리프트·슬립 복귀 방어
        if let split = Self.sampleCPUSplit(prevUser: &prevUserTick, prevSys: &prevSysTick,
                                           prevNice: &prevNiceTick, prevIdle: &prevIdleTick) {
            cpuUser = split.userPct
            cpuSystem = split.sysPct
            cpu = split.userPct + split.sysPct
            push(&cpuUserHistory, split.userPct)
            push(&cpuSystemHistory, split.sysPct)
            push(&cpuHistory, cpu)
        }
        let ram = Self.sampleRAM(totalGB: ramTotalGB)
        ramUsedGB = ram.usedGB
        ramAppGB = ram.appGB
        ramWiredGB = ram.wiredGB
        ramCompGB = ram.compGB
        ramInactiveGB = ram.inactiveGB
        push(&ramHistory, ram.pct)
        push(&ramAppHistory, ram.appPct)
        push(&ramWiredHistory, ram.wiredPct)
        push(&ramCompHistory, ram.compPct)
        if let g = Self.sampleGPU() {
            gpu = g
            push(&gpuHistory, g)
        }
        let dmg = sampleDaemon(elapsed: dt)
        daemonCPU = dmg.cpu
        daemonRSSGB = dmg.rssGB
        daemonPidCount = dmg.pidCount
        // 불일치 감지 (T-073): 실행 중인데 측정 대상 0 → 상승 엣지에서 1회 로그.
        if Self.shouldReportDaemonMismatch(running: daemonRunning, pidCount: dmg.pidCount,
                                           alreadyLogged: mismatchLogged) {
            mismatchLogged = true
            logger.error(code: "E-MAC-NET-0010", feature: "데몬측정",
                         "리스너 0개·rusage실패 \(dmg.rusageFails)·lsof=\(Self.lsofHead())")
        } else if dmg.pidCount > 0 {
            mismatchLogged = false
        }
        push(&daemonCPUHistory, max(0, dmg.cpu)) // 데몬은 원값(100 초과 허용), 클램프 없음
        push(&daemonRSSHistory, dmg.rssGB)
        appRSSGB = Self.bytesToGB(Self.appFootprintBytes())
    }

    /// 자가 footprint 바이트 (T-133, nonisolated): 활성 상태 보기와 동일 지표.
    nonisolated static func appFootprintBytes() -> UInt64 {
        var info = rusage_info_v2()
        let ok: Int32 = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0)
            }
        }
        guard ok == 0 else { return 0 }
        let fp = info.ri_phys_footprint
        return fp != 0 ? fp : UInt64(info.ri_resident_size)
    }

    /// 바이트 → GB (순수, 테스트 가능, T-133).
    nonisolated static func bytesToGB(_ bytes: UInt64) -> Double {
        Double(bytes) / 1024 / 1024 / 1024
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > Self.historyLength { arr.removeFirst(arr.count - Self.historyLength) }
    }

    // MARK: - 데몬 (리스너 + 자식 합산)
    // 주의: proc_pidpath는 python 바이너리 경로를 돌려줘서 "litert-lm" 매칭 불가.
    // :9379 리스너를 lsof로 찾고(5틱 캐시) 자식은 ppid 워크.
    // 측정 로직은 파일 하단 extension에 분리 (타입 본문 길이 관리).
    private var listenerCache: [pid_t] = []
    private var tickCount = 0
    private var mismatchLogged = false

    private func sampleDaemon(elapsed: Double) -> DaemonSample {
        tickCount += 1
        if tickCount == 1 || tickCount % 5 == 0 {
            listenerCache = Self.listenerPIDs()
        }
        let pids = Self.daemonPIDs(listeners: listenerCache)
        var totalTime: UInt64 = 0
        var totalRSS: UInt64 = 0
        var fails = 0
        var seen: [pid_t: UInt64] = [:]
        for pid in pids {
            var info = rusage_info_v2()
            let ok: Int32 = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard ok == 0 else { fails += 1; continue }
            totalTime += info.ri_user_time + info.ri_system_time
            // 활성 상태 보기와 동일 지표: footprint 우선, 0이면 resident로 폴백
            let fp = info.ri_phys_footprint
            totalRSS += fp != 0 ? fp : UInt64(info.ri_resident_size)
            seen[pid] = info.ri_user_time + info.ri_system_time
        }
        var cpuPct = 0.0
        let prevTotal = prevProc.values.reduce(0, +)
        if !prevProc.isEmpty, totalTime >= prevTotal, elapsed > 0 {
            cpuPct = Self.daemonCPUPercent(deltaNS: totalTime - prevTotal, elapsed: elapsed)
        }
        prevProc = seen
        return DaemonSample(cpu: cpuPct, rssGB: Double(totalRSS) / 1024 / 1024 / 1024,
                            pidCount: pids.count, rusageFails: fails)
    }

    // MARK: - 순수 헬퍼 (테스트 가능, nonisolated)
    nonisolated static func cpuPercent(used: UInt64, idle: UInt64, prevUsed: UInt64, prevIdle: UInt64) -> Double? {
        let du = used >= prevUsed ? used - prevUsed : 0
        let di = idle >= prevIdle ? idle - prevIdle : 0
        guard du + di > 0 else { return nil }
        return Double(du) / Double(du + di) * 100.0
    }

    nonisolated static func ramUsedBytes(active: UInt64, inactive: UInt64, wired: UInt64,
                                         compressed: UInt64, pageSize: UInt64) -> UInt64 {
        // 활성 상태 보기 정의: inactive(파일캐시)는 사용량에서 제외, 별도 표기
        _ = inactive
        return (active + wired + compressed) * pageSize
    }

    nonisolated static func ramInactiveBytes(inactive: UInt64, pageSize: UInt64) -> UInt64 {
        inactive * pageSize
    }

    /// 데몬 CPU%: 실측 경과초로 나눔 (타이머 드리프트 보정, 단일코어 기준).
    nonisolated static func daemonCPUPercent(deltaNS: UInt64, elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        return Double(deltaNS) / 1_000_000_000.0 / elapsed * 100.0
    }

    nonisolated static func gpuFromStats(_ stats: [String: Any]) -> Double? {
        (stats["Device Utilization %"] as? NSNumber)?.doubleValue
    }

    /// 차트용 0~100 클램프 (데몬 CPU는 단일코어 기준이라 100 초과 가능).
    nonisolated static func clamp100(_ v: Double) -> Double {
        min(100, max(0, v))
    }

    /// CPU 누적 스택 (활성 상태 보기식): 아래=시스템, 위=시스템+사용자 합계. 교차 없음.
    nonisolated static func cpuStacked(user: Double, sys: Double) -> (sys: Double, total: Double) {
        (sys, sys + user)
    }

    /// RAM 누적 스택 값 (T-289: large_tuple 해소).
    struct RAMStack {
        let app: Double
        let appWired: Double
        let total: Double
    }

    /// RAM 누적 스택: 아래=App, 중간=App+Wired, 위=App+Wired+압축. 교차 없음.
    nonisolated static func ramStacked(app: Double, wired: Double, comp: Double) -> RAMStack {
        RAMStack(app: app, appWired: app + wired, total: app + wired + comp)
    }

    /// 절대 틱 기준 X 도메인 (최근 60틱 고정, 데이터 적으면 오른쪽부터 채워짐).
    nonisolated static func xDomain(tick: Int) -> ClosedRange<Int> {
        (tick - (historyLength - 1)) ... tick
    }

    nonisolated static func totalMemoryGB() -> Double {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &size, &len, nil, 0) == 0 else { return 32.0 }
        return Double(size) / 1024 / 1024 / 1024
    }

}
