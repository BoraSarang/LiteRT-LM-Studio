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

/// 전송 히스토리 범위 (T-149, 전역 설정, 기본 10턴).
/// 1턴 = 사용자 1 + 어시스턴트 1. 명시적 0=제한 없음.
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

    /// 저장 키 "historyTurns" 읽기. 미설정 시 10턴 기본, 명시적 0은 제한 없음.
    nonisolated static func currentTurns() -> Int {
        guard UserDefaults.standard.object(forKey: "historyTurns") != nil else {
            return HistoryWindow.turns10.rawValue
        }
        return UserDefaults.standard.integer(forKey: "historyTurns")
    }
}

/// Ollama식 통합 상태 (T-183): 모델은 공용, 호출 경로(데몬/앱 내 엔진)만 다름.
/// 대화 가능 = 데몬 실행 중 OR 앱 내 엔진 준비됨. 사이드바 상태 1줄 표시용.
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
            return UnifiedStatus(title: "대화 가능", detail: "앱 내 엔진 · \(label)",
                                 live: true, unlinked: false)
        }
        // T-187: 중지 사유를 선택 경로 기준으로 안내.
        return UnifiedStatus(title: "중지됨",
                             detail: engineMode == .native ? "엔진 실행 필요" : "서버 시작 (⌘R)",
                             live: false, unlinked: false)
    }
}
/// 생성 옵션 묶음 (T-176): CLI·앱 내 엔진 공통 샘플링+출력 파라미터.
/// 기본값은 describe 실측·Gallery 대조 (temp 1.0·topK 64·topP 0.95).
struct GenerationOptions: Equatable, Hashable {
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
    case timeout(String) // T-311: 응답 스톨 워치독 발화

    /// error_message_ko.json 키.
    var code: String {
        switch self {
        case .notReady, .initFailed: "E-MAC-ENG-0001"
        case .inferenceFailed: "E-MAC-ENG-0002"
        case .timeout: "E-MAC-ENG-0005"
        }
    }
}

/// 앱 내 엔진 벤치마크 결과 (T-132): BenchmarkInfo 매핑용 순수 값.
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

/// 앱 내 엔진 추론 엔진 추상 (T-130). LiteRTLM import 없이 ChatStore·테스트에서 사용.
@MainActor
protocol InferenceEngine: AnyObject {
    /// 준비된 모델 ID (없으면 nil).
    var preparedModelID: String? { get }
    /// 모델 준비 (lazy init, 이미 준비됐으면 즉시 반환). MTP는 Capabilities로 자체 판정.
    func prepare(modelID: String) async throws
    /// 메모리 반납.
    func release()
    /// 스트리밍 추론. history는 현재 제외 과거 turns (윈도우 적용분, 초기 메시지로 사용).
    /// sessionID는 채팅방 식별자 — 같은 방의 후속 턴은 동일 Conversation을 이어써 KV를 잇는다.
    func stream(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        options: GenerationOptions,
        sessionID: String
    ) -> AsyncThrowingStream<String, Error>
    /// 벤치마크 측정 (T-132): 고정 프롬프트 1턴 실측.
    func benchmark(modelID: String) async throws -> EngineBenchmark
    /// 진행 중 추론 중단.
    func cancel()
    /// 세션 대화 제거 (재시도 꼬리 정리·1회성 호출 정리용). 기본 no-op.
    func evictSession(modelID: String, sessionID: String)
}

/// 엔진 기본값: 이벤트 스트림 매핑 (T-266 S-1), 세션 제거 no-op.
extension InferenceEngine {
    func evictSession(modelID: String, sessionID: String) {}
    func streamEvents(
        prompt: String,
        image: ChatStore.ChatImage?,
        history: [(role: String, text: String)],
        options: GenerationOptions,
        sessionID: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let base = stream(prompt: prompt, image: image, history: history,
                          options: options, sessionID: sessionID)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in base {
                        continuation.yield(.text(chunk))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
