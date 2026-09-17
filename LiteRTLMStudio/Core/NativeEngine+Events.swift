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
        let input = StreamConsumeInput(engine: engine, mid: mid, past: past, message: message,
                                       keyEntries: keyEntries, opts: opts)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.consumeStream(input, firstReuse: true,
                                                 continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: EngineError.inferenceFailed("\(error)"))
                }
            }
        }
    }

    /// 스트림 소비 요청 묶음 (T-277, 파라미터 수 린트 회피).
    struct StreamConsumeInput {
        let engine: Engine
        let mid: String
        let past: [Message]
        let message: Message
        let keyEntries: [String]
        let opts: GenerationOptions
    }

    /// 스트림 소비 (T-277): 재사용 핸들 거부 시 무효화 후 새 대화로 1회 재시도.
    private func consumeStream(_ input: StreamConsumeInput, firstReuse: Bool,
                               continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var allowReuse = firstReuse
        while true {
            let setup = try await preparedStream(engine: input.engine, modelID: input.mid,
                                                 past: input.past, entries: input.keyEntries,
                                                 opts: input.opts, allowReuse: allowReuse)
            do {
                let gen = setup.conversation.sendMessageStream(
                    input.message, maxOutputTokens: input.opts.maxTokens,
                    thinkingConfig: setup.thinking)
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
                return
            } catch {
                // T-289: 취소는 재시도 없이 즉시 전파 (stop 무시 방지).
                if error is CancellationError { throw error }
                guard allowReuse, setup.reused, Self.isStartStreamFailure(error) else { throw error }
                invalidateReuse()
                DebugLogger.shared.info(feature: "네이티브엔진", "재사용 시작 실패 → 새 대화 재시도")
                allowReuse = false
            }
        }
    }

    /// 시작 실패 판정 (순수, 테스트 가능, T-277): 재사용 핸들 거부일 때만 재시도.
    nonisolated static func isStartStreamFailure(_ error: Error) -> Bool {
        guard let lite = error as? LiteRTLMError,
              case .conversation(.failedToStartStream) = lite else { return false }
        return true
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
