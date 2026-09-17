import Foundation

/// 대화 재사용 키 (T-191): 채팅방당 고정 키.
/// 히스토리는 매 턴 늘어나므로 키에 포함하면 매번 새 Conversation이 생겨
/// KV 캐시가 재사용되지 않음 → 모델+방ID+옵션만으로 고정.
/// 같은 방의 후속 턴은 동일 Conversation 객체를 이어써 KV를 그대로 잇는다.
struct ConvKey: Equatable, Hashable {
    var modelID: String
    /// 채팅방 식별자 (ChatStore.currentSessionID). 방이 다르면 KV 공유 금지.
    var sessionID: String
    var options: GenerationOptions
}

/// SPM LiteRTLM 앱 내 엔진 (T-130). 프로세스 내 추론, 모델당 Engine 1개 캐시.
/// LiteRTLM Swift 소스는 앱 타깃 직접 포함 (EngineVendor는 바이너리만).
@MainActor
final class NativeEngine: InferenceEngine, ObservableObject {
    /// 수명주기 상태 (T-185): 사이드바 실행/중지/다시 실행 버튼 표시용.
    enum State: Equatable {
        case idle // 미초기화
        case preparing // 준비 중
        case ready // 준비됨 (preparedModelIDs 비어있지 않음)
        case failed // 준비 실패 (lastError 병행)
    }

    /// 모델별 Engine 캐시 (P0-1): 앱 수명 동안 재사용, LRU 3개 제한.
    var engines: [String: Engine] = [:]
    var engineAccessOrder: [String] = [] // LRU용
    let maxCachedEngines = 3

    /// 프로토콜 준수용: 가장 최근 사용된 준비된 모델 ID (InferenceEngine.protocol).
    var preparedModelID: String? {
        engineAccessOrder.last
    }

    /// Conversation 풀 (P0-2): KV 캐시 완전 재사용.
    var conversations: [ConvKey: Conversation] = [:]
    var conversationAccessOrder: [ConvKey] = [] // LRU용
    let maxCachedConversations = 20

    @Published private(set) var preparedModelIDs: Set<String> = []
    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String?
    /// 현재 활성 대화 (UI 바인딩용, T-266).
    var activeConversation: Conversation?
    /// 현재 활성 키 (T-191, T-290).
    var activeKey: ConvKey?
    /// 준비된 모델의 도구 지원 여부 (T-290): 모델별 캐시.
    private var preparedSupportsFC: [String: Bool] = [:]

    /// 백엔드 캐시 (P0-3): 최초 1회만 디스크 읽기.
    nonisolated(unsafe) private static var cachedBackends: EngineBackends?
    nonisolated(unsafe) private static var cachedResidency: Bool?
    nonisolated(unsafe) private static var cachedVisualBudget: Int32?
    private let logger = DebugLogger.shared
    private static var flagsInstalled = false

    /// 모델 파일 경로. `~/.litert-lm/models` 읽기 전용 참조 (AGENTS.local).
    nonisolated static func modelPath(for modelID: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".litert-lm/models/\(modelID)/model.litertlm").path
    }

    /// 컴파일 캐시 경로 (P2-1): cachesDirectory 사용 (시스템 자동 관리).
    nonisolated static func engineCacheDir() -> String {
        let base = FileManager.default.urls(for: .cachesDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LiteRTLMStudio/EngineCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// 백엔드 캐시 무효화 (설정 변경 시 호출).
    nonisolated static func invalidateBackendCache() {
        cachedBackends = nil
        cachedResidency = nil
        cachedVisualBudget = nil
    }

    func prepare(modelID: String) async throws {
        if preparedModelIDs.contains(modelID), engines[modelID] != nil {
            logger.info(feature: "앱내엔진", "캐시 히트: \(modelID) 이미 준비됨")
            return
        }
        state = .preparing
        lastError = nil
        Self.installFlags()

        // MTP: 사용자 설정(ConfigStore) 우선, 모델 메타데이터는 지원 여부만 확인 (폴백용)
        let caps = Capabilities(modelPath: Self.modelPath(for: modelID))
        let modelSupportsMTP = caps?.hasSpeculativeDecodingSupport() ?? false
        let userMTP = ConfigStore.savedMTP(modelID: modelID) ?? false
        let mtp = userMTP && modelSupportsMTP
        ExperimentalFlags.enableSpeculativeDecoding = mtp
        if mtp {
            logger.info(feature: "앱내엔진", "MTP 활성화: 사용자 설정=\(userMTP), 모델지원=\(modelSupportsMTP)")
        } else if userMTP && !modelSupportsMTP {
            logger.info(feature: "앱내엔진", "MTP 비활성화: 모델이 지원하지 않음 (\(modelID))")
        } else if !userMTP && modelSupportsMTP {
            logger.info(feature: "앱내엔진", "MTP 비활성화: 사용자 설정 OFF")
        }
        
        // T-290: 도구 미지원 모델은 도구 없이 대화 (강제 등록 시 추론 실패).
        let supportsFC = caps?.supportsFunctionCalling() ?? false
        preparedSupportsFC[modelID] = supportsFC
        if !supportsFC {
            logger.info(feature: "앱내엔진", "도구 미지원 모델 — 도구 없이 대화 (\(modelID))")
        }

        // P1-3: 채널 콘텐츠를 KV 캐시에서 제외하여 용량 절약·프리필 가속
        ExperimentalFlags.filterChannelContentFromKvCache = true

        // 백엔드/플래그 캐시 사용 (P0-3)
        let (config, residency, visualBudget) = Self.getCachedBackends()
        ExperimentalFlags.gpuEnableMetalResidencySet = residency
        ExperimentalFlags.visualTokenBudget = visualBudget
        // 디버그: 실제 적용 설정 (하드코딩 금지 — 해석된 값 그대로)
        let appliedMaxTokens = ConfigStore.maxNumTokensValue(from: ConfigStore.defaultURL)
        let appliedVision = String(describing: config.vision)
        logger.info(feature: "앱내엔진",
            "설정: model=\(modelID) MTP=\(mtp) maxTokens=\(String(describing: appliedMaxTokens))")
        logger.info(feature: "앱내엔진",
            "백엔드: llm=\(config.backend) vision=\(appliedVision) residency=\(residency)")

        do {
            try await boot(modelID: modelID, backends: config)
        } catch {
            // T-273: 인코더 없는 모델은 모달 제외하고 1회 재시도.
            guard let fallback = Self.modalFallback(config) else {
                throw EngineError.initFailed("\(error)")
            }
            logger.info(feature: "앱내엔진", "vision·audio 제외 폴백 초기화 (\(modelID))")
            try await boot(modelID: modelID, backends: fallback)
        }
    }

    /// 백엔드/플래그 캐시 조회 (P0-3): 최초 1회만 디스크 I/O.
    private static func getCachedBackends() -> (config: EngineBackends, residency: Bool, visualBudget: Int32) {
        if let cached = cachedBackends,
           let residency = cachedResidency,
           let visualBudget = cachedVisualBudget {
            return (cached, residency, visualBudget)
        }
        let config = resolveBackends(configURL: ConfigStore.defaultURL)
        let residency = residencyEnabled()
        let visualBudget = visualBudget()
        cachedBackends = config
        cachedResidency = residency
        cachedVisualBudget = visualBudget
        return (config, residency, visualBudget)
    }

    /// 엔진 기동: 캐시에서 가져오거나 새로 생성 (P0-1).
    private func boot(modelID: String, backends: EngineBackends) async throws {
        let engine: Engine
        if let cached = engines[modelID] {
            engine = cached
            logger.info(feature: "앱내엔진", "Engine 캐시 히트: \(modelID)")
        } else {
            let config: EngineConfig
            do {
                // P1-2: ConfigStore에서 maxNumTokens(KV 캐시 크기) 읽기
                let maxTokens = ConfigStore.maxNumTokensValue(from: ConfigStore.defaultURL)
                config = try EngineConfig(modelPath: Self.modelPath(for: modelID),
                                          backend: backends.backend,
                                          visionBackend: backends.vision,
                                          audioBackend: backends.audio,
                                          maxNumTokens: maxTokens,
                                          cacheDir: Self.engineCacheDir())
            } catch {
                logger.error(code: "E-MAC-ENG-0001", feature: "앱내엔진",
                             "EngineConfig 실패 (\(modelID)): \(error)")
                throw EngineError.initFailed("\(error)")
            }
            engine = Engine(engineConfig: config)
            let started = Date()
            do {
                try await engine.initialize()
            } catch {
                state = .failed
                lastError = EngineError.initFailed("").code
                logger.error(code: "E-MAC-ENG-0001", feature: "앱내엔진",
                             "초기화 실패 (\(modelID)): \(error)")
                throw EngineError.initFailed("\(error)")
            }
            let secs = Date().timeIntervalSince(started)
            logger.perf(feature: "앱내엔진", "\(modelID) 초기화 \(String(format: "%.1f", secs))s")
            // LRU 캐시 등록
            registerEngine(modelID, engine)
        }
        engines[modelID] = engine
        preparedModelIDs.insert(modelID)
        state = .ready
    }

    /// Engine LRU 등록 (P0-1).
    private func registerEngine(_ modelID: String, _ engine: Engine) {
        engineAccessOrder.removeAll { $0 == modelID }
        engineAccessOrder.append(modelID)
        if engineAccessOrder.count > maxCachedEngines {
            let evicted = engineAccessOrder.removeFirst()
            engines[evicted] = nil
            preparedModelIDs.remove(evicted)
            preparedSupportsFC.removeValue(forKey: evicted)
            logger.info(feature: "앱내엔진", "Engine LRU 제거: \(evicted)")
        }
    }

    func release() {
        activeConversation = nil
        activeKey = nil
        // 전체 해제는 restart()에서만. 모델별은 releaseModel() 사용.
    }

    /// 특정 모델만 해제 (모델 전환 시).
    func releaseModel(_ modelID: String) {
        engines[modelID] = nil
        engineAccessOrder.removeAll { $0 == modelID }
        preparedModelIDs.remove(modelID)
        preparedSupportsFC.removeValue(forKey: modelID)
        // 관련 Conversation도 정리
        conversations = conversations.filter { $0.key.modelID != modelID }
        conversationAccessOrder.removeAll { $0.modelID == modelID }
        state = preparedModelIDs.isEmpty ? .idle : .ready
    }

    /// 다시 실행 (T-185): 해당 모델만 반납 후 처음부터 준비.
    func restart(modelID: String) async throws {
        releaseModel(modelID)
        try await prepare(modelID: modelID)
    }

    /// 이벤트 스트림은 NativeEngine+Events 분리 (T-266, 본문 길이 관리).

    func stream(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        options: GenerationOptions,
        sessionID: String
    ) -> AsyncThrowingStream<String, Error> {
        guard let modelID = preparedModelIDs.first(where: { engines[$0] != nil }),
              let engine = engines[modelID] else {
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
        let opts = options
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let setup = try await self.preparedStream(
                        engine: engine, modelID: modelID, past: past,
                        sessionID: sessionID, opts: opts)
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

    /// 스트림 준비물 묶음 (T-277): 대화+설정+재사용 여부 (튜플 3원소 린트 회피).
    struct PreparedSetup: Sendable {
        let conversation: Conversation
        let thinking: ThinkingConfig?
        let reused: Bool
    }

    /// 스트림 준비물 (T-191 분리, P0-2 Conversation 풀 사용).
    /// 키는 모델+방ID+옵션으로 턴 수와 무관하게 고정 → 같은 방의 후속 턴은
    /// 동일 Conversation 객체를 이어써 KV를 그대로 잇는다 (프리필 생략).
    func preparedStream(engine: Engine, modelID: String, past: [Message],
                        sessionID: String, opts: GenerationOptions, allowReuse: Bool = true)
    async throws -> PreparedSetup {
        let sampler = try SamplerConfig(
            topK: opts.topK, topP: Float(opts.topP),
            temperature: Float(opts.temperature), seed: opts.seed ?? 0)
        let sysMsg = opts.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let thinking: ThinkingConfig? = opts.thinkingEnabled
            ? ThinkingConfig(enableThinking: true,
                             thinkingTokenBudget: opts.thinkingBudget) : nil

        let key = ConvKey(modelID: modelID, sessionID: sessionID, options: opts)

        if allowReuse,
           let live = conversations[key] {
            // LRU 갱신
            conversationAccessOrder.removeAll { $0 == key }
            conversationAccessOrder.append(key)
            activeConversation = live
            activeKey = key
            logger.info(feature: "앱내엔진", "Conversation 풀 히트: KV 캐시 재사용 (방 \(sessionID.prefix(8)))")
            return PreparedSetup(conversation: live, thinking: thinking, reused: true)
        }

        let conversation = try await engine.createConversation(
            with: ConversationConfig(
                systemMessage: sysMsg.isEmpty ? nil : Message(sysMsg, role: .system),
                initialMessages: past,
                tools: Self.toolsForConversation(supportsFC: preparedSupportsFC[modelID] ?? false,
                                                 registered: LocalTools.registered()),
                samplerConfig: sampler,
                enableToolCallStreaming: true,
                thinkingConfig: thinking))

        // Conversation 풀 등록 (P0-2)
        registerConversation(key, conversation)
        activeConversation = conversation
        activeKey = key

        return PreparedSetup(conversation: conversation, thinking: thinking, reused: false)
    }

    /// Conversation LRU 등록 (P0-2).
    private func registerConversation(_ key: ConvKey, _ conversation: Conversation) {
        conversationAccessOrder.removeAll { $0 == key }
        conversationAccessOrder.append(key)
        conversations[key] = conversation
        if conversationAccessOrder.count > maxCachedConversations {
            let evicted = conversationAccessOrder.removeFirst()
            conversations[evicted] = nil
            logger.info(feature: "앱내엔진", "Conversation LRU 제거: \(evicted.modelID)")
        }
    }

    /// 재사용·도구 게이트는 NativeEngine+Events 분리 (T-290, 본문 길이 관리).

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
        guard let engine = engines[modelID] else { throw EngineError.notReady }
        do {
            let conversation = try await engine.createConversation()
            onStage(.measuring)
            let prompt = Message("Describe Seoul in three sentences.")
            for try await _ in conversation.sendMessageStream(prompt) {
                try Task.checkCancellation()
            }
            onStage(.summarizing)
            let info = try conversation.getBenchmarkInfo()
            logger.perf(feature: "앱내벤치",
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

    /// 실험 플래그 1회 설치 (MTP·벤치마크·도구 스트리밍).
    private static func installFlags() {
        guard !flagsInstalled else { return }
        flagsInstalled = true
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableBenchmark = true
        ExperimentalFlags.enableConversationToolCallStreaming = true
    }
}