import Foundation

/// 서버 무수신 타임아웃 (T-344, 파일 스코프): 워치독 발화 시 전송 실패로 전환.
struct ServerStallError: Error {}

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
            flushText(idx: idx, acc: state.acc, thinkingAcc: state.thinkingAcc)
            state.lastFlush = Date()
        }
        return false
    }

    /// 본문·추론 반영 (T-274/T-278): 인라인 <think> 분리 후 저장 (덮어쓰기라 중복 없음).
    /// final은 스트림 종료 시에만 (미닫힘 꼬리 답변 분리).
    func flushText(idx: Int, acc: String, thinkingAcc: String, final: Bool = false) {
        let split = ThinkTag.extract(acc, final: final)
        messages[idx].text = split.clean
        if split.thought.isEmpty {
            messages[idx].thinking = thinkingAcc.isEmpty ? nil : thinkingAcc
        } else if thinkingAcc.isEmpty {
            messages[idx].thinking = split.thought
        } else {
            messages[idx].thinking = split.thought + "\n" + thinkingAcc
        }
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
            let done = state.toolAcc.finalized()
            let names = done.map(\.name).joined(separator: ", ")
            logger.info(feature: "도구", "호출 감지 \(names) (\(done.count)건)")
        }
    }

    /// 서버 전송 실행 (T-345): 스톨 1회 자동 복구 포함 (본문 길이 관리로 Stream 분리).
    func runServerSend(prompt: String, image: ChatImage?, idx: Int, started: Date,
                       stallRetried: Bool = false) async {
        do {
            try await self.runServerTurns(prompt: prompt, image: image, idx: idx, started: started)
            let elapsed = Date().timeIntervalSince(started)
            let chars = messages[idx].text.count
            messages[idx].perf = Self.perfLine(chars: chars, elapsed: elapsed)
            messages[idx].finishedAt = Date() // T-077 완료 시각 기록
            logger.perf(feature: "채팅전송", "완료 elapsed=\(String(format: "%.1f", elapsed))s chars=\(chars)")
        } catch is CancellationError {
            logger.info(feature: "채팅중단", "사용자 중단")
        } catch is ServerStallError {
            guard !stallRetried, let restart = restartDaemon, await restart() else {
                self.requestTimedOut(at: idx)
                preparing = false
                streaming = false
                save()
                return
            }
            messages[idx].toolCalls = nil // 스톨 턴 부분 칩 제거 후 재전송
            messages[idx].thinking = nil
            logger.info(feature: "채팅전송", "스톨 복구 — 데몬 재시작 후 1회 재전송")
            await self.runServerSend(prompt: prompt, image: image, idx: idx,
                                     started: Date(), stallRetried: true)
        } catch {
            self.requestFailed(at: idx, error: error)
        }
        preparing = false
        streaming = false
        save()
    }

    /// 서버 멀티턴 전송 (T-268 S-3): tool_calls 종료 시 로컬 실행 후 재전송, 최대 3턴.
    /// messages[]는 user/assistant만 유지, tool 턴은 요청 히스토리에만 포함.
    /// T-343: 턴별 구간 타이밍+요청 크기 로그 (전체 TTFT와 분리 진단).
    func runServerTurns(prompt: String, image: ChatImage?, idx: Int, started: Date) async throws {
        var state = SSEStreamState(lastFlush: started)
        var extraHistory: [[String: Any]] = []
        var turn = 0
        // T-344: 서버 무수신 워치독 (네이티브 stallWatch 대응). 60초 무수신이면
        // 전송 태스크를 취소해 명확한 타임아웃 실패로 전환한다 (300초 방치 방지).
        let gate = StreamProgressGate(idleLimit: Self.stallIdleLimit)
        let watch = startServerWatch(gate: gate, myTask: currentTask)
        defer { watch.cancel() }
        do {
            while true {
                try Task.checkCancellation()
                let legStart = Date()
                let hadFirstToken = state.firstTokenAt != nil
                logTurnRequest(turn: turn, extraHistory: extraHistory)
                let req = try chatRequest(prompt: prompt, image: image, extraHistory: extraHistory)
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                for try await line in bytes.lines {
                    gate.tic()
                    if applySSELine(line, state: &state, idx: idx, started: started) { break }
                }
                flushTurn(state: state, idx: idx)
                // T-343 최종 답변 TTFT: guard보다 먼저 (텍스트 턴은 guard에서 break).
                if turn > 0, !hadFirstToken, let first = state.firstTokenAt {
                    logger.perf(feature: "채팅전송",
                                "최종 답변 TTFT=\(Self.elapsed(from: legStart, to: first))s (재전송 후)")
                }
                let calls = state.toolAcc.finalized()
                guard state.toolAcc.finishReason == "tool_calls",
                      !calls.isEmpty, turn < ServerToolHistory.maxTurns else { break }
                let names = calls.map(\.name).joined(separator: ", ")
                logger.perf(feature: "도구",
                            "\(turn + 1)턴 판단 \(Self.elapsed(from: legStart))s (\(names))")
                turn += 1
                _ = await runTurnCalls(calls, extraHistory: &extraHistory, idx: idx, turn: turn)
                state.toolAcc = ToolCallAccumulator()
                logger.info(feature: "도구", "서버 \(turn)턴 재전송 (\(names), \(calls.count)건 실행)")
            }
        } catch is CancellationError {
            if gate.isStalled() { throw ServerStallError() }
            throw CancellationError()
        }
        // T-278: 전체 종료 시 미닫힘 꼬리 답변 분리.
        flushText(idx: idx, acc: state.acc, thinkingAcc: state.thinkingAcc, final: true)
    }

    /// 서버 무수신 워치독 시작 (T-344 분리): 20초마다 대기 로그, 60초에 전송 취소.
    func startServerWatch(gate: StreamProgressGate,
                          myTask: Task<Void, Never>?) -> Task<Void, Never> {
        Task { [weak self] in
            var lastWarn = Date.distantPast
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let idle = gate.idle()
                if idle >= 20, Date().timeIntervalSince(lastWarn) >= 20 {
                    lastWarn = Date()
                    self.logger.info(feature: "채팅전송", "서버 응답 대기 중 (\(Int(idle))s 무수신)")
                }
                if gate.isStalled() {
                    self.logger.error(code: "E-MAC-NET-0006", feature: "채팅전송",
                                      "서버 \(Int(Self.stallIdleLimit))초 무수신 — 전송 중단")
                    myTask?.cancel()
                    return
                }
            }
        }
    }

    /// 도구 실행+원장 반영 (T-344 분리): 실행 결과 문자 수 반환.
    func runTurnCalls(_ calls: [ToolCallRecord], extraHistory: inout [[String: Any]],
                      idx: Int, turn: Int) async -> Int {
        let execStart = Date()
        extraHistory.append(ServerToolHistory.assistantMessage(calls: calls))
        var toolChars = 0
        for call in calls {
            let content = await executeServerTool(call)
            toolChars += content.count
            extraHistory.append(ServerToolHistory.toolMessage(
                callID: call.callID, content: content))
        }
        logger.perf(feature: "도구",
                    "\(turn)턴 실행 \(Self.elapsed(from: execStart))s 결과 \(toolChars)자")
        let outcomes = await ToolLedger.shared.drain(since: execStart)
        mergeToolOutcomes(idx: idx, calls: calls, outcomes: outcomes)
        return toolChars
    }

    /// 턴 요청 크기 로그 (순수 조회+기록, T-343): 히스토리·도구결과·도구 수.
    func logTurnRequest(turn: Int, extraHistory: [[String: Any]]) {
        let historyChars = pastTurns().reduce(0) { $0 + $1.text.count }
        let extraBytes = Self.jsonBytes(extraHistory)
        let toolCount = LocalTools.registered().count
        logger.info(feature: "채팅전송",
                    "\(turn + 1)턴 요청 히스토리 \(historyChars)자 "
                        + "도구결과 \(extraBytes)B 도구 \(toolCount)종")
    }

    /// 경과 초 포맷 (순수, T-343).
    nonisolated static func elapsed(from: Date, to: Date = Date()) -> String {
        String(format: "%.1f", to.timeIntervalSince(from))
    }

    /// JSON 바이트 수 (순수, T-343): 최상위 배열·객체가 아니면 0
    /// (NSJSONSerialization은 그 외에 NSException을 던져 try?로 못 잡음).
    nonisolated static func jsonBytes(_ value: Any) -> Int {
        guard value is [Any] || value is [String: Any] else { return 0 }
        return (try? JSONSerialization.data(withJSONObject: value))?.count ?? 0
    }

    /// 턴 종료 반영 (T-268): 본문·생각·칩 확정.
    func flushTurn(state: SSEStreamState, idx: Int, final: Bool = false) {
        flushText(idx: idx, acc: state.acc, thinkingAcc: state.thinkingAcc, final: final)
        let fresh = state.toolAcc.finalized()
        if !fresh.isEmpty {
            messages[idx].toolCalls = ServerToolHistory.merged(
                messages[idx].toolCalls ?? [], with: fresh)
        }
    }

    /// 서버 도구 1건 실행 (T-268): 승인 게이트+원장 기록은 각 도구 run() 내부
    /// runTolled가 1회 담당. 여기서 또 감싸면 팝업·원장이 2번 발생한다 (T-343).
    func executeServerTool(_ call: ToolCallRecord) async -> String {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            await ToolLedger.shared.record(toolName: call.name, detail: call.argumentsJSON,
                                           result: "인자 파싱 실패", denied: false, failed: true)
            return "인자 파싱 실패"
        }
        do {
            let result = try await ToolManager(tools: LocalTools.registered(permission: .allowAll))
                .execute(name: call.name, arguments: args)
            if let text = result as? String { return text }
            return NativeEngine.jsonString(result)
        } catch {
            await ToolLedger.shared.record(toolName: call.name, detail: call.argumentsJSON,
                                           result: "도구 실행 실패: \(error.localizedDescription)",
                                           denied: false, failed: true)
            return "도구 실행 실패: \(error.localizedDescription)"
        }
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
