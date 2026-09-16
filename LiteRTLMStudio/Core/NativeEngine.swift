import Foundation

/// SPM LiteRTLM 네이티브 엔진 (T-130). 프로세스 내 추론, 모델당 Engine 1개.
/// LiteRTLM Swift 소스는 앱 타깃 직접 포함 (EngineVendor는 바이너리만).
@MainActor
final class NativeEngine: InferenceEngine, ObservableObject {
    /// 수명주기 상태 (T-185): 사이드바 실행/중지/다시 실행 버튼 표시용.
    enum State: Equatable {
        case idle // 미초기화
        case preparing // 준비 중
        case ready // 준비됨 (preparedModelID 병행)
        case failed // 준비 실패 (lastError 병행)
    }

    private var engine: Engine?
    @Published private(set) var preparedModelID: String?
    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String?
    private var activeConversation: Conversation?
    /// 재사용 키 (T-191): live conversation을 만든 시점의 모델+히스토리+옵션.
    private var activeKey: ConvKey?

    /// 대화 재사용 키 (T-191): 저장분이 현재 앞부분이면 KV 이어쓰기, 프리필 생략.
    struct ConvKey: Equatable {
        var modelID: String
        var history: [String]
        var options: GenerationOptions

        /// 접두사 재사용 판정 (순수, 테스트 가능, T-191).
        nonisolated static func reuses(stored: ConvKey, modelID: String,
                                       history: [String], options: GenerationOptions) -> Bool {
            stored.modelID == modelID && stored.options == options
                && history.count >= stored.history.count
                && Array(history.prefix(stored.history.count)) == stored.history
        }

        /// 히스토리 키 항목 (순수, 테스트 가능, T-191): 역할+본문 결합.
        nonisolated static func entries(_ history: [(role: String, text: String)]) -> [String] {
            history.map { "\($0.role)\n\($0.text)" }
        }
    }
    private let logger = DebugLogger.shared
    private static var flagsInstalled = false

    /// 모델 파일 경로. `~/.litert-lm/models` 읽기 전용 참조 (AGENTS.local).
    nonisolated static func modelPath(for modelID: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".litert-lm/models/\(modelID)/model.litertlm").path
    }

    /// 컴파일 캐시 경로 (재부팅 콜드 방지, Application Support 고정).
    nonisolated static func engineCacheDir() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LiteRTLMStudio/EngineCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// 엔진 백엔드 묶음 (T-177): config.json 추종 결과.
    struct EngineBackends: Equatable {
        var backend: Backend = .gpu
        var vision: Backend? = .cpu()
        var audio: Backend?
    }

    /// config.json 추종 백엔드 (순수, 테스트 가능, T-177): default 섹션 읽기.
    /// 실패·미기재 시 기존 고정값 (.gpu/.cpu()/nil). npu 등 미지원은 gpu로 폴백.
    nonisolated static func resolveBackends(configURL: URL) -> EngineBackends {
        func parsed(_ s: String?, threads: Int?) -> Backend? {
            switch s {
            case "cpu": .cpu(threadCount: threads)
            case "gpu": .gpu
            default: nil
            }
        }
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let def = json["default"] as? [String: Any] else {
            return EngineBackends()
        }
        let threads = def["cpu_thread_count"] as? Int
        return EngineBackends(
            backend: parsed(def["backend"] as? String, threads: threads) ?? .gpu,
            vision: parsed(def["vision_backend"] as? String, threads: nil),
            audio: parsed(def["audio_backend"] as? String, threads: nil))
    }

    /// Metal residency (T-177): 미설정 시 켬 (Gallery 동일).
    nonisolated static func residencyEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "metalResidency") as? Bool ?? true
    }

    /// Visual 예산 (T-177): 미설정 시 1120 (describe 상한, Gemma4 5단 중 최대).
    nonisolated static func visualBudget(_ defaults: UserDefaults = .standard) -> Int32 {
        Int32(defaults.object(forKey: "visualTokenBudget") as? Int ?? 1120)
    }

    func prepare(modelID: String) async throws {
        if preparedModelID == modelID, engine != nil { return }
        release()
        state = .preparing
        lastError = nil
        Self.installFlags()
        // MTP는 모델 메타데이터로 자체 판정 (T-130, describe 불필요).
        let mtp = Capabilities(modelPath: Self.modelPath(for: modelID))?
            .hasSpeculativeDecodingSupport() ?? false
        ExperimentalFlags.enableSpeculativeDecoding = mtp
        ExperimentalFlags.gpuEnableMetalResidencySet = Self.residencyEnabled()
        ExperimentalFlags.visualTokenBudget = Self.visualBudget()
        let resolved = Self.resolveBackends(configURL: ConfigStore.defaultURL)
        let config: EngineConfig
        do {
            config = try EngineConfig(modelPath: Self.modelPath(for: modelID),
                                      backend: resolved.backend,
                                      visionBackend: resolved.vision,
                                      audioBackend: resolved.audio,
                                      cacheDir: Self.engineCacheDir())
        } catch {
            throw EngineError.initFailed("\(error)")
        }
        let engine = Engine(engineConfig: config)
        let started = Date()
        do {
            try await engine.initialize()
        } catch {
            state = .failed
            lastError = EngineError.initFailed("").code
            throw EngineError.initFailed("\(error)")
        }
        let secs = Date().timeIntervalSince(started)
        logger.perf(feature: "네이티브엔진", "\(modelID) 초기화 \(String(format: "%.1f", secs))s")
        self.engine = engine
        preparedModelID = modelID
        state = .ready
    }

    func release() {
        activeConversation = nil
        activeKey = nil
        engine = nil
        preparedModelID = nil
        state = .idle
    }

    /// 다시 실행 (T-185): 반납 후 처음부터 준비. 동일 모델 early-return 우회용.
    func restart(modelID: String) async throws {
        release()
        try await prepare(modelID: modelID)
    }

    func stream(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        keyHistory: [String],
        options: GenerationOptions
    ) -> AsyncThrowingStream<String, Error> {
        guard let engine else {
            return AsyncThrowingStream { $0.finish(throwing: EngineError.notReady) }
        }
        // T-193: 재사용 판정은 전체 전사 키로 (윈도우 슬라이드와 무관).
        let keyEntries = keyHistory
        let mid = preparedModelID ?? ""
        let past = history.map { turn in
            Message(turn.text, role: turn.role == "user" ? .user : .model)
        }
        let message: Message
        if let image {
            message = Message(contents: [
                Content.imageData(image.data),
                Content.text(prompt)
            ])
        } else {
            message = Message(prompt)
        }
        // 캡처값은 Sendable (String·Double·배열) — actor 격리 충돌 없음.
        let opts = options
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let setup = try await self.preparedStream(
                        engine: engine, modelID: mid, past: past,
                        entries: keyEntries, opts: opts)
                    let gen = setup.conversation.sendMessageStream(
                        message, maxOutputTokens: opts.maxTokens, thinkingConfig: setup.thinking)
                    for try await chunk in gen {
                        continuation.yield(chunk.toString)
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

    /// 스트림 준비물 (T-191 분리): 샘플러 묶음 + 대화 (재사용 시 live, 아니면 생성).
    private func preparedStream(engine: Engine, modelID: String, past: [Message],
                                entries: [String], opts: GenerationOptions)
    async throws -> (conversation: Conversation, thinking: ThinkingConfig?) {
        let sampler = try SamplerConfig(
            topK: opts.topK, topP: Float(opts.topP),
            temperature: Float(opts.temperature), seed: opts.seed ?? 0)
        let sysMsg = opts.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let thinking: ThinkingConfig? = opts.thinkingEnabled
            ? ThinkingConfig(enableThinking: true,
                             thinkingTokenBudget: opts.thinkingBudget) : nil
        if let live = reusableConversation(modelID: modelID, history: entries, options: opts) {
            logger.info(feature: "네이티브엔진", "대화 재사용 (KV 이어쓰기)")
            return (live, thinking)
        }
        let conversation = try await engine.createConversation(
            with: ConversationConfig(
                systemMessage: sysMsg.isEmpty ? nil : Message(sysMsg, role: .system),
                initialMessages: past,
                samplerConfig: sampler,
                thinkingConfig: thinking))
        activeConversation = conversation
        activeKey = ConvKey(modelID: modelID, history: entries, options: opts)
        return (conversation, thinking)
    }

    /// 재사용 대화 확정 (T-191 분리): 저장 키가 현재와 접두사 일치면 live.
    private func reusableConversation(modelID: String, history: [String],
                                      options: GenerationOptions) -> Conversation? {
        guard let live = activeConversation, let key = activeKey,
              ConvKey.reuses(stored: key, modelID: modelID,
                             history: history, options: options)
        else { return nil }
        return live
    }

    func cancel() {
        // T-191: 중단 시 KV/본문 어긋남 가능 → 다음 전송은 새로 생성.
        activeKey = nil
        try? activeConversation?.cancel()
    }

    /// 벤치마크 측정 (T-132): 고정 프롬프트 1턴 실측 후 BenchmarkInfo 매핑.
    /// CLI `benchmark`(256/256 고정)와 조건이 달라 근사 비교용.
    func benchmark(modelID: String) async throws -> EngineBenchmark {
        try await benchmarkWithProgress(modelID: modelID, onStage: { _ in })
    }

    /// 벤치마크 측정 + 진행 알림 (T-216): prepare→측정→정리 단계를 콜백으로 전달.
    /// 오버로드 대신 별도 이름 (동명 오버로드가 타입 추론을 무겁게 함).
    func benchmarkWithProgress(modelID: String,
                               onStage: @escaping (BenchmarkPhase) -> Void) async throws -> EngineBenchmark {
        onStage(.preparing)
        try await prepare(modelID: modelID)
        guard let engine else { throw EngineError.notReady }
        do {
            let conversation = try await engine.createConversation()
            activeConversation = conversation
            activeKey = nil // T-191: 벤치가 대화를 가로채면 다음 채팅은 새로 생성.
            onStage(.measuring)
            let prompt = Message("Describe Seoul in three sentences.")
            for try await _ in conversation.sendMessageStream(prompt) {
                try Task.checkCancellation()
            }
            onStage(.summarizing)
            let info = try conversation.getBenchmarkInfo()
            logger.perf(feature: "네이티브벤치",
                        "완료 prefill=\(info.lastPrefillTokensPerSecond) decode=\(info.lastDecodeTokensPerSecond)")
            return EngineBenchmark(
                initTime: info.initTimeInSecond,
                ttft: info.timeToFirstTokenInSecond,
                prefillTokens: info.lastPrefillTokenCount,
                prefillSpeed: info.lastPrefillTokensPerSecond,
                decodeTokens: info.lastDecodeTokenCount,
                decodeSpeed: info.lastDecodeTokensPerSecond
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EngineError.inferenceFailed("\(error)")
        }
    }

    /// 실험 플래그 1회 설치 (MTP·벤치마크).
    private static func installFlags() {
        guard !flagsInstalled else { return }
        flagsInstalled = true
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableBenchmark = true
    }
}
