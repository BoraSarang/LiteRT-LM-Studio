import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// 추종 게이트 상태 박스 (T-044): escaping 휠 모니터가 최신값을 읽기 위한 참조형.
/// `pinnedToBottom`(@State, 오버레이 표시용)과 별도로 제스처 시각만 보관.
final class FollowGate: ObservableObject {
    var hover = false
    var lastWheel = Date.distantPast
    var lastContent: CGFloat = 0 // T-048 마지막 관측 문서 높이 (증가 감지용)
    var maxTextLen: Int = 0 // T-106 마지막 응답 텍스트 길이 최대치 (stale 높이 무관 추종용)
    var entryWorks: [DispatchWorkItem] = [] // T-078 진입 점프 독립 예약
    var entrySince = Date.distantPast // T-078 진입 시작 시각 (휠 존중용)
    var wheelAccum: CGFloat = 0 // T-080 휠 누적 (미세 접촉 무시용)
    var lastDocHeights: [CGFloat] = [] // T-080 진입 수렴 안정 판정용
    var kickDone = false // T-083 프록시 킥 1회 플래그
    var verifyKickDone = false // T-086 수렴 검증 킥 플래그
    var lastJumpSession: UUID? // T-112 이중 발사 제거용 (마지막 점프 세션)
    var lastJumpAt = Date.distantPast // T-112 이중 발사 제거용 (마지막 점프 시각)
}

/// 상위 NSScrollView 탐색 (T-047): 절대좌표 점프용 AppKit 진입점. 렌더 없음(AIModelTalk 이식).
/// ScrollViewProxy의 레이아웃 스냅샷 오차 없이 문서 끝으로 이동한다.
struct ScrollViewFinder: NSViewRepresentable {
    let onFound: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        DispatchQueue.main.async { [weak host] in
            guard let host else { return }
            // 계층 부착이 늦는 경우가 있어 재시도 — 발견 시 즉시 중단.
            var attempt = 0
            func walk() {
                var current: NSView? = host
                while let candidate = current {
                    if let scrollView = candidate as? NSScrollView {
                        onFound(scrollView)
                        return
                    }
                    current = candidate.superview
                }
                attempt += 1
                if attempt < 40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: walk)
                }
            }
            walk()
        }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
