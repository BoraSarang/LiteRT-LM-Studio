import Foundation

/// wigolo 탐색·진단 분리 (T-288, 본문 길이 관리).
extension WigoloManager {
    nonisolated static var binOverrideKey: String { "wigoloBin" }
    nonisolated static var npmOverrideKey: String { "npmBin" }

    /// 고정 베이스 URL (비격리 접근용).
    nonisolated static var baseURL: URL { URL(string: "http://\(host):\(port)")! }

    /// 바이너리 탐색 (순수 경로 조합+존재 확인, 테스트 가능).
    /// override → homebrew → npm-global → nvm 전버전(최신 우선) 순.
    nonisolated static func resolveBinary(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        overridePath: String? = UserDefaults.standard.string(forKey: binOverrideKey)
    ) -> String? {
        if let o = overridePath, !o.isEmpty { return o } // 명시 지정은 신뢰
        let fm = FileManager.default
        var candidates = ["/opt/homebrew/bin/wigolo", "\(home)/.npm-global/bin/wigolo"]
        candidates += nvmBinDirs(home: home, fm: fm).map { $0 + "/wigolo" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// nvm 버전 bin 목록 (최신 우선, 테스트 가능).
    nonisolated static func nvmBinDirs(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        fm: FileManager = .default
    ) -> [String] {
        guard let versions = try? fm.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") else {
            return []
        }
        return versions.sorted(by: >).map { "\(home)/.nvm/versions/node/\($0)/bin" }
    }

    /// wigolo 스크립트의 node 실행기 탐색 (순수, 테스트 가능, T-310):
    /// 같은 디렉터리의 node. 없으면 nil (그대로 실행 시도).
    nonisolated static func nodeForWigolo(bin: String) -> String? {
        let node = (bin as NSString).deletingLastPathComponent + "/node"
        return FileManager.default.isExecutableFile(atPath: node) ? node : nil
    }

    /// wigolo 실행 커맨드 (순수, 테스트 가능, T-310): GUI 앱 PATH는 축약이라
    /// shebang(`env node`)이 실패한다. 같은 디렉터리 node로 직접 실행.
    nonisolated static func wigoloCommand(_ bin: String, _ args: [String])
        -> (executable: String, args: [String]) {
        guard let node = nodeForWigolo(bin: bin) else { return (bin, args) }
        return (node, [bin] + args)
    }

    /// wigolo/npm 실행용 PATH 디렉터리 목록 (순수, T-310): nvm·homebrew·npm-global.
    nonisolated static func nodePathDirs(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin"]
            + nvmBinDirs(home: home)
    }

    /// PATH 확장 환경 (순수, T-310): 기존 환경 유지, PATH만 우선 확장.
    nonisolated static func processEnvironment(addingPathDirs dirs: [String]) -> [String: String] {
        let existing = ProcessInfo.processInfo.environment
        let base = (existing["PATH"] ?? "").isEmpty
            ? "/usr/bin:/bin:/usr/sbin:/sbin" : existing["PATH"]!
        var env = existing
        env["PATH"] = (dirs + [base]).joined(separator: ":")
        return env
    }

    /// npm 탐색 (순수 경로 조합+존재 확인, 테스트 가능): override → homebrew → nvm 전버전.
    nonisolated static func resolveNpm(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        overridePath: String? = UserDefaults.standard.string(forKey: npmOverrideKey)
    ) -> String? {
        if let o = overridePath, !o.isEmpty { return o } // 명시 지정은 신뢰
        let fm = FileManager.default
        var candidates = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]
        candidates += nvmBinDirs(home: home, fm: fm).map { $0 + "/npm" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// 컴포넌트 상태 4칸 (T-288): CLI·데몬·브라우저·모델.
    struct WigoloHealth: Sendable, Equatable {
        var cli = false
        var daemon = false
        var browser = false
        var models = false

        var allOK: Bool { cli && daemon && browser && models }
    }

    /// doctor 출력 파싱 (순수, 테스트 가능, T-288): 섹션별 긍정 신호 판독.
    nonisolated static func parseDoctor(_ text: String) -> (browser: Bool, models: Bool) {
        let lines = text.components(separatedBy: .newlines)
        var browser = false
        var models = false
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("browsers:") {
                browser = lower.contains(" ok") || lower.contains("ok ")
                    || lower.trimmingCharacters(in: .whitespaces).hasSuffix("ok")
            }
            if lower.contains("embeddings model:") {
                models = lower.contains("installed") && !lower.contains("not installed")
            }
        }
        return (browser, models)
    }
}

/// serve 실행+로그 확장 (T-308, WigoloManager 본문 길이 관리).
extension WigoloManager {
    /// serve 실행+출력 수집.
    func runServe(binary bin: String) async {
        // T-310: node shebang이 앱 PATH에서 실패("env: node") → node 직접 실행+PATH 주입.
        let cmd = Self.wigoloCommand(bin, ["serve"])
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd.executable)
        p.arguments = cmd.args
        p.environment = Self.processEnvironment(addingPathDirs: Self.nodePathDirs())
        // serve 출력 파이프 수집 (없으면 실패 원인 추적 불가).
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        appendServeLog("$ \(cmd.executable) \(cmd.args.joined(separator: " "))")
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let line = String(data: h.availableData, encoding: .utf8) ?? ""
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { @MainActor in self?.appendServeLog(line) }
        }
        p.terminationHandler = { [weak self] proc in
            // 실행 중 종료면 중지로 확정 (stop()과 중복 기록 방지: alive면 skip).
            Task { @MainActor in self?.noteServeExit(proc) }
        }
        do {
            try p.run()
            process = p
            logger.info(feature: "웹검색", "wigolo 데몬 시작 (\(bin))")
            try? await Task.sleep(for: .seconds(3))
            await recheck()
            appendServeLog(status == .running
                ? "헬스 확인 OK (127.0.0.1:3333)"
                : "헬스 확인 실패 — 위 출력을 확인해 주세요")
        } catch {
            status = .failed
            lastError = "E-MAC-NET-0015"
            appendServeLog("시작 실패: \(error)")
            logger.error(code: "E-MAC-NET-0015", feature: "웹검색", "데몬 시작 실패: \(error)")
        }
    }

    /// serve 비정상 종료 확정.
    func noteServeExit(_ proc: Process) {
        let code = proc.terminationStatus
        guard process === proc || process == nil else { return }
        guard status == .running, code != 0 else { return }
        appendServeLog("종료 (코드 \(code))")
        status = .stopped
        logger.error(code: "E-MAC-NET-0015", feature: "웹검색",
                     "wigolo 데몬 비정상 종료: 코드 \(code)")
    }

    /// serve 실행 로그 상한 (순수, 테스트 가능): 꼬리 cap줄 유지.
    nonisolated static func cappedServeLog(_ lines: [String], cap: Int = 300) -> [String] {
        lines.count <= cap ? lines : Array(lines.suffix(cap))
    }

    /// serve 실행 로그 추가 (300줄 cap).
    func appendServeLog(_ line: String) {
        serveLog.append(contentsOf: line.components(separatedBy: .newlines).filter { !$0.isEmpty })
        serveLog = Self.cappedServeLog(serveLog)
    }
}
