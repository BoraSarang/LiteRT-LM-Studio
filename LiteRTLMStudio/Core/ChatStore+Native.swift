import Foundation

/// 앱 내 엔진 이벤트 누적 상태 (T-266 S-1, 순수·테스트 가능).
struct NativeStreamState: Sendable {
    var acc = ""
    var thinkingAcc = ""
    var tools: [ToolCallRecord] = []

    /// 표시용 생각 (빈 문자열은 nil 취급을 호출 측에서).
    var thinking: String? { thinkingAcc.isEmpty ? nil : thinkingAcc }

    /// 이벤트 1건 누적. 도구 호출이면 표시 갱신용 레코드 반환.
    mutating func apply(_ event: StreamEvent) -> ToolCallRecord? {
        switch event {
        case .text(let chunk):
            acc += chunk
        case .thinking(let chunk):
            thinkingAcc += chunk
        case .toolCall(let rec):
            if let idx = tools.firstIndex(where: { $0.callID == rec.callID }) {
                tools[idx] = rec
            } else {
                tools.append(rec)
            }
            return rec
        }
        return nil
    }
}

/// 앱 내 엔진 전송 확장 (T-130): 분기·토큰·실패 매핑.
extension ChatStore {
    /// 앱 내 엔진 분기 판정 (T-130, 테스트 가능): 선택 경로+주입 모두 필요.
    /// T-186부터 전역 설정 대신 입력창 route를 본다.
    func usesNative() -> Bool {
        route == .native && inferenceEngine != nil
    }

    /// 경로별 전송 가능 (순수, 테스트 가능, T-186).
    /// CLI는 데몬 실행, 앱 내 엔진는 엔진 준비가 각각 필요.
    nonisolated static func routeReady(route: EngineMode, daemonRunning: Bool,
                                       nativePrepared: Bool) -> Bool {
        switch route {
        case .cli: daemonRunning
        case .native: nativePrepared
        }
    }

    /// 전송 가능 판정 (순수, 테스트 가능, T-146): 스트리밍 중 제외,
    /// 데몬 실행 중 또는 앱 내 엔진 준비. CLI 모드(nativeReady=false)는 기존 조건과 동일.
    nonisolated static func sendAllowed(streaming: Bool, daemonRunning: Bool, nativeReady: Bool) -> Bool {
        !streaming && (daemonRunning || nativeReady)
    }

    /// 첫 토큰 기록 (T-130, CLI·앱 내 엔진 공용): preparing 해제+TTFT 로그.
    func noteFirstToken(started: Date) {
        preparing = false
        let ttft = Date().timeIntervalSince(started)
        logger.perf(feature: "채팅전송", "첫 토큰 TTFT=\(String(format: "%.1f", ttft))s")
    }

    /// 앱 내 엔진 전송 (T-130): prepare → 스트림 소비. 완료·PERF·중단 골격은 CLI와 동일.
    func runNative(engine: any InferenceEngine, prompt: String,
                   image: ChatImage?, idx: Int, started: Date) async {
        do {
            try await engine.prepare(modelID: model)
            // T-190 TTFT 구간 분리: prepare cost vs (대화 생성+프리필) cost.
            let prepareElapsed = Date().timeIntervalSince(started)
            // T-149: 전송 범위 설정 적용 (제한 없음이면 전량, 기존 동작).
            // 재사용 키는 방ID 고정 — 같은 방의 후속 턴은 동일 Conversation을
            // 이어써 KV를 잇는다 (히스토리 길이에 무관).
            let windowed = Self.windowedHistory(Array(messages.dropLast(2)),
                                                turns: HistoryWindow.currentTurns())
            let past = windowed.map { (role: $0.role, text: $0.text) }
            let histChars = past.reduce(0) { $0 + $1.text.count }
            logger.perf(feature: "채팅전송",
                        "준비 완료 \(String(format: "%.1f", prepareElapsed))s "
                            + "히스토리 \(past.count)개 \(histChars)자")
            let stream = engine.streamEvents(prompt: prompt, image: image,
                                                   history: Array(past),
                                                   options: generationOptions(),
                                                   sessionID: currentSessionID?.uuidString ?? "")
            var state = NativeStreamState()
            var firstTokenAt: Date?
            var lastFlush = started
            for try await event in stream {
                if Task.isCancelled { break }
                if firstTokenAt == nil {
                    firstTokenAt = Date()
                    self.noteFirstToken(started: started)
                }
                consumeNativeEvent(event, state: &state, idx: idx,
                                   lastFlush: &lastFlush, started: started)
            }
            // T-289: 취소로 빠졌으면 완료 확정 금지 (중단 상태 유지).
            if Task.isCancelled { return }
            await finishNative(at: idx, state: state, started: started)
        } catch is CancellationError {
            logger.info(feature: "채팅중단", "사용자 중단")
        } catch {
            if Task.isCancelled {
                logger.info(feature: "채팅중단", "사용자 중단")
            } else {
                // T-282 진단: 관측 가능값 (메시지 수·도구 턴 수).
                let toolTurns = messages.filter { !($0.toolCalls?.isEmpty ?? true) }.count
                logger.info(feature: "채팅전송",
                            "실패 맥락 messages=\(messages.count) 도구턴=\(toolTurns)")
                self.nativeFailed(at: idx, error: error)
            }
        }
        preparing = false
        streaming = false
        save()
    }

    /// 스트리밍 이벤트 1건 반영 (T-282 분리): 누적+호출 표시+묶음 반영.
    func consumeNativeEvent(_ event: StreamEvent, state: inout NativeStreamState, idx: Int,
                            lastFlush: inout Date, started: Date) {
        if let rec = state.apply(event) {
            messages[idx].toolCalls = state.tools
            logger.info(feature: "도구", "앱 내 엔진 호출: \(rec.name)")
        }
        // T-148: 0.1초 묶음 갱신 (토큰당 전체 리렌더 방지). 종료 후 최종 반영.
        if Self.shouldFlushText(now: Date(), lastFlush: lastFlush) {
            flushText(idx: idx, acc: state.acc, thinkingAcc: state.thinkingAcc)
            lastFlush = Date()
        }
    }

    /// 앱 내 엔진 완료 반영 (T-266 분리): 본문·PERF·시각 확정.
    /// T-266 S-2: 원장 배출로 도구 상태·결과 반영 (순서 매칭).
    /// T-282: 최종 flush+칩 확정도 담당 (호출부 길이 관리).
    func finishNative(at idx: Int, state: NativeStreamState, started: Date) async {
        flushText(idx: idx, acc: state.acc, thinkingAcc: state.thinkingAcc, final: true)
        messages[idx].toolCalls = state.tools.isEmpty ? nil : state.tools
        let outcomes = await ToolLedger.shared.drain(since: started)
        if !outcomes.isEmpty, var calls = messages[idx].toolCalls {
            let states = ToolLedger.statuses(count: calls.count, outcomes: outcomes)
            for i in calls.indices {
                calls[i].status = states[i]
                if i < outcomes.count {
                    calls[i].result = String(outcomes[i].result.prefix(100))
                }
            }
            messages[idx].toolCalls = calls
            logger.info(feature: "도구", "실행 반영 \(outcomes.count)건")
        }
        let elapsed = Date().timeIntervalSince(started)
        messages[idx].perf = Self.perfLine(chars: state.acc.count, elapsed: elapsed)
        messages[idx].finishedAt = Date() // T-077 완료 시각 기록
        logger.perf(feature: "채팅전송", "완료 elapsed=\(String(format: "%.1f", elapsed))s chars=\(state.acc.count)")
    }

    /// 앱 내 엔진 실패 반영 (T-130): EngineError 코드 매핑.
    func nativeFailed(at idx: Int, error: Error) {
        let code = (error as? EngineError)?.code ?? EngineError.inferenceFailed("").code
        lastError = code
        messages[idx].text = code == EngineError.initFailed("").code
            ? "엔진 초기화에 실패했습니다. 모델 파일과 메모리를 확인해 주세요. (E-MAC-ENG-0001)"
            : "앱 내 엔진 추론에 실패했습니다. 다른 엔진 모드로 바꿔 다시 시도해 주세요. (E-MAC-ENG-0002)"
        messages[idx].isError = true
        messages[idx].finishedAt = Date()
        logger.error(code: code, feature: "채팅전송", "\(error)")
    }

}
