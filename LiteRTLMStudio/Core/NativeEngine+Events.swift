import Foundation

/// 네이티브 이벤트 스트림 확장 (T-266 S-1 분리: 본문 길이 관리).
/// 본문·생각 채널·도구 호출 분리. 문자열 스트림(`stream`)은 프로토콜 기본값 유지.
extension NativeEngine {
    /// 이벤트 스트림 (T-266 S-1): 본문·생각 채널·도구 호출 분리.
    /// tool_call 채널 외 채널 내용은 생각으로 취급 (키 로깅으로 관측).
    func streamEvents(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        keyHistory: [String],
        options: GenerationOptions
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let engine else {
            return AsyncThrowingStream { $0.finish(throwing: EngineError.notReady) }
        }
        let keyEntries = keyHistory
        let mid = preparedModelID ?? ""
        let past = history.map { turn in
            Message(turn.text, role: turn.role == "user" ? .user : .model)
        }
        let message: Message = if let image {
            Message(contents: [Content.imageData(image.data), Content.text(prompt)])
        } else {
            Message(prompt)
        }
        let opts = options
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let setup = try await self.preparedStream(
                        engine: engine, modelID: mid, past: past,
                        entries: keyEntries, opts: opts)
                    let gen = setup.conversation.sendMessageStream(
                        message, maxOutputTokens: opts.maxTokens, thinkingConfig: setup.thinking)
                    var loggedChannels = Set<String>()
                    for try await chunk in gen {
                        for key in chunk.channels.keys where !loggedChannels.contains(key) {
                            loggedChannels.insert(key)
                            DebugLogger.shared.info(feature: "도구", "네이티브 채널 발견: \(key)")
                        }
                        for event in Self.events(
                            from: chunk,
                            toolChannel: ExperimentalFlags.conversationToolCallStreamingChannelName) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: EngineError.inferenceFailed("\(error)"))
                }
            }
        }
    }

    /// 청크→이벤트 매핑 (순수, 테스트 가능, T-266 S-1).
    nonisolated static func events(from chunk: Message, toolChannel: String) -> [StreamEvent] {
        var out: [StreamEvent] = []
        let text = chunk.toString
        if !text.isEmpty { out.append(.text(text)) }
        for (key, value) in chunk.channels where !value.isEmpty {
            if key == toolChannel { continue } // S-2에서 디코딩
            out.append(.thinking(value))
        }
        for call in chunk.toolCalls {
            out.append(.toolCall(ToolCallRecord(
                callID: call.id, name: call.name,
                argumentsJSON: Self.jsonString(call.arguments),
                status: .received)))
        }
        return out
    }

    /// Any JSON 문자열화 (S-1 표시용, 실패 시 빈 객체).
    nonisolated static func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
