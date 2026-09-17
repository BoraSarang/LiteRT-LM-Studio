import Foundation

/// 스킬 정보 (T-285): 폴더명+첫 줄 설명+켜짐.
struct SkillInfo: Identifiable, Hashable, Sendable {
    let name: String
    let blurb: String
    let enabled: Bool
    var id: String { name }
}

/// SKILL.md 스킬 저장소 (T-285): 스캔+토글+프롬프트 조립.
/// 디렉터리: Application Support/LiteRTLMStudio/Skills/<이름>/SKILL.md
enum SkillsStore {
    nonisolated static var keyPrefix: String { "skillEnabled." }
    nonisolated static var promptCap: Int { 8192 }

    nonisolated static func skillsDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LiteRTLMStudio/Skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 스캔 (SKILL.md 있는 폴더만, 이름순).
    nonisolated static func scan() -> [(name: String, blurb: String)] {
        let dir = skillsDir()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [(name: String, blurb: String)] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let readme = entry.appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: readme, encoding: .utf8) else { continue }
            out.append((entry.lastPathComponent, firstLine(text)))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// 첫 줄 설명 추출 (순수, 테스트 가능): # 제거·80자 절단.
    nonisolated static func firstLine(_ text: String) -> String {
        let line = text.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let stripped = line.hasPrefix("#")
            ? line.dropFirst().trimmingCharacters(in: .whitespaces) : line
        return String(stripped.prefix(80))
    }

    /// 개별 활성화 여부 (기본 켜짐, 테스트 가능).
    nonisolated static func isEnabled(_ name: String,
                                      defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: keyPrefix + name) == nil
            || defaults.bool(forKey: keyPrefix + name)
    }

    /// 개별 ON/OFF 저장 (테스트 가능).
    nonisolated static func setEnabled(_ name: String, _ on: Bool,
                                       defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: keyPrefix + name)
    }

    /// 목록 (스캔+플래그 결합).
    nonisolated static func list() -> [SkillInfo] {
        scan().map { SkillInfo(name: $0.name, blurb: $0.blurb, enabled: isEnabled($0.name)) }
    }

    /// 프롬프트 조립 (켜진 스킬 본문 연결, cap 초과 절단).
    /// - Returns: 본문+잘림 여부.
    nonisolated static func assembledPrompt() -> (text: String, truncated: Bool) {
        var parts: [String] = []
        var used = 0
        var truncated = false
        for info in list() where info.enabled {
            let url = skillsDir().appendingPathComponent(info.name).appendingPathComponent("SKILL.md")
            guard let body = try? String(contentsOf: url, encoding: .utf8),
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let chunk = "## Skill: \(info.name)\n\(body)"
            if used + chunk.count > promptCap {
                truncated = true
                break
            }
            parts.append(chunk)
            used += chunk.count
        }
        return (parts.joined(separator: "\n\n"), truncated)
    }

    /// MCP 안내 블록 (순수, 테스트 가능): 서버명 목록+호출 유도.
    nonisolated static func mcpBlock(serverNames: [String]) -> String {
        guard !serverNames.isEmpty else { return "" }
        return "사용 가능 MCP 서버: \(serverNames.joined(separator: ", ")). "
            + "외부 도구 사용 전 mcp_list_tools로 목록 확인 후 mcp_call로 실행."
    }

    /// 전체 추가 블록 조립 (스킬+MCP, 빈 문자열이면 주입 생략).
    nonisolated static func extrasBlock(serverNames: [String]) -> String {
        let (skills, truncated) = assembledPrompt()
        var sections: [String] = []
        if !skills.isEmpty {
            sections.append(skills + (truncated ? "\n(이하 생략: 8KB 초과)" : ""))
        }
        let mcp = mcpBlock(serverNames: serverNames)
        if !mcp.isEmpty { sections.append(mcp) }
        return sections.joined(separator: "\n\n")
    }
}
