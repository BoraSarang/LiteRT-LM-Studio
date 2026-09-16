import Foundation

/// wigolo 로컬 데몬 관리 (T-269): 127.0.0.1:3333 고정, 앱 소유 자식으로 실행.
/// 설치·초기화는 사용자 몫 (`npm i -g wigolo` 후 `wigolo serve`), 앱은 기동만 담당.
@MainActor
final class WigoloManager: ObservableObject {
    enum Status: String {
        case stopped = "중지", starting = "시작 중…", running = "실행 중", failed = "실패", missing = "미설치"
    }

    static let host = "127.0.0.1"
    static let port = 3333
    nonisolated static var binOverrideKey: String { "wigoloBin" }

    @Published var status: Status = .stopped
    @Published var lastError: String?

    private var process: Process?
    private let logger = DebugLogger.shared

    var baseURL: URL { Self.baseURL }

    /// 고정 베이스 URL (비격리 접근용).
    nonisolated static var baseURL: URL { URL(string: "http://\(host):\(port)")! }

    /// 바이너리 탐색 (순수 경로 조합+존재 확인, 테스트 가능).
    /// override → homebrew → nvm 최신 → npm-global 순.
    nonisolated static func resolveBinary(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        overridePath: String? = UserDefaults.standard.string(forKey: binOverrideKey)
    ) -> String? {
        var candidates: [String] = []
        if let o = overridePath, !o.isEmpty { return o } // 명시 지정은 신뢰
        candidates.append("/opt/homebrew/bin/wigolo")
        candidates.append("\(home)/.npm-global/bin/wigolo")
        let fm = FileManager.default
        if let nvm = try? fm.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node").sorted().last {
            candidates.append("\(home)/.nvm/versions/node/\(nvm)/bin/wigolo")
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// 시작 (바이너리 없으면 .missing, 설치 안내 로그).
    func start() {
        guard process?.isRunning != true else { return }
        guard let bin = Self.resolveBinary() else {
            status = .missing
            lastError = "E-MAC-EXEC-0001"
            logger.error(code: "E-MAC-EXEC-0001", feature: "웹검색",
                         "wigolo 미설치. `npm i -g wigolo` 후 다시 시도해 주세요.")
            return
        }
        status = .starting
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["serve"]
        do {
            try p.run()
            process = p
            logger.info(feature: "웹검색", "wigolo 데몬 시작 (\(bin))")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                await self?.recheck()
            }
        } catch {
            status = .failed
            lastError = "E-MAC-NET-0015"
            logger.error(code: "E-MAC-NET-0015", feature: "웹검색", "데몬 시작 실패: \(error)")
        }
    }

    /// 중지 (앱 소유 프로세스만).
    func stop() {
        process?.terminate()
        process = nil
        status = .stopped
        logger.info(feature: "웹검색", "wigolo 데몬 중지")
    }

    /// 상태 재확인 (소유 프로세스 alive → running, 아니면 헬스체크).
    func recheck() async {
        if process?.isRunning == true {
            if await isHealthy() {
                status = .running
                return
            }
        }
        status = await isHealthy() ? .running : .stopped
        if status == .running { logger.info(feature: "웹검색", "외부 wigolo 연결됨") }
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
