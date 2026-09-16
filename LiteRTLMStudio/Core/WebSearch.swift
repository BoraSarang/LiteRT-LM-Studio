import Foundation

/// 웹 검색 결과 1건 (T-269): 제공자 무관 공통형.
struct WebHit: Sendable, Hashable {
    let title: String
    let url: String
    let excerpt: String
}

/// wigolo search 결과 1건 (T-269, 파일 스코프).
struct WigoloSearchResult: Decodable {
    var title: String?
    var url: String?
    var excerpt: String?
    var citationID: String?

    enum CodingKeys: String, CodingKey {
        case title, url, excerpt
        case citationID = "citation_id"
    }
}

/// wigolo search 응답 (T-269): 문서 계약 기준, 전 필드 optional 디코딩.
struct WigoloSearchResponse: Decodable {
    var results: [WigoloSearchResult]?
}

/// DDG 관련 주제 1건 (T-269, 파일 스코프).
struct DDGTopic: Decodable {
    var text: String? // "Text"
    var firstURL: String? // "FirstURL"

    enum CodingKeys: String, CodingKey {
        case text = "Text"
        case firstURL = "FirstURL"
    }
}

/// DuckDuckGo Instant Answer 응답 (T-269, 공식·키없음).
struct DDGResponse: Decodable {
    var abstractText: String? // "AbstractText"
    var abstractURL: String? // "AbstractURL"
    var relatedTopics: [DDGTopic]? // "RelatedTopics"

    enum CodingKeys: String, CodingKey {
        case abstractText = "AbstractText"
        case abstractURL = "AbstractURL"
        case relatedTopics = "RelatedTopics"
    }
}

/// 웹 검색 체인 (T-269): wigolo → DuckDuckGo → Wikipedia, 첫 성공 반환.
/// 키 불필요 경로만 사용. 전 파서 순수·테스트 가능.
enum WebSearch {
    nonisolated static var excerptCap: Int { 300 }
    nonisolated static var fetchCap: Int { 8192 }
    nonisolated static var toggleKey: String { "webSearchEnabled" }

    /// 설정 토글 (기본 켜짐).
    nonisolated static func enabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: toggleKey) == nil || defaults.bool(forKey: toggleKey)
    }

    /// wigolo 응답 파싱 (순수).
    nonisolated static func parseWigolo(_ data: Data) -> [WebHit] {
        guard let res = try? JSONDecoder().decode(WigoloSearchResponse.self, from: data),
              let items = res.results else { return [] }
        return items.compactMap { item in
            guard let url = item.url, !url.isEmpty else { return nil }
            return WebHit(title: item.title?.isEmpty == false ? item.title! : url,
                          url: url, excerpt: item.excerpt ?? "")
        }
    }

    /// DDG IA 파싱 (순수): 초록+관련 주제.
    nonisolated static func parseDDG(_ data: Data) -> [WebHit] {
        guard let res = try? JSONDecoder().decode(DDGResponse.self, from: data) else { return [] }
        var out: [WebHit] = []
        if let text = res.abstractText, !text.isEmpty, let url = res.abstractURL {
            out.append(WebHit(title: String(text.prefix(80)), url: url, excerpt: text))
        }
        for topic in res.relatedTopics ?? [] {
            guard let text = topic.text, !text.isEmpty,
                  let url = topic.firstURL, !url.isEmpty else { continue }
            out.append(WebHit(title: String(text.prefix(80)), url: url, excerpt: text))
        }
        return out
    }

    /// Wikipedia opensearch 파싱 (순수): [질의, [제목], [설명], [URL]].
    nonisolated static func parseWiki(_ data: Data) -> [WebHit] {
        guard let arr = try? JSONDecoder().decode([WikiPart].self, from: data),
              arr.count == 4,
              case .strings(let titles) = arr[1],
              case .strings(let descs) = arr[2],
              case .strings(let urls) = arr[3] else { return [] }
        return zip(zip(titles, descs), urls).map { pair, url in
            WebHit(title: pair.0, url: url, excerpt: pair.1)
        }
    }

    /// 모델 전달용 포맷 (순수): 번호+제목+URL+발췌 cap.
    nonisolated static func formatForModel(_ hits: [WebHit]) -> String {
        hits.enumerated().map { idx, hit in
            let excerpt = String(hit.excerpt.prefix(excerptCap))
            return "[\(idx + 1)] \(hit.title)\n\(hit.url)\n\(excerpt)"
        }.joined(separator: "\n\n")
    }

    /// HTML 태그 제거 (순수, fetch 폴백용).
    nonisolated static func stripHTML(_ html: String) -> String {
        var out = html.replacingOccurrences(of: "<script[\\s\\S]*?</script>",
                                            with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "<style[\\s\\S]*?</style>",
                                       with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = out.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        return String(collapsed.prefix(fetchCap))
    }

    /// 검색 체인 실행: wigolo → DDG → Wikipedia.
    static func search(query: String, maxResults: Int = 5) async throws -> [WebHit] {
        let logger = DebugLogger.shared
        if let hits = try? await searchViaWigolo(query: query, maxResults: maxResults),
           !hits.isEmpty {
            logger.info(feature: "웹검색", "wigolo \(hits.count)건")
            return Array(hits.prefix(maxResults))
        }
        if let hits = try? await searchViaDDG(query: query), !hits.isEmpty {
            logger.info(feature: "웹검색", "DuckDuckGo 폴백 \(hits.count)건")
            return Array(hits.prefix(maxResults))
        }
        if let hits = try? await searchViaWiki(query: query), !hits.isEmpty {
            logger.info(feature: "웹검색", "Wikipedia 폴백 \(hits.count)건")
            return Array(hits.prefix(maxResults))
        }
        logger.error(code: "E-MAC-NET-0015", feature: "웹검색", "전체 체인 실패: \(query.prefix(40))")
        throw WebSearchError.allFailed
    }

    /// 페이지 가져오기: wigolo fetch → 직접 GET.
    static func fetch(url: String) async throws -> String {
        if let text = try? await fetchViaWigolo(url: url), !text.isEmpty {
            return String(text.prefix(fetchCap))
        }
        if let text = try? await fetchDirect(url: url), !text.isEmpty {
            DebugLogger.shared.info(feature: "웹검색", "직접 가져오기 폴백")
            return text
        }
        DebugLogger.shared.error(code: "E-MAC-NET-0015", feature: "웹검색",
                                 "가져오기 실패: \(url.prefix(80))")
        throw WebSearchError.allFailed
    }

    /// wigolo search 호출.
    static func searchViaWigolo(query: String, maxResults: Int) async throws -> [WebHit] {
        var req = URLRequest(url: WigoloManager.baseURL.appendingPathComponent("v1/search"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "max_results": maxResults])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw WebSearchError.badStatus }
        return parseWigolo(data)
    }

    /// DDG Instant Answer 호출 (공식·키없음).
    static func searchViaDDG(query: String) async throws -> [WebHit] {
        var parts = URLComponents(string: "https://api.duckduckgo.com/")!
        parts.queryItems = [URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "format", value: "json"),
                            URLQueryItem(name: "no_html", value: "1"),
                            URLQueryItem(name: "skip_disambig", value: "1")]
        var req = URLRequest(url: parts.url!)
        req.timeoutInterval = 15
        req.setValue("LiteRTLMStudio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw WebSearchError.badStatus }
        return parseDDG(data)
    }

    /// Wikipedia opensearch 호출 (공식·키없음).
    static func searchViaWiki(query: String) async throws -> [WebHit] {
        var parts = URLComponents(string: "https://ko.wikipedia.org/w/api.php")!
        parts.queryItems = [URLQueryItem(name: "action", value: "opensearch"),
                            URLQueryItem(name: "search", value: query),
                            URLQueryItem(name: "limit", value: "5"),
                            URLQueryItem(name: "format", value: "json")]
        var req = URLRequest(url: parts.url!)
        req.timeoutInterval = 15
        req.setValue("LiteRTLMStudio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw WebSearchError.badStatus }
        return parseWiki(data)
    }

    /// wigolo fetch 호출.
    static func fetchViaWigolo(url: String) async throws -> String {
        var req = URLRequest(url: WigoloManager.baseURL.appendingPathComponent("v1/fetch"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["url": url])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw WebSearchError.badStatus }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8).map { String($0.prefix(fetchCap)) } ?? ""
        }
        for key in ["markdown", "content", "text"] {
            if let text = json[key] as? String, !text.isEmpty {
                return String(text.prefix(fetchCap))
            }
        }
        return ""
    }

    /// 직접 GET 폴백 (512KB cap+태그 제거).
    static func fetchDirect(url: String) async throws -> String {
        guard let target = URL(string: url) else { throw WebSearchError.badURL }
        var req = URLRequest(url: target)
        req.timeoutInterval = 20
        req.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw WebSearchError.badStatus }
        guard data.count < 512 * 1024,
              let html = String(data: data, encoding: .utf8) else { throw WebSearchError.tooLarge }
        return stripHTML(html)
    }
}

/// 웹 검색 오류 (T-269).
enum WebSearchError: Error {
    case allFailed
    case badStatus
    case badURL
    case tooLarge
}

/// opensearch 혼합 배열 요소 (T-269): 문자열 또는 문자열 배열.
enum WikiPart: Decodable {
    case string(String)
    case strings([String])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            self = .strings((try? c.decode([String].self)) ?? [])
        }
    }
}

/// 웹 검색 도구 (T-269): 질의 → 제목·URL·발췌 묶음.
struct WebSearchTool: Tool {
    static let name = "web_search"
    static let description = "웹에서 최신 정보를 검색합니다. 모델 지식 이후 소식·사실 확인에 사용하세요."

    @ToolParam(description: "검색 질의")
    var query: String = ""
    @ToolParam(description: "최대 결과 수 (기본 5)")
    var maxResults: Int = 5

    func run() async throws -> Any {
        let q = query
        let limit = Swift.min(Swift.max(1, maxResults), 8)
        guard WebSearch.enabled() else {
            await ToolLedger.shared.record(toolName: Self.name, detail: q,
                                           result: "웹 검색이 꺼져 있습니다.", denied: true)
            return "웹 검색이 꺼져 있습니다. 설정에서 켜 주세요."
        }
        return await LocalTools.runTolled(toolName: Self.name, detail: q) {
            let hits = try await WebSearch.search(query: q, maxResults: limit)
            guard !hits.isEmpty else { return "검색 결과 없음" }
            return WebSearch.formatForModel(hits)
        }
    }
}

/// 페이지 가져오기 도구 (T-269): URL → 마크다운 본문.
struct WebFetchTool: Tool {
    static let name = "web_fetch"
    static let description = "웹 페이지 본문을 가져옵니다. 검색 결과 URL의 내용을 읽을 때 사용하세요."

    @ToolParam(description: "가져올 페이지 URL")
    var url: String = ""

    func run() async throws -> Any {
        let target = url
        guard WebSearch.enabled() else {
            await ToolLedger.shared.record(toolName: Self.name, detail: target,
                                           result: "웹 검색이 꺼져 있습니다.", denied: true)
            return "웹 검색이 꺼져 있습니다. 설정에서 켜 주세요."
        }
        return await LocalTools.runTolled(toolName: Self.name, detail: target) {
            try await WebSearch.fetch(url: target)
        }
    }
}
