import Foundation

/// SPM LiteRTLM 네이티브 엔진 (T-130). 프로세스 내 추론, 모델당 Engine 1개.
/// LiteRTLM Swift 소스는 앱 타깃 직접 포함 (EngineVendor는 바이너리만).
@MainActor
final class NativeEngine: InferenceEngine, ObservableObject {
    private var engine: Engine?
    @Published private(set) var preparedModelID: String?
    private var activeConversation: Conversation?
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

    func prepare(modelID: String) async throws {
        if preparedModelID == modelID, engine != nil { return }
        release()
        Self.installFlags()
        // MTP는 모델 메타데이터로 자체 판정 (T-130, describe 불필요).
        let mtp = Capabilities(modelPath: Self.modelPath(for: modelID))?
            .hasSpeculativeDecodingSupport() ?? false
        ExperimentalFlags.enableSpeculativeDecoding = mtp
        let config: EngineConfig
        do {
            config = try EngineConfig(modelPath: Self.modelPath(for: modelID),
                                      backend: .gpu, visionBackend: .cpu(),
                                      cacheDir: Self.engineCacheDir())
        } catch {
            throw EngineError.initFailed("\(error)")
        }
        let engine = Engine(engineConfig: config)
        let started = Date()
        do {
            try await engine.initialize()
        } catch {
            throw EngineError.initFailed("\(error)")
        }
        let secs = Date().timeIntervalSince(started)
        logger.perf(feature: "네이티브엔진", "\(modelID) 초기화 \(String(format: "%.1f", secs))s")
        self.engine = engine
        preparedModelID = modelID
    }

    func release() {
        activeConversation = nil
        engine = nil
        preparedModelID = nil
    }

    func stream(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        guard let engine else {
            return AsyncThrowingStream { $0.finish(throwing: EngineError.notReady) }
        }
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
        let temp = Float(temperature)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let sampler = try SamplerConfig(topK: 40, topP: 0.95, temperature: temp)
                    let conversation = try await engine.createConversation(
                        with: ConversationConfig(initialMessages: past,
                                                 samplerConfig: sampler))
                    self.activeConversation = conversation
                    for try await chunk in conversation.sendMessageStream(message) {
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

    func cancel() {
        try? activeConversation?.cancel()
    }

    /// 벤치마크 측정 (T-132): 고정 프롬프트 1턴 실측 후 BenchmarkInfo 매핑.
    /// CLI `benchmark`(256/256 고정)와 조건이 달라 근사 비교용.
    func benchmark(modelID: String) async throws -> EngineBenchmark {
        try await prepare(modelID: modelID)
        guard let engine else { throw EngineError.notReady }
        do {
            let conversation = try await engine.createConversation()
            activeConversation = conversation
            let prompt = Message("Describe Seoul in three sentences.")
            for try await _ in conversation.sendMessageStream(prompt) {
                try Task.checkCancellation()
            }
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
