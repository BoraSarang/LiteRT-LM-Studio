import Foundation

/// `litert-lm benchmark` 실행·파싱. 단계 표시 + 지표 추출 (Swift Charts 표시용).
/// T-216 수동 시작(pending→start)+경과+단계 / T-217 기록 전달 / T-218 AI 분석.
@MainActor
final class BenchmarkStore: ObservableObject {
    /// 단계 열거 (T-224 분리: BenchmarkStage 별칭, 기존 `BenchmarkStore.Stage` 호출 호환).
    typealias Stage = BenchmarkStage

    struct Metrics: Codable, Equatable {
        var backend = "-"
        var prefillTokens = 0, decodeTokens = 0, runs = 0
        var prefillSpeed = 0.0, decodeSpeed = 0.0
        var initTime = 0.0, ttft = 0.0

        /// 숫자 이해를 돕는 한국어 해설.
        var explanation: [(String, String)] {
            [
                ("첫 토큰까지 \(fmt(ttft))초",
                 ttft < 2 ? "체감 반응이 빠릅니다. 엔터 후 바로 답이 나오기 시작해요."
                     : ttft < 10 ? "보통 수준입니다. 짧은 질문에는 충분해요."
                     : "다소 느립니다. prefill이 무거운 긴 입력에서 두드러져요."),
                ("생성 속도 초당 \(fmt(decodeSpeed))토큰",
                 decodeSpeed >= 15 ? "긴 답변도 술술 나옵니다."
                     : decodeSpeed >= 5 ? "읽는 속도와 비슷해 무난합니다."
                     : "답이 한 글자씩 끊겨 보일 수 있어요. 짧게 답해 달라고 하세요."),
                ("입력 처리 초당 \(fmt(prefillSpeed))토큰",
                 "긴 문서·이미지를 함께 보낼 때의 준비 속도입니다."),
                ("엔진 준비 \(fmt(initTime))초",
                 "첫 실행 한 번만 드는 비용입니다. 데몬이 떠 있으면 다시 안 들어요.")
            ]
        }

        private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
    }

    @Published var stage: Stage = .initEngine
    @Published var currentIter = 0
    @Published var totalIter = 1
    @Published var logLines: [String] = []
    @Published var metrics: Metrics?
    @Published var running = false
    /// T-216: 측정 시작 전 대기 상태 (모델·모드 선택 후 시작 버튼).
    @Published var pendingModelID: String?
    @Published var pendingRoute: EngineMode = .cli
    /// T-216: 측정 경과 시간 (0.5초 틱).
    @Published var elapsed: TimeInterval = 0
    @Published var startedAt: Date?
    /// T-218: AI 분석 결과 (마크다운) + 진행 상태.
    @Published var analysisMarkdown = ""
    @Published var analyzing = false
    @Published var analysisError: String?
    /// T-223: 분석에 쓴 엔진 표기 ("Gemma 4 · 12B·CLI 데몬").
    @Published var analysisEngineLabel = ""
    /// T-224: 기록별 분석 결과·엔진 표기 (기록 클릭해도 유지).
    @Published var analysisCache: [BenchmarkRecord.ID: String] = [:]
    @Published var analysisEngineByRecord: [BenchmarkRecord.ID: String] = [:]
    /// T-224: 현재 분석 중인 슬롯 (nil=라이브). `analyzing`과 함께 판정.
    @Published var analyzingSlotID: BenchmarkRecord.ID?

    private var process: Process?
    private var nativeTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var activeModelID = ""
    private var activeRoute: EngineMode = .cli
    /// T-218: 분석 확장(BenchmarkHistory.swift)에서 사용하므로 internal.
    let logger = DebugLogger.shared

    /// 앱 내 엔진 측정 제공자 (T-132, ContentView가 nativeEngine으로 연결).
    var nativeBenchmark: ((String) async throws -> EngineBenchmark)?
    /// 앱 내 엔진 측정 제공자 + 진행 알림 (T-216, 설정되면 우선 사용).
    var nativeBenchmarkStaged: ((String, @escaping (BenchmarkPhase) -> Void) async throws -> EngineBenchmark)?
    /// 측정 경로 (T-186): 호출 측이 입력창 route로 지정. 기본 CLI.
    var route: EngineMode = .cli
    /// T-217: 측정 종료 시 기록 전달 (AppServices가 히스토리에 추가).
    var onRecord: ((BenchmarkRecord) -> Void)?

    /// T-216: 시작 전 선택만 저장 (자동 실행 없음).
    func prepare(modelID: String, route: EngineMode) {
        guard !running else { return }
        pendingModelID = modelID
        pendingRoute = route
        self.route = route
        logger.info(feature: "벤치마크", "\(modelID) 측정 대기 (\(route.title))")
    }

    /// T-216: 대기 중인 측정 시작.
    func start() {
        guard !running, let modelID = pendingModelID else { return }
        logger.info(feature: "벤치마크", "\(modelID) benchmark 시작 (기본 토큰)")
        activeModelID = modelID
        activeRoute = pendingRoute
        route = pendingRoute
        reset()
        if route == .native, nativeBenchmarkStaged != nil || nativeBenchmark != nil {
            runNative(modelID: modelID)
            return
        }
        runCLI(modelID: modelID)
    }

    /// 기존 호출 호환 (T-132/T-186): 지정 모델로 즉시 시작.
    func run(modelID: String) {
        guard !running else { return }
        prepare(modelID: modelID, route: route)
        start()
    }

    /// 상태 초기화 (CLI·앱 내 엔진 공용).
    private func reset() {
        stage = .initEngine
        currentIter = 0
        totalIter = 1
        logLines = []
        metrics = nil
        analysisMarkdown = ""
        analysisError = nil
        analyzing = false
        analyzingSlotID = nil
        running = true
        startedAt = Date()
        elapsed = 0
        startTick()
    }

    private func startTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                if let since = self.startedAt {
                    self.elapsed = Date().timeIntervalSince(since)
                }
            }
        }
    }

    private func stopTick() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// 앱 내 엔진 완료 반영 (T-216 분리): 지표+단계+기록.
    private func completeNative(_ met: Metrics) {
        metrics = met
        stage = .done
        running = false
        stopTick()
        logger.perf(feature: "벤치마크",
                    "앱 내 엔진 완료 prefill=\(met.prefillSpeed) decode=\(met.decodeSpeed)")
        emitRecord(status: .done, metrics: met)
    }

    /// 앱 내 엔진 중단 반영 (T-216 분리).
    private func interruptNative() {
        running = false
        stopTick()
        logLines.append("— 사용자 중단 —")
        logger.info(feature: "벤치마크", "사용자 중단")
        emitRecord(status: .cancelled, metrics: metrics)
    }

    /// 앱 내 엔진 실패 반영 (T-216 분리, T-273 코드 정정): EngineError 코드 우선.
    private func failNative(_ error: Error) {
        running = false
        stopTick()
        stage = .initEngine
        let code = (error as? EngineError)?.code ?? "E-MAC-ENG-0002"
        logger.error(code: code, feature: "벤치마크", "\(error)")
        emitRecord(status: .failed, metrics: nil)
    }

    /// 앱 내 엔진 측정 (T-132/T-216): 고정 프롬프트 1턴 → Metrics 매핑 + 단계 콜백.
    func runNative(modelID: String, measure: @escaping (String) async throws -> EngineBenchmark) {
        nativeTask?.cancel()
        activeModelID = modelID
        if !running { reset() }
        nativeTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.stage = .initEngine
                self.logLines.append("엔진 준비 중… (첫 실행은 수 분 가능)")
                self.currentIter = 1
                let info = try await measure(modelID)
                self.stage = .summarize
                self.completeNative(Self.makeMetrics(info))
            } catch is CancellationError {
                self.interruptNative()
            } catch {
                self.failNative(error)
            }
        }
    }

    /// 앱 내 엔진 측정 (staged 제공자 우선, T-216).
    private func runNative(modelID: String) {
        if let staged = nativeBenchmarkStaged {
            nativeTask?.cancel()
            nativeTask = Task { [weak self] in
                guard let self else { return }
                do {
                    self.stage = .initEngine
                    self.logLines.append("엔진 준비 중… (첫 실행은 수 분 가능)")
                    self.currentIter = 1
                    let info = try await staged(modelID) { [weak self] phase in
                        Task { @MainActor in
                            switch phase {
                            case .preparing: self?.stage = .initEngine
                            case .measuring: self?.stage = .measure
                            case .summarizing: self?.stage = .summarize
                            }
                        }
                    }
                    self.stage = .summarize
                    self.completeNative(Self.makeMetrics(info))
                } catch is CancellationError {
                    self.interruptNative()
                } catch {
                    self.failNative(error)
                }
            }
            return
        }
        if let measure = nativeBenchmark {
            runNative(modelID: modelID, measure: measure)
        }
    }

    /// CLI 측정 (기존 경로): `litert-lm benchmark` 프로세스+파싱.
    private func runCLI(modelID: String) {
        activeModelID = modelID
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: UvManager.litertBin)
        proc.arguments = ["benchmark", modelID]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard !text.isEmpty else { return }
            Task { @MainActor in
                self?.ingest(text)
            }
        }
        proc.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.finish(code: proc.terminationStatus)
            }
        }
        process = proc
        do {
            try proc.run()
        } catch {
            running = false
            stopTick()
            logger.error(code: "E-MAC-NET-0004", feature: "벤치마크", "실행 실패: \(error)")
            emitRecord(status: .failed, metrics: nil)
        }
    }

    func cancel() {
        // T-216: UI 상태는 즉시 내리고(중지 체감 개선), 엔진 중단은 병행.
        let wasRunning = running
        nativeTask?.cancel()
        nativeTask = nil
        process?.terminate()
        stopTick()
        if wasRunning {
            running = false
            logLines.append("— 사용자 중단 —")
            emitRecord(status: .cancelled, metrics: metrics)
        }
        logger.info(feature: "벤치마크", "사용자 중단")
    }

    /// T-217: 종료 기록 전달 (중복 방지: 호출 측에서 1회만).
    private var didEmitRecord = false
    private func emitRecord(status: BenchmarkStatus, metrics: Metrics?) {
        guard !didEmitRecord else { return }
        didEmitRecord = true
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? elapsed
        let rec = BenchmarkRecord(date: Date(), modelID: activeModelID.isEmpty ? (pendingModelID ?? "") : activeModelID,
                                  route: activeRoute, metrics: metrics, durationSec: duration, status: status,
                                  logTail: Array(logLines.suffix(100)))
        onRecord?(rec)
        // 다음 측정을 위해 리셋 (기록 후 중복 전달 방지).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.didEmitRecord = false
        }
    }
}

// MARK: - CLI 출력 파싱 (T-126 분리: 클래스 본문 길이 분산)

private extension BenchmarkStore {
    /// 앱 내 엔진 결과 매핑 (T-216 분리): EngineBenchmark → Metrics.
    nonisolated static func makeMetrics(_ info: EngineBenchmark) -> Metrics {
        Metrics(backend: "앱 내 엔진 GPU",
                prefillTokens: info.prefillTokens,
                decodeTokens: info.decodeTokens,
                runs: 1,
                prefillSpeed: info.prefillSpeed,
                decodeSpeed: info.decodeSpeed,
                initTime: info.initTime,
                ttft: info.ttft)
    }

    /// 실수 지표 테이블 (T-126): prefix → Metrics 필드.
    static let doubleFields: [(String, WritableKeyPath<Metrics, Double>)] = [
        ("Prefill speed:", \.prefillSpeed),
        ("Decode speed:", \.decodeSpeed),
        ("Init time:", \.initTime),
        ("Time to first token:", \.ttft)
    ]

    /// 정수 지표 테이블 (T-126): prefix → Metrics 필드.
    static let intFields: [(String, WritableKeyPath<Metrics, Int>)] = [
        ("Number of tokens in prefill:", \.prefillTokens),
        ("Number of tokens in decode:", \.decodeTokens)
    ]

    func ingest(_ text: String) {
        let lines = text.split(separator: "\n").map(String.init)
        logLines.append(contentsOf: lines)
        if logLines.count > 300 { logLines.removeFirst(100) }
        var met = metrics ?? Metrics()
        for line in lines {
            ingestLine(line, into: &met)
        }
        metrics = met
    }

    /// 한 줄 반영 (T-126 분리): 단계 전이 + 테이블 지표.
    func ingestLine(_ line: String, into met: inout Metrics) {
        if line.contains("Benchmarking model:") { stage = .initEngine }
        if let (cur, tot) = Self.match(line, "Running iteration (\\d+) of (\\d+)") {
            stage = .measure
            currentIter = cur
            totalIter = tot
        }
        if line.contains("Results") { stage = .summarize }
        for (prefix, path) in Self.doubleFields {
            if let val = Self.value(line, prefix) { met[keyPath: path] = val }
        }
        for (prefix, path) in Self.intFields {
            if let val = Self.int(line, prefix) { met[keyPath: path] = val }
        }
        if line.hasPrefix("Backend") {
            let tail = line.split(separator: ":").last
                .map { $0.trimmingCharacters(in: .whitespaces) }
            met.backend = tail ?? met.backend
        }
    }

    func finish(code: Int32) {
        running = false
        stopTick()
        stage = metrics == nil ? .initEngine : .done
        if code == 0, metrics != nil {
            stage = .done
            let met = metrics!
            logger.perf(feature: "벤치마크",
                        "완료 prefill=\(met.prefillSpeed) decode=\(met.decodeSpeed) ttft=\(met.ttft)")
            emitRecord(status: .done, metrics: met)
        } else if code != 0 {
            logger.error(code: "E-MAC-NET-0004", feature: "벤치마크", "종료코드=\(code)")
            if code != 15 { emitRecord(status: .failed, metrics: metrics) }
            // SIGTERM(15)=사용자 중단은 cancel()에서 이미 기록.
        }
    }

    // MARK: - 관대한 정규식 파서 (출력 변형에 강하게)
    static func match(_ line: String, _ pattern: String) -> (Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let found = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              found.numberOfRanges == 3,
              let r1 = Range(found.range(at: 1), in: line),
              let r2 = Range(found.range(at: 2), in: line)
        else { return nil }
        guard let first = Int(line[r1]), let second = Int(line[r2]) else { return nil }
        return (first, second)
    }

    static func value(_ line: String, _ prefix: String) -> Double? {
        guard line.contains(prefix) else { return nil }
        let num = line.replacingOccurrences(of: prefix, with: "")
            .replacingOccurrences(of: "tokens/s", with: "")
            .replacingOccurrences(of: "s", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(num)
    }

    static func int(_ line: String, _ prefix: String) -> Int? {
        guard line.contains(prefix) else { return nil }
        let num = line.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespaces)
        return Int(num)
    }
}
