import Foundation

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

    /// 인자 요약 (칩 표시용, 순수): 80자 절단.
    var summary: String {
        let flat = argumentsJSON.replacingOccurrences(of: "\n", with: " ")
        return String(flat.prefix(80))
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
