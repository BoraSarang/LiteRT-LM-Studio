import Foundation

/// 웹 검색 결과 1건 (T-269): 제공자 무관 공통형.
struct WebHit: Sendable, Hashable {
    let title: String
    let url: String
    let excerpt: String
}

/// wigolo search 결과 1건 (T-269, T-288 실측: excerpt·snippet 양 대응).
struct WigoloSearchResult: Decodable {
    var title: String?
    var url: String?
    var excerpt: String?
    var snippet: String?
    var citationID: String?

    enum CodingKeys: String, CodingKey {
        case title, url, excerpt, snippet
        case citationID = "citation_id"
    }

    /// 본문 발췌 (순수): excerpt 우선, 없으면 snippet.
    var body: String {
        if let excerpt, !excerpt.isEmpty { return excerpt }
        return snippet ?? ""
    }
}

/// wigolo search 응답 (T-269): 문서 계약 기준, 전 필드 optional 디코딩.
struct WigoloSearchResponse: Decodable {
    var results: [WigoloSearchResult]?
}

/// 웹 검색 (T-269, T-284 wigolo 단일화): 폴백 없음.
/// 전 파서 순수·테스트 가능.
enum WebSearch {
    nonisolated static var excerptCap: Int { 300 }
    nonisolated static var fetchCap: Int { 8192 }
    nonisolated static var autoFetchCap: Int { 2000 } // T-316: 1위 자동 첨부 상한
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

    /// 검색 실행 (T-284 wigolo 단일): 미설치·미실행이면 즉시 안내 반환.
    static func search(query: String, maxResults: Int = 5) async throws -> [WebHit] {
        let logger = DebugLogger.shared
        do {
            let hits = try await searchViaWigolo(query: query, maxResults: maxResults)
            if !hits.isEmpty {
                logger.info(feature: "웹검색", "wigolo \(hits.count)건")
                return Array(hits.prefix(maxResults))
            }
        } catch {
            logger.error(code: "E-MAC-NET-0015", feature: "웹검색",
                         "wigolo 실패: \(error.localizedDescription)")
        }
        throw WebSearchError.allFailed
    }

    /// 페이지 가져오기 (T-284 wigolo 단일).
    static func fetch(url: String) async throws -> String {
        do {
            let text = try await fetchViaWigolo(url: url)
            if !text.isEmpty { return String(text.prefix(fetchCap)) }
        } catch {
            DebugLogger.shared.error(code: "E-MAC-NET-0015", feature: "웹검색",
                                     "가져오기 실패: \(url.prefix(80))")
        }
        throw WebSearchError.allFailed
    }

    /// wigolo 사용 가능 여부 (T-284): 바이너리+헬스. 미설치면 검색 불가.
    static func available() async -> Bool {
        guard WigoloManager.resolveBinary() != nil else { return false }
        var req = URLRequest(url: WigoloManager.baseURL.appendingPathComponent("openapi.json"))
        req.timeoutInterval = 5
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return true
    }

    /// 미사용 안내문 (T-284, T-288 초기 설정 구분, 모델 전달용 정상 응답).
    nonisolated static var unavailableMessage: String {
        "웹 검색을 사용할 수 없습니다. 설정 → 도구 → 내장 검색에서 설치·초기 설정을 마쳐 주세요."
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
                                           result: "웹 도구가 꺼져 있습니다.", denied: true)
            return "웹 도구가 꺼져 있습니다. 설정에서 켜 주세요."
        }
        guard await WebSearch.available() else {
            await ToolLedger.shared.record(toolName: Self.name, detail: q,
                                           result: WebSearch.unavailableMessage, denied: true)
            NotificationCenter.default.post(name: .requestWigoloInstall, object: nil)
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
    static let description = "웹 페이지 본문을 가져옵니다. 검색 결과 URL의 내용을 읽을 때 사용하세요."

    @ToolParam(description: "가져올 페이지 URL")
    var url: String = ""

    func run() async throws -> Any {
        let target = url
        guard WebSearch.enabled() else {
            await ToolLedger.shared.record(toolName: Self.name, detail: target,
                                           result: "웹 도구가 꺼져 있습니다.", denied: true)
            return "웹 도구가 꺼져 있습니다. 설정에서 켜 주세요."
        }
        guard await WebSearch.available() else {
            await ToolLedger.shared.record(toolName: Self.name, detail: target,
                                           result: WebSearch.unavailableMessage, denied: true)
            NotificationCenter.default.post(name: .requestWigoloInstall, object: nil)
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
