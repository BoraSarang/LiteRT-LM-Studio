import Foundation

/// 카탈로그 패밀리 필터 (T-234).
enum CatalogFamily: String, CaseIterable, Sendable {
    case all
    case gemma
    case qwen
    case other

    var title: String {
        switch self {
        case .all: return L(L10n.ModelCatalog.familyAll)
        case .gemma: return "Gemma"
        case .qwen: return "Qwen"
        case .other: return L(L10n.ModelCatalog.familyOther)
        }
    }
}

/// 카탈로그 정렬 (T-234, HF API sort 매핑).
enum CatalogSort: String, CaseIterable, Sendable {
    case downloads
    case likes
    case updated

    var title: String {
        switch self {
        case .downloads: return L(L10n.ModelCatalog.sortDownloads)
        case .likes: return L(L10n.ModelCatalog.sortLikes)
        case .updated: return L(L10n.ModelCatalog.sortUpdated)
        }
    }

    /// HF API sort 파라미터 (`updated`는 lastModified).
    var apiValue: String {
        switch self {
        case .downloads: return "downloads"
        case .likes: return "likes"
        case .updated: return "lastModified"
        }
    }
}

/// 카탈로그 뱃지 (T-234): pipeline_tag 매핑. Tool/Reasoning은 설치 후 확정.
enum CatalogBadge: String, Sendable {
    case text
    case vision
    case audio
    case tts

    var title: String {
        switch self {
        case .text: return "Text"
        case .vision: return "Vision"
        case .audio: return "Audio"
        case .tts: return "TTS"
        }
    }
}

/// 추천 모델 1건 (T-234, 수동 큐레이션).
struct RecommendedModel: Sendable, Hashable {
    let repo: String
    let label: String
    let suggestedID: String
    let blurb: String
}

/// HF 카탈로그 1건 (T-234).
struct CatalogEntry: Identifiable, Hashable, Sendable {
    var id: String { repo }
    let repo: String
    var likes: Int = 0
    var downloads: Int = 0
    var createdAt: String?
    var lastModified: String?
    var pipelineTag: String?
    var siblings: [String] = []
    var gated: Bool = false

    /// 목록행 표시명 (`org` 제외, `litert-lm` 접미사 제거).
    var shortName: String {
        let base = repo.split(separator: "/").last.map(String.init) ?? repo
        if let range = base.range(of: "-litert-lm", options: .caseInsensitive) {
            return String(base[..<range.lowerBound])
        }
        return base
    }

    var org: String { repo.split(separator: "/").first.map(String.init) ?? "" }
}

/// 카탈로그 둘러보기 모드 (T-234): 기본 recommended, 확장 시 전체.
enum CatalogMode: Sendable {
    case recommended
    case all
}

/// HF 카탈로그 파싱+조회 (T-234, PLAN_v49). 네트워크는 `CatalogStore` 담당.
enum ModelCatalog {
    static let pageSize = 20

    /// 추천 모델 8종 (수동 큐레이션, 순서 고정).
    nonisolated static func recommendedModels() -> [RecommendedModel] {
        [
            RecommendedModel(repo: "litert-community/gemma-4-E2B-it-litert-lm", label: "Gemma 4 E2B",
                      suggestedID: "gemma4-e2b", blurb: "노트북용 경량, 추론·도구·이미지 지원"),
            RecommendedModel(repo: "litert-community/gemma-4-12B-it-litert-lm", label: "Gemma 4 12B",
                      suggestedID: "gemma4-12b", blurb: "균형형 12B, QAT 양자화"),
            RecommendedModel(repo: "google/gemma-3n-E2B-it-litert-lm", label: "Gemma 3n E2B",
                      suggestedID: "gemma3n-e2b", blurb: "모바일 우선 E2B"),
            RecommendedModel(repo: "google/gemma-3n-E4B-it-litert-lm", label: "Gemma 3n E4B",
                      suggestedID: "gemma3n-e2b", blurb: "모바일 우선 E4B"),
            RecommendedModel(repo: "litert-community/Qwen3-4B", label: "Qwen3 4B",
                      suggestedID: "qwen3-4b", blurb: "가성비 4B 텍스트"),
            RecommendedModel(repo: "litert-community/Qwen2.5-1.5B-Instruct", label: "Qwen2.5 1.5B",
                      suggestedID: "qwen2.5-1.5b", blurb: "초경량 1.5B 입문용"),
            RecommendedModel(repo: "litert-community/Qwen2-VL-2B", label: "Qwen2-VL 2B",
                      suggestedID: "qwen2-vl-2b", blurb: "이미지+텍스트 2B"),
            RecommendedModel(repo: "litert-community/Qwen3-ASR-0.6B", label: "Qwen3-ASR 0.6B",
                      suggestedID: "qwen3-asr-0.6b", blurb: "음성 인식 0.6B")
        ]
    }

    /// 목록 API URL (검색·정렬·페이징).
    nonisolated static func searchURL(query: String, sort: CatalogSort,
                                      cursor: String? = nil) -> URL? {
        var comps = URLComponents(string: "https://huggingface.co/api/models")
        var items = [
            URLQueryItem(name: "filter", value: "litert-lm"),
            URLQueryItem(name: "sort", value: sort.apiValue),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "\(pageSize)")
        ]
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "search", value: trimmed)) }
        if let cursor, !cursor.isEmpty { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        comps?.queryItems = items
        return comps?.url
    }

    /// 게이트 판정 (순수, T-335): HF `gated`는 false 또는 "auto"/"manual".
    nonisolated static func isGated(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let s = value as? String {
            let lower = s.lowercased()
            return lower == "auto" || lower == "manual" || lower == "true"
        }
        return false
    }

    /// 목록 응답 파싱 (순수).
    nonisolated static func parseList(_ data: Data) -> [CatalogEntry] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { obj -> CatalogEntry? in
            guard let repo = (obj["modelId"] as? String) ?? (obj["id"] as? String) else { return nil }
            return CatalogEntry(
                repo: (obj["modelId"] as? String) ?? repo,
                likes: obj["likes"] as? Int ?? 0,
                downloads: obj["downloads"] as? Int ?? 0,
                createdAt: obj["createdAt"] as? String,
                lastModified: obj["lastModified"] as? String,
                pipelineTag: obj["pipeline_tag"] as? String,
                siblings: ModelDownload.litertlmSiblings(from: data),
                gated: isGated(obj["gated"])
            )
        }
    }

    /// 다음 페이지 커서 추출 (Link 헤더, 순수).
    nonisolated static func nextCursor(linkHeader: String?) -> String? {
        guard let header = linkHeader else { return nil }
        // `<https://...&cursor=abc>; rel="next"` 형태.
        for part in header.split(separator: ",") {
            let seg = part.trimmingCharacters(in: .whitespaces)
            guard seg.hasSuffix("rel=\"next\"") else { continue }
            guard let start = seg.firstIndex(of: "<"), let end = seg.firstIndex(of: ">") else { continue }
            let url = String(seg[seg.index(after: start) ..< end])
            guard let comps = URLComponents(string: url) else { continue }
            if let cursor = comps.queryItems?.first(where: { $0.name == "cursor" })?.value,
               !cursor.isEmpty { return cursor }
        }
        return nil
    }

    /// 상세 응답 파싱 (순수, `.litertlm` 형제 포함).
    nonisolated static func parseDetail(repo: String, data: Data) -> CatalogEntry? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return CatalogEntry(
            repo: (obj["modelId"] as? String) ?? repo,
            likes: obj["likes"] as? Int ?? 0,
            downloads: obj["downloads"] as? Int ?? 0,
            createdAt: obj["createdAt"] as? String,
            lastModified: obj["lastModified"] as? String,
            pipelineTag: obj["pipeline_tag"] as? String,
            siblings: ModelDownload.litertlmSiblings(from: data),
            gated: isGated(obj["gated"])
        )
    }

    /// 패밀리 판정 (순수).
    nonisolated static func family(of repo: String) -> CatalogFamily {
        let lower = repo.lowercased()
        if lower.contains("gemma") { return .gemma }
        if lower.contains("qwen") { return .qwen }
        return .other
    }

    /// 뱃지 매핑 (순수, pipeline_tag 기준).
    nonisolated static func badges(pipelineTag: String?) -> [CatalogBadge] {
        guard let tag = pipelineTag?.lowercased() else { return [.text] }
        if tag.contains("image-text") { return [.vision] }
        if tag.contains("text-to-speech") { return [.tts] }
        if tag.contains("speech") || tag.contains("audio") { return [.audio] }
        return [.text]
    }

    /// ID에서 파라미터 규모 추출 (참고용, 순수. `27B`·`0.6B`·`300m`).
    nonisolated static func paramsHint(repo: String) -> String? {
        let pattern = #"(\d+(?:\.\d+)?)\s*([bBmM])\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: repo, range: NSRange(repo.startIndex..., in: repo)),
              let num = Range(match.range(at: 1), in: repo),
              let unit = Range(match.range(at: 2), in: repo) else { return nil }
        return "\(String(repo[num]))\(String(repo[unit]).uppercased())"
    }

    /// ISO8601 → n일 전 (순수).
    nonisolated static func daysAgo(iso: String?, now: Date = Date()) -> Int? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        return max(0, Int(now.timeIntervalSince(date) / 86400))
    }

    /// 다운로드수 축약 (`1140146` → `1.1M`).
    nonisolated static func prettyCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// 파일명 → 검색어 정제 (순수, T-251): 확장자·양자화 토큰 제거 후 앞 3토큰.
    nonisolated static func searchStem(fileName: String) -> String {
        var base = fileName
        if let dot = base.lastIndex(of: ".") { base = String(base[..<dot]) }
        let noise: Set<String> = ["mixed", "int4", "int8", "q4", "q8", "fp16", "fp32",
                                  "it", "instruct", "5s", "i8", "web", "litertlm", "task"]
        let tokens = base.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map(String.init)
            .filter { !noise.contains($0.lowercased()) && !$0.isEmpty }
        return tokens.prefix(3).joined(separator: " ")
    }
}

/// 카탈로그 상태 보관 (T-234, 창 수명).
@MainActor
final class CatalogStore: ObservableObject {
    @Published var mode: CatalogMode = .recommended
    @Published var query = ""
    @Published var family: CatalogFamily = .all
    @Published var sort: CatalogSort = .downloads
    @Published var entries: [CatalogEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = false
    @Published var selectedRepo: String?
    @Published var detail: CatalogEntry?
    @Published var readme: String?
    @Published var fileSizes: [String: Int64] = [:]
    @Published var token = ""

    private var cursor: String?
    private var lastQueryKey = ""
    private let logger = DebugLogger.shared

    var recommended: [RecommendedModel] { ModelCatalog.recommendedModels() }

    /// 패밀리 필터 적용 목록 (순수 판정 경유).
    var filtered: [CatalogEntry] {
        guard family != .all else { return entries }
        return entries.filter { ModelCatalog.family(of: $0.repo) == family }
    }

    /// 검색 실행 (전체 모드 전환 + 캐시 적중 시 생략).
    func search() async {
        mode = .all
        let key = "\(query)|\(sort.apiValue)"
        if key == lastQueryKey, !entries.isEmpty {
            logger.info(feature: "카탈로그", "[CACHE] 검색 캐시 적중")
            return
        }
        lastQueryKey = key
        cursor = nil
        entries = []
        await loadPage()
    }

    /// 다음 페이지.
    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await loadPage()
    }

    private func loadPage() async {
        guard let url = ModelCatalog.searchURL(query: query, sort: sort, cursor: cursor) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var req = URLRequest(url: url)
        if let auth = ModelDownload.authHeader(token: token) {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let link = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Link")
            cursor = ModelCatalog.nextCursor(linkHeader: link)
            hasMore = cursor != nil
            entries += ModelCatalog.parseList(data)
            logger.info(feature: "카탈로그", "목록 \(entries.count)건 (질의: \(query))")
        } catch {
            errorMessage = "목록 조회 실패: \(error.localizedDescription)"
            logger.error(code: "E-MAC-NET-0013", feature: "카탈로그",
                         "목록 조회 실패: \(error.localizedDescription)")
        }
    }

    /// 상세 선택 (상세+README 병렬 조회).
    func select(repo: String) async {
        selectedRepo = repo
        detail = nil
        readme = nil
        fileSizes = [:]
        guard let url = URL(string: "https://huggingface.co/api/models/\(repo)") else { return }
        var req = URLRequest(url: url)
        if let auth = ModelDownload.authHeader(token: token) {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        do {
            async let detailData = URLSession.shared.data(for: req)
            async let readmeText = fetchReadme(repo: repo)
            let ((data, _), text) = try await (detailData, readmeText)
            detail = ModelCatalog.parseDetail(repo: repo, data: data)
            readme = text
        } catch {
            errorMessage = "상세 조회 실패: \(error.localizedDescription)"
            logger.error(code: "E-MAC-NET-0013", feature: "카탈로그",
                         "상세 조회 실패: \(error.localizedDescription)")
        }
    }

    private func fetchReadme(repo: String) async throws -> String? {
        guard let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/README.md") else {
            return nil
        }
        var req = URLRequest(url: url)
        if let auth = ModelDownload.authHeader(token: token) {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        guard data.count < 512 * 1024 else { return nil } // 과대 방지
        return String(data: data, encoding: .utf8)
    }

    /// 선택 파일 크기 lazy 조회 (HEAD).
    func loadSize(repo: String, file: String) async {
        let key = "\(repo)/\(file)"
        guard fileSizes[key] == nil,
              let url = ModelDownload.fileURL(repo: repo, file: file) else { return }
        if let size = await ModelDownload.remoteFileSize(url: url, token: token.isEmpty ? nil : token) {
            fileSizes[key] = size
        }
    }
}
