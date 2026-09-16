import Foundation

/// SSE 스트림 누적 확장 (T-266 분리: ChatStore 본문 길이 관리).
/// T-148 한 줄 적용 + T-266 생각·도구 델타 누적.
extension ChatStore {
    /// SSE 스트림 누적 상태 (T-148): 한 줄 적용 호출 간 전달용 묶음.
    /// T-266: 생각·도구 호출 누적 추가.
    struct SSEStreamState {
        var acc = ""
        var thinkingAcc = ""
        var toolAcc = ToolCallAccumulator()
        var firstTokenAt: Date?
        var lastFlush = Date.distantPast
    }

    /// SSE 한 줄 적용 (T-148 분리): 델타 누적+첫 토큰 기록+0.1초 묶음 반영.
    /// T-266: 본문 외에 thinking·tool_calls 델타도 누적.
    /// - Returns: 스트림 종료 여부 (취소 또는 DONE).
    func applySSELine(_ line: String, state: inout SSEStreamState, idx: Int, started: Date) -> Bool {
        if Task.isCancelled { return true }
        if let data = ChatSSEParser.payloadData(from: line),
           let delta = ToolChunkParser.parseDelta(data) {
            applyToolDelta(delta, state: &state, idx: idx, started: started)
        }
        guard let content = ChatSSEParser.content(from: line) else {
            return ChatSSEParser.isDone(line)
        }
        if state.firstTokenAt == nil {
            state.firstTokenAt = Date()
            noteFirstToken(started: started)
        }
        state.acc += content
        if Self.shouldFlushText(now: Date(), lastFlush: state.lastFlush) {
            messages[idx].text = state.acc
            messages[idx].thinking = state.thinkingAcc.isEmpty ? nil : state.thinkingAcc
            state.lastFlush = Date()
        }
        return false
    }

    /// 도구·생각 델타 반영 (T-266): 누적+드문 갱신은 즉시 (조각 빈도 낮음).
    func applyToolDelta(_ delta: ChatToolDelta, state: inout SSEStreamState, idx: Int, started: Date) {
        let (event, thinking) = state.toolAcc.apply(delta: delta)
        if let thinking, !thinking.isEmpty {
            if state.firstTokenAt == nil {
                state.firstTokenAt = Date()
                noteFirstToken(started: started)
            }
            state.thinkingAcc += thinking
            messages[idx].thinking = state.thinkingAcc
        }
        if event != nil {
            messages[idx].toolCalls = ServerToolHistory.merged(
                messages[idx].toolCalls ?? [], with: state.toolAcc.finalized())
        }
        if state.toolAcc.finishReason == "tool_calls" {
            logger.info(feature: "도구", "호출 감지 \(state.toolAcc.finalized().count)건")
        }
    }

    /// 서버 멀티턴 전송 (T-268 S-3): tool_calls 종료 시 로컬 실행 후 재전송, 최대 3턴.
    /// messages[]는 user/assistant만 유지, tool 턴은 요청 히스토리에만 포함.
    func runServerTurns(prompt: String, image: ChatImage?, idx: Int, started: Date) async throws {
        var state = SSEStreamState(lastFlush: started)
        var extraHistory: [[String: Any]] = []
        var turn = 0
        while true {
            try Task.checkCancellation()
            let req = try chatRequest(prompt: prompt, image: image, extraHistory: extraHistory)
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            for try await line in bytes.lines where !applySSELine(
                line, state: &state, idx: idx, started: started) {
            }
            flushTurn(state: state, idx: idx)
            let calls = state.toolAcc.finalized()
            guard state.toolAcc.finishReason == "tool_calls",
                  !calls.isEmpty, turn < ServerToolHistory.maxTurns else { break }
            turn += 1
            let turnStart = Date()
            extraHistory.append(ServerToolHistory.assistantMessage(calls: calls))
            for call in calls {
                extraHistory.append(ServerToolHistory.toolMessage(
                    callID: call.callID, content: await executeServerTool(call)))
            }
            let outcomes = await ToolLedger.shared.drain(since: turnStart)
            mergeToolOutcomes(idx: idx, calls: calls, outcomes: outcomes)
            state.toolAcc = ToolCallAccumulator()
            logger.info(feature: "도구", "서버 \(turn)턴 재전송 (\(calls.count)건 실행)")
        }
    }

    /// 턴 종료 반영 (T-268): 본문·생각·칩 확정.
    func flushTurn(state: SSEStreamState, idx: Int) {
        messages[idx].text = state.acc
        messages[idx].thinking = state.thinkingAcc.isEmpty ? nil : state.thinkingAcc
        let fresh = state.toolAcc.finalized()
        if !fresh.isEmpty {
            messages[idx].toolCalls = ServerToolHistory.merged(
                messages[idx].toolCalls ?? [], with: fresh)
        }
    }

    /// 서버 도구 1건 실행 (T-268): 승인 게이트+원장 기록은 runTolled가 담당.
    func executeServerTool(_ call: ToolCallRecord) async -> String {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            await ToolLedger.shared.record(toolName: call.name, detail: call.argumentsJSON,
                                           result: "인자 파싱 실패", denied: false, failed: true)
            return "인자 파싱 실패"
        }
        let result = await LocalTools.runTolled(toolName: call.name, detail: call.argumentsJSON) {
            try await ToolManager(tools: LocalTools.registered(permission: .allowAll))
                .execute(name: call.name, arguments: args)
        }
        if let text = result as? String { return text }
        return NativeEngine.jsonString(result)
    }

    /// 실행 결과 칩 반영 (T-268): 순서 매칭으로 상태·결과 부여.
    func mergeToolOutcomes(idx: Int, calls: [ToolCallRecord], outcomes: [ToolLedger.Entry]) {
        guard var current = messages[idx].toolCalls else { return }
        let states = ToolLedger.statuses(count: calls.count, outcomes: outcomes)
        for (i, call) in calls.enumerated() {
            guard let j = current.firstIndex(where: { $0.callID == call.callID }) else { continue }
            current[j].status = states[i]
            if i < outcomes.count {
                current[j].result = String(outcomes[i].result.prefix(100))
            }
        }
        messages[idx].toolCalls = current
    }
}
