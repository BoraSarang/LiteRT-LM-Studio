import Foundation

/// 대화 재사용 키 (T-191): 모델+방ID+옵션으로 고정 — 히스토리를 키에 넣으면
/// 매 턴 새 Conversation이 생겨 KV 재사용이 깨진다.
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
    /// 실패 원인 원문 (T-336): 코드만 보이던 사이드바에 원인 표시.
    @Published private(set) var lastErrorDetail: String?
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

    /// 컴파일 캐시 경로 (P2-1 → T-314): 앱 홈 `engine-cache` (StudioPaths).
    nonisolated static func engineCacheDir() -> String {
        StudioPaths.engineCachePath
    }

    /// 백엔드 캐시 무효화 (설정 변경 시 호출).
    nonisolated static func invalidateBackendCache() {
        cachedBackends = nil
        cachedResidency = nil
        cachedVisualBudget = nil
    }

    func prepare(modelID: String) async throws {
        if preparedModelIDs.contains(modelID), engines[modelID] != nil {
            engineAccessOrder.removeAll { $0 == modelID }
            engineAccessOrder.append(modelID)
            logger.info(feature: "앱내엔진", "캐시 히트: \(modelID) 이미 준비됨")
            return
        }
        // T-340/T-336: 빈 선택·파일 부재를 엔진 진입 전에 원인 확정 (빈 경로 혼동 방지).
        let path = Self.modelPath(for: modelID)
        guard !modelID.isEmpty, FileManager.default.fileExists(atPath: path) else {
            let why = modelID.isEmpty ? L(L10n.EngineNotice.noModel) : L(L10n.EngineNotice.noFile, path)
            markInitFailed(why)
            throw EngineError.initFailed(why)
        }
        state = .preparing
        lastError = nil
        lastErrorDetail = nil
        Self.installFlags()

        // MTP: 사용자 설정(ConfigStore) 우선, 모델 메타데이터는 지원 여부만 확인 (폴백용)
        let caps = Capabilities(modelPath: path)
        let modelSupportsMTP = caps?.hasSpeculativeDecodingSupport() ?? false
        let mtp = resolveMTP(modelID: modelID, supported: modelSupportsMTP)

        // T-290: 도구 미지원 모델은 도구 없이 대화 (강제 등록 시 추론 실패).
        let supportsFC = caps?.supportsFunctionCalling() ?? false
        preparedSupportsFC[modelID] = supportsFC
        if !supportsFC {
            logger.info(feature: "앱내엔진", "도구 미지원 모델 — 도구 없이 대화 (\(modelID))")
        }

        // P1-3: 채널 콘텐츠를 KV 캐시에서 제외하여 용량 절약·프리필 가속
        ExperimentalFlags.filterChannelContentFromKvCache = true

        // 백엔드/플래그 캐시 사용 (P0-3)
        let backends = Self.getCachedBackends()
        let config = backends.config
        ExperimentalFlags.gpuEnableMetalResidencySet = backends.residency
        ExperimentalFlags.visualTokenBudget = backends.visualBudget
        // 디버그: 실제 적용 설정 (하드코딩 금지 — 해석된 값 그대로)
        let appliedMaxTokens = ConfigStore.maxNumTokensValue(from: ConfigStore.defaultURL)
        let appliedVision = String(describing: config.vision)
        logger.info(feature: "앱내엔진",
            "설정: model=\(modelID) MTP=\(mtp) maxTokens=\(String(describing: appliedMaxTokens))")
        logger.info(feature: "앱내엔진",
            "백엔드: llm=\(config.backend) vision=\(appliedVision) residency=\(backends.residency)")

        do {
            try await boot(modelID: modelID, backends: config)
        } catch {
            // T-273: 인코더 없는 모델은 모달 제외하고 1회 재시도.
            guard let fallback = Self.modalFallback(config) else {
                // R2-15: config 실패 지점에서 state가 .preparing에 멈췄던 결함 → 실패 확정.
                markInitFailed("\(error)")
                throw EngineError.initFailed("\(error)")
            }
            logger.info(feature: "앱내엔진", "vision·audio 제외 폴백 초기화 (\(modelID))")
            do {
                try await boot(modelID: modelID, backends: fallback)
            } catch {
                markInitFailed("\(error)")
                throw EngineError.initFailed("\(error)")
            }
        }
    }

    /// 준비 실패 확정 (R2-15): 에러·상태를 failed로 고정.
    private func markInitFailed(_ message: String) {
        state = .failed
        lastError = EngineError.initFailed("").code
        lastErrorDetail = message
        logger.error(code: "E-MAC-ENG-0001", feature: "앱내엔진", "초기화 실패: \(message)")
    }

    /// 백엔드/플래그 캐시 값 (P0-3/T-360): 튜플 대신 명명 구조체.
    struct CachedBackends {
        let config: EngineBackends
        let residency: Bool
        let visualBudget: Int32
    }

    /// 백엔드/플래그 캐시 조회 (P0-3): 최초 1회만 디스크 I/O.
    private static func getCachedBackends() -> CachedBackends {
        if let cached = cachedBackends,
           let residency = cachedResidency,
           let visualBudget = cachedVisualBudget {
            return CachedBackends(config: cached, residency: residency, visualBudget: visualBudget)
        }
        let picked = CachedBackends(config: resolveBackends(configURL: ConfigStore.defaultURL),
                                    residency: residencyEnabled(),
                                    visualBudget: visualBudget())
        cachedBackends = picked.config
        cachedResidency = picked.residency
        cachedVisualBudget = picked.visualBudget
        return picked
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
                lastErrorDetail = "\(error)"
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

    /// 평문 스트림: 이벤트 스트림 단일 경로 위임 (본문만 추출).
    /// 재시도·무효화는 streamEvents가 담당 — 단일 추론 경로.
    func stream(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        options: GenerationOptions,
        sessionID: String
    ) -> AsyncThrowingStream<String, Error> {
        let events = streamEvents(prompt: prompt, image: image, history: history,
                                  options: options, sessionID: sessionID)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in events {
                        if case .text(let chunk) = event { continuation.yield(chunk) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
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

    /// 스트림 준비물 (T-191, P0-2 풀 사용): 키는 모델+방ID+옵션 고정이라
    /// 같은 방의 후속 턴은 동일 Conversation을 이어써 KV를 잇는다 (프리필 생략).
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

        let tools = Self.toolsForConversation(supportsFC: preparedSupportsFC[modelID] ?? false,
                                              registered: LocalTools.registered())
        let conversation = try await engine.createConversation(
            with: ConversationConfig(
                systemMessage: sysMsg.isEmpty ? nil : Message(sysMsg, role: .system),
                initialMessages: past, tools: tools, samplerConfig: sampler,
                enableToolCallStreaming: !tools.isEmpty, // T-311: 빈 도구면 끔 (스톨 방지)
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

    /// 실험 플래그 1회 설치 (MTP·벤치마크·도구 스트리밍).
    private static func installFlags() {
        guard !flagsInstalled else { return }
        flagsInstalled = true
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableBenchmark = true
        ExperimentalFlags.enableConversationToolCallStreaming = true
    }
}

/// 앱 내 엔진 캐시 수명주기 확장 (T-360 분리: 타입 본문 길이 관리).
extension NativeEngine {
    /// Engine LRU 등록 (P0-1).
    private func registerEngine(_ modelID: String, _ engine: Engine) {
        engineAccessOrder.removeAll { $0 == modelID }
        engineAccessOrder.append(modelID)
        if engineAccessOrder.count > maxCachedEngines {
            let evicted = engineAccessOrder.removeFirst()
            dropModel(evicted)
            logger.info(feature: "앱내엔진", "Engine LRU 제거: \(evicted)")
        }
    }

    /// 모델 1건 완전 정리 (엔진+대화+지원여부+활성 포인터).
    private func dropModel(_ modelID: String) {
        engines[modelID] = nil
        engineAccessOrder.removeAll { $0 == modelID }
        preparedModelIDs.remove(modelID)
        preparedSupportsFC.removeValue(forKey: modelID)
        conversations = conversations.filter { $0.key.modelID != modelID }
        conversationAccessOrder.removeAll { $0.modelID == modelID }
        if activeKey?.modelID == modelID {
            activeConversation = nil
            activeKey = nil
        }
        // R2-17: 마지막 엔진 방출 시 .ready 잔존 → .idle 갱신 (UI 표시 불일치 방지).
        if preparedModelIDs.isEmpty { state = .idle }
    }

    /// 전체 해제 (중지 버튼): 모든 구조물 반납+idle. 모델별은 releaseModel() 사용.
    func release() {
        activeConversation = nil
        activeKey = nil
        conversations.removeAll()
        conversationAccessOrder.removeAll()
        engines.removeAll()
        engineAccessOrder.removeAll()
        preparedModelIDs.removeAll()
        preparedSupportsFC.removeAll()
        state = .idle
    }

    /// 특정 모델만 해제 (모델 전환 시).
    func releaseModel(_ modelID: String) {
        dropModel(modelID)
        state = preparedModelIDs.isEmpty ? .idle : .ready
    }

    /// 다시 실행 (T-185): 해당 모델만 반납 후 처음부터 준비.
    func restart(modelID: String) async throws {
        releaseModel(modelID)
        try await prepare(modelID: modelID)
    }
}
