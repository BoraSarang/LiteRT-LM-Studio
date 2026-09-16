import Foundation

/// 추론 엔진 모드 (T-130, 전역 설정, 기본 CLI).
/// - cli: `litert-lm serve` 데몬 + OpenAI 호환 HTTP (기존 동작).
/// - native: SPM LiteRTLM Engine 프로세스 내 추론 (opt-in).
enum EngineMode: String, CaseIterable {
    case cli
    case native

    var title: String {
        switch self {
        case .cli: "서버"
        case .native: "앱 내 엔진"
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

/// Ollama식 통합 상태 (T-183): 모델은 공용, 호출 경로(데몬/네이티브)만 다름.
/// 대화 가능 = 데몬 실행 중 OR 네이티브 준비됨. 사이드바 상태 1줄 표시용.
struct UnifiedStatus: Equatable {
    var title: String
    var detail: String
    var live: Bool
    var unlinked: Bool

    /// 통합 상태 판정 (순수, 테스트 가능, T-183).
    /// - preparedLabel: 표시용 모델명 (호출 측이 ModelAlias.display로 변환).
    nonisolated static func resolve(daemonRunning: Bool, unlinkedRunning: Bool,
                                    engineMode: EngineMode,
                                    preparedLabel: String?) -> UnifiedStatus {
        if unlinkedRunning {
            return UnifiedStatus(title: "외부 실행 중 (미연결)", detail: "▶ 버튼으로 재연결",
                                 live: false, unlinked: true)
        }
        if daemonRunning {
            if engineMode == .native, let label = preparedLabel {
                return UnifiedStatus(title: "대화 가능", detail: "서버+앱 내 엔진 · \(label)",
                                     live: true, unlinked: false)
            }
            return UnifiedStatus(title: "대화 가능", detail: "데몬 :9379",
                                 live: true, unlinked: false)
        }
        if engineMode == .native, let label = preparedLabel {
            return UnifiedStatus(title: "대화 가능", detail: "네이티브 · \(label)",
                                 live: true, unlinked: false)
        }
        // T-187: 중지 사유를 선택 경로 기준으로 안내.
        return UnifiedStatus(title: "중지됨",
                             detail: engineMode == .native ? "엔진 실행 필요" : "서버 시작 (⌘R)",
                             live: false, unlinked: false)
    }
}
/// 생성 옵션 묶음 (T-176): CLI·네이티브 공통 샘플링+출력 파라미터.
/// 기본값은 describe 실측·Gallery 대조 (temp 1.0·topK 64·topP 0.95).
struct GenerationOptions: Equatable {
    var temperature = 1.0
    var topK = 64
    var topP = 0.95
    var seed: Int?
    var maxTokens: Int?
    var thinkingEnabled = false
    var thinkingBudget = -1
    var systemPrompt = ""
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

/// 벤치마크 진행 단계 알림 (T-216): 엔진 내부 prepare→측정→정리를 UI 단계에 매핑.
enum BenchmarkPhase: Equatable {
    case preparing
    case measuring
    case summarizing
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
    /// 스트리밍 추론. history는 현재 제외 과거 turns (윈도우 적용분, 초기 메시지로 사용).
    /// keyHistory는 전체 전사 키 항목 (T-193, 윈도우 슬라이드와 무관한 재사용 판정용).
    func stream(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        keyHistory: [String],
        options: GenerationOptions
    ) -> AsyncThrowingStream<String, Error>
    /// 벤치마크 측정 (T-132): 고정 프롬프트 1턴 실측.
    func benchmark(modelID: String) async throws -> EngineBenchmark
    /// 진행 중 추론 중단.
    func cancel()
}
