import Foundation

/// 기존 흩어진 앱 데이터를 `~/.litert-lm-studio`로 1회 이사 (T-314, PLAN_v92).
/// - 소형 JSON·스킬: 복사(원본=백업), 대용량 캐시·스테이징: 이동(동일 볼륨 rename).
/// - `studioHomeMigrated` 플래그로 1회만. 실패 항목은 원본 유지(다음 실행 재시도 가능).
enum StudioMigrator {
    nonisolated static var flagKey: String { "studioHomeMigrated" }

    struct Summary {
        var copied = 0
        var moved = 0
        var failed = 0
        var skipped = false
        var isEmpty: Bool { copied == 0 && moved == 0 }
    }

    // MARK: - 구 경로 루트

    nonisolated static func legacyAppSupport(_ fm: FileManager = .default) -> URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LiteRTLMStudio", isDirectory: true)
    }

    nonisolated static func legacyCaches(_ fm: FileManager = .default) -> URL {
        fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LiteRTLMStudio", isDirectory: true)
    }

    nonisolated static func legacyDocuments(_ fm: FileManager = .default) -> URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/.LiteRT-LM", isDirectory: true)
    }

    // MARK: - 실행

    @discardableResult
    nonisolated static func runIfNeeded(defaults: UserDefaults = .standard,
                                        fileManager fm: FileManager = .default) -> Summary {
        if defaults.bool(forKey: flagKey) { return Summary(skipped: true) }
        let summary = run(home: StudioPaths.home(defaults),
                          legacyAppSupport: legacyAppSupport(fm),
                          legacyCaches: legacyCaches(fm),
                          legacyDocuments: legacyDocuments(fm),
                          fileManager: fm)
        // 실패 항목이 있으면 플래그를 남기지 않아 다음 실행에 재시도한다.
        if summary.failed == 0 { defaults.set(true, forKey: flagKey) }
        return summary
    }

    /// 실제 이사 (테스트: 임시 폴더 주입).
    @discardableResult
    nonisolated static func run(home: URL, legacyAppSupport: URL, legacyCaches: URL,
                                legacyDocuments: URL, fileManager fm: FileManager = .default) -> Summary {
        StudioPaths.ensureAll(home)
        var s = Summary()
        let hasLegacy = fm.fileExists(atPath: legacyAppSupport.path)
            || fm.fileExists(atPath: legacyCaches.path)
            || fm.fileExists(atPath: legacyDocuments.path)
        guard hasLegacy else { return s }

        // 1) 소형 JSON 복사 (원본 유지=백업).
        copyIfNeeded(legacyAppSupport.appendingPathComponent("chat-history.json"),
                     StudioPaths.chatsDir(home).appendingPathComponent("chat-history.json"), fm, &s)
        copyIfNeeded(legacyAppSupport.appendingPathComponent("mcp-servers.json"),
                     StudioPaths.mcpDir(home).appendingPathComponent("servers.json"), fm, &s)
        copyIfNeeded(legacyAppSupport.appendingPathComponent("BenchmarkHistory.json"),
                     StudioPaths.benchmarksDir(home).appendingPathComponent("history.json"), fm, &s)
        copyIfNeeded(legacyAppSupport.appendingPathComponent("release-notes.json"),
                     home.appendingPathComponent("release-notes.json"), fm, &s)

        // 2) 스킬 폴더 복사 (SKILL.md 가진 폴더만).
        let legacySkills = legacyAppSupport.appendingPathComponent("Skills", isDirectory: true)
        if let names = try? fm.contentsOfDirectory(atPath: legacySkills.path) {
            for name in names where name != ".DS_Store" {
                let src = legacySkills.appendingPathComponent(name).appendingPathComponent("SKILL.md")
                let dstDir = StudioPaths.skillsDir(home).appendingPathComponent(name, isDirectory: true)
                copyIfNeeded(src, dstDir.appendingPathComponent("SKILL.md"), fm, &s, parent: dstDir)
            }
        }

        // 3) 엔진 캐시 이동 (재생성 가능·대용량).
        for root in [legacyCaches.appendingPathComponent("EngineCache", isDirectory: true),
                     legacyAppSupport.appendingPathComponent("EngineCache", isDirectory: true)] {
            moveChildren(root, StudioPaths.engineCacheDir(home), fm, &s)
        }

        // 4) 스테이징·작업폴더 이동 (Documents/.LiteRT-LM).
        if let entries = try? fm.contentsOfDirectory(atPath: legacyDocuments.path) {
            for name in entries where name != ".DS_Store" {
                let src = legacyDocuments.appendingPathComponent(name)
                if name == "workspace" {
                    moveChildren(src, StudioPaths.workspaceDir(home), fm, &s)
                } else {
                    moveIfNeeded(src, StudioPaths.stagingDir(home).appendingPathComponent(name), fm, &s)
                }
            }
        }

        DebugLogger.shared.info(feature: "마이그레이션",
                                "이사 완료: 복사 \(s.copied)건·이동 \(s.moved)건 → \(home.path)")
        return s
    }

    // MARK: - 파일 연산 (실패는 원본 유지)

    private nonisolated static func copyIfNeeded(_ src: URL, _ dst: URL, _ fm: FileManager,
                                                 _ s: inout Summary, parent: URL? = nil) {
        guard fm.fileExists(atPath: src.path),
              !fm.fileExists(atPath: dst.path) else { return }
        try? fm.createDirectory(at: parent ?? dst.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        do {
            try fm.copyItem(at: src, to: dst)
            s.copied += 1
        } catch {
            s.failed += 1
            DebugLogger.shared.error(code: "E-MAC-STOR-0013", feature: "마이그레이션",
                                     "복사 실패 \(src.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private nonisolated static func moveIfNeeded(_ src: URL, _ dst: URL, _ fm: FileManager,
                                                 _ s: inout Summary) {
        guard fm.fileExists(atPath: src.path),
              !fm.fileExists(atPath: dst.path) else { return }
        try? fm.createDirectory(at: dst.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: src, to: dst)
            s.moved += 1
        } catch {
            // 볼륨이 다르거나 rename 실패 시 복사 폴백 (원본 유지).
            do {
                try fm.copyItem(at: src, to: dst)
                s.copied += 1
            } catch {
                s.failed += 1
                DebugLogger.shared.error(code: "E-MAC-STOR-0013", feature: "마이그레이션",
                                         "이동 실패 \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private nonisolated static func moveChildren(_ dir: URL, _ dstDir: URL, _ fm: FileManager,
                                                 _ s: inout Summary) {
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        for name in names where name != ".DS_Store" {
            moveIfNeeded(dir.appendingPathComponent(name), dstDir.appendingPathComponent(name), fm, &s)
        }
    }
}
