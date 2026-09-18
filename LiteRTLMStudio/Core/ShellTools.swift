import Foundation

/// 셸·파일 가드 (T-272, 순수·테스트 가능): 차단 패턴+jail.
/// 임의 명령 허용 대신 하드 차단선 유지 (AGENTS 파괴적 가드와 동일).
enum ShellGuard {
    /// 차단 정규식 (소문자 비교): 매칭 시 실행 없이 거부.
    nonisolated static var blockedPatterns: [(pattern: String, reason: String)] {
        [
            (#"rm\s+-[a-z]*r"#, "재귀 삭제 금지"),
            (#"(^|[\s;&|])sudo(\s|$)"#, "관리자 권한 금지"),
            (#":\(\)\s*\{"#, "포크밤 금지"),
            (#"\b(dd|mkfs)\b"#, "디스크 직접 쓰기 금지"),
            (#"\|\s*(sh|bash|zsh)\b"#, "파이프 셸 실행 금지"),
            (#"\.env\b"#, "환경 파일 접근 금지"),
            (#"keystore|mobileprovision"#, "서명 자산 접근 금지"),
            (#"\.ssh/"#, "SSH 자산 접근 금지")
        ]
    }

    /// 작업폴더 루트 (설정 지정, 기본값 내장).
    nonisolated static func workspaceRoot(
        override: String? = UserDefaults.standard.string(forKey: "workspaceRoot")
    ) -> URL {
        if let o = override, !o.isEmpty {
            return URL(fileURLWithPath: (o as NSString).expandingTildeInPath)
        }
        return StudioPaths.workspaceURL
    }

    /// 명령 감사 (순수): 차단 사유 또는 nil(통과).
    nonisolated static func audit(command: String) -> String? {
        let lower = command.lowercased()
        return blockedPatterns.first {
            lower.range(of: $0.pattern, options: .regularExpression) != nil
        }?.reason
    }

    /// jail 해석 (순수): 루트 밖이면 nil (`..` 탈출·절대경로 포함).
    nonisolated static func jailed(_ path: String, root: URL) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : root.appendingPathComponent(expanded)
        let norm = url.standardized
        let base = root.standardized.path
        guard norm.path == base || norm.path.hasPrefix(base + "/") else { return nil }
        return norm
    }
}

/// 셸 실행 도구 (T-272): 임의 명령+확인 팝업(명령 전문 표시).
/// allowlist 대신 차단선+jail+출력 cap. Allow 모드에서도 칩에 전문 기록.
struct RunShellTool: Tool {
    static let name = "run_shell"
    static let description = "셸 명령을 실행합니다. 조회·빌드·스크립트 실행에 사용하세요. 삭제·관리자 명령은 차단됩니다."

    @ToolParam(description: "실행할 셸 명령 전문 (예: ls -la)")
    var command: String = ""

    func run() async throws -> Any {
        let cmd = command
        if let reason = ShellGuard.audit(command: cmd) {
            await ToolLedger.shared.record(toolName: Self.name, detail: cmd,
                                           result: "차단됨: \(reason)", denied: true)
            DebugLogger.shared.info(feature: "셸도구", "차단: \(reason)")
            return "차단됨: \(reason)"
        }
        return await LocalTools.runTolled(toolName: Self.name, detail: cmd) {
            let root = ShellGuard.workspaceRoot()
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let (out, code) = await UvManager.runProcess(
                "/bin/zsh", args: ["-c", cmd], timeout: 30)
            let clipped = String(out.prefix(8000))
            return "exit=\(code)\n\(clipped)"
        }
    }
}

/// 코드 저장 도구 (T-272): 작업폴더 한정+덮어쓰기 표시+512KB cap.
struct SaveCodeTool: Tool {
    static let name = "save_code"
    static let description = "코드·텍스트 파일을 작업폴더에 저장합니다. path는 작업폴더 기준 상대경로 권장."

    @ToolParam(description: "저장 경로 (작업폴더 기준, 예: hello.py)")
    var path: String = ""
    @ToolParam(description: "파일 전체 내용")
    var content: String = ""

    nonisolated static var sizeCap: Int { 512 * 1024 }

    func run() async throws -> Any {
        let relPath = path
        let body = content
        let root = ShellGuard.workspaceRoot()
        guard let url = ShellGuard.jailed(relPath, root: root) else {
            await ToolLedger.shared.record(toolName: Self.name, detail: relPath,
                                           result: "차단됨: 작업폴더 밖 경로", denied: true)
            return "차단됨: 작업폴더 밖에는 저장할 수 없습니다."
        }
        guard body.utf8.count <= Self.sizeCap else {
            return "저장 실패: 512KB를 초과합니다."
        }
        guard !body.contains("\0") else {
            return "저장 실패: 바이너리는 저장할 수 없습니다."
        }
        let existed = FileManager.default.fileExists(atPath: url.path)
        let detail = existed
            ? "\(relPath) (덮어쓰기, 기존 \(Self.fileSize(url)) bytes)"
            : "\(relPath) (신규, \(body.utf8.count) bytes)"
        return await LocalTools.runTolled(toolName: Self.name, detail: detail) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
            return existed ? "덮어씀: \(relPath)" : "저장됨: \(relPath)"
        }
    }

    /// 기존 파일 크기 (없으면 0).
    nonisolated static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}

/// 파일 읽기 도구 (T-272, 검증용): 작업폴더 한정+100KB cap.
struct ReadFileTool: Tool {
    static let name = "read_file"
    static let description = "작업폴더 안 텍스트 파일을 읽습니다. 저장 결과 검증에 사용하세요."

    @ToolParam(description: "읽을 경로 (작업폴더 기준)")
    var path: String = ""

    nonisolated static var sizeCap: Int { 100 * 1024 }

    func run() async throws -> Any {
        let relPath = path
        let root = ShellGuard.workspaceRoot()
        guard let url = ShellGuard.jailed(relPath, root: root) else {
            await ToolLedger.shared.record(toolName: Self.name, detail: relPath,
                                           result: "차단됨: 작업폴더 밖 경로", denied: true)
            return "차단됨: 작업폴더 밖은 읽을 수 없습니다."
        }
        return await LocalTools.runTolled(toolName: Self.name, detail: relPath) {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.sizeCap,
                  let text = String(data: data, encoding: .utf8) else {
                throw ShellReadError.unreadable
            }
            return text
        }
    }
}

/// 파일 읽기 오류 (T-272).
enum ShellReadError: Error {
    case unreadable
}
