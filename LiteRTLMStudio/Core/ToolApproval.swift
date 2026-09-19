import AppKit
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
    /// 호출부 2곳은 의도적 분리 — 완료 반영은 인덱스 순서, 서버 재시도는 callID 매칭.
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
    private var requestedAt: Date? // T-347: 승인 대기 실측 분리
    private let logger = DebugLogger.shared

    /// 승인 요청. 허용 true, 거부·타임아웃·중복 false.
    /// T-289: 채팅 취소 시 즉시 거부 해제 (120초 고착 방지).
    func request(toolName: String, detail: String) async -> Bool {
        guard pending == nil else {
            logger.info(feature: "도구", "\(toolName) 승인 중복 요청, 거부 처리")
            return false
        }
        pending = Request(toolName: toolName, detail: detail)
        requestedAt = Date()
        logger.info(feature: "도구", "승인 요청: \(toolName) \(detail.prefix(40))")
        // T-346: 별창 포커스 시 메인 창 뒤에 팝업이 가려져 "안 물어봐"로 보이는 경우 대응.
        // 2초 뒤에도 대기 중이면 앱을 앞으로 가져온다 (승인·거부·취소 흐름 불변).
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.pending != nil else { return }
            self.logger.info(feature: "도구", "승인 대기 중 — 메인 창을 앞으로 가져옴")
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == mainWindowTitle })?.makeKeyAndOrderFront(nil)
        }
        return await withTaskCancellationHandler {
            await self.suspendApproval(toolName: toolName)
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.pending != nil else { return }
                self.logger.info(feature: "도구", "\(toolName) 승인 대기 중 채팅 취소 → 거부 해제")
                self.finish(with: false)
            }
        }
    }

    /// 승인 대기 서스펜드 (T-289 분리): 취소 선착 시 즉시 거부 반환.
    private func suspendApproval(toolName: String) async -> Bool {
        await withCheckedContinuation { cont in
            guard !Task.isCancelled else {
                pending = nil
                cont.resume(returning: false)
                return
            }
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

    /// 사용자 응답 (허용/거부). T-283: 멱등 — 팝업 닫힘 시 중복 호출 무시.
    func resolve(_ allow: Bool) {
        guard pending != nil else { return }
        logger.info(feature: "도구", allow ? "사용자 허용" : "사용자 거부")
        finish(with: allow)
    }

    private func finish(with allow: Bool) {
        guard continuation != nil else { return } // T-289: 이중 재개 방지
        timeoutWork?.cancel()
        timeoutWork = nil
        pending = nil
        if let at = requestedAt {
            // T-347: 승인 대기 실측 (실행 로그와 분리) — 허용/거부/타임아웃 모두 기록.
            let wait = Date().timeIntervalSince(at)
            logger.perf(feature: "도구", "승인 대기 \(String(format: "%.2f", wait))s (\(allow ? "허용" : "거부"))")
        }
        requestedAt = nil
        continuation?.resume(returning: allow)
        continuation = nil
    }
}
