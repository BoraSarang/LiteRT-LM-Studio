import Foundation

/// 앱 소유 데이터의 단일 홈 (T-314, PLAN_v92).
/// 기본 `~/.litert-lm-studio`, UserDefaults "studioHome"으로 재지정(재실행 반영).
/// 외부 도구 소유(`~/.litert-lm` config·models)는 여기로 옮기지 않는다.
enum StudioPaths {
    nonisolated static var homeKey: String { "studioHome" }

    /// 기본 홈 (순수).
    nonisolated static var defaultHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".litert-lm-studio", isDirectory: true)
    }

    /// 홈 해석 (순수, 테스트 가능): 절대경로(또는 `~` 확장) 지정값 우선, 그 외 기본.
    nonisolated static func resolveHome(override: String?) -> URL {
        guard let raw = override?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return defaultHome }
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return defaultHome }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// 현재 홈 (UserDefaults 주입 가능).
    nonisolated static func home(_ defaults: UserDefaults = .standard) -> URL {
        resolveHome(override: defaults.string(forKey: homeKey))
    }

    // MARK: - 하위 경로 (순수)

    nonisolated static func chatsDir(_ home: URL) -> URL {
        home.appendingPathComponent("chats", isDirectory: true)
    }

    nonisolated static func mcpDir(_ home: URL) -> URL {
        home.appendingPathComponent("mcp", isDirectory: true)
    }

    nonisolated static func skillsDir(_ home: URL) -> URL {
        home.appendingPathComponent("skills", isDirectory: true)
    }

    nonisolated static func benchmarksDir(_ home: URL) -> URL {
        home.appendingPathComponent("benchmarks", isDirectory: true)
    }

    nonisolated static func engineCacheDir(_ home: URL) -> URL {
        home.appendingPathComponent("engine-cache", isDirectory: true)
    }

    nonisolated static func stagingDir(_ home: URL) -> URL {
        home.appendingPathComponent("staging", isDirectory: true)
    }

    nonisolated static func workspaceDir(_ home: URL) -> URL {
        home.appendingPathComponent("workspace", isDirectory: true)
    }

    // MARK: - 현재 홈 편의 (디렉터리 생성)

    @discardableResult
    nonisolated static func ensure(_ dir: URL) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static var chatHistoryURL: URL {
        ensure(chatsDir(home())).appendingPathComponent("chat-history.json")
    }

    nonisolated static var mcpServersURL: URL {
        ensure(mcpDir(home())).appendingPathComponent("servers.json")
    }

    nonisolated static var skillsURL: URL { ensure(skillsDir(home())) }

    nonisolated static var benchmarkHistoryURL: URL {
        ensure(benchmarksDir(home())).appendingPathComponent("history.json")
    }

    nonisolated static var releaseNotesURL: URL {
        ensure(home()).appendingPathComponent("release-notes.json")
    }

    nonisolated static var engineCachePath: String { ensure(engineCacheDir(home())).path }

    nonisolated static var stagingURL: URL { ensure(stagingDir(home())) }

    nonisolated static var workspaceURL: URL { ensure(workspaceDir(home())) }

    /// 하위 폴더 전체 준비 (앱 시작 시 1회).
    nonisolated static func ensureAll(_ home: URL = StudioPaths.home()) {
        _ = ensure(chatsDir(home))
        _ = ensure(mcpDir(home))
        _ = ensure(skillsDir(home))
        _ = ensure(benchmarksDir(home))
        _ = ensure(engineCacheDir(home))
        _ = ensure(stagingDir(home))
        _ = ensure(workspaceDir(home))
    }
}
