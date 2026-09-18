import Foundation

/// 앱 내 엔진 이벤트 스트림 확장 (T-266 S-1 분리: 본문 길이 관리).
/// 본문·생각 채널·도구 호출 분리. 문자열 스트림(`stream`)은 프로토콜 기본값 유지.
extension NativeEngine {
    /// 이벤트 스트림 (T-266 S-1): 본문·생각 채널·도구 호출 분리.
    /// tool_call 채널 외 채널 내용은 생각으로 취급 (키 로깅으로 관측).
    /// P1: consumeStream/StreamConsumeInput 제거로 경로 단축.
    func streamEvents(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        options: GenerationOptions,
        sessionID: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let modelID = preparedModelID,
              let engine = engines[modelID] else {
            return AsyncThrowingStream { $0.finish(throwing: EngineError.notReady) }
        }
        let mid = modelID
        let sid = sessionID
        let past = history.map { turn in
            Message(turn.text, role: turn.role == "user" ? .user : .model)
        }
        let message: Message = if let image {
            Message(contents: [Content.imageData(image.data), Content.text(prompt)])
        } else {
            Message(prompt)
        }
        let opts = options
        let toolChannel = ExperimentalFlags.conversationToolCallStreamingChannelName

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // P1: preparedStream 직접 호출, 재시도 로직 인라인
                    var allowReuse = true
                    while true {
                        let setup = try await self.preparedStream(
                            engine: engine, modelID: mid, past: past,
                            sessionID: sid, opts: opts, allowReuse: allowReuse)
                        do {
                            let gen = setup.conversation.sendMessageStream(
                                message, maxOutputTokens: opts.maxTokens,
                                thinkingConfig: setup.thinking)
                            var loggedChannels = Set<String>()
                            for try await chunk in gen {
                                for key in chunk.channels.keys where !loggedChannels.contains(key) {
                                    loggedChannels.insert(key)
                                    DebugLogger.shared.info(feature: "도구", "앱 내 엔진 채널 발견: \(key)")
                                }
                                for event in Self.events(from: chunk, toolChannel: toolChannel) {
                                    continuation.yield(event)
                                }
                            }
                            Self.logStreamDone()
                            // T-311 근본원인: 정상 완료 시 finish를 빼먹으면 AsyncThrowingStream이
                            // 끝나지 않아 소비 루프가 영원히 대기한다 (무한 "응답중").
                            continuation.finish()
                            return
                        } catch {
                            // T-289: 취소는 재시도 없이 즉시 전파
                            if error is CancellationError { throw error }
                            Self.logStreamError(error)
                            // 실패한 대화는 풀에서 제거 (오염 루프 방지).
                            // 시작 실패가 아니면 재시도 없이 전파 — 다음 전송(재시도 버튼)이 새로 만든다.
                            invalidateReuse()
                            guard allowReuse, setup.reused, Self.isStartStreamFailure(error) else { throw error }
                            DebugLogger.shared.info(feature: "앱내엔진", "재사용 시작 실패 → 새 대화 재시도")
                            allowReuse = false
                        }
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: EngineError.inferenceFailed("\(error)"))
                }
            }
        }
    }

    /// 세션 대화 제거: 해당 모델+방의 풀 항목 삭제 (옵션 무관).
    /// 재시도(꼬리 제거 후 재생성)·1회성 호출 정리에 사용.
    func evictSession(modelID: String, sessionID: String) {
        conversations = conversations.filter {
            !($0.key.modelID == modelID && $0.key.sessionID == sessionID)
        }
        conversationAccessOrder.removeAll {
            $0.modelID == modelID && $0.sessionID == sessionID
        }
        if activeKey?.modelID == modelID && activeKey?.sessionID == sessionID {
            activeConversation = nil
            activeKey = nil
        }
    }

    /// 진행 중 추론 중단 (T-191, D2): 풀에 남은 끊긴 Conversation 재사용을 막기
    /// 위해 activeKey 세션을 먼저 제거하고 대화만 취소한다.
    func cancel() {
        if let key = activeKey {
            evictSession(modelID: key.modelID, sessionID: key.sessionID)
        }
        try? activeConversation?.cancel()
    }

    /// 재사용 무효화 (T-277): 시작 실패 시 새 대화로 재시도.
    /// 실패한 대화는 풀에서도 제거 — 깨진 KV/핸들이 남아 재시도마다 즉시 실패하는
    /// 오염 루프(INTERNAL state 7 등) 방지. 다음 전송은 새로 생성해 복구한다.
    func invalidateReuse() {
        if let key = activeKey {
            evictSession(modelID: key.modelID, sessionID: key.sessionID)
        }
        activeConversation = nil
        activeKey = nil
    }

    /// 대화용 도구 목록 (순수, 테스트 가능, T-290): 미지원 모델은 빈 배열.
    nonisolated static func toolsForConversation(supportsFC: Bool,
                                                 registered: [any Tool]) -> [any Tool] {
        supportsFC ? registered : []
    }

    /// 시작 실패 판정 (순수, 테스트 가능, T-277): 재사용 핸들 거부일 때만 재시도.
    nonisolated static func isStartStreamFailure(_ error: Error) -> Bool {
        guard let lite = error as? LiteRTLMError,
              case .conversation(.failedToStartStream) = lite else { return false }
        return true
    }

    /// 스트림 정상 종료 계측 (T-311 진단): 소비 루프가 마지막 청크에 도달했는지 구분.
    nonisolated static func logStreamDone() {
        DebugLogger.shared.info(feature: "앱내엔진", "엔진 스트림 정상 종료(마지막 청크 도달)")
    }

    /// 스트림 오류 계측 (T-311 진단): 실패 원인 문자열을 DebugPanel에 남긴다.
    nonisolated static func logStreamError(_ error: Error) {
        DebugLogger.shared.error(code: "E-MAC-ENG-0006", feature: "앱내엔진",
                                 "엔진 스트림 오류: \(error)")
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
