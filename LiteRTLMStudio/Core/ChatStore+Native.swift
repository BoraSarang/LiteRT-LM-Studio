import Foundation

/// 1회 실행 마커 (T-311): 스톨 강제 마무리와 정상 종료가 겹치면 중복 완료·저장 방지.
@MainActor
final class OnceMarker {
    private var ran = false
    func run(_ body: () -> Void) {
        guard !ran else { return }
        ran = true
        body()
    }
}

/// 진행 문자 수 공유 셀 (T-311): 스톨 발화 시점에 누적량을 로그로 남기기 위한 관측용.
final class ProgressCell {
    var chars = 0
    var thinking = 0
}

/// 응답 스트림 진행 게이트 (순수, 테스트 가능, T-311): 토큰마다 시계를 리셋하고,
/// idle초 이상 진행이 없으면 1회 발화한다 (엔진 스톨을 무한 "응답중" 대신 명확한 실패로).
final class StreamProgressGate {
    let idleLimit: TimeInterval
    private let now: () -> Date
    private var lastProgress: Date
    private var fired = false

    init(idleLimit: TimeInterval, now: @escaping () -> Date = Date.init) {
        self.idleLimit = idleLimit
        self.now = now
        self.lastProgress = now()
    }

    /// 진행 발생 (토큰 1건마다 호출).
    func tic() { lastProgress = now() }

    /// idle 초과 여부 (1회 발화 후 계속 true, 병합 처리용).
    func isStalled() -> Bool {
        if !fired, now().timeIntervalSince(lastProgress) > idleLimit { fired = true }
        return fired
    }
}

/// 앱 내 엔진 이벤트 누적 상태 (T-266 S-1, 순수·테스트 가능).
struct NativeStreamState: Sendable {
    var acc = ""
    var thinkingAcc = ""
    var tools: [ToolCallRecord] = []
    var eventCount = 0

    /// 표시용 생각 (빈 문자열은 nil 취급을 호출 측에서).
    var thinking: String? { thinkingAcc.isEmpty ? nil : thinkingAcc }

    /// 이벤트 1건 누적. 도구 호출이면 표시 갱신용 레코드 반환.
    mutating func apply(_ event: StreamEvent) -> ToolCallRecord? {
        eventCount += 1
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
    /// 첫터치 프리필 토글 저장 키 (T-302): @AppStorage(SettingsView)와 동일.
    nonisolated static var prefillWarmupKey: String { "prefillWarmup" }

    /// 응답 스톨 워치독 무진행 한계 (T-311): 토큰 없이 60초면 중단.
    nonisolated static var stallIdleLimit: TimeInterval { 60 }

    /// 예열 실행 판정 (순수, 테스트 가능, T-302).
    /// 이미 대상 모델이 준비됨(alreadyPrepared)·스트리밍·진행 중이면 false.
    nonisolated static func warmupWanted(enabled: Bool, nativeRoute: Bool,
                                         alreadyPrepared: Bool,
                                         streaming: Bool, warming: Bool) -> Bool {
        enabled && nativeRoute && !alreadyPrepared && !streaming && !warming
    }

    /// 방 열람 예열 (T-302): currentSessionID didSet에서 자동 호출.
    /// 엔진 init(1~2s)을 전송 전에 선소비해 첫 턴 준비 구간을 제거.
    /// 방 대화 프리필은 옵션 확정 전이라 키 불일치 위험 → prepare 선행까지만.
    /// 실패는 조용히 로그만 (사용자 흐름 무방해, E-MAC-PERF-0001).
    func warmupForNextSend() {
        guard let engine = inferenceEngine else { return }
        guard Self.warmupWanted(enabled: prefillWarmupEnabled,
                                nativeRoute: usesNative(),
                                alreadyPrepared: engine.preparedModelID == model,
                                streaming: streaming,
                                warming: warmupTask != nil) else { return }
        logger.info(feature: "프리필", "방 열람 예열 시작 model=\(model)")
        warmupTask = Task { [weak self] in
            let started = Date()
            guard let self else { return }
            do {
                try await engine.prepare(modelID: self.model)
                let elapsed = Date().timeIntervalSince(started)
                self.logger.perf(feature: "프리필", "예열 완료 \(String(format: "%.1f", elapsed))s")
            } catch is CancellationError {
            } catch {
                self.logger.error(code: "E-MAC-PERF-0001", feature: "프리필", "예열 실패: \(error)")
            }
            self.warmupTask = nil
        }
    }

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
    /// T-311: C++ 스트림 종료를 신뢰하지 않는 강제 마무리 — 무진행 60초 시 워치독이
    /// 직접 실패 전환·플래그 해제·저장까지 수행한다 (무한 "응답중" 방지).
    func runNative(engine: any InferenceEngine, prompt: String,
                   image: ChatImage?, idx: Int, started: Date) async {
        let gate = StreamProgressGate(idleLimit: Self.stallIdleLimit)
        let once = OnceMarker()
        let progress = ProgressCell()
        let watch = stallWatch(engine: engine, gate: gate, once: once,
                               progress: progress, idx: idx)
        do {
            try await engine.prepare(modelID: model)
            // T-190 TTFT 구간 분리: prepare cost vs (대화 생성+프리필) cost.
            let prepareElapsed = Date().timeIntervalSince(started)
            // T-149: 전송 범위 설정 적용 (제한 없음이면 전량, 기존 동작).
            // 재사용 키는 방ID 고정 — 같은 방의 후속 턴은 동일 Conversation을
            // 이어써 KV를 잇는다 (히스토리 길이에 무관).
            let past = pastTurns().map { (role: $0.role, text: $0.text) }
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
            var lastLog = started
            for try await event in stream {
                if Task.isCancelled { break }
                gate.tic()
                if firstTokenAt == nil {
                    firstTokenAt = Date()
                    self.noteFirstToken(started: started)
                }
                consumeNativeEvent(event, state: &state, idx: idx,
                                   lastFlush: &lastFlush, started: started)
                progress.chars = state.acc.count
                progress.thinking = state.thinkingAcc.count
                Self.logDecodeProgress(logger: logger, state: state,
                                       started: started, lastLog: &lastLog)
            }
            logger.info(feature: "앱내엔진",
                        "소비 루프 종료 (이벤트 \(state.eventCount)건, chars=\(state.acc.count))")
            watch.cancel()
            // T-289: 취소로 빠졌으면 완료 확정 금지 (중단 상태 유지).
            if Task.isCancelled {
                once.run { self.endRun() }
                return
            }
            await finishNative(at: idx, state: state, started: started)
            once.run { self.endRun() }
        } catch {
            watch.cancel()
            handleNativeError(error, idx: idx, gate: gate)
            once.run { self.endRun() }
        }
    }

    /// 전송 마무리 (T-311 분리): 스트리밍 플래그 해제+저장 (1회 보장).
    private func endRun() {
        preparing = false
        streaming = false
        save()
    }

    /// 디코드 진행 로그 (T-311 진단): 2초 간격·누적 글자 수 — 느림vs멈춤 구분.
    nonisolated static func logDecodeProgress(logger: DebugLogger, state: NativeStreamState,
                                              started: Date, lastLog: inout Date) {
        guard Date().timeIntervalSince(lastLog) >= 2 else { return }
        lastLog = Date()
        let elapsed = Date().timeIntervalSince(started)
        logger.info(feature: "디코드",
                    "진행 중 chars=\(state.acc.count) think=\(state.thinkingAcc.count) "
                        + "elapsed=\(String(format: "%.1f", elapsed))s")
    }

    /// 진행 워치독 (T-311): 1초 폴링, 무진행 한계 도달 시 엔진 중단.
    /// C++ 스트림이 중단에 응답하지 않아도 강제로 실패 전환을 완료한다 (1회).
    private func stallWatch(engine: any InferenceEngine, gate: StreamProgressGate,
                            once: OnceMarker, progress: ProgressCell,
                            idx: Int) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if gate.isStalled() {
                    self.logger.error(code: "E-MAC-ENG-0005", feature: "채팅전송",
                                      "응답이 \(Int(gate.idleLimit))초간 진행 없음: "
                                          + "chars=\(progress.chars) think=\(progress.thinking) — 강제 중단")
                    engine.cancel()
                    once.run {
                        self.nativeFailed(at: idx, error: EngineError.timeout(""))
                        self.endRun()
                    }
                    return
                }
            }
        }
    }

    /// 네이티브 실패 확정 (T-311 분리): 스톨·사용자 중단·실패 구분.
    private func handleNativeError(_ error: Error, idx: Int, gate: StreamProgressGate) {
        if gate.isStalled() {
            logger.info(feature: "채팅중단", "응답 멈춤 워치독 발화")
            nativeFailed(at: idx, error: EngineError.timeout(""))
        } else if error is CancellationError || Task.isCancelled {
            logger.info(feature: "채팅중단", "사용자 중단")
        } else {
            // T-282 진단: 관측 가능값 (메시지 수·도구 턴 수).
            let toolTurns = messages.filter { !($0.toolCalls?.isEmpty ?? true) }.count
            logger.info(feature: "채팅전송",
                        "실패 맥락 messages=\(messages.count) 도구턴=\(toolTurns)")
            nativeFailed(at: idx, error: error)
        }
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
        if code == EngineError.initFailed("").code {
            messages[idx].text = "엔진 초기화에 실패했습니다. 모델 파일과 메모리를 확인해 주세요. (E-MAC-ENG-0001)"
        } else if code == EngineError.timeout("").code {
            // T-311: 스톨 워치독 — 무한 "응답중" 방지.
            messages[idx].text = "응답 생성이 멈춰 중지했습니다. 다시 시도해 주세요. (E-MAC-ENG-0005)"
        } else {
            messages[idx].text = "앱 내 엔진 추론에 실패했습니다. 다른 엔진 모드로 바꿔 다시 시도해 주세요. (E-MAC-ENG-0002)"
        }
        messages[idx].isError = true
        messages[idx].finishedAt = Date()
        logger.error(code: code, feature: "채팅전송", "\(error)")
    }

}
