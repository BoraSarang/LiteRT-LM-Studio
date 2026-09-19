import Foundation

/// 도구 호출 표시 포맷 (T-342, 순수·테스트 가능): 인자 JSON→한글 요약, 결과 JSON→pretty.
/// T-360: 파일 길이 관리를 위해 `ToolEvents.swift`에서 분리.
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
