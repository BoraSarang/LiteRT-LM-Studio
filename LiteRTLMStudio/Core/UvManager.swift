import Foundation

/// uv + litert-lm 설치 상태 관리. Swift Process PATH 미의존을 위해 uv 절대경로 사용.
@MainActor
final class UvManager: ObservableObject {
    static let uvPath = "/opt/homebrew/bin/uv"
    static let litertBin = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/litert-lm").path

    /// 조회 전·미설치 상태 토큰 (표시 문구와 분리, T-363).
    nonisolated static let checkingStatus = "__checking__"
    nonisolated static let missingStatus = "__missing__"

    /// 표시용 버전 문자열 (확인 중·없음은 번역, 그 외 원문).
    nonisolated static func display(_ raw: String) -> String {
        switch raw {
        case checkingStatus: return L(L10n.Env.checking)
        case missingStatus: return L(L10n.Env.missing)
        default: return raw
        }
    }

    nonisolated static func isChecking(_ raw: String) -> Bool { raw == checkingStatus }
    nonisolated static func isMissing(_ raw: String) -> Bool { raw == missingStatus }

    @Published var uvVersion = UvManager.checkingStatus
    @Published var litertVersion = UvManager.checkingStatus
    @Published var uvAvailable = false
    @Published var lastError: String?

    private let logger = DebugLogger.shared

    func refresh() async {
        logger.info(feature: "환경확인", "uv/litert-lm 상태 조회 시작")
        async let uv = run(UvManager.uvPath, args: ["--version"])
        async let lv = run(UvManager.litertBin, args: ["--version"])
        let (uvOut, uvCode) = await uv
        let (litOut, litCode) = await lv
        uvAvailable = uvCode == 0
        uvVersion = uvCode == 0 ? uvOut.trimmingCharacters(in: .whitespacesAndNewlines)
            : UvManager.missingStatus
        litertVersion = litCode == 0 ? litOut.trimmingCharacters(in: .whitespacesAndNewlines)
            : UvManager.missingStatus
        if uvCode != 0 {
            lastError = "E-MAC-VALID-0001"
            logger.error(code: "E-MAC-VALID-0001", feature: "환경확인", "uv를 찾을 수 없음")
        } else {
            logger.info(feature: "환경확인", "uv=\(uvVersion) litert-lm=\(litertVersion)")
        }
    }

    /// 종료 코드와 합친 출력을 반환하는 작은 Process 래퍼.
    /// 타임아웃 시 프로세스 종료 후 124 반환 (T-127, hang 무한대기 방지).
    func run(_ path: String, args: [String], timeout: TimeInterval = 30) async -> (String, Int32) {
        await Self.runProcess(path, args: args, timeout: timeout)
    }

    /// 인스턴스 상태 비의존 실행기 (T-127): TaskGroup 병렬 호출용 nonisolated.
    nonisolated static func runProcess(
        _ path: String,
        args: [String],
        timeout: TimeInterval = 30
    ) async -> (String, Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                let state = TimeoutState()
                do {
                    try p.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if p.isRunning {
                            state.timedOut = true
                            p.terminate()
                        }
                    }
                    p.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if state.timedOut {
                        cont.resume(returning: ("timeout after \(Int(timeout))s: \(path)", 124))
                    } else {
                        cont.resume(returning: (String(data: data, encoding: .utf8) ?? "",
                                               p.terminationStatus))
                    }
                } catch {
                    cont.resume(returning: ("\(error)", 127))
                }
            }
        }
    }
}

/// 타임아웃 플래그 (T-127): 워치독·대기 스레드 공유.
private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var timedOut: Bool {
        get { lock.withLock { flag } }
        set { lock.withLock { flag = newValue } }
    }
}
