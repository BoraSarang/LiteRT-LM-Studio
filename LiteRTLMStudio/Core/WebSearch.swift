import Foundation

/// 웹 검색 결과 1건 (T-269): 제공자 무관 공통형.
struct WebHit: Sendable, Hashable {
    let title: String
    let url: String
    let excerpt: String
}

/// Exa search 결과 1건 (T-352): 전 필드 optional 디코딩.
struct ExaSearchResult: Decodable {
    var title: String?
    var url: String?
    var text: String?
    var highlights: [String]?
    var publishedDate: String?

    enum CodingKeys: String, CodingKey {
        case title, url, text, highlights, publishedDate
    }

    /// 본문 발췌 (순수): 하이라이트 우선, 없으면 text 앞부분.
    var body: String {
        if let highlights, !highlights.isEmpty {
            return highlights.joined(separator: " ")
        }
        if let text, !text.isEmpty {
            return String(text.prefix(WebSearch.excerptCap))
        }
        return ""
    }
}

/// Exa search 응답 (T-352).
struct ExaSearchResponse: Decodable {
    var results: [ExaSearchResult]?
}

/// Exa contents 결과 1건 (T-352): URL → 텍스트 본문.
struct ExaContentResult: Decodable {
    var url: String?
    var text: String?
}

/// Exa contents 응답 (T-352).
struct ExaContentsResponse: Decodable {
    var results: [ExaContentResult]?
}

/// 웹 검색 (T-269, T-352 Exa REST 교체): 폴백 없음.
/// 전 파서 순수·테스트 가능.
enum WebSearch {
    nonisolated static var excerptCap: Int { 300 }
    nonisolated static var fetchCap: Int { 8192 }
    nonisolated static var autoFetchCap: Int { 2000 } // T-316: 1위 자동 첨부 상한
    nonisolated static var toggleKey: String { "webSearchEnabled" }
    nonisolated static var apiKeyKey: String { "exaApiKey" }

    /// Exa API 키 (순수): 설정 저장값.
    nonisolated static func apiKey(_ defaults: UserDefaults = .standard) -> String {
        (defaults.string(forKey: apiKeyKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 설정 토글 (기본 켜짐).
    nonisolated static func enabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: toggleKey) == nil || defaults.bool(forKey: toggleKey)
    }

    /// Exa search 응답 파싱 (순수).
    nonisolated static func parseExaSearch(_ data: Data) -> [WebHit] {
        guard let res = try? JSONDecoder().decode(ExaSearchResponse.self, from: data),
              let items = res.results else { return [] }
        return items.compactMap { item in
            guard let url = item.url, !url.isEmpty else { return nil }
            return WebHit(title: item.title?.isEmpty == false ? item.title! : url,
                          url: url, excerpt: item.body.prefix(excerptCap).description)
        }
    }

    /// Exa contents 응답 파싱 (순수): 1번째 결과 본문.
    nonisolated static func parseExaContents(_ data: Data) -> String {
        guard let res = try? JSONDecoder().decode(ExaContentsResponse.self, from: data),
              let text = res.results?.first?.text, !text.isEmpty else { return "" }
        return String(text.prefix(fetchCap))
    }

    /// 모델 전달용 포맷 (순수): 번호+제목+URL+발췌 cap.
    nonisolated static func formatForModel(_ hits: [WebHit]) -> String {
        hits.enumerated().map { idx, hit in
            let excerpt = String(hit.excerpt.prefix(excerptCap))
            return "[\(idx + 1)] \(hit.title)\n\(hit.url)\n\(excerpt)"
        }.joined(separator: "\n\n")
    }

    /// 검색+1위 본문 합성 (순수, T-316): 본문 없으면 검색 목록만.
    nonisolated static func combinedForModel(hits: [WebHit], topBody: String) -> String {
        var out = formatForModel(hits)
        let body = topBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            out += "\n\n[1번 페이지 본문]\n" + String(body.prefix(autoFetchCap))
        }
        return out
    }

    /// 검색 실행 (T-352 Exa 단일): 키 미설정이면 즉시 안내 반환.
    static func search(query: String, maxResults: Int = 5) async throws -> [WebHit] {
        let logger = DebugLogger.shared
        do {
            let hits = try await searchViaExa(query: query, maxResults: maxResults)
            if !hits.isEmpty {
                logger.info(feature: "웹검색", "Exa \(hits.count)건")
                return Array(hits.prefix(maxResults))
            }
        } catch {
            logger.error(code: "E-MAC-NET-0015", feature: "웹검색",
                         "Exa 실패: \(error.localizedDescription)")
        }
        throw WebSearchError.allFailed
    }

    /// 페이지 가져오기 (T-352 Exa 단일).
    static func fetch(url: String) async throws -> String {
        do {
            let text = try await fetchViaExa(url: url)
            if !text.isEmpty { return String(text.prefix(fetchCap)) }
        } catch {
            DebugLogger.shared.error(code: "E-MAC-NET-0015", feature: "웹검색",
                                     "가져오기 실패: \(url.prefix(80))")
        }
        throw WebSearchError.allFailed
    }

    /// Exa 사용 가능 여부 (T-352): API 키 존재. 미설정이면 검색 불가.
    nonisolated static func available() -> Bool {
        !apiKey().isEmpty
    }

    /// 미사용 안내문 (T-284, T-352 키 발급 안내 포함, 모델 전달용 정상 응답).
    nonisolated static var unavailableMessage: String {
        "웹 검색을 사용할 수 없습니다. 설정 → 도구 → 웹에서 Exa API 키를 입력해 주세요. (키 발급: https://dashboard.exa.ai)"
    }

    /// Exa search 요청 본문 (순수, T-352): 하이라이트 + 라이브 크롤(maxAgeHours=0).
    nonisolated static func searchBody(query: String, maxResults: Int) -> [String: Any] {
        ["query": query, "numResults": maxResults, "type": "auto",
         "contents": ["highlights": true, "maxAgeHours": 0]]
    }

    /// Exa contents 요청 본문 (순수, T-352): 텍스트 + 라이브 크롤(maxAgeHours=0).
    nonisolated static func contentsBody(url: String) -> [String: Any] {
        ["urls": [url], "text": true, "maxAgeHours": 0]
    }

    /// Exa search 호출 (T-352): 하이라이트 포함, 발췌용 가볍게.
    /// maxAgeHours=0(T-353): 캐시 대신 라이브 크롤 — 릴리스·최신 소식의 낡은 캐시 방지.
    static func searchViaExa(query: String, maxResults: Int) async throws -> [WebHit] {
        let data = try await exaPOST(path: "search",
                                     body: searchBody(query: query, maxResults: maxResults))
        return parseExaSearch(data)
    }

    /// 1위 본문 조회 (T-316, 무예외): 실패·빈 본문이면 "" (검색 결과 유지).
    static func topBody(url: String) async -> String {
        guard let target = URL(string: url),
              ["http", "https"].contains(target.scheme?.lowercased() ?? "") else { return "" }
        do {
            return try await fetch(url: url)
        } catch {
            DebugLogger.shared.info(feature: "웹검색", "1위 본문 생략: \(error.localizedDescription)")
            return ""
        }
    }

    /// Exa contents 호출 (T-352): URL 목록 → 텍스트 본문.
    /// maxAgeHours=0(T-353): 항상 라이브 크롤 (캐시된 낡은 릴리스 목록 회피).
    static func fetchViaExa(url: String) async throws -> String {
        let data = try await exaPOST(path: "contents", body: contentsBody(url: url))
        return parseExaContents(data)
    }

    /// Exa 공통 POST (T-352): api.exa.ai 도메인 + Bearer 인증.
    nonisolated static func exaPOST(path: String, body: [String: Any]) async throws -> Data {
        guard let endpoint = URL(string: "https://api.exa.ai/\(path)") else {
            throw WebSearchError.badURL
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey())", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw WebSearchError.badStatus }
        return data
    }
}

/// 웹 검색 오류 (T-269, T-284 단일화).
enum WebSearchError: Error {
    case allFailed
    case badStatus
    case badURL
    case tooLarge
}

/// 웹 검색 도구 (T-269): 질의 → 제목·URL·발췌 묶음.
struct WebSearchTool: Tool {
    static let name = "web_search"
    static let description = "웹에서 최신 정보를 검색합니다. 모델 지식 이후 소식·사실 확인에 사용하세요. "
        + "결과에 [1번 페이지 본문]이 있으면 그 내용으로 바로 답하고, 부족하면 지체 없이 web_fetch로 원문을 읽으세요."

    @ToolParam(description: "검색 질의")
    var query: String = ""
    @ToolParam(description: "최대 결과 수 (기본 5)")
    var maxResults: Int = 5

    func run() async throws -> Any {
        let q = query
        let limit = Swift.min(Swift.max(1, maxResults), 8)
        guard WebSearch.enabled() else {
            await ToolLedger.shared.record(toolName: Self.name, detail: q,
                                           result: "웹 도구가 꺼져 있습니다.", denied: true)
            return "웹 도구가 꺼져 있습니다. 설정에서 켜 주세요."
        }
        guard WebSearch.available() else {
            await ToolLedger.shared.record(toolName: Self.name, detail: q,
                                           result: WebSearch.unavailableMessage, denied: true)
            return WebSearch.unavailableMessage
        }
        return await LocalTools.runTolled(toolName: Self.name, detail: q) {
            do {
                let hits = try await WebSearch.search(query: q, maxResults: limit)
                guard !hits.isEmpty else { return "검색 결과 없음" }
                // T-316: 1위 본문 자동 첨부 (발췌만으로 답 불가 질의 대응).
                // 실패해도 검색 결과는 유지 — 2턴 절약이 목적이지 강제가 아님.
                let body = await WebSearch.topBody(url: hits[0].url)
                return WebSearch.combinedForModel(hits: hits, topBody: body)
            } catch WebSearchError.allFailed {
                // T-283: 결과 없음은 실패가 아님 (벤더 스트림 유지용 정상 응답).
                return "검색 결과 없음"
            }
        }
    }
}

/// 페이지 가져오기 도구 (T-269): URL → 마크다운 본문.
struct WebFetchTool: Tool {
    static let name = "web_fetch"
    static let description = "웹 페이지 본문을 가져옵니다. 검색 결과 URL이나 확인이 필요한 페이지의 내용을 읽을 때 사용하세요. "
        + "필요하면 말로만 예고하지 말고 즉시 이 도구를 호출하세요."

    @ToolParam(description: "가져올 페이지 URL")
    var url: String = ""

    func run() async throws -> Any {
        let target = url
        guard WebSearch.enabled() else {
            await ToolLedger.shared.record(toolName: Self.name, detail: target,
                                           result: "웹 도구가 꺼져 있습니다.", denied: true)
            return "웹 도구가 꺼져 있습니다. 설정에서 켜 주세요."
        }
        guard WebSearch.available() else {
            await ToolLedger.shared.record(toolName: Self.name, detail: target,
                                           result: WebSearch.unavailableMessage, denied: true)
            return WebSearch.unavailableMessage
        }
        return await LocalTools.runTolled(toolName: Self.name, detail: target) {
            do {
                return try await WebSearch.fetch(url: target)
            } catch WebSearchError.allFailed {
                return "페이지를 가져오지 못했습니다"
            } catch WebSearchError.badURL {
                return "URL이 올바르지 않습니다"
            }
        }
    }
}
