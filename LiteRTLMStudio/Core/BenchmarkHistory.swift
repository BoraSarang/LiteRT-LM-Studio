import Foundation

// MARK: - T-224 측정 단계 (BenchmarkStore.Stage 별칭 원본)

/// 측정 4단계 (초기화→측정→정리→완료).
enum BenchmarkStage: Int, CaseIterable {
    case initEngine = 0, measure, summarize, done
    var title: String {
        switch self {
        case .initEngine: "1. 엔진 초기화"
        case .measure: "2. 측정 실행"
        case .summarize: "3. 결과 정리"
        case .done: "4. 완료"
        }
    }
}

// MARK: - T-216 예상·경과 문구 (순수, 테스트 가능)

extension BenchmarkStore {
    /// T-216: 예상 소요 문구 (순수, 테스트 가능).
    nonisolated static func estimateText(route: EngineMode, avgDuration: TimeInterval?) -> String {
        if let avg = avgDuration, avg > 0 {
            let lo = max(10, avg * 0.7), hi = avg * 1.3
            return "예상 약 \(elapsedText(lo))~\(elapsedText(hi)) (이전 기록 평균)"
        }
        switch route {
        case .native: return "예상 약 1~3분 (첫 준비 포함)"
        case .cli: return "예상 약 3~10분 (12B는 워밍업 타임아웃 가능)"
        }
    }

    /// T-216: 경과 표기 (순수, 테스트 가능).
    nonisolated static func elapsedText(_ sec: TimeInterval) -> String {
        let total = max(0, Int(sec))
        if total < 60 { return "\(total)초" }
        return "\(total / 60)분 \(total % 60)초"
    }
}

// MARK: - T-217 히스토리 기록·보관

/// 측정 종료 상태.
enum BenchmarkStatus: String, Codable, Equatable {
    case done
    case cancelled
    case failed

    var title: String {
        switch self {
        case .done: "완료"
        case .cancelled: "중단"
        case .failed: "실패"
        }
    }
}

/// 히스토리 1건 (Codable 영속).
struct BenchmarkRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var modelID: String
    var route: EngineMode
    var metrics: BenchmarkStore.Metrics?
    var durationSec: TimeInterval
    var status: BenchmarkStatus
    /// T-224: 종료 시점 로그 꼬리 (기록별 원문 출력용, 최대 100줄).
    var logTail: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, date, modelID, route, metrics, durationSec, status, logTail
    }

    /// 목록 표시 1줄 (순수, 테스트 가능).
    var summary: String {
        let speed = metrics.map { String(format: "%.1f tok/s", $0.decodeSpeed) } ?? "-"
        return "\(modelID) · \(route.title) · \(status.title) · \(speed)"
    }
}

extension EngineMode: Codable {}

/// 구 JSON 호환 디코딩 (T-224): logTail 없으면 빈 배열 (memberwise 유지용 익스텐션).
extension BenchmarkRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        modelID = try c.decode(String.self, forKey: .modelID)
        route = try c.decode(EngineMode.self, forKey: .route)
        metrics = try c.decodeIfPresent(BenchmarkStore.Metrics.self, forKey: .metrics)
        durationSec = try c.decodeIfPresent(TimeInterval.self, forKey: .durationSec) ?? 0
        status = try c.decode(BenchmarkStatus.self, forKey: .status)
        logTail = try c.decodeIfPresent([String].self, forKey: .logTail) ?? []
    }
}

/// 보관 수 설정 (T-217): 10(기본)/50/100/제한없음. UserDefaults "benchmarkRetention".
enum BenchmarkRetention: Int, CaseIterable, Codable {
    case ten = 10
    case fifty = 50
    case hundred = 100
    case unlimited = 0

    var title: String {
        switch self {
        case .ten: "10개"
        case .fifty: "50개"
        case .hundred: "100개"
        case .unlimited: "제한 없음"
        }
    }

    nonisolated static func current(_ defaults: UserDefaults = .standard) -> BenchmarkRetention {
        BenchmarkRetention(rawValue: defaults.object(forKey: "benchmarkRetention") as? Int ?? 10)
            ?? .ten
    }
}

/// 히스토리 영속 (JSON, cap 적용).
@MainActor
final class BenchmarkHistoryStore: ObservableObject {
    @Published var records: [BenchmarkRecord] = []
    /// T-225: 창·사이드바 공유 선택 (채팅 currentSessionID 대응).
    @Published var selectedRecordID: BenchmarkRecord.ID?
    let storageURL: URL

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            self.storageURL = Self.resolvedURL()
        }
        load()
    }

    nonisolated static func resolvedURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LiteRTLMStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("BenchmarkHistory.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([BenchmarkRecord].self, from: data)
        else { return }
        records = decoded.sorted { $0.date > $1.date }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: storageURL)
    }

    /// 추가 + 보관 수 적용 (순수 cap은 테스트 가능).
    func append(_ record: BenchmarkRecord, retention: BenchmarkRetention) {
        records.insert(record, at: 0)
        records = Self.capped(records, retention: retention)
        save()
    }

    func remove(_ id: BenchmarkRecord.ID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clear() {
        records = []
        save()
    }

    /// 최근 N건 (사이드바 표시용, 순수 호출).
    func recent(limit: Int = 3) -> [BenchmarkRecord] { Array(records.prefix(limit)) }

    /// 모델 필터 (순수, 테스트 가능).
    nonisolated static func filtered(_ records: [BenchmarkRecord],
                                     modelID: String?) -> [BenchmarkRecord] {
        guard let modelID, !modelID.isEmpty, modelID != "전체" else { return records }
        return records.filter { $0.modelID == modelID }
    }

    /// 보관 수 적용 (순수, 테스트 가능).
    nonisolated static func capped(_ records: [BenchmarkRecord],
                                   retention: BenchmarkRetention) -> [BenchmarkRecord] {
        guard retention != .unlimited else { return records }
        return Array(records.prefix(retention.rawValue))
    }

    /// 같은 모델 평균 소요 (예측·비교용, 최대 5건).
    nonisolated static func averageDuration(_ records: [BenchmarkRecord],
                                            modelID: String, limit: Int = 5) -> TimeInterval? {
        let same = records.filter { $0.modelID == modelID && $0.status == .done }.prefix(limit)
        guard !same.isEmpty else { return nil }
        return same.reduce(0) { $0 + $1.durationSec } / Double(same.count)
    }
}

// MARK: - T-221 상세 표시 우선순위 (순수, 테스트 가능)

/// 상세 표시 우선순위: 실행 중 > 명시적 선택 > 최신 라이브 결과 > 최신 기록 > 빈 상태.
/// 이전 버그: `metrics != nil`이면 기록 분기가 막혀 클릭해도 "측정 전"이 뜸.
enum BenchmarkDetailMode: Equatable {
    case running
    case selected
    case live
    case latest
    case empty

    nonisolated static func resolve(running: Bool, hasSelection: Bool,
                                    liveDone: Bool, hasHistory: Bool) -> BenchmarkDetailMode {
        if running { return .running }
        if hasSelection { return .selected }
        if liveDone { return .live }
        if hasHistory { return .latest }
        return .empty
    }
}

// MARK: - T-218 AI 분석 (요청 실행; 프롬프트·작업은 BenchmarkAnalysis.swift)

extension BenchmarkStore {
    /// 분석 요청 묶음 (T-126: 파라미터 수 제한 대응).
    private struct AnalysisRequest {
        var baseURL: URL
        var model: String
        var route: EngineMode
        var options: GenerationOptions
        var engine: (any InferenceEngine)?
        var prompt: String
    }

    /// T-218/T-224/T-227: 측정한 경로·모델로 분석 (세션 오염 방지: 별도 요청, 히스토리 미기록).
    /// slotID가 있으면 해당 기록 슬롯에, 없으면 라이브 결과에 저장.
    /// 앱 내 엔진는 해당 모델로 준비된 엔진이 필요 (자동 준비 없음 — 발열·시간).
    func analyze(record: BenchmarkRecord, avgDuration: TimeInterval?,
                 chat: ChatStore, slotID: BenchmarkRecord.ID?) {
        guard !analyzing else { return }
        analyzing = true
        analyzingSlotID = slotID
        analysisError = nil
        let job = AnalysisJob.make(record: record, avgDuration: avgDuration,
                                   modelDisplay: ModelAlias.display(id: record.modelID))
        analysisEngineLabel = job.engineLabel
        if let slotID {
            analysisEngineByRecord[slotID] = job.engineLabel
            analysisCache[slotID] = ""
        } else {
            analysisMarkdown = ""
        }
        logger.info(feature: "벤치마크", "AI 분석 시작 (\(job.engineLabel))")
        if record.route == .native, chat.inferenceEngine?.preparedModelID != record.modelID {
            analyzing = false
            analyzingSlotID = nil
            analysisError = "앱 내 엔진이 준비되지 않았습니다. 사이드바 엔진 행에서 실행 후 다시 시도해 주세요."
            logger.info(feature: "벤치마크", "분석 차단 (앱 내 엔진 미준비)")
            return
        }
        let request = AnalysisRequest(baseURL: chat.baseURL, model: record.modelID, route: record.route,
                                      options: chat.generationOptions(),
                                      engine: chat.inferenceEngine, prompt: job.prompt)
        Task { [weak self] in
            do {
                try await Self.analyzeResult(store: self, request: request, slotID: slotID)
            } catch is CancellationError {
                self?.analysisError = "분석이 중단되었습니다."
            } catch {
                self?.analysisError = "분석 실패: 서버 상태를 확인해 주세요. (E-MAC-ENG-0002)"
                self?.logger.error(code: "E-MAC-ENG-0002", feature: "벤치마크", "분석 실패: \(error)")
            }
            self?.analyzing = false
            self?.analyzingSlotID = nil
        }
    }

    /// 분석 요청 실행 (T-126 분리, 동기 throw 전달).
    private static func analyzeResult(store: BenchmarkStore?,
                                      request: AnalysisRequest,
                                      slotID: BenchmarkRecord.ID?) async throws {
        let text: String
        if request.route == .native, let engine = request.engine {
            text = try await collectNative(engine: engine, prompt: request.prompt,
                                           options: request.options)
        } else {
            text = try await requestCLI(baseURL: request.baseURL,
                                        model: request.model, prompt: request.prompt)
        }
        if let slotID {
            store?.analysisCache[slotID] = text
        } else {
            store?.analysisMarkdown = text
        }
        store?.logger.info(feature: "벤치마크", "AI 분석 완료 \(text.count)자")
    }

    private static func collectNative(engine: any InferenceEngine, prompt: String,
                                      options: GenerationOptions) async throws -> String {
        var acc = ""
        let stream = await engine.stream(prompt: prompt, image: nil, history: [],
                                         options: options, sessionID: "")
        for try await chunk in stream {
            try Task.checkCancellation()
            acc += chunk
        }
        return acc
    }

    private struct CLIChatChoice: Decodable {
        var message: CLIChatMessage?
    }

    private struct CLIChatMessage: Decodable {
        var content: String?
    }

    private struct CLIChatResponse: Decodable {
        var choices: [CLIChatChoice]?
    }

    private static func requestCLI(baseURL: URL, model: String, prompt: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.7, "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(CLIChatResponse.self, from: data)
        return decoded.choices?.first?.message?.content ?? ""
    }
}
