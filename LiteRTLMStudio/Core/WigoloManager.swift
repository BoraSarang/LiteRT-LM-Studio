import Foundation

/// wigolo 로컬 데몬 관리 (T-269, T-284 설정 통합): 127.0.0.1:3333 고정.
/// 설치(npm i -g)는 설정 UI 버튼+확인 후 실행, 진행 로그 스트리밍.
/// 앱 시작 시 자동 serve, 종료 시 앱 소유 프로세스만 정리 (외부는 유지).
@MainActor
final class WigoloManager: ObservableObject {
    enum Status: String {
        case stopped = "중지", starting = "시작 중…", running = "실행 중",
             failed = "실패", missing = "미설치", installing = "설치 중…"
    }

    static let host = "127.0.0.1"
    static let port = 3333

    @Published var status: Status = .stopped
    @Published var lastError: String?
    @Published var version: String?
    @Published var installLog: [String] = []
    @Published var external = false // 앱이 띄우지 않은 기존 serve에 연결 중
    @Published var installStage: String? // T-288 설치 단계 표시 ("[1/3] 패키지" 등)
    @Published var health = WigoloHealth() // T-288 4칸 상태
    @Published var serveLog: [String] = [] // T-308 serve 실행 로그 (출력 파이프 수집)

    var process: Process?
    private var installProcess: Process?
    let logger = DebugLogger.shared

    var baseURL: URL { Self.baseURL }

    /// 시작 (이미 떠 있으면 바인드, 바이너리 없으면 .missing).
    func start() {
        guard process?.isRunning != true else { return }
        Task {
            if await isHealthy() {
                status = .running
                external = true
                logger.info(feature: "웹검색", "기존 wigolo에 연결 (외부 프로세스)")
                return
            }
            external = false
            guard let bin = Self.resolveBinary() else {
                status = .missing
                lastError = "E-MAC-EXEC-0001"
                logger.error(code: "E-MAC-EXEC-0001", feature: "웹검색",
                             "wigolo 미설치. 설정에서 설치 후 다시 시도해 주세요.")
                return
            }
            status = .starting
            await runServe(binary: bin)
        }
    }

    /// serve 실행+출력 수집은 WigoloSupport 확장 (T-308, 본문 길이 관리).

    /// 중지 (앱 소유 프로세스만, T-308: serveLog는 유지해 원인 추적).
    func stop() {
        if process?.isRunning == true { appendServeLog("중지 요청") }
        process?.terminate()
        process = nil
        external = false
        status = .stopped
        logger.info(feature: "웹검색", "wigolo 데몬 중지")
    }

    /// 자동 시작 (앱 시작 시): 켜짐+설치됨+미실행이면 serve.
    func ensureRunning() async {
        guard WebSearch.enabled() else { return }
        if await isHealthy() {
            status = .running
            return
        }
        guard Self.resolveBinary() != nil else {
            status = .missing
            return
        }
        start()
    }

    /// 설치 파이프라인 (T-288): [1/3] 패키지 → [2/3] 초기화 → [3/3] 검증.
    /// 확인 팝업 후 호출. 단계별 로그+DebugLogger 기록.
    func install() {
        guard installProcess?.isRunning != true else { return }
        guard Self.resolveNpm() != nil else {
            lastError = "E-MAC-EXEC-0002"
            logger.error(code: "E-MAC-EXEC-0002", feature: "웹검색",
                         "npm을 찾을 수 없습니다. Node.js 설치 후 다시 시도해 주세요.")
            return
        }
        status = .installing
        installLog = []
        logger.info(feature: "웹검색", "wigolo 설치 파이프라인 시작")
        Task { [weak self] in await self?.runInstallPipeline() }
    }

    /// 파이프라인 실행 (순차 3단계, 취소 시 중단).
    func runInstallPipeline() async {
        guard let npm = Self.resolveNpm() else { return }
        installStage = "[1/3] 패키지"
        appendInstallLog("[1/3] 패키지: $ npm i -g wigolo")
        logger.info(feature: "웹검색", "[1/3] 패키지 설치 시작")
        let pkg = await runStreaming(executable: npm, args: ["i", "-g", "wigolo"],
                                      timeout: 600,
                                      environment: Self.processEnvironment(addingPathDirs: Self.nodePathDirs()))
        guard status == .installing else { return } // 취소됨
        if pkg != 0 {
            await finishInstall(code: pkg, stage: "[1/3] 패키지")
            return
        }
        guard let bin = Self.resolveBinary() else {
            await finishInstall(code: 1, stage: "[1/3] 패키지")
            return
        }
        installStage = "[2/3] 초기화"
        // T-310: nvm node로 직접 실행해야 shebang env-node가 살아난다.
        let initCmd = Self.wigoloCommand(bin, ["init"])
        appendInstallLog("[2/3] 초기화: $ \(initCmd.executable) \(initCmd.args.joined(separator: " "))")
        logger.info(feature: "웹검색", "[2/3] 초기화 시작")
        let initCode = await runStreaming(executable: initCmd.executable, args: initCmd.args,
                                          timeout: 600,
                                          environment: Self.processEnvironment(addingPathDirs: Self.nodePathDirs()))
        guard status == .installing else { return } // 취소됨
        if initCode != 0 {
            await finishInstall(code: initCode, stage: "[2/3] 초기화")
            return
        }
        installStage = "[3/3] 검증"
        appendInstallLog("[3/3] 검증: $ wigolo doctor")
        logger.info(feature: "웹검색", "[3/3] 검증 시작")
        await doctor()
        installStage = nil
        if health.allOK {
            appendInstallLog("설치 완료 (4칸 정상)")
            logger.info(feature: "웹검색", "wigolo 설치 파이프라인 완료")
            status = .stopped
            await fetchVersion()
            await recheck()
        } else {
            status = .failed
            lastError = "E-MAC-EXEC-0001"
            appendInstallLog("검증 미통과 — 로그 확인 후 다시 시도")
            logger.error(code: "E-MAC-EXEC-0001", feature: "웹검색", "wigolo 검증 미통과")
        }
    }

    /// 로그 스트리밍 실행 (취소·타임아웃 지원). 종료코드 반환 (124=타임아웃).
    /// environment: PATH shebang 발동용 선택 주입 (T-310).
    func runStreaming(executable: String, args: [String], timeout: TimeInterval,
                      environment: [String: String]? = nil) async -> Int32 {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            if let environment { p.environment = environment }
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let line = String(data: h.availableData, encoding: .utf8) ?? ""
                guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task { @MainActor in self?.appendInstallLog(line) }
            }
            var done = false
            let finish: (Int32) -> Void = { code in
                guard !done else { return }
                done = true
                pipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in cont.resume(returning: code) }
            }
            p.terminationHandler = { proc in finish(proc.terminationStatus) }
            p.terminationHandler = { proc in finish(proc.terminationStatus) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning {
                    p.terminate()
                    finish(124)
                }
            }
            do {
                try p.run()
                installProcess = p
            } catch {
                finish(1)
            }
        }
    }

    /// 설치 취소.
    func cancelInstall() {
        installProcess?.terminate()
        installProcess = nil
        installStage = nil
        status = .stopped
        appendInstallLog("취소됨")
        logger.info(feature: "웹검색", "wigolo 설치 취소")
    }

    /// 설치 종료 처리 (T-288): 단계별 실패 기록.
    func finishInstall(code: Int32, stage: String) async {
        installProcess = nil
        installStage = nil
        status = .failed
        lastError = "E-MAC-EXEC-0001"
        appendInstallLog("\(stage) 실패 (종료코드 \(code))")
        logger.error(code: "E-MAC-EXEC-0001", feature: "웹검색",
                     "wigolo \(stage) 실패: 종료코드 \(code)")
    }

    /// doctor 실행 (T-288): CLI+브라우저+모델 판독, 데몬은 REST로. 결과 health 반영+로그.
    func doctor() async {
        var result = WigoloHealth()
        result.cli = Self.resolveBinary() != nil
        result.daemon = await isHealthy()
        if let bin = Self.resolveBinary() {
            // T-310: node 경유 실행 (shebang env-node 확보).
            let cmd = Self.wigoloCommand(bin, ["doctor"])
            let (out, code) = await UvManager.runProcess(cmd.executable, args: cmd.args, timeout: 120)
            if code == 0 {
                appendInstallLog(out)
                let parsed = Self.parseDoctor(out)
                result.browser = parsed.browser
                result.models = parsed.models
            } else {
                logger.error(code: "E-MAC-EXEC-0001", feature: "웹검색",
                             "wigolo doctor 실패: 종료코드 \(code)")
            }
        }
        health = result
        logger.info(feature: "웹검색",
                    "doctor: CLI=\(result.cli) 데몬=\(result.daemon) "
                        + "브라우저=\(result.browser) 모델=\(result.models)")
    }

    /// 버전 조회 (`wigolo --version` 첫 줄, T-310: node 경유).
    func fetchVersion() async {
        guard let bin = Self.resolveBinary() else { return }
        let cmd = Self.wigoloCommand(bin, ["--version"])
        let (out, code) = await UvManager.runProcess(cmd.executable, args: cmd.args, timeout: 30)
        if code == 0 {
            version = out.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first
        }
    }

    /// 설치 로그 추가 (300줄 cap).
    func appendInstallLog(_ line: String) {
        installLog.append(contentsOf: line.components(separatedBy: .newlines).filter { !$0.isEmpty })
        if installLog.count > 300 { installLog.removeFirst(installLog.count - 300) }
    }

    /// serve 실행 로그는 WigoloSupport 확장 (T-308, 본문 길이 관리).

    /// 상태 재확인 (소유 프로세스 alive → running, 아니면 헬스체크).
    func recheck() async {
        if process?.isRunning == true {
            if await isHealthy() {
                status = .running
                return
            }
        }
        status = await isHealthy() ? .running : .stopped
        if status == .running {
            logger.info(feature: "웹검색", "외부 wigolo 연결됨")
            if version == nil { await fetchVersion() }
        }
    }

    /// 헬스체크 (순수 요청, 테스트 가능 구조): /openapi.json 5초.
    func isHealthy() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("openapi.json"))
        req.timeoutInterval = 5
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return true
    }
}
