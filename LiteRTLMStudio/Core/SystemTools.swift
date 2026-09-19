import AppKit
import Foundation

/// Shortcuts 실행 허용 목록 (T-270): 사용자가 등록한 이름만 실행.
enum ShortcutsAllowlist {
    nonisolated static var key: String { "shortcutsAllowlist" }

    nonisolated static func names(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    nonisolated static func isAllowed(_ name: String, defaults: UserDefaults = .standard) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return names(defaults: defaults).contains {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    nonisolated static func setNames(_ list: [String], defaults: UserDefaults = .standard) {
        var unique: [String] = []
        for raw in list {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if !unique.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                unique.append(name)
            }
        }
        defaults.set(unique, forKey: key)
    }

    nonisolated static func add(_ name: String, defaults: UserDefaults = .standard) {
        setNames(names(defaults: defaults) + [name], defaults: defaults)
    }

    nonisolated static func remove(_ name: String, defaults: UserDefaults = .standard) {
        setNames(names(defaults: defaults).filter {
            $0.caseInsensitiveCompare(name) != .orderedSame
        }, defaults: defaults)
    }
}

/// URL 열기 정책 (T-270, 순수): http·https만 허용.
enum OpenURLPolicy {
    nonisolated static func allowed(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

/// 시스템 정보 요약 (T-270, 순수): 모델에게 그대로 전달.
enum SystemInfoReport {
    nonisolated static func text() -> String {
        let info = ProcessInfo.processInfo
        var lines = ["macOS \(info.operatingSystemVersionString)"]
        lines.append("CPU 코어 \(info.processorCount)개 · 물리 메모리 \(bytes(info.physicalMemory))")
        lines.append("가동 시간 \(uptime(info.systemUptime)) · 발열 상태 \(thermal(info.thermalState))")
        if info.isLowPowerModeEnabled { lines.append("저전력 모드 켜짐") }
        if let disk = disk() { lines.append("디스크 여유 \(bytes(disk.free)) / 전체 \(bytes(disk.total))") }
        return lines.joined(separator: "\n")
    }

    nonisolated static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    nonisolated static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return "\(total / 3600)시간 \((total % 3600) / 60)분"
    }

    nonisolated static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "정상"
        case .fair: return "보통"
        case .serious: return "높음"
        case .critical: return "위험"
        @unknown default: return "알 수 없음"
        }
    }

    nonisolated static func disk() -> (free: UInt64, total: UInt64)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey
        ]), let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return (UInt64(max(0, free)), UInt64(max(0, total)))
    }
}

/// 클립보드 접근 (T-270): AppKit은 메인 스레드에서만.
enum ClipboardAccess {
    @MainActor static func read() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    @MainActor static func write(_ text: String) -> Bool {
        let board = NSPasteboard.general
        board.clearContents()
        return board.setString(text, forType: .string)
    }
}

/// URL 열기 (T-270): AppKit은 메인 스레드에서만.
enum WorkspaceAccess {
    @MainActor static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

/// 시스템 정보·현재 상태 도구 (T-270): 부작용 없음.
struct GetSystemInfoTool: Tool {
    static let name = "get_system_info"
    static let description = "Mac의 메모리·CPU 코어·디스크 여유·가동 시간 등 시스템 상태를 알려줍니다."

    func run() async throws -> Any {
        await LocalTools.runTolled(toolName: Self.name, detail: "시스템 정보 조회") {
            SystemInfoReport.text()
        }
    }
}

/// 클립보드 읽기 도구 (T-270): 부작용 없음.
struct ReadClipboardTool: Tool {
    static let name = "read_clipboard"
    static let description = "클립보드에 복사되어 있는 텍스트를 읽어 옵니다."

    func run() async throws -> Any {
        await LocalTools.runTolled(toolName: Self.name, detail: "클립보드 읽기") {
            let text = await ClipboardAccess.read()
            return text.isEmpty ? "클립보드가 비어 있습니다." : text
        }
    }
}

/// 클립보드 쓰기 도구 (T-270): 게이트 승인 필요.
struct WriteClipboardTool: Tool {
    static let name = "write_clipboard"
    static let description = "텍스트를 클립보드에 복사합니다."

    @ToolParam(description: "복사할 텍스트")
    var text = ""

    func run() async throws -> Any {
        let body = text
        return await LocalTools.runTolled(toolName: Self.name,
                                          detail: "클립보드에 복사 (\(body.count)자)") {
            let ok = await ClipboardAccess.write(body)
            return ok ? "클립보드에 복사했습니다." : "클립보드 쓰기에 실패했습니다."
        }
    }
}

/// URL 열기 도구 (T-270): http·https만, 게이트 승인 필요.
struct OpenURLTool: Tool {
    static let name = "open_url"
    static let description = "http·https 주소를 기본 브라우저로 엽니다."

    @ToolParam(description: "열 주소 (http 또는 https)")
    var url = ""

    func run() async throws -> Any {
        let raw = url
        guard let target = OpenURLPolicy.allowed(raw) else {
            let reason = "차단됨: http 또는 https 주소만 열 수 있습니다."
            await ToolLedger.shared.record(toolName: Self.name, detail: raw,
                                           result: reason, denied: true)
            DebugLogger.shared.info(feature: "시스템도구", "open_url 차단: \(raw)")
            return reason
        }
        return await LocalTools.runTolled(toolName: Self.name, detail: target.absoluteString) {
            let ok = await WorkspaceAccess.open(target)
            return ok ? "열었습니다: \(target.absoluteString)" : "열기에 실패했습니다."
        }
    }
}

/// Shortcuts 실행 도구 (T-270): 허용 목록 이름만, 게이트 승인 필요.
struct RunShortcutTool: Tool {
    static let name = "run_shortcut"
    static let description = "허용 목록에 등록된 단축어(Shortcuts)를 실행합니다. 설정 > 도구에서 이름을 등록하세요."

    @ToolParam(description: "실행할 단축어 이름 (허용 목록에 있어야 함)")
    var shortcut = ""

    func run() async throws -> Any {
        let target = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ShortcutsAllowlist.isAllowed(target) else {
            let reason = "차단됨: '\(target)'은(는) 허용 목록에 없습니다. 설정 > 도구에서 추가하세요."
            await ToolLedger.shared.record(toolName: Self.name, detail: target,
                                           result: reason, denied: true)
            DebugLogger.shared.error(code: "E-MAC-PERM-0016", feature: "시스템도구",
                                     "허용 목록에 없는 단축어: \(target)")
            return target.isEmpty ? "실행할 단축어 이름이 비어 있습니다." : reason
        }
        return await LocalTools.runTolled(toolName: Self.name, detail: "단축어 실행: \(target)") {
            let (out, code) = await UvManager.runProcess("/usr/bin/shortcuts",
                                                         args: ["run", target], timeout: 60)
            let clipped = String(out.prefix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
            if code != 0 {
                return "단축어 실행 실패(exit=\(code)): \(clipped)"
            }
            return clipped.isEmpty ? "단축어 '\(target)'을(를) 실행했습니다." : "실행됨: \(clipped)"
        }
    }
}
