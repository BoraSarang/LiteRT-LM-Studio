import AppKit
import XCTest
@testable import LiteRTLMStudio

/// 리팩토링 회귀군 (T-124/T-126): PLAN_v6 이후 추출 순수 로직.
final class LiteRTLMStudioRefactorTests: XCTestCase {
    /// SSE 파서 (T-119/T-124): 종료 마커·델타 추출·비SSE 무시.
    func testChatSSEParser() {
        XCTAssertTrue(ChatSSEParser.isDone("data: [DONE]"))
        XCTAssertTrue(ChatSSEParser.isDone("data:[DONE]  "))
        XCTAssertFalse(ChatSSEParser.isDone("data: {\"choices\":[]}"))
        XCTAssertFalse(ChatSSEParser.isDone(": ping"))
        XCTAssertFalse(ChatSSEParser.isDone(""))
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"안녕\"}}]}"
        XCTAssertEqual(ChatSSEParser.content(from: line), "안녕")
        XCTAssertNil(ChatSSEParser.content(from: "data: [DONE]"))
        XCTAssertNil(ChatSSEParser.content(from: ": comment"))
        XCTAssertNil(ChatSSEParser.content(from: ""))
        XCTAssertNil(ChatSSEParser.content(from: "data: not-json"))
        XCTAssertNil(ChatSSEParser.content(from: "data: {\"choices\":[{\"delta\":{}}]}"))
    }
    /// 이미지 축소 (T-114/T-124): 불량은 nil, 정상은 768 상한 JPEG.
    func testImageDownscale() {
        XCTAssertNil(ImageUtil.downscaledJPEG(Data("x".utf8)))
        let img = NSImage(size: NSSize(width: 1600, height: 100))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: img.size).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation else {
            XCTFail("테스트 이미지 생성 실패")
            return
        }
        guard let out = ImageUtil.downscaledJPEG(tiff) else {
            XCTFail("축소 실패")
            return
        }
        XCTAssertEqual(out.mime, "image/jpeg")
        XCTAssertEqual(out.note, "768x48")
        XCTAssertFalse(out.data.isEmpty)
    }
    /// 시간 포맷 단일화 (T-114/T-124): 래퍼는 중앙과 동일 출력.
    func testTimeFormat() {
        let epoch = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(TimeFormat.debugTime(epoch).count, 12)
        XCTAssertEqual(TimeFormat.logTime(epoch).count, 8)
        XCTAssertEqual(DaemonManager.logTimeString(epoch), TimeFormat.logTime(epoch))
        XCTAssertEqual(DebugPanelView.timeString(epoch), TimeFormat.debugTime(epoch))
    }
    /// 로그 상한 (T-119/T-124): 2000건 유지, 최신 보존.
    func testLoggerCap() {
        let log = DebugLogger()
        for i in 0 ..< 2100 { log.info(feature: "t", "m\(i)") }
        XCTAssertEqual(log.entries.count, 2000)
        XCTAssertEqual(log.entries.last?.message, "m2099")
    }
    /// 진입 1회 판정 (T-126): 킥·관측·확정·종료.
    func testDecideEntry() {
        typealias E = ContentView
        var base = E.EntrySnapshot(
            attempt: 10, kickDone: true, emptyMessages: false,
            docH0: 500, expectMin: 100, maxY: 900, offsetY: 840,
            docH: 1500, clipH: 600, stable: true, painted: true
        )
        // 수렴: 하단 도달.
        XCTAssertEqual(E.decideEntry(base).verdict, .finish("수렴"))
        // 짧음: 스크롤 여지 없음.
        base.maxY = 50
        XCTAssertEqual(E.decideEntry(base).verdict, .finish("짧음"))
        // 확정: 정착됐으나 하단 아님.
        base.maxY = 900
        base.offsetY = 100
        XCTAssertEqual(E.decideEntry(base).verdict, .confirmJump)
        // 관측: 최소 회차 미달.
        base.attempt = 2
        XCTAssertEqual(E.decideEntry(base).verdict, .observe)
        // 관측: 미정착.
        base.attempt = 10
        base.stable = false
        XCTAssertEqual(E.decideEntry(base).verdict, .observe)
        // 킥: 미완+내용있음+증거 충족.
        let kick = E.EntrySnapshot(
            attempt: 0, kickDone: false, emptyMessages: false,
            docH0: 500, expectMin: 100
        )
        XCTAssertTrue(E.decideEntry(kick).kick)
        XCTAssertEqual(E.decideEntry(kick).verdict, .observe)
        // 킥 생략: 빈 방.
        var noKick = kick
        noKick.emptyMessages = true
        XCTAssertFalse(E.decideEntry(noKick).kick)
    }
    /// 채팅 요청 생성 (T-126): 메서드·모델·스트림·이미지 페이로드.
    @MainActor
    func testChatRequest() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-req-\(UUID().uuidString).json")
        let store = ChatStore(storageURL: url)
        store.model = "test-model"
        // 전송 시점 버퍼: 이전 왕복 + 낙관적 쌍 (dropLast(2)가 낙관적 쌍 제거).
        store.messages = [
            ChatStore.Message(role: "user", text: "old"),
            ChatStore.Message(role: "assistant", text: "prev"),
            ChatStore.Message(role: "user", text: "hello"),
            ChatStore.Message(role: "assistant", text: "")
        ]
        let req = try store.chatRequest(prompt: "hello")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/v1/chat/completions")
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["stream"] as? Bool, true)
        let msgs = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs.first?["content"] as? String, "old")
        XCTAssertEqual(msgs.last?["content"] as? String, "hello")
        let imgReq = try store.chatRequest(
            prompt: "see", image: ChatStore.ChatImage(data: Data([1, 2, 3]), mime: "image/jpeg")
        )
        let imgBody = try XCTUnwrap(imgReq.httpBody)
        let imgJson = try XCTUnwrap(
            JSONSerialization.jsonObject(with: imgBody) as? [String: Any]
        )
        let imgMsgs = try XCTUnwrap(imgJson["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(imgMsgs.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        try? FileManager.default.removeItem(at: url)
    }

    /// PERF 뱃지 문구 (T-126).
    func testPerfLine() {
        XCTAssertEqual(ChatStore.perfLine(chars: 0, elapsed: 0), "0.0s · 약 0 tok/s")
        XCTAssertTrue(ChatStore.perfLine(chars: 400, elapsed: 10).contains("tok/s"))
    }
}

/// 가짜 엔진 (T-130): 스크립트 청크·실패 주입. LiteRTLM 모듈 비의존.
@MainActor
final class FakeEngine: InferenceEngine {
    var preparedModelID: String?
    var prepareCalls: [String] = []
    var prepareError: Error?
    var chunks = ["hello", " world"]
    var streamShouldFail = false
    var cancelled = false
    var released = false

    func prepare(modelID: String) async throws {
        prepareCalls.append(modelID)
        if let e = prepareError { throw e }
        preparedModelID = modelID
    }

    func release() {
        released = true
        preparedModelID = nil
    }

    func stream(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        keyHistory: [String],
        options: GenerationOptions
    ) -> AsyncThrowingStream<String, Error> {
        lastPrompt = prompt
        lastImage = image
        lastHistory = history
        lastKeyHistory = keyHistory
        lastOptions = options
        let chunks = chunks
        let shouldFail = streamShouldFail
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            if shouldFail {
                continuation.finish(throwing: EngineError.inferenceFailed("fake"))
            } else {
                continuation.finish()
            }
        }
    }

    var lastPrompt: String?
    var lastImage: ChatStore.ChatImage?
    var lastHistory: [(role: String, text: String)] = []
    var lastKeyHistory: [String] = []
    var lastOptions: GenerationOptions?

    func cancel() { cancelled = true }

    var benchmarkResult = EngineBenchmark(initTime: 1.5, ttft: 2.5,
                                          prefillTokens: 10, prefillSpeed: 20,
                                          decodeTokens: 30, decodeSpeed: 15)
    var benchmarkError: Error?

    func benchmark(modelID: String) async throws -> EngineBenchmark {
        if let e = benchmarkError { throw e }
        return benchmarkResult
    }
}

/// 네이티브 전송 회귀군 (T-130): ChatStore 분기·매핑·중단.
@MainActor
final class LiteRTLMStudioNativeTests: XCTestCase {
    private func makeStore() -> ChatStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-native-\(UUID().uuidString).json")
        return ChatStore(storageURL: url)
    }

    private func withNativeMode(_ raw: String? = "native", _ body: () -> Void) {
        let key = "engineMode"
        let prev = UserDefaults.standard.string(forKey: key)
        if let raw {
            UserDefaults.standard.set(raw, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        defer {
            if let prev {
                UserDefaults.standard.set(prev, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        body()
    }

    private func waitStreaming(_ store: ChatStore, timeout: TimeInterval = 10) async {
        let end = Date().addingTimeInterval(timeout)
        while store.streaming, Date() < end {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// 분기 결정 (T-130/T-186): 입력창 route+주입일 때만 네이티브.
    func testUsesNative() {
        let store = makeStore()
        store.route = .native
        store.inferenceEngine = nil
        XCTAssertFalse(store.usesNative())
        store.inferenceEngine = FakeEngine()
        XCTAssertTrue(store.usesNative())
        store.route = .cli
        store.inferenceEngine = FakeEngine()
        XCTAssertFalse(store.usesNative())
    }

    /// 경로별 전송 가능 (T-186): CLI=데몬 실행, 네이티브=엔진 준비.
    func testRouteReady() {
        typealias C = ChatStore
        XCTAssertTrue(C.routeReady(route: .cli, daemonRunning: true, nativePrepared: false))
        XCTAssertFalse(C.routeReady(route: .cli, daemonRunning: false, nativePrepared: true))
        XCTAssertTrue(C.routeReady(route: .native, daemonRunning: false, nativePrepared: true))
        XCTAssertFalse(C.routeReady(route: .native, daemonRunning: true, nativePrepared: false))
    }

    /// 미준비 차단 (T-185): 네이티브 선택+미준비면 자동 초기화 없이 안내, CLI 폴백 없음.
    func testNativeNotReadyNotice() {
        let store = makeStore()
        let fake = FakeEngine()
        fake.preparedModelID = nil
        store.inferenceEngine = fake
        store.route = .native
        store.send("준비 안 됐을 때")
        XCTAssertTrue(fake.prepareCalls.isEmpty)
        XCTAssertFalse(store.streaming)
        XCTAssertEqual(store.messages.last?.isError, true)
        XCTAssertTrue(store.messages.last?.text.contains("준비되지 않았습니다") == true)
    }

    /// 키 분리 (T-193): 재사용 키는 전체 전사, 초기 메시지는 윈도우 적용분.
    func testKeyHistoryIsFullTranscript() async {
        let store = makeStore()
        let fake = FakeEngine()
        fake.preparedModelID = "gemma4-12b"
        store.inferenceEngine = fake
        store.route = .native
        store.messages = [
            ChatStore.Message(role: "user", text: "old"),
            ChatStore.Message(role: "assistant", text: "prev"),
            ChatStore.Message(role: "user", text: "old2"),
            ChatStore.Message(role: "assistant", text: "prev2")
        ]
        let key = "historyTurns"
        let prev = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(1, forKey: key) // 1턴 = 2개
        defer {
            if let prev {
                UserDefaults.standard.set(prev, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        store.send("see")
        await waitStreaming(store)
        XCTAssertEqual(fake.lastHistory.count, 2)
        XCTAssertEqual(fake.lastKeyHistory.count, 4)
    }

    /// 엔진 모드 기본값 (T-130): 미설정 시 CLI.
    func testEngineModeCurrent() {
        withNativeMode(nil) {
            XCTAssertEqual(EngineMode.current(), .cli)
        }
        withNativeMode("native") {
            XCTAssertEqual(EngineMode.current(), .native)
        }
        XCTAssertEqual(EngineMode.cli.title, "CLI 데몬")
        XCTAssertEqual(EngineMode.native.title, "네이티브")
    }

    /// 네이티브 성공 경로 (T-130/T-185): 버블·PERF·준비·시각 기록. 준비된 엔진 전제.
    func testNativeSendSuccess() async {
        let store = makeStore()
        let fake = FakeEngine()
        fake.preparedModelID = "gemma4-12b"
        store.inferenceEngine = fake
        store.route = .native
        store.send("hi")
        await waitStreaming(store)
        XCTAssertFalse(store.streaming)
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages.last?.text, "hello world")
        XCTAssertFalse(store.messages.last?.isError ?? true)
        XCTAssertNotNil(store.messages.last?.perf)
        XCTAssertNotNil(store.messages.last?.finishedAt)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(fake.prepareCalls, ["gemma4-12b"])
    }

    /// 준비 실패 (T-130): E-MAC-ENG-0001 버블.
    func testNativePrepareFailure() async {
        let store = makeStore()
        let fake = FakeEngine()
        fake.preparedModelID = "gemma4-12b"
        fake.prepareError = EngineError.initFailed("no file")
        store.inferenceEngine = fake
        store.route = .native
        store.send("hi")
        await waitStreaming(store)
        XCTAssertEqual(store.lastError, "E-MAC-ENG-0001")
        XCTAssertTrue(store.messages.last?.isError ?? false)
        XCTAssertTrue(store.messages.last?.text.contains("E-MAC-ENG-0001") ?? false)
    }

    /// 추론 실패 (T-130): E-MAC-ENG-0002 버블.
    func testNativeInferenceFailure() async {
        let store = makeStore()
        let fake = FakeEngine()
        fake.preparedModelID = "gemma4-12b"
        fake.streamShouldFail = true
        store.inferenceEngine = fake
        store.route = .native
        store.send("hi")
        await waitStreaming(store)
        XCTAssertEqual(store.lastError, "E-MAC-ENG-0002")
        XCTAssertTrue(store.messages.last?.isError ?? false)
    }

    /// 중단 전파 (T-130): stop이 엔진 cancel 호출.
    func testStopCancelsEngine() {
        let store = makeStore()
        let fake = FakeEngine()
        store.inferenceEngine = fake
        store.stop()
        XCTAssertTrue(fake.cancelled)
        XCTAssertFalse(store.streaming)
    }

    /// 실패 매핑 직접 검증 (T-130): 코드별 문구.
    func testNativeFailedMapping() {
        let store = makeStore()
        store.messages.append(ChatStore.Message(role: "user", text: "q"))
        store.messages.append(ChatStore.Message(role: "assistant", text: ""))
        store.nativeFailed(at: 1, error: EngineError.initFailed("x"))
        XCTAssertEqual(store.lastError, "E-MAC-ENG-0001")
        store.nativeFailed(at: 1, error: EngineError.inferenceFailed("y"))
        XCTAssertEqual(store.lastError, "E-MAC-ENG-0002")
        XCTAssertTrue(store.messages[1].text.contains("E-MAC-ENG-0002"))
    }

    /// 매핑 전달 (T-131/T-176): 프롬프트·이미지·히스토리·생성 옵션이 어댑터까지 그대로.
    func testNativeMappingPassthrough() async {
        let store = makeStore()
        store.temperature = 0.9
        store.topK = 32
        store.topP = 0.8
        store.maxTokens = 500
        store.seed = 7
        store.messages = [
            ChatStore.Message(role: "user", text: "old"),
            ChatStore.Message(role: "assistant", text: "prev")
        ]
        let fake = FakeEngine()
        fake.preparedModelID = "gemma4-12b"
        store.inferenceEngine = fake
        let image = ChatStore.ChatImage(data: Data([1, 2, 3]), mime: "image/jpeg")
        store.route = .native
        store.send("see", image: image)
        await waitStreaming(store)
        XCTAssertEqual(fake.lastPrompt, "see")
        XCTAssertEqual(fake.lastImage?.mime, "image/jpeg")
        XCTAssertEqual(fake.lastImage?.data, Data([1, 2, 3]))
        XCTAssertEqual(fake.lastHistory.map { "\($0.role):\($0.text)" },
                       ["user:old", "assistant:prev"])
        XCTAssertEqual(fake.lastOptions?.temperature ?? -1, 0.9, accuracy: 0.0001)
        XCTAssertEqual(fake.lastOptions?.topK, 32)
        XCTAssertEqual(fake.lastOptions?.topP ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(fake.lastOptions?.maxTokens, 500)
        XCTAssertEqual(fake.lastOptions?.seed, 7)
    }

    /// config 추종 백엔드 (T-177): default 섹션 파싱·폴백.
    func testResolveBackends() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("litert-backends-\(UUID().uuidString).json")
        let json = """
        {"default": {"backend": "cpu", "cpu_thread_count": 8,
          "vision_backend": "gpu", "audio_backend": "cpu"}}
        """
        try json.write(to: tmp, atomically: true, encoding: .utf8)
        let r = NativeEngine.resolveBackends(configURL: tmp)
        XCTAssertEqual(r.backend, .cpu(threadCount: 8))
        XCTAssertEqual(r.vision, .gpu)
        XCTAssertEqual(r.audio, .cpu(threadCount: nil))
        try? FileManager.default.removeItem(at: tmp)
        // 파일 없으면 기존 고정값.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("litert-missing-\(UUID().uuidString).json")
        let d = NativeEngine.resolveBackends(configURL: missing)
        XCTAssertEqual(d.backend, .gpu)
        XCTAssertEqual(d.vision, .cpu(threadCount: nil))
        XCTAssertNil(d.audio)
    }

    /// residency·visual 기본값 (T-177): 미설정 시 켬·1120.
    func testEngineAdvancedDefaults() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        XCTAssertTrue(NativeEngine.residencyEnabled(suite))
        XCTAssertEqual(NativeEngine.visualBudget(suite), 1120)
        suite.set(false, forKey: "metalResidency")
        suite.set(280, forKey: "visualTokenBudget")
        XCTAssertFalse(NativeEngine.residencyEnabled(suite))
        XCTAssertEqual(NativeEngine.visualBudget(suite), 280)
    }

    /// 요청 바디 (T-176): top_p·max_tokens·seed 전송, top_k 제외.
    func testChatRequestSampling() throws {
        let store = makeStore()
        store.topP = 0.8
        store.maxTokens = 500
        store.seed = 7
        let req = try store.chatRequest(prompt: "hi")
        let json = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        XCTAssertEqual(json?["top_p"] as? Double ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(json?["max_tokens"] as? Int, 500)
        XCTAssertEqual(json?["seed"] as? Int, 7)
        XCTAssertNil(json?["top_k"])
    }
}
