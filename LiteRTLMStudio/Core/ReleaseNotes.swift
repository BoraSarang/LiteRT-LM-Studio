import Foundation

/// 새소식 출처 (T-294): 엔진 릴리즈 vs 앱 릴리즈 (버전 체계 분리).
enum ReleaseSource: String, Codable {
    case engine
    case app
}

/// GitHub Release 1건 (T-262): 버전·이름·What's New 원문·링크·게시일.
struct AppRelease: Identifiable, Codable {
    var id: String { "\(source.rawValue):\(tag)" }
    let tag: String
    let name: String
    let body: String
    let url: String
    let publishedAt: Date?
    let prerelease: Bool
    let source: ReleaseSource // T-294 (구 캐시는 디코딩 기본값 .engine)

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case name
        case body
        case url = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case source
    }

    init(tag: String, name: String, body: String, url: String,
         publishedAt: Date? = nil, prerelease: Bool = false,
         source: ReleaseSource = .engine) {
        self.tag = tag
        self.name = name
        self.body = body
        self.url = url
        self.publishedAt = publishedAt
        self.prerelease = prerelease
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? tag
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        prerelease = try c.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        source = try c.decodeIfPresent(ReleaseSource.self, forKey: .source) ?? .engine
        if let raw = try c.decodeIfPresent(String.self, forKey: .publishedAt) {
            publishedAt = Self.isoDate(raw)
        } else {
            publishedAt = nil
        }
    }

    /// ISO8601 파싱 (GitHub `published_at` 형식, 순수).
    nonisolated static func isoDate(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }
}

/// 새소식 파서·비교 순수함수 묶음 (T-262, 테스트 가능).
enum ReleaseNotesParser {
    /// Releases API 응답 파싱 (순수): 빈 배열·손상 JSON은 빈 배열.
    nonisolated static func parse(_ data: Data) -> [AppRelease] {
        guard let list = try? JSONDecoder().decode([AppRelease].self, from: data) else { return [] }
        return list.filter { !$0.tag.isEmpty }
    }

    /// What's New 요약 (순수): 빈 줄·마크다운 기호 제거 후 최대 N줄.
    nonisolated static func summaryLines(_ body: String, max: Int = 3) -> [String] {
        let lines = body.components(separatedBy: .newlines)
            .map { line in
                var s = line.trimmingCharacters(in: .whitespaces)
                while s.hasPrefix("#") { s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces) }
                for mark in ["- ", "* ", "> "] where s.hasPrefix(mark) {
                    s = String(s.dropFirst(mark.count))
                }
                return s
            }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(max))
    }

    /// 태그 표시용 (순수): 선행 `v` 제거.
    nonisolated static func displayVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// 숫자 구간 버전 비교 (순수): 선행 v·접미사(-rc.1 등) 무시.
    nonisolated static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lparts = numericParts(lhs)
        let rparts = numericParts(rhs)
        for (left, right) in zip(lparts, rparts) where left != right {
            return left < right ? .orderedAscending : .orderedDescending
        }
        if lparts.count == rparts.count { return .orderedSame }
        return lparts.count < rparts.count ? .orderedAscending : .orderedDescending
    }

    /// 설치 버전보다 새 정식 릴리즈가 있는지 (순수, T-262).
    /// T-294: 엔진 출처만 판정 (앱 버전 체계 분리).
    nonisolated static func newerStable(_ releases: [AppRelease], installed: String?) -> AppRelease? {
        guard let installed, !installed.isEmpty else { return nil }
        return releases
            .filter { $0.source == .engine }
            .filter { !$0.prerelease }
            .filter { compare($0.tag, installed) == .orderedDescending }
            .sorted { compare($0.tag, $1.tag) == .orderedDescending }
            .first
    }

    /// 설치된 앱 버전보다 새 앱 정식 릴리즈가 있는지 (순수, 앱 자체 업데이트용).
    /// 엔진 판정(newerStable)과 대칭: 앱 출처만 판정.
    nonisolated static func newerApp(_ releases: [AppRelease], installed: String?) -> AppRelease? {
        guard let installed, !installed.isEmpty else { return nil }
        return releases
            .filter { $0.source == .app }
            .filter { !$0.prerelease }
            .filter { compare($0.tag, installed) == .orderedDescending }
            .sorted { compare($0.tag, $1.tag) == .orderedDescending }
            .first
    }

    /// 버전 문자열에서 숫자 구간 추출 (순수).
    nonisolated static func numericParts(_ tag: String) -> [Int] {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s = String(s.dropFirst()) }
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        return s.split(separator: ".").compactMap { Int($0) }
    }
}

/// 앱 자체 업데이트 확인 주기 (설정 영속, 기본 weekly).
enum UpdateCheckFrequency: String, CaseIterable, Identifiable, Sendable {
    case atLaunch
    case daily
    case weekly
    case never

    var id: String { rawValue }

    var titleKey: L10nKey {
        switch self {
        case .atLaunch: L10n.Update.frequencyAtLaunch
        case .daily: L10n.Update.frequencyDaily
        case .weekly: L10n.Update.frequencyWeekly
        case .never: L10n.Update.frequencyNever
        }
    }

    var title: String { L(titleKey) }

    /// 확인 주기가 됐는지 (순수, 테스트 가능).
    /// atLaunch는 이번 실행에서 아직 확인 안 했으면 true.
    nonisolated static func shouldCheck(
        frequency: Self,
        lastChecked: Date?,
        now: Date,
        launchDate: Date
    ) -> Bool {
        switch frequency {
        case .never:
            return false
        case .atLaunch:
            guard let last = lastChecked else { return true }
            return last < launchDate
        case .daily:
            guard let last = lastChecked else { return true }
            return now.timeIntervalSince(last) >= 86_400
        case .weekly:
            guard let last = lastChecked else { return true }
            return now.timeIntervalSince(last) >= 604_800
        }
    }
}

/// 새소식 스토어 (T-262): GitHub Releases 조회+JSON 누적 캐시+6시간 가드.
@MainActor
final class ReleaseNotes: ObservableObject {
    nonisolated static var engineAPIURL: URL? {
        URL(string: "https://api.github.com/repos/google-ai-edge/LiteRT-LM/releases?per_page=20")
    }

    /// 앱 저장소 릴리즈 (T-294): 현재 비어 있음 → 빈 결과는 조용히 스킵.
    nonisolated static var appAPIURL: URL? {
        URL(string: "https://api.github.com/repos/BoraSarang/LiteRT-LM-Studio/releases?per_page=20")
    }

    nonisolated static var fetchedAtKey: String { "releaseNotesFetchedAt" }
    nonisolated static var freshness: TimeInterval { 6 * 3600 } // 6시간
    nonisolated static var maxKept: Int { 20 }
    /// 출처별 보관 상한 (엔진 20건이 앱을 밀어내지 않도록 분리).
    nonisolated static var maxKeptEngine: Int { 20 }
    nonisolated static var maxKeptApp: Int { 10 }
    /// 앱 업데이트 확인 시각 키·주기 키 (UserDefaults 영속).
    nonisolated static var appUpdateCheckedAtKey: String { "appUpdateCheckedAt" }
    nonisolated static var appUpdateFrequencyKey: String { "appUpdateFrequency" }

    @Published var releases: [AppRelease] = []
    @Published var isLoading = false
    @Published var showingCache = false // 오프라인·실패 시 저장분 표시
    @Published var lastError: String?

    let storageURL: URL
    private let logger = DebugLogger.shared

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            self.storageURL = Self.resolvedURL()
        }
        loadCache()
    }

    nonisolated static func resolvedURL() -> URL {
        let dst = StudioPaths.releaseNotesURL
        // 마이그레이터 미실행·실패 대비 폴백: 구 경로가 남아 있으면 1회 복사.
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first!
            .appendingPathComponent("LiteRTLMStudio/release-notes.json")
        if !FileManager.default.fileExists(atPath: dst.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: dst)
        }
        return dst
    }

    /// 최신 정식 릴리즈 (화면 표시용, T-294 엔진만).
    var latestStable: AppRelease? {
        releases.filter { !$0.prerelease && $0.source == .engine }
            .sorted { ReleaseNotesParser.compare($0.tag, $1.tag) == .orderedDescending }
            .first
    }

    /// 화면 표시분 (게시일 내림차순, 엔진·앱 혼합 최대 3건, 날짜 없음은 뒤로).
    var featured: [AppRelease] {
        let all = releases.sorted {
            switch ($0.publishedAt, $1.publishedAt) {
            case let (a?, b?): a > b
            case (_?, nil): true
            case (nil, _?): false
            default: $0.tag > $1.tag
            }
        }
        return Array(all.prefix(3))
    }

    /// 설치된 앱 버전보다 새 앱 정식 릴리즈 (없으면 nil=최신).
    func appUpdate(installed: String?) -> AppRelease? {
        ReleaseNotesParser.newerApp(releases, installed: installed)
    }

    /// 필요 시 조회 (6시간 이내 성공분 있으면 캐시 유지).
    func refreshIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: Self.fetchedAtKey)
        if last > 0, Date().timeIntervalSince1970 - last < Self.freshness, !releases.isEmpty {
            return
        }
        await refresh()
    }

    /// 주기에 따라 필요하면 앱 업데이트를 확인한다 (앱 시작 시 호출).
    /// 확인했으면 시각을 기록한다 (성공 여부 무관 — 실패 시 다음 주기에 재시도).
    func autoCheckAppUpdate(now: Date = Date(), launchDate: Date = Date()) async {
        let raw = UserDefaults.standard.string(forKey: Self.appUpdateFrequencyKey)
        let frequency = UpdateCheckFrequency(rawValue: raw ?? "") ?? .weekly
        guard frequency != .never else { return }
        let last: Date? = {
            let t = UserDefaults.standard.double(forKey: Self.appUpdateCheckedAtKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }()
        guard UpdateCheckFrequency.shouldCheck(frequency: frequency, lastChecked: last,
                                              now: now, launchDate: launchDate) else { return }
        await refresh()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.appUpdateCheckedAtKey)
    }

    /// Releases 조회+누적 저장 (T-294 엔진+앱 2원). 한쪽 실패·빈 결과는 조용히
    /// 스킵하고, 양쪽 다 실패했을 때만 E-MAC-NET-0014. 실패해도 캐시는 유지.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        var fresh: [AppRelease] = []
        var failures = 0
        if let engine = await Self.fetch(url: Self.engineAPIURL, source: .engine) {
            fresh += engine
        } else {
            failures += 1
        }
        if let app = await Self.fetch(url: Self.appAPIURL, source: .app) {
            fresh += app
        } else {
            failures += 1
            logger.info(feature: "새소식", "앱 저장소 조회 스킵 (릴리즈 없음 가능)")
        }
        guard !fresh.isEmpty else {
            if failures > 0 {
                lastError = "E-MAC-NET-0014"
                showingCache = !releases.isEmpty
                logger.error(code: "E-MAC-NET-0014", feature: "새소식", "조회 실패, 저장분 표시")
            }
            return
        }
        merge(fresh)
        showingCache = false
        lastError = nil
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.fetchedAtKey)
        logger.info(feature: "새소식", "릴리즈 \(fresh.count)건 조회·누적 \(releases.count)건")
    }

    /// 단일 저장소 조회 (T-294): 실패·비200·빈 결과는 nil (조용히 스킵).
    nonisolated static func fetch(url: URL?, source: ReleaseSource) async -> [AppRelease]? {
        guard let url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let tagged = ReleaseNotesParser.parse(data).map { rel in
            AppRelease(tag: rel.tag, name: rel.name, body: rel.body, url: rel.url,
                       publishedAt: rel.publishedAt, prerelease: rel.prerelease, source: source)
        }
        return tagged.isEmpty ? nil : tagged
    }

    /// 새 분합 + 출처별 cap (엔진 20·앱 10) + 출처+태그 중복 제거 + 원자 저장.
    /// 엔진이 앞에 와도 앱이 잘리지 않는다 (합산 cap 시절 버그 수정).
    func merge(_ fresh: [AppRelease]) {
        var seen = Set<String>()
        var engine: [AppRelease] = []
        var app: [AppRelease] = []
        for rel in fresh + releases where seen.insert(rel.id).inserted {
            if rel.source == .app {
                app.append(rel)
            } else {
                engine.append(rel)
            }
        }
        releases = Array(engine.prefix(Self.maxKeptEngine)) + Array(app.prefix(Self.maxKeptApp))
        save()
    }

    func loadCache() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([AppRelease].self, from: data)
        else { return }
        releases = decoded
        showingCache = true
    }

    func save() {
        guard let data = try? JSONEncoder().encode(releases) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
