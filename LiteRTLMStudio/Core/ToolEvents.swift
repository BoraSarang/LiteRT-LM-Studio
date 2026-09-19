import Foundation

/// 서버 도구 인자 정규화 (T-350, 순수·테스트 가능): 인자 없는 도구의 빈 문자열·
/// 공백·null은 빈 객체로 취급해 파싱 실패("인자 파싱 실패")를 막는다.
/// 데몬이 같은 인자 JSON을 중복 조각으로 보내면 `{}{}`처럼 이어지는데,
/// 이 경우 첫 완전 객체만 채택한다 (중복 델타 흡수).
/// 진짜 malformed JSON이면 nil (호출 측이 실패 기록).
enum ServerToolArgs {
    nonisolated static func normalize(_ raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "null" else { return [:] }
        guard let slice = firstObjectEnd(of: trimmed) else { return nil }
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    /// 첫 완전 JSON 객체의 끝 인덱스까지 잘라낸 문자열 (순수): 문자열 안의 따옴표·
    /// 중첩을 추적해 `{}{}`같은 연결 객체에서 첫 `{...}`만 반환. 완전 객체가 없으면 nil.
    nonisolated static func firstObjectEnd(of text: String) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index?
        for i in text.indices {
            let c = text[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 { end = i; break }
            default:
                break
            }
            if end != nil { break }
        }
        guard let end else { return nil }
        return String(text[text.startIndex...end])
    }
}

/// 도구 호출 상태 (T-266 S-1): 수신 → S-2에서 실행 결과로 전이.
enum ToolCallStatus: String, Codable, Sendable {
    case streaming // 조각 수신 중
    case received // 호출 확정 (S-1 종착)
    case done // 실행 완료 (S-2)
    case failed // 실행 실패 (S-2)
    case denied // 사용자 거부 (S-2)
}

/// 도구 호출 1건 (T-266 S-1): 이름·인자 원문·상태. 결과는 S-2.
struct ToolCallRecord: Identifiable, Codable, Hashable, Sendable {
    var id: String { callID }
    let callID: String
    let name: String
    var argumentsJSON: String
    var status: ToolCallStatus
    var result: String?

    init(callID: String, name: String, argumentsJSON: String = "",
         status: ToolCallStatus = .streaming, result: String? = nil) {
        self.callID = callID
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.status = status
        self.result = result
    }

    /// 인자 요약 (순수): 80자 절단. 원문 보존용(포맷 실패 폴백·진단).
    var summary: String {
        let flat = argumentsJSON.replacingOccurrences(of: "\n", with: " ")
        return String(flat.prefix(80))
    }

    /// 칩 표시명 (순수, T-317/T-342): 카탈로그의 한글 제목, 미등록은 원문.
    var displayTitle: String {
        ToolCatalog.title(for: name)
    }

    /// 대표 인자 (순수, T-342): 도구별 맞춤 요약, JSON 문법 제거.
    var displayArg: String {
        ToolCallFormat.argument(argumentsJSON, tool: name)
    }

    /// 펼침 결과 (순수, T-342): JSON이면 들여쓰기 정리, 아니면 원문.
    var displayResult: String {
        guard let result else { return "" }
        return ToolCallFormat.pretty(result)
    }

    /// 결과 원문 토글이 필요한지 (순수): 정리 결과가 원문과 다를 때만.
    var hasPrettiedResult: Bool {
        guard let result else { return false }
        return ToolCallFormat.pretty(result) != result
    }

    /// 외부열기 URL (순수, T-317): web_fetch의 http(s)만.
    var externalURL: URL? {
        guard name == "web_fetch" else { return nil }
        let raw = displayArg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}

/// 도구 호출 표시 포맷 (T-342, 순수·테스트 가능): 인자 JSON→한글 요약, 결과 JSON→pretty.
enum ToolCallFormat {
    /// 인자 JSON → 사람이 읽는 요약. JSON 파싱 실패 시 문법 문자만 제거한 평문.
    nonisolated static func argument(_ json: String, tool: String) -> String {
        guard let dict = object(json) else { return plain(json) }
        if basicTools.contains(tool) { return basicArgument(dict, tool: tool) }
        if fileTools.contains(tool) { return fileArgument(dict, tool: tool) }
        if eventTools.contains(tool) { return eventArgument(dict, tool: tool) }
        if webTools.contains(tool) { return webArgument(dict, tool: tool) }
        return generic(dict)
    }

    private nonisolated static let basicTools: Set<String> = [
        "get_time", "read_clipboard", "get_system_info", "calculate",
        "write_clipboard", "open_url", "run_shortcut"
    ]
    private nonisolated static let fileTools: Set<String> = ["run_shell", "read_file", "save_code"]
    private nonisolated static let eventTools: Set<String> = [
        "list_calendar_events", "list_reminders", "add_reminder", "add_calendar_event",
        "delete_reminder", "delete_calendar_event"
    ]
    private nonisolated static let webTools: Set<String> = [
        "web_search", "web_fetch", "mcp_list_tools", "mcp_call"
    ]

    /// 기본 도구 (시각·클립보드·계산·URL·단축어).
    private nonisolated static func basicArgument(_ dict: [String: Any], tool: String) -> String {
        switch tool {
        case "get_time", "read_clipboard", "get_system_info": return ""
        case "calculate": return text(dict["expression"])
        case "write_clipboard":
            let n = text(dict["text"]).count
            return n == 0 ? "" : "내용 \(n)자"
        case "open_url": return text(dict["url"])
        case "run_shortcut": return text(dict["shortcut"])
        default: return ""
        }
    }

    /// 파일·셸 도구 (경로·명령·코드).
    private nonisolated static func fileArgument(_ dict: [String: Any], tool: String) -> String {
        switch tool {
        case "run_shell": return text(dict["command"])
        case "read_file": return text(dict["path"])
        case "save_code": return join([text(dict["path"]), codeLength(dict["content"])])
        default: return ""
        }
    }

    /// 캘린더·미리 알림 도구.
    private nonisolated static func eventArgument(_ dict: [String: Any], tool: String) -> String {
        switch tool {
        case "list_calendar_events": return "\(dict["days"] as? Int ?? 7)일"
        case "list_reminders":
            return (dict["includeCompleted"] as? Bool ?? false) ? "완료 포함" : "미완료만"
        case "add_reminder", "delete_reminder", "add_calendar_event", "delete_calendar_event":
            return join([text(dict["title"]), text(dict["when"])])
        default: return ""
        }
    }

    /// 웹·MCP 도구.
    private nonisolated static func webArgument(_ dict: [String: Any], tool: String) -> String {
        switch tool {
        case "web_search": return text(dict["query"])
        case "web_fetch": return text(dict["url"])
        case "mcp_list_tools": return text(dict["server"])
        case "mcp_call": return join([text(dict["server"]), text(dict["tool"])])
        default: return ""
        }
    }

    /// 결과 텍스트가 JSON 객체·배열이면 들여쓰기 정리, 아니면 원문.
    nonisolated static func pretty(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
              let out = String(data: pretty, encoding: .utf8) else { return raw }
        return out
    }

    /// JSON 객체 디코드 (실패 시 nil).
    private nonisolated static func object(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// 문자열 값 (문자열 아니면 빈 값).
    private nonisolated static func text(_ any: Any?) -> String {
        (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 코드 길이 표시: "코드 N자" (빈 값은 생략).
    private nonisolated static func codeLength(_ any: Any?) -> String {
        let n = text(any).count
        return n == 0 ? "" : "코드 \(n)자"
    }

    /// 미지 도구 폴백: 값만 `·`로 연결 (빈 값·null 제외, 각 40자).
    private nonisolated static func generic(_ dict: [String: Any]) -> String {
        let values = dict.keys.sorted().compactMap { key -> String? in
            guard let value = dict[key] else { return nil }
            guard !(value is NSNull) else { return nil }
            let s: String
            if let str = value as? String { s = str } else { s = "\(value)" }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : String(t.prefix(40))
        }
        return join(values)
    }

    /// JSON 문법 문자 제거 후 공백 정리.
    private nonisolated static func plain(_ raw: String) -> String {
        let scalars = raw.replacingOccurrences(of: "\n", with: " ")
            .filter { !"{}[]\"".contains($0) }
        return scalars.split(separator: " ").joined(separator: " ").prefix(80).description
    }

    /// 빈 조각 제외 후 ` · ` 연결.
    private nonisolated static func join(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// 스트림 이벤트 (T-266 S-1): 본문·생각·도구 호출 3채널.
enum StreamEvent: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case toolCall(ToolCallRecord)
}

/// SSE tool_calls 델타 누적기 (T-266 S-1, 순수·테스트 가능).
/// OpenAI 표준: index별 id/name/arguments 조각 append.
struct ToolCallAccumulator: Sendable {
    private var byIndex: [Int: ToolCallRecord] = [:]
    private(set) var finishReason: String?

    /// 델타 JSON 1건 적용. tool_calls·finish_reason·reasoning_content를 뽑는다.
    /// - Returns: (완성 단계 이벤트, thinking 조각). 미완성 조각은 nil 이벤트.
    mutating func apply(delta: ChatToolDelta) -> (event: StreamEvent?, thinking: String?) {
        if let reason = delta.finishReason { finishReason = reason }
        var event: StreamEvent?
        if let calls = delta.toolCalls {
            for frag in calls {
                let idx = frag.index ?? 0
                var rec = byIndex[idx] ?? ToolCallRecord(
                    callID: frag.id ?? "call-\(idx)",
                    name: frag.function?.name ?? "")
                if let id = frag.id, !id.isEmpty { rec = ToolCallRecord(
                    callID: id, name: rec.name, argumentsJSON: rec.argumentsJSON,
                    status: rec.status, result: rec.result) }
                if let name = frag.function?.name, !name.isEmpty { rec = ToolCallRecord(
                    callID: rec.callID, name: name, argumentsJSON: rec.argumentsJSON,
                    status: rec.status, result: rec.result) }
                if let args = frag.function?.arguments, !args.isEmpty {
                    rec = ToolCallRecord(callID: rec.callID, name: rec.name,
                                         argumentsJSON: rec.argumentsJSON + args,
                                         status: rec.status, result: rec.result)
                }
                byIndex[idx] = rec
                event = .toolCall(rec)
            }
        }
        return (event, delta.reasoningContent)
    }

    /// 확정 목록 (index 순). 조각 수신 중은 received로 승격.
    func finalized() -> [ToolCallRecord] {
        byIndex.sorted { $0.key < $1.key }.map { _, rec in
            ToolCallRecord(callID: rec.callID, name: rec.name,
                           argumentsJSON: rec.argumentsJSON,
                           status: rec.status == .streaming ? .received : rec.status,
                           result: rec.result)
        }
    }

    var hasCalls: Bool { !byIndex.isEmpty }
}

/// SSE 델타 디코딩 (T-266 S-1, Codable): content·tool_calls·reasoning_content.
struct ChatToolDelta: Decodable {
    struct FunctionFrag: Decodable {
        var name: String?
        var arguments: String?
    }
    struct CallFrag: Decodable {
        var index: Int?
        var id: String?
        var type: String?
        var function: FunctionFrag?
    }
    var content: String?
    var reasoningContent: String?
    var toolCalls: [CallFrag]?
    var finishReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        reasoningContent = try c.decodeIfPresent(String.self, forKey: .reasoningContent)
        toolCalls = try c.decodeIfPresent([CallFrag].self, forKey: .toolCalls)
        // finish_reason은 choice 레벨이라 별도 파서에서 주입.
        finishReason = nil
    }

    /// 테스트·내부 조립용.
    init(content: String? = nil, reasoningContent: String? = nil,
         toolCalls: [CallFrag]? = nil, finishReason: String? = nil) {
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
        self.finishReason = finishReason
    }
}

/// SSE choice 1건 파싱 (순수, T-266 S-1): delta + finish_reason 묶음.
enum ToolChunkParser {
    nonisolated static func parseDelta(_ data: Data) -> ChatToolDelta? {
        guard let chunk = try? JSONDecoder().decode(SSEChoiceChunk.self, from: data),
              let choice = chunk.choices?.first else { return nil }
        var delta = choice.delta ?? ChatToolDelta()
        delta.finishReason = choice.finishReason
        return delta
    }
}

/// 서버 tool 턴 조립 (T-268 S-3, 순수·테스트 가능): OpenAI 표준 assistant/tool 메시지.
enum ServerToolHistory {
    nonisolated static var maxTurns: Int { 3 }

    /// assistant(tool_calls) 메시지 1건.
    nonisolated static func assistantMessage(calls: [ToolCallRecord]) -> [String: Any] {
        ["role": "assistant", "tool_calls": calls.map {
            ["id": $0.callID, "type": "function",
             "function": ["name": $0.name, "arguments": $0.argumentsJSON]]
        }]
    }

    /// tool 결과 메시지 1건.
    nonisolated static func toolMessage(callID: String, content: String) -> [String: Any] {
        ["role": "tool", "tool_call_id": callID, "content": content]
    }

    /// 칩 목록 병합 (순수): callID 일치 교체, 신규 추가.
    nonisolated static func merged(_ current: [ToolCallRecord],
                                   with fresh: [ToolCallRecord]) -> [ToolCallRecord] {
        var out = current
        for rec in fresh {
            if let j = out.firstIndex(where: { $0.callID == rec.callID }) {
                out[j] = rec
            } else {
                out.append(rec)
            }
        }
        return out
    }
}

/// SSE 청크 choice 디코딩 (T-266 S-1, 파일 스코프: nesting 린트 회피).
struct SSEChoice: Decodable {
    var delta: ChatToolDelta?
    var finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

/// SSE 청크 디코딩 모델 (T-266 S-1, 파일 스코프).
struct SSEChoiceChunk: Decodable {
    var choices: [SSEChoice]?
}

/// 인라인 <think> 분리 (T-274, 순수·테스트 가능): Qwen류가 본문에 섞어 보내는 추론 태그.
/// 미닫힘은 뒤 전체를 추론으로 (스트리밍 중간 상태).
/// T-278: 종료 시점(final) 미닫힘은 마지막 빈줄 뒤를 답변으로 분리 (닫기 태그 생략 모델 대응).
/// T-289: final 분리는 미닫힘 잔여 안에서만 (닫힌 블록 오염 방지).
/// 쪼갤 곳 없으면 미닫힘 전체를 답변으로 승격 (빈 본문 방지). 공백 조각은 버림.
enum ThinkTag {
    nonisolated static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func extract(_ text: String, final: Bool = false) -> (clean: String, thought: String) {
        var clean = text
        var closed: [String] = []
        var tail = ""
        var leftOpen = false
        while let open = clean.range(of: "<think>") {
            let afterOpen = open.upperBound
            if let close = clean.range(of: "</think>", range: afterOpen ..< clean.endIndex) {
                let part = trim(String(clean[afterOpen ..< close.lowerBound]))
                if !part.isEmpty { closed.append(part) }
                clean.removeSubrange(open.lowerBound ..< close.upperBound)
            } else {
                tail = trim(String(clean[afterOpen...]))
                clean.removeSubrange(open.lowerBound ..< clean.endIndex)
                leftOpen = true
                break
            }
        }
        let base = closed.joined(separator: "\n")
        let answerHead = trim(clean)
        guard leftOpen else { return (answerHead, base) }
        if final, let split = tail.range(of: "\n\n", options: .backwards) {
            let head = trim(String(tail[..<split.lowerBound]))
            let last = trim(String(tail[split.upperBound...]))
            if !last.isEmpty {
                let thought = base.isEmpty ? head : head.isEmpty ? base : base + "\n" + head
                let answer = answerHead.isEmpty ? last : answerHead + "\n\n" + last
                return (answer, thought)
            }
        }
        if final, answerHead.isEmpty {
            return (tail, base)
        }
        let thought = base.isEmpty ? tail : tail.isEmpty ? base : base + "\n" + tail
        return (answerHead, thought)
    }
}
