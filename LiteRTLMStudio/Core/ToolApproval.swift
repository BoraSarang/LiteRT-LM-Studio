import Foundation

/// 도구 실행 원장 (T-266 S-2): 실행 결과를 순서대로 보관, 턴 종료 시 배출.
/// run()은 호출 ID를 모르므로 순서 매칭 (벤더가 순차 실행).
actor ToolLedger {
    static let shared = ToolLedger()

    struct Entry: Sendable {
        let toolName: String
        let detail: String
        let result: String
        let denied: Bool
        let failed: Bool
        let at: Date
    }

    private var entries: [Entry] = []

    func record(toolName: String, detail: String, result: String,
                denied: Bool, failed: Bool = false) {
        entries.append(Entry(toolName: toolName, detail: detail, result: result,
                             denied: denied, failed: failed, at: Date()))
    }

    /// 턴 시작 이후 항목을 순서대로 배출 (테스트 가능).
    func drain(since: Date) -> [Entry] {
        let kept = entries.filter { $0.at >= since }
        entries.removeAll { $0.at >= since }
        return kept
    }

    /// 배출+상태 매칭 (순수, 테스트 가능): 순서대로 done/denied/failed 부여.
    nonisolated static func statuses(count: Int, outcomes: [Entry]) -> [ToolCallStatus] {
        (0 ..< count).map { idx in
            guard idx < outcomes.count else { return .received }
            if outcomes[idx].denied { return .denied }
            if outcomes[idx].failed { return .failed }
            return .done
        }
    }
}

/// 도구 승인 게이트 (T-266 S-2): Ask 모드 1회성 허용/거부, 120초 무응답 거부.
@MainActor
final class ToolApproval: ObservableObject {
    static let shared = ToolApproval()
    nonisolated static var timeout: TimeInterval { 120 }

    struct Request: Identifiable {
        let id = UUID()
        let toolName: String
        let detail: String
    }

    @Published private(set) var pending: Request?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutWork: DispatchWorkItem?
    private let logger = DebugLogger.shared

    /// 승인 요청. 허용 true, 거부·타임아웃·중복 false.
    func request(toolName: String, detail: String) async -> Bool {
        guard pending == nil else {
            logger.info(feature: "도구", "\(toolName) 승인 중복 요청, 거부 처리")
            return false
        }
        pending = Request(toolName: toolName, detail: detail)
        logger.info(feature: "도구", "승인 요청: \(toolName) \(detail.prefix(40))")
        return await withCheckedContinuation { cont in
            continuation = cont
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.logger.info(feature: "도구", "\(toolName) 승인 시간 초과, 거부 처리")
                    self?.finish(with: false)
                }
            }
            timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: work)
        }
    }

    /// 사용자 응답 (허용/거부).
    func resolve(_ allow: Bool) {
        logger.info(feature: "도구", allow ? "사용자 허용" : "사용자 거부")
        finish(with: allow)
    }

    private func finish(with allow: Bool) {
        timeoutWork?.cancel()
        timeoutWork = nil
        pending = nil
        continuation?.resume(returning: allow)
        continuation = nil
    }
}
