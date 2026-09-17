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
