import Foundation

/// litert-lm serve 데몬 생명주기 관리 (127.0.0.1:9379 고정, AGENTS.local.md).
@MainActor
final class DaemonManager: ObservableObject {
    enum Status: String {
        case stopped = "중지", starting = "시작 중…", running = "실행 중", failed = "실패"
    }
    static let host = "127.0.0.1"

    static let port = 9379

    /// 로그 시각 (T-094): HH:mm:ss.
    nonisolated static func logTimeString(_ date: Date) -> String {
        TimeFormat.logTime(date)
    }

    /// 로그 행 타임스탬프 (순수, 테스트 가능, T-094).
    nonisolated static func stampedLines(_ chunk: String, time: String) -> [String] {
        chunk.split(separator: "\n").map { "[\(time)] \($0)" }
    }

    /// 로그 비우기 (T-094 터미널 지우기).
    func clearLog() {
        logLines.removeAll()
    }

    @Published var status: Status = .stopped
    @Published var logLines: [String] = []
    @Published var uptimeSince: Date?
    @Published var lastError: String?
    @Published var external = false // 앱이 띄우지 않은 기존 데몬에 연결 중
    @Published var muted = false // 외부 연결 해제 후 자동 재연결 억제 (명시적 시작까지)
    @Published var unlinkedRunning = false // 연결 해제한 외부 데몬이 여전히 실행 중 (T-179)

    private var process: Process?
    private var pollTask: Task<Void, Never>?
    private var unhealthyStreak = 0
    private let logger = DebugLogger.shared
    private let uv = UvManager()

    var baseURL: URL { URL(string: "http://\(Self.host):\(Self.port)")! }

    /// 3초 주기 헬스 폴러 (멱등). 상태 굳음 방지: 외부 기동 감지·죽음 감지.
    func beginPolling() {
        guard pollTask == nil else { return }
        logger.info(feature: "데몬감시", "헬스 폴러 시작 (3s)")
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self?.pollOnce()
            }
        }
    }

    private func pollOnce() async {
        // 앱 소유 프로세스 alive면 running 확정 (헬스 무관).
        if process?.isRunning == true {
            if status != .running {
                status = .running
                uptimeSince = uptimeSince ?? Date()
                logger.info(feature: "데몬감시", "소유 프로세스 확인 → 실행 중")
            }
            unhealthyStreak = 0
            unlinkedRunning = false
            return
        }
        let healthy = await isHealthy()
        // mute여도 서버 실상은 표시 (T-179): 중지로 보이지만 떠 있으면 미연결로 안내.
        unlinkedRunning = Self.unlinkedRunning(muted: muted, healthy: healthy)
        let before = (status, external)
        let next = Self.transition(status: status, external: external, muted: muted,
                                   healthy: healthy, streak: unhealthyStreak)
        status = next.status
        external = next.external
        unhealthyStreak = next.streak
        if next.status == .running { uptimeSince = uptimeSince ?? Date() }
        if next.status != .running { uptimeSince = nil }
        if (before.0 != next.status) || (before.1 != next.external) {
            logger.info(feature: "데몬감시", "\(before.0.rawValue)→\(next.status.rawValue) 외부=\(next.external)")
        }
    }

    /// 미연결 외부 실행 판정 (순수, 테스트 가능, T-179).
    /// mute+healthy면 서버는 살아있고 연결만 끊긴 상태라 별도 표시한다.
    nonisolated static func unlinkedRunning(muted: Bool, healthy: Bool) -> Bool {
        muted && healthy
    }

    /// 상태 전이 결과 (T-289: large_tuple 해소).
    struct Transition: Equatable {
        let status: Status
        let external: Bool
        let streak: Int
    }

    /// 상태 전이표 (순수, 테스트 가능).
    nonisolated static func transition(status: Status, external: Bool, muted: Bool,
                                       healthy: Bool, streak: Int) -> Transition {
        if healthy {
            // 시작 중(start 루프 담당)은 폴러가 건드리지 않는다.
            if status == .starting { return Transition(status: status, external: external, streak: 0) }
            if status == .running { return Transition(status: .running, external: external, streak: 0) }
            if muted { return Transition(status: .stopped, external: false, streak: 0) } // 재연결 억제
            return Transition(status: .running, external: true, streak: 0) // 외부 기동 감지·연결
        }
        // unhealthy
        if status == .running {
            let next = streak + 1
            if next >= 3 { return Transition(status: .failed, external: false, streak: 0) } // 죽음 확정
            return Transition(status: .running, external: external, streak: next)
        }
        return Transition(status: status, external: external, streak: 0)
    }

    func start() async {
        logger.info(feature: "데몬시작", "litert-lm serve 기동 시작")
        muted = false // 명시적 시작은 억제 해제
        unlinkedRunning = false
        guard process?.isRunning != true else { return }
        // 이미 떠 있는 데몬(터미널/이전 실행)이 있으면 바인드 실패 대신 연결한다.
        if await isHealthy() {
            status = .running
            external = true
            uptimeSince = Date()
            logger.info(feature: "데몬시작", "기존 실행 중 데몬에 연결 (외부 프로세스)")
            return
        }
        external = false
        status = .starting
        let p = Process()
        p.executableURL = URL(fileURLWithPath: UvManager.litertBin)
        p.arguments = ["serve", "--host", Self.host, "--port", "\(Self.port)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let line = String(data: h.availableData, encoding: .utf8) ?? ""
            guard !line.isEmpty else { return }
            Task { @MainActor in
                let stamp = Self.logTimeString(Date())
                self?.logLines.append(contentsOf: Self.stampedLines(line, time: stamp))
                if self?.logLines.count ?? 0 > 500 { self?.logLines.removeFirst(200) }
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            status = .failed
            lastError = "E-MAC-NET-0004"
            logger.error(code: "E-MAC-NET-0004", feature: "데몬시작", "프로세스 기동 실패: \(error)")
            return
        }
        // /v1/models 폴링 (임의 sleep 금지 → 상태 폴링)
        for _ in 0..<24 {
            if await isHealthy() {
                status = .running
                uptimeSince = Date()
                logger.info(feature: "데몬시작", "헬스체크 통과, 실행 중")
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        status = .failed
        lastError = "E-MAC-NET-0004"
        logger.error(code: "E-MAC-NET-0004", feature: "데몬시작", "헬스체크 타임아웃")
        stop()
    }

    func stop() {
        // 외부 데몬은 종료하지 않고 연결만 끊는다 (사용자 프로세스 보호).
        // 외부 종료가 필요하면 takeOverAndRestart() (확인 대화상자 경유).
        // 연결 해제 후 폴러의 자동 재연결을 억제한다 (명시적 시작까지).
        if external { muted = true }
        logger.info(feature: "데몬중지", external ? "외부 데몬 연결 해제 (재연결 억제)" : "데몬 중지")
        process?.terminate()
        process = nil
        external = false
        status = .stopped
        unlinkedRunning = false // 다음 폴링에서 실측으로 갱신
        uptimeSince = nil
        unhealthyStreak = 0
    }

    /// 외부 데몬 인수: litert-lm 프로세스 종료 후 앱 데몬으로 재시작.
    /// 반드시 확인 대화상자를 거쳐 호출한다.
    func takeOverAndRestart() async {
        logger.info(feature: "데몬인수", "외부 프로세스 종료 시작")
        let targets = SystemMonitor.daemonPIDs(listeners: SystemMonitor.listenerPIDs())
        for pid in targets {
            kill(pid, SIGTERM)
        }
        for _ in 0..<10 {
            if await !isHealthy() { break }
            try? await Task.sleep(for: .seconds(1))
        }
        for pid in SystemMonitor.daemonPIDs(listeners: SystemMonitor.listenerPIDs()) {
            kill(pid, SIGKILL)
        }
        try? await Task.sleep(for: .seconds(1))
        external = false
        status = .stopped
        await start()
    }

    func isHealthy() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/models"))
        req.timeoutInterval = 5 // T-119 폴러(3s) 적체 방지: 실패는 빨리 확정
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
