import Foundation

/// uv + litert-lm 설치 상태 관리. Swift Process PATH 미의존을 위해 uv 절대경로 사용.
@MainActor
final class UvManager: ObservableObject {
    static let uvPath = "/opt/homebrew/bin/uv"
    static let litertBin = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/litert-lm").path

    @Published var uvVersion = "확인 중…"
    @Published var litertVersion = "확인 중…"
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
        uvVersion = uvCode == 0 ? uvOut.trimmingCharacters(in: .whitespacesAndNewlines) : "없음"
        litertVersion = litCode == 0 ? litOut.trimmingCharacters(in: .whitespacesAndNewlines) : "없음"
        if uvCode != 0 {
            lastError = "E-MAC-VALID-0001"
            logger.error(code: "E-MAC-VALID-0001", feature: "환경확인", "uv를 찾을 수 없음")
        } else {
            logger.info(feature: "환경확인", "uv=\(uvVersion) litert-lm=\(litertVersion)")
        }
    }

    func upgradeLitertLM() async -> Bool {
        logger.info(feature: "업그레이드", "uv tool upgrade litert-lm 시작")
        let (out, code) = await run(UvManager.uvPath, args: ["tool", "upgrade", "litert-lm"])
        logger.info(feature: "업그레이드", out.prefix(500).description)
        await refresh()
        return code == 0
    }

    /// 종료 코드와 합친 출력을 반환하는 작은 Process 래퍼.
    func run(_ path: String, args: [String]) async -> (String, Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    cont.resume(returning: (String(data: data, encoding: .utf8) ?? "", p.terminationStatus))
                } catch {
                    cont.resume(returning: ("\(error)", 127))
                }
            }
        }
    }
}
