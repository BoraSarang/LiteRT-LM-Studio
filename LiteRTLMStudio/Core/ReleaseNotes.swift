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

    /// 버전 문자열에서 숫자 구간 추출 (순수).
    nonisolated static func numericParts(_ tag: String) -> [Int] {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s = String(s.dropFirst()) }
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        return s.split(separator: ".").compactMap { Int($0) }
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LiteRTLMStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("release-notes.json")
    }

    /// 최신 정식 릴리즈 (화면 표시용, T-294 엔진만).
    var latestStable: AppRelease? {
        releases.filter { !$0.prerelease && $0.source == .engine }
            .sorted { ReleaseNotesParser.compare($0.tag, $1.tag) == .orderedDescending }
            .first
    }

    /// 화면 표시분 (정식 우선, 최대 3건).
    var featured: [AppRelease] {
        let stable = releases.filter { !$0.prerelease }
        let rest = releases.filter { $0.prerelease }
        return Array((stable + rest).prefix(3))
    }

    /// 필요 시 조회 (6시간 이내 성공분 있으면 캐시 유지).
    func refreshIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: Self.fetchedAtKey)
        if last > 0, Date().timeIntervalSince1970 - last < Self.freshness, !releases.isEmpty {
            return
        }
        await refresh()
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

    /// 새 분합 + 출처+태그 중복 제거 + 20건 cap + 원자 저장.
    func merge(_ fresh: [AppRelease]) {
        var seen = Set<String>()
        var merged: [AppRelease] = []
        for rel in fresh + releases where seen.insert(rel.id).inserted {
            merged.append(rel)
        }
        releases = Array(merged.prefix(Self.maxKept))
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
