import Foundation

/// 추론 엔진 모드 (T-130, 전역 설정, 기본 CLI).
/// - cli: `litert-lm serve` 데몬 + OpenAI 호환 HTTP (기존 동작).
/// - native: SPM LiteRTLM Engine 프로세스 내 추론 (opt-in).
enum EngineMode: String, CaseIterable {
    case cli
    case native

    var title: String {
        switch self {
        case .cli: "CLI 데몬"
        case .native: "네이티브"
        }
    }

    /// 저장 키 "engineMode" 읽기 (미설정 시 cli).
    nonisolated static func current() -> EngineMode {
        EngineMode(rawValue: UserDefaults.standard.string(forKey: "engineMode") ?? "") ?? .cli
    }
}

/// 전송 히스토리 범위 (T-149, 전역 설정, 기본 제한 없음).
/// 1턴 = 사용자 1 + 어시스턴트 1. 0은 제한 없음(기존 동작 그대로).
enum HistoryWindow: Int, CaseIterable {
    case unlimited = 0
    case turns10 = 10
    case turns20 = 20
    case turns40 = 40

    var title: String {
        switch self {
        case .unlimited: "제한 없음"
        case .turns10: "10턴"
        case .turns20: "20턴"
        case .turns40: "40턴"
        }
    }

    /// 저장 키 "historyTurns" 읽기 (미설정 시 0=제한 없음).
    nonisolated static func currentTurns() -> Int {
        UserDefaults.standard.integer(forKey: "historyTurns")
    }
}

/// 엔진 오류 (T-130): LiteRTLM 모듈 비의존. ChatStore가 코드로 매핑.
enum EngineError: Error, Equatable {
    case notReady
    case initFailed(String)
    case inferenceFailed(String)

    /// error_message_ko.json 키.
    var code: String {
        switch self {
        case .notReady, .initFailed: "E-MAC-ENG-0001"
        case .inferenceFailed: "E-MAC-ENG-0002"
        }
    }
}

/// 네이티브 벤치마크 결과 (T-132): BenchmarkInfo 매핑용 순수 값.
struct EngineBenchmark: Equatable {
    var initTime = 0.0
    var ttft = 0.0
    var prefillTokens = 0
    var prefillSpeed = 0.0
    var decodeTokens = 0
    var decodeSpeed = 0.0
}

/// 네이티브 추론 엔진 추상 (T-130). LiteRTLM import 없이 ChatStore·테스트에서 사용.
@MainActor
protocol InferenceEngine: AnyObject {
    /// 준비된 모델 ID (없으면 nil).
    var preparedModelID: String? { get }
    /// 모델 준비 (lazy init, 이미 준비됐으면 즉시 반환). MTP는 Capabilities로 자체 판정.
    func prepare(modelID: String) async throws
    /// 메모리 반납.
    func release()
    /// 스트리밍 추론. history는 현재 제외 과거 turns.
    func stream(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        temperature: Double
    ) -> AsyncThrowingStream<String, Error>
    /// 벤치마크 측정 (T-132): 고정 프롬프트 1턴 실측.
    func benchmark(modelID: String) async throws -> EngineBenchmark
    /// 진행 중 추론 중단.
    func cancel()
}
