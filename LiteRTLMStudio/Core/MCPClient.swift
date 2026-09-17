import Foundation

/// MCP 서버 설정 (T-285): stdio 실행형·SSE 원격형.
struct MCPServerConfig: Codable, Identifiable, Hashable, Sendable {
    enum Transport: String, Codable, Sendable {
        case stdio
        case sse
    }

    var id = UUID()
    var name: String
    var transport: Transport = .stdio
    var command: String = ""
    var args: [String] = []
    var url: String = ""
    var enabled = true

    /// 실행 가능 여부 (순수): stdio는 명령 필수, SSE는 http(s) URL 필수.
    var isRunnable: Bool {
        switch transport {
        case .stdio: return !command.trimmingCharacters(in: .whitespaces).isEmpty
        case .sse:
            guard let u = URL(string: url),
                  u.scheme == "http" || u.scheme == "https" else { return false }
            return true
        }
    }
}

/// MCP 도구 정의 (T-285): 이름·설명·입력 스키마 원문.
struct MCPToolDef: Sendable, Hashable {
    let name: String
    let description: String
    let inputSchemaText: String
}

/// MCP 오류 (T-285).
enum MCPError: Error, Equatable {
    case notRunnable
    case spawnFailed(String)
    case timeout
    case badResponse(String)
    case serverError(code: Int, message: String)
}

/// MCP JSON-RPC 클라이언트 (T-285): 호출당 프로세스 1회 (v1 단순형).
/// stdio는 줄단위 JSON-RPC, SSE는 Streamable HTTP POST.
enum MCPClient {
    nonisolated static var timeout: TimeInterval { 30 }

    /// 요청 봉투 조립 (순수, 테스트 가능).
    nonisolated static func envelope(id: Int, method: String,
                                     params: [String: Any] = [:]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    }

    /// SSE/HTTP 응답에서 JSON 추출 (순수, 테스트 가능): 원시 JSON 또는 마지막 data: 줄.
    nonisolated static func extractJSON(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        var last: [String: Any]?
        for line in trimmed.components(separatedBy: .newlines) {
            let body = line.hasPrefix("data:") ? String(line.dropFirst(5)) : line
            guard let data = body.trimmingCharacters(in: .whitespaces).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            last = obj
        }
        return last
    }

    /// 에러 봉투 판독 (순수, 테스트 가능).
    nonisolated static func responseError(_ obj: [String: Any]) -> MCPError? {
        guard let err = obj["error"] as? [String: Any] else { return nil }
        return .serverError(code: err["code"] as? Int ?? -1,
                            message: err["message"] as? String ?? "unknown")
    }

    /// 도구 목록 조회.
    static func listTools(server: MCPServerConfig) async throws -> [MCPToolDef] {
        guard server.isRunnable else { throw MCPError.notRunnable }
        let obj = try await request(server: server, method: "tools/list")
        if let err = responseError(obj) { throw err }
        guard let result = obj["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]] else {
            throw MCPError.badResponse("tools/list result 없음")
        }
        return tools.compactMap { item -> MCPToolDef? in
            guard let name = item["name"] as? String else { return nil }
            let desc = item["description"] as? String ?? ""
            var schema = "{}"
            if let dict = item["inputSchema"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: dict),
               let str = String(data: data, encoding: .utf8) {
                schema = str
            }
            return MCPToolDef(name: name, description: desc, inputSchemaText: schema)
        }
    }

    /// 도구 호출 → 텍스트 결합 반환.
    static func callTool(server: MCPServerConfig, tool: String,
                         arguments: [String: Any]) async throws -> String {
        guard server.isRunnable else { throw MCPError.notRunnable }
        let obj = try await request(server: server, method: "tools/call",
                                    params: ["name": tool, "arguments": arguments])
        if let err = responseError(obj) { throw err }
        guard let result = obj["result"] as? [String: Any],
              let blocks = result["content"] as? [[String: Any]] else {
            throw MCPError.badResponse("tools/call result 없음")
        }
        var texts: [String] = []
        var nonText = 0
        for block in blocks {
            if block["type"] as? String == "text", let text = block["text"] as? String {
                texts.append(text)
            } else {
                nonText += 1
            }
        }
        if nonText > 0 {
            texts.append("(이미지 등 비텍스트 \(nonText)건 제외)")
        }
        return texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 전송 분기 요청.
    static func request(server: MCPServerConfig, method: String,
                        params: [String: Any] = [:]) async throws -> [String: Any] {
        switch server.transport {
        case .stdio: return try await requestStdio(server: server, method: method, params: params)
        case .sse: return try await requestHTTP(server: server, method: method, params: params)
        }
    }

    /// stdio 호출 1회: initialize + 본요청 (v1 단순형).
    static func requestStdio(server: MCPServerConfig, method: String,
                             params: [String: Any]) async throws -> [String: Any] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [server.command] + server.args
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            throw MCPError.spawnFailed("\(error)")
        }
        defer { if proc.isRunning { proc.terminate() } }
        func send(_ obj: [String: Any], id: Int) throws {
            var full = obj
            full["id"] = id
            let data = try JSONSerialization.data(withJSONObject: full)
            inPipe.fileHandleForWriting.write(data)
            inPipe.fileHandleForWriting.write(Data("\n".utf8))
        }
        // MCP 핸드셰이크 후 본요청 (서버는 notifications 무시 가능).
        try send(["jsonrpc": "2.0", "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05",
                             "capabilities": [:] as [String: Any],
                             "clientInfo": ["name": "LiteRT-LM Studio", "version": "1"]]], id: 0)
        try send(envelope(id: 1, method: method, params: params), id: 1)
        try inPipe.fileHandleForWriting.close()
        let data = try await readAll(handle: outPipe.fileHandleForReading, proc: proc)
        guard let obj = extractJSON(String(data: data, encoding: .utf8) ?? ""),
              let id = obj["id"] as? Int, id == 1 else {
            throw MCPError.badResponse("응답 id 불일치 또는 파싱 실패")
        }
        return obj
    }

    /// 종료·타임아웃 포함 전체 출력 읽기.
    static func readAll(handle: FileHandle, proc: Process) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            var buffer = Data()
            let timer = DispatchWorkItem {
                if proc.isRunning { proc.terminate() }
                cont.resume(throwing: MCPError.timeout)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            handle.readabilityHandler = { h in
                let chunk = h.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    timer.cancel()
                    if !Task.isCancelled {
                        cont.resume(returning: buffer)
                    } else {
                        cont.resume(throwing: CancellationError())
                    }
                } else {
                    buffer.append(chunk)
                }
            }
            proc.terminationHandler = { _ in
                handle.readabilityHandler = nil
                timer.cancel()
            }
        }
    }

    /// Streamable HTTP 호출 (JSON 직응답 또는 SSE data: 파싱).
    static func requestHTTP(server: MCPServerConfig, method: String,
                            params: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: server.url) else { throw MCPError.notRunnable }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: envelope(id: 1, method: method, params: params))
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw MCPError.badStatus
        }
        guard let obj = extractJSON(String(data: data, encoding: .utf8) ?? ""),
              let id = obj["id"] as? Int, id == 1 else {
            throw MCPError.badResponse("응답 id 불일치 또는 파싱 실패")
        }
        return obj
    }
}

/// HTTP 상태 오류 확장 (T-285): MCPError 케이스 추가 없이 재사용.
extension MCPError {
    static var badStatus: MCPError { .badResponse("HTTP 200 아님") }
}
