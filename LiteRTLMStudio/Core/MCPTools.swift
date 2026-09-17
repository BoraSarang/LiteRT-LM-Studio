import Foundation

/// MCP 게이트웨이 도구 2종 (T-285): 정적 Tool 2개로 임의 MCP 서버·도구를 중계.
/// 기존 권한·원장·칩 인프라 그대로 사용. 인자 JSON 파싱은 순수 함수로 분리.
struct MCPListToolsTool: Tool {
    static let name = "mcp_list_tools"
    static let description = "MCP 서버의 도구 목록을 조회합니다. 외부 도구 사용 전 먼저 호출하세요."

    @ToolParam(description: "서버 이름 (비우면 전체)")
    var server: String = ""

    func run() async throws -> Any {
        let target = server.trimmingCharacters(in: .whitespacesAndNewlines)
        return await LocalTools.runTolled(toolName: Self.name, detail: target) {
            let servers = await MCPStore.shared.enabledServers.filter {
                target.isEmpty || $0.name == target
            }
            guard !servers.isEmpty else { return "사용 가능한 MCP 서버 없음" }
            var lines: [String] = []
            for srv in servers {
                do {
                    let tools = try await MCPClient.listTools(server: srv)
                    if tools.isEmpty {
                        lines.append("[\(srv.name)] 도구 없음")
                    } else {
                        lines.append("[\(srv.name)]")
                        for tool in tools {
                            lines.append("- \(tool.name): \(tool.description)")
                        }
                    }
                } catch {
                    lines.append("[\(srv.name)] 조회 실패: \(error)")
                }
            }
            return lines.joined(separator: "\n")
        }
    }
}

/// MCP 호출 게이트웨이 (T-285).
struct MCPCallTool: Tool {
    static let name = "mcp_call"
    static let description = "MCP 서버의 도구를 실행합니다. 목록은 mcp_list_tools로 먼저 확인하세요."

    @ToolParam(description: "서버 이름")
    var server: String = ""
    @ToolParam(description: "도구 이름")
    var tool: String = ""
    @ToolParam(description: "인자 JSON 객체 문자열 (예: {\"q\": \"검색어\"})")
    var argumentsJson: String = "{}"

    /// 인자 JSON 파싱 (순수, 테스트 가능): 실패 시 빈 객체.
    nonisolated static func parseArguments(_ text: String) -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func run() async throws -> Any {
        let srvName = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolName = tool.trimmingCharacters(in: .whitespacesAndNewlines)
        let args = Self.parseArguments(argumentsJson)
        guard let srv = await MCPStore.shared.enabledServers.first(where: { $0.name == srvName }) else {
            await ToolLedger.shared.record(toolName: Self.name, detail: srvName,
                                           result: "MCP 서버 없음 (꺼짐·미등록)", denied: true)
            return "MCP 서버 없음: \(srvName). 설정에서 확인해 주세요."
        }
        return await LocalTools.runTolled(toolName: Self.name,
                                          detail: "\(srvName).\(toolName)") {
            do {
                return try await MCPClient.callTool(server: srv, tool: toolName, arguments: args)
            } catch {
                DebugLogger.shared.error(code: "E-MAC-NET-0016", feature: "MCP",
                                         "\(srvName).\(toolName) 실패: \(error)")
                return "MCP 호출 실패: \(error)"
            }
        }
    }
}
