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

    /// RAM 누적 스택: 아래=App, 중간=App+Wired, 위=App+Wired+압축. 교차 없음.
    nonisolated static func ramStacked(app: Double, wired: Double, comp: Double)
        -> (app: Double, appWired: Double, total: Double) {
        (app, app + wired, app + wired + comp)
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

    // MARK: - 라이브 샘플 (nonisolated, GCD 호출)
    /// CPU 틱 묶음 (lint 파라미터 수 회피용 구조체).
    struct CPUTicks {
        let user: UInt64
        let sys: UInt64
        let nice: UInt64
        let idle: UInt64
    }

    /// CPU 성분 샘플. cpu_ticks 인덱스: [0]=user [1]=system [2]=idle [3]=nice.
    nonisolated private static func sampleCPUSplit(
        prevUser: inout UInt64,
        prevSys: inout UInt64,
        prevNice: inout UInt64,
        prevIdle: inout UInt64
    ) -> (userPct: Double, sysPct: Double)? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        var user: UInt64 = 0
        var sys: UInt64 = 0
        var nice: UInt64 = 0
        var idle: UInt64 = 0
        info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) { ptr in
            for idx in 0 ..< Int(cpuCount) {
                let ticks = ptr[idx].cpu_ticks
                user += UInt64(ticks.0)
                sys += UInt64(ticks.1)
                idle += UInt64(ticks.2)
                nice += UInt64(ticks.3)
            }
        }
        let hadPrev = prevUser > 0 || prevSys > 0 || prevNice > 0 || prevIdle > 0
        defer {
            prevUser = user
            prevSys = sys
            prevNice = nice
            prevIdle = idle
        }
        guard hadPrev else { return nil } // 첫 샘플은 델타 없음
        let cur = CPUTicks(user: user, sys: sys, nice: nice, idle: idle)
        let prev = CPUTicks(user: prevUser, sys: prevSys, nice: prevNice, idle: prevIdle)
        return cpuSplit(cur: cur, prev: prev)
    }

    /// CPU 성분 분리 (순수, 테스트 가능). nice는 사용자로 합산 (활성 상태 보기와 동일).
    nonisolated static func cpuSplit(
        cur: CPUTicks,
        prev: CPUTicks
    ) -> (userPct: Double, sysPct: Double)? {
        let du = (cur.user >= prev.user ? cur.user - prev.user : 0)
            + (cur.nice >= prev.nice ? cur.nice - prev.nice : 0)
        let ds = cur.sys >= prev.sys ? cur.sys - prev.sys : 0
        let di = cur.idle >= prev.idle ? cur.idle - prev.idle : 0
        let total = du + ds + di
        guard total > 0 else { return nil }
        return (Double(du) / Double(total) * 100.0, Double(ds) / Double(total) * 100.0)
    }

    /// RAM 스냅샷 (lint large_tuple 회피용 구조체).
    struct RAMSample {
        let usedGB: Double
        let pct: Double
        let inactiveGB: Double
        let appGB: Double
        let wiredGB: Double
        let compGB: Double
        let appPct: Double
        let wiredPct: Double
        let compPct: Double
    }

    /// RAM 성분 바이트 묶음 (lint large_tuple 회피용 구조체).
    struct RAMComponents {
        let app: UInt64
        let wired: UInt64
        let comp: UInt64
    }

    /// RAM 성분 바이트 (순수, 테스트 가능). App=active, inactive는 캐시된 파일로 별도.
    nonisolated static func ramComponentBytes(
        active: UInt64,
        wired: UInt64,
        compressed: UInt64,
        pageSize: UInt64
    ) -> RAMComponents {
        RAMComponents(app: active * pageSize, wired: wired * pageSize, comp: compressed * pageSize)
    }

    nonisolated private static func sampleRAM(totalGB: Double) -> RAMSample {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let ok: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard ok == KERN_SUCCESS else {
            return RAMSample(usedGB: 0, pct: 0, inactiveGB: 0, appGB: 0, wiredGB: 0, compGB: 0,
                             appPct: 0, wiredPct: 0, compPct: 0)
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)
        let comp = ramComponentBytes(active: UInt64(stats.active_count), wired: UInt64(stats.wire_count),
                                     compressed: UInt64(stats.compressor_page_count), pageSize: ps)
        let used = ramUsedBytes(active: UInt64(stats.active_count), inactive: UInt64(stats.inactive_count),
                                wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count),
                                pageSize: ps)
        let div = 1024.0 * 1024.0 * 1024.0
        let usedGB = Double(used) / div
        let appGB = Double(comp.app) / div
        let wiredGB = Double(comp.wired) / div
        let compGB = Double(comp.comp) / div
        let inactiveGB = Double(ramInactiveBytes(inactive: UInt64(stats.inactive_count),
                                                pageSize: ps)) / div
        func pct(_ v: Double) -> Double { totalGB > 0 ? v / totalGB * 100.0 : 0 }
        return RAMSample(usedGB: usedGB, pct: pct(usedGB), inactiveGB: inactiveGB,
                         appGB: appGB, wiredGB: wiredGB, compGB: compGB,
                         appPct: pct(appGB), wiredPct: pct(wiredGB), compPct: pct(compGB))
    }

    nonisolated private static func sampleGPU() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Double?
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            defer {
                IOObjectRelease(svc)
                svc = IOIteratorNext(iter)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any],
                  let val = gpuFromStats(stats)
            else { continue }
            best = max(best ?? 0, val)
        }
        return best
    }
}

// MARK: - 데몬 측정 (타입 본문 길이 관리용 분리, T-073)
extension SystemMonitor {
    /// 데몬 샘플 묶음 (lint large_tuple 회피용 구조체, T-073 진단 포함).
    struct DaemonSample {
        let cpu: Double
        let rssGB: Double
        let pidCount: Int
        let rusageFails: Int
    }

    /// 불일치 보고 판정 (순수, 테스트 가능, T-073): 실행 중+0개+미기록일 때만.
    nonisolated static func shouldReportDaemonMismatch(running: Bool, pidCount: Int,
                                                      alreadyLogged: Bool) -> Bool {
        running && pidCount == 0 && !alreadyLogged
    }

    /// :9379 리스너 PID (동기, 5틱마다만 호출). -n -P로 이름 해석 없이 빠르게.
    static func listenerPIDs() -> [pid_t] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-n", "-P", "-i", ":9379", "-sTCP:LISTEN", "-t"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return pids(fromLsof: out)
    }

    /// 리스너 + 모든 자손 (ppid 워크).
    static func daemonPIDs(listeners: [pid_t]) -> [pid_t] {
        guard !listeners.isEmpty else { return [] }
        var ppidMap: [pid_t: pid_t] = [:]
        let bufSize = Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0))
        guard bufSize > 0 else { return listeners }
        var pids = [pid_t](repeating: 0, count: bufSize / MemoryLayout<pid_t>.size)
        let count = Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(bufSize)))
        var info = proc_bsdinfo()
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            let size = proc_pidinfo(pid, Int32(PROC_PIDTBSDINFO), 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            guard size == MemoryLayout<proc_bsdinfo>.size else { continue }
            ppidMap[pid] = pid_t(info.pbi_ppid)
        }
        return descendants(of: listeners, in: ppidMap)
    }

    /// 순수: ppid 맵에서 roots + 자손 전부.
    nonisolated static func descendants(of roots: [pid_t], in ppidMap: [pid_t: pid_t]) -> [pid_t] {
        var out = Set(roots)
        var queue = roots
        while let cur = queue.popLast() {
            for (pid, ppid) in ppidMap where ppid == cur && !out.contains(pid) {
                out.insert(pid)
                queue.append(pid)
            }
        }
        return Array(out)
    }

    /// 순수: lsof -t 출력 파싱.
    nonisolated static func pids(fromLsof out: String) -> [pid_t] {
        out.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// 진단용 lsof 원문 앞부분 (T-073): 불일치 로그용, 최대 120자.
    nonisolated static func lsofHead() -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-n", "-P", "-i", ":9379", "-sTCP:LISTEN"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return "lsof 실행 실패" }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let head = out.split(separator: "\n").prefix(3).joined(separator: "|")
        return head.isEmpty ? "(빈 출력)" : String(head.prefix(120))
    }
}
