import Foundation

/// 스킬 출처 (T-315, PLAN_v93) — 우선순위: opencode > claude > agents > 기타.
enum SkillSource: String, Codable, CaseIterable, Sendable {
    case opencode, claude, agents, other

    var label: String {
        switch self {
        case .opencode: return "opencode"
        case .claude:   return "claude"
        case .agents:   return "agents"
        case .other:    return "기타"
        }
    }

    /// 낮을수록 높은 우선순위 (중복 시 높은 우선순위 승).
    var priority: Int {
        switch self {
        case .opencode: return 0
        case .claude:   return 1
        case .agents:   return 2
        case .other:    return 3
        }
    }
}

/// 스킬 정보 (T-285, T-315): 폴더명+첫 줄 설명+켜짐+루트+출처.
struct SkillInfo: Identifiable, Hashable, Sendable {
    let name: String
    let blurb: String
    let enabled: Bool
    /// 스킬이 위치한 루트(앱 홈 또는 외부 추가 폴더). 프롬프트 조립·표시용.
    let root: String
    /// 앱 홈(`~/.litert-lm-studio/skills`) 스킬 여부 (false=외부 루트).
    let isBuiltin: Bool
    /// 외부 스킬일 때 출처 (nil=앱 홈).
    let source: SkillSource?
    var id: String { root + "/" + name }
}

/// 스캔 결과 한 항목 (루트·출처 미포함, T-315).
struct SkillEntry: Identifiable, Hashable, Sendable {
    let name: String
    let blurb: String
    var id: String { name }
}

/// SKILL.md 스킬 저장소 (T-285, T-315): 스캔+토글+프롬프트 조립+외부 임포트.
/// 기본 디렉터리: `~/.litert-lm-studio/skills/<이름>/SKILL.md`
enum SkillsStore {
    nonisolated static var keyPrefix: String { "skillEnabled." }
    nonisolated static var promptCap: Int { 8192 }
    /// 외부 스킬 루트 목록 키 (UserDefaults 배열, 절대경로).
    nonisolated static var rootsKey: String { "skillRoots" }

    nonisolated static func skillsDir() -> URL { StudioPaths.skillsURL }

    // MARK: - 외부 루트

    /// 사용자가 추가한 외부 루트 (존재하는 디렉터리만).
    nonisolated static func extraRoots(defaults: UserDefaults = .standard,
                                       fileManager fm: FileManager = .default) -> [URL] {
        (defaults.stringArray(forKey: rootsKey) ?? []).compactMap { path in
            let expanded = (path as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return url
        }
    }

    nonisolated static func addRoot(_ path: String, defaults: UserDefaults = .standard) {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return }
        var list = defaults.stringArray(forKey: rootsKey) ?? []
        guard !list.contains(expanded) else { return }
        list.append(expanded)
        defaults.set(list, forKey: rootsKey)
        DebugLogger.shared.info(feature: "스킬", "외부 루트 추가: \(expanded)")
    }

    nonisolated static func removeRoot(_ path: String, defaults: UserDefaults = .standard) {
        let expanded = (path as NSString).expandingTildeInPath
        var list = defaults.stringArray(forKey: rootsKey) ?? []
        list.removeAll { $0 == expanded }
        defaults.set(list, forKey: rootsKey)
        DebugLogger.shared.info(feature: "스킬", "외부 루트 제거: \(expanded)")
    }

    /// 스캔 대상 루트 (앱 홈 우선, 중복 제거).
    nonisolated static func roots(defaults: UserDefaults = .standard,
                                  fileManager fm: FileManager = .default) -> [URL] {
        let base = skillsDir()
        var out = [base]
        for r in extraRoots(defaults: defaults, fileManager: fm) where r.standardized.path != base.standardized.path {
            out.append(r)
        }
        return out
    }

    // MARK: - 스캔

    /// SKILL.md 있는 폴더 스캔 (모든 루트, 이름순).
    nonisolated static func scan(defaults: UserDefaults = .standard,
                                 fileManager fm: FileManager = .default)
        -> [(entry: SkillEntry, root: URL)] {
        var out: [(entry: SkillEntry, root: URL)] = []
        for dir in roots(defaults: defaults, fileManager: fm) {
            for item in scanRoot(dir, fm) {
                out.append((item, dir))
            }
        }
        return out.sorted { a, b in
            a.root.path != b.root.path ? a.root.path < b.root.path : a.entry.name < b.entry.name
        }
    }

    /// 단일 루트 스캔 (순수).
    nonisolated static func scanRoot(_ dir: URL, _ fm: FileManager = .default) -> [SkillEntry] {
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [SkillEntry] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let readme = entry.appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: readme, encoding: .utf8) else { continue }
            out.append(SkillEntry(name: entry.lastPathComponent, blurb: firstLine(text)))
        }
        return out
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

    /// 루트 경로 → 출처 매핑 (알려진 외부 루트 우선순위 순).
    nonisolated static func sourceForRoot(_ rootPath: String) -> SkillSource? {
        let normRoot = (rootPath as NSString).standardizingPath
        let known = knownExternalRootsWithSource()
        for (url, src) in known where url.standardized.path == normRoot {
            return src
        }
        // 사용자 추가 루트: 기타
        let extra = extraRoots()
        if extra.contains(where: { $0.standardized.path == normRoot }) {
            return .other
        }
        return nil
    }

    /// 목록 (스캔+플래그 결합).
    nonisolated static func list(defaults: UserDefaults = .standard,
                                 fileManager fm: FileManager = .default) -> [SkillInfo] {
        let builtin = skillsDir().standardized.path
        return scan(defaults: defaults, fileManager: fm).map { s in
            let isBuiltin = s.root.standardized.path == builtin
            let src = isBuiltin ? nil : sourceForRoot(s.root.path)
            return SkillInfo(name: s.entry.name, blurb: s.entry.blurb,
                             enabled: isEnabled(s.entry.name, defaults: defaults),
                             root: s.root.path,
                             isBuiltin: isBuiltin,
                             source: src)
        }
    }

    /// 프롬프트 조립 (켜진 스킬 본문 연결, cap 초과 절단).
    /// - Returns: 본문+잘림 여부.
    nonisolated static func assembledPrompt() -> (text: String, truncated: Bool) {
        var parts: [String] = []
        var used = 0
        var truncated = false
        for info in list() where info.enabled {
            let url = URL(fileURLWithPath: info.root)
                .appendingPathComponent(info.name).appendingPathComponent("SKILL.md")
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

    // MARK: - 외부 스킬 임포트 (T-315)

    struct ImportCandidate: Identifiable, Hashable, Sendable {
        let name: String
        let blurb: String
        let root: String
        let installed: Bool
        let source: SkillSource
        var id: String { root + "/" + name }
    }

    /// 알려진 외부 스킬 루트 + 출처 (우선순위 순: opencode > claude > agents).
    nonisolated static func knownExternalRootsWithSource(_ fm: FileManager = .default)
        -> [(url: URL, source: SkillSource)] {
        let home = fm.homeDirectoryForCurrentUser
        return [
            (home.appendingPathComponent(".opencode/skills", isDirectory: true), SkillSource.opencode),
            (home.appendingPathComponent(".claude/skills", isDirectory: true), SkillSource.claude),
            (home.appendingPathComponent(".agents/skills", isDirectory: true), SkillSource.agents)
        ]
    }

    /// 임포트 후보 (기본 홈에 같은 이름 SKILL.md가 있으면 installed=true).
    /// 동일 이름 중복 시 높은 우선순위 출처만 남김.
    nonisolated static func importCandidates(fileManager fm: FileManager = .default,
                                             home: URL = StudioPaths.home()) -> [ImportCandidate] {
        let target = home.appendingPathComponent("skills", isDirectory: true)
        let installedNames = Set(scanRoot(target, fm).map { $0.name })
        var bestByName: [String: ImportCandidate] = [:]
        for (rootURL, src) in knownExternalRootsWithSource(fm) {
            for item in scanRoot(rootURL, fm) {
                let candidate = ImportCandidate(name: item.name, blurb: item.blurb,
                                                root: rootURL.path,
                                                installed: installedNames.contains(item.name),
                                                source: src)
                let key = candidate.name
                if let existing = bestByName[key] {
                    if src.priority < existing.source.priority {
                        bestByName[key] = candidate
                    }
                } else {
                    bestByName[key] = candidate
                }
            }
        }
        return bestByName.values.sorted { $0.name < $1.name }
    }

    /// 후보 폴더를 앱 홈 skills로 복사 (같은 이름 있으면 건너뜀).
    @discardableResult
    nonisolated static func importSkill(_ candidate: ImportCandidate,
                                        home: URL = StudioPaths.home(),
                                        fileManager fm: FileManager = .default) -> Bool {
        let src = URL(fileURLWithPath: candidate.root)
            .appendingPathComponent(candidate.name, isDirectory: true)
        let dstDir = home.appendingPathComponent("skills", isDirectory: true)
        try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        let dst = dstDir.appendingPathComponent(candidate.name, isDirectory: true)
        guard !fm.fileExists(atPath: dst.path) else {
            DebugLogger.shared.info(feature: "스킬", "임포트 건너뜀(이미 있음): \(candidate.name)")
            return false
        }
        do {
            try fm.copyItem(at: src, to: dst)
            DebugLogger.shared.info(feature: "스킬",
                                    "임포트 완료: \(candidate.name) ← \(candidate.root)")
            return true
        } catch {
            DebugLogger.shared.error(code: "E-MAC-STOR-0014", feature: "스킬",
                                     "임포트 실패 \(candidate.name): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 프롬프트 블록

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
