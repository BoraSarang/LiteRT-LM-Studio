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
    var clampWorks: [DispatchWorkItem] = [] // T-202 지연 보정 독립 예약 (finish 취소와 분리)
    var entrySince = Date.distantPast // T-078 진입 시작 시각 (휠 존중용)
    var wheelAccum: CGFloat = 0 // T-080 휠 누적 (미세 접촉 무시용)
    var lastDocHeights: [CGFloat] = [] // T-080 진입 수렴 안정 판정용
    var kickDone = false // T-083 진입 킥 1회 플래그
    var lastJumpSession: UUID? // T-112 이중 발사 제거용 (마지막 점프 세션)
    var lastJumpAt = Date.distantPast // T-112 이중 발사 제거용 (마지막 점프 시각)
    var entryEpoch = 0 // T-202 진입 세대 (낡은 폴링 폐기용)
    var finishDocH: CGFloat = 0 // T-204 종료 시점 문서 높이 (붕괴·고착 판정 기준)
    var finishOffset: CGFloat = 0 // T-204 종료 시점 오프셋 (이동량 가드 기준)
    var anchorMaxY: CGFloat = 0 // T-206 하단 앵커 실측 (AppKit 추정과 대조용, @State 아님)
}

/// 상위 NSScrollView 탐색 (T-047): 절대좌표 점프용 AppKit 진입점. 렌더 없음(AIModelTalk 이식).
/// ScrollViewProxy의 레이아웃 스냅샷 오차 없이 문서 끝으로 이동한다.
/// T-207: updateNSView 재탐색으로 교체 감지 (구 포인터 명령 사각지대 해소).
struct ScrollViewFinder: NSViewRepresentable {
    let onFound: (NSScrollView) -> Void

    /// 발견 인스턴스 보관 (T-207): 동일이면 @State 갱신 생략 (루프 방지).
    final class Coord {
        weak var found: NSScrollView?
    }

    func makeCoordinator() -> Coord { Coord() }

    /// 조상 체인에서 NSScrollView 탐색 (순수 조회, 테스트 불가-AppKit).
    nonisolated static func find(from host: NSView) -> NSScrollView? {
        var current: NSView? = host
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView { return scrollView }
            current = candidate.superview
        }
        return nil
    }

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        let coord = context.coordinator
        let report = onFound
        DispatchQueue.main.async { [weak host] in
            guard let host else { return }
            // 계층 부착이 늦는 경우가 있어 재시도 — 발견 시 즉시 중단.
            var attempt = 0
            func walk() {
                if let found = Self.find(from: host) {
                    coord.found = found
                    report(found)
                    return
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

    func updateNSView(_ nsView: NSView, context: Context) {
        // T-207 교체 감지: SwiftUI가 스크롤뷰를 교체하면 구 포인터가 사각지대.
        // 비동기+인스턴스 변경 시에만 보고 (빈번 호출·루프 방지).
        let coord = context.coordinator
        let report = onFound
        DispatchQueue.main.async { [weak nsView] in
            guard let host = nsView,
                  let found = Self.find(from: host),
                  found !== coord.found else { return }
            let replaced = coord.found != nil // 최초 발견이면 교체 아님
            coord.found = found
            if replaced {
                DebugLogger.shared.info(feature: "스크롤", "스크롤뷰 교체 감지")
            }
            report(found)
        }
    }
}

// MARK: - 보정 (파일 길이 관리용 분리, T-204)

extension ContentView {
    /// 빈 영역 판정 (순수, 테스트 가능, T-198): 문서 끝 초과면 보정 대상.
    /// 방 전환 잔재 등 오프셋이 문서 밖에 있으면 타임라인이 휑하게 보임.
    nonisolated static func blankOffset(cur: CGFloat, docHeight: CGFloat, clipHeight: CGFloat,
                                        threshold: CGFloat = 8) -> Bool {
        cur > max(0, docHeight - clipHeight) + threshold
    }

    /// 빈 영역 보정 (T-198): 문서 밖 오프셋만 하단으로 수렴.
    /// 정상 위치(읽는 중 포함)는 절대 건드리지 않음.
    func clampToDocument() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        guard Self.blankOffset(cur: sv.contentView.bounds.origin.y,
                               docHeight: doc.bounds.height,
                               clipHeight: sv.contentView.bounds.height) else { return }
        let maxY = max(0, doc.bounds.height - sv.contentView.bounds.height)
        sv.contentView.setBoundsOrigin(NSPoint(x: 0, y: maxY))
        sv.reflectScrolledClipView(sv.contentView)
        reconcilePin()
        refreshFinishMark() // T-205 후속 판정 기준
        logger.info(feature: "스크롤", "빈 영역 보정 → 하단")
    }

    /// 위 고착 보정 (T-202): 진입 후 휠 입력 없이 상단에 머물면 하단으로.
    /// 문서 밖 오버슛과 달리 문서 안이라 휠 가드 필수 (읽는 중 위치 불변).
    func clampTopStuck() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        guard followGate.lastWheel < followGate.entrySince else { return }
        guard Self.topStuck(offset: sv.contentView.bounds.origin.y,
                            docHeight: doc.bounds.height,
                            clipHeight: sv.contentView.bounds.height) else { return }
        jumpToBottom()
        refreshFinishMark() // T-205 보정 후 기준 갱신 (자기차단 방지)
        logger.info(feature: "스크롤", "위 고착 보정 → 하단")
    }

    /// 종료 기준 갱신 (T-205): 보정 점프 후 현재 위치를 새 기준으로.
    /// 안 하면 보정 점프 자체가 이동량 가드를 오염시켜 후속 보정이 영구 스킵됨.
    func refreshFinishMark() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        followGate.finishDocH = doc.bounds.height
        followGate.finishOffset = sv.contentView.bounds.origin.y
    }

    /// 붕괴 보정 (T-204): 종료 후 문서가 크게 줄면 종료 시점 오프셋이 허공에 남음.
    /// LazyVStack 추정 팽창 후 실측 수렴이 원인. 종료 후 거의 안 움직였을 때만 (읽기 보호).
    func correctCollapsedBottom() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        guard followGate.finishDocH > 0 else { return }
        let offset = sv.contentView.bounds.origin.y
        guard abs(offset - followGate.finishOffset) < 60 else { return }
        let cur = doc.bounds.height
        guard Self.docCollapsed(finish: followGate.finishDocH, current: cur) else { return }
        jumpToBottom()
        refreshFinishMark() // T-205 반복 점프 방지 + 후속 판정 기준
        logger.info(feature: "스크롤", "문서 붕괴 보정 → 하단")
    }

    /// 고착 보정 (T-204): 종료 후 거의 안 움직였는데 하단이 안 보이면 하단으로.
    /// 휠 시각 대신 오프셋 이동량을 봐서 헛스크롤 오염에 강함.
    func correctStuckBottom() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        guard !chat.streaming, !chat.preparing else { return }
        guard !pinnedToBottom else { return }
        guard followGate.finishDocH > 0 else { return }
        guard Self.stuckBottom(offset: sv.contentView.bounds.origin.y,
                               finishOffset: followGate.finishOffset,
                               docHeight: doc.bounds.height,
                               clipHeight: sv.contentView.bounds.height) else { return }
        jumpToBottom()
        refreshFinishMark() // T-205 후속 판정 기준
        logger.info(feature: "스크롤", "고착 보정 → 하단")
    }

    /// 진입 확정 착지 (T-209): 절대 점프 → 프록시 chatBottom → 0.2초 후 확정.
    /// AppKit 직접 점프만으로는 동결된 추정치를 못 깨고 허공에 남음.
    /// 프록시는 SwiftUI 레이아웃을 깨우고, 확정 점프가 실측 기준으로 교정
    /// (T-167 오버슛은 여기서 흡수, 지연 보정 6종 유지).
    func settleToBottom() {
        jumpToBottom()
        scrollProxy?.scrollTo("chatBottom", anchor: .bottom)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.jumpToBottom()
            self.refreshFinishMark()
        }
    }

    /// 스윕 복구 (T-208): 얼어붙은 추정치를 깨는 해머. 맨 위로 갔다가 하단으로.
    /// 점프만으로는 추정치 공간을 못 벗어나서 실측 강제용. 고착 방에서만 1회.
    func sweepBottomRecover() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        guard !chat.streaming, !chat.preparing else { return }
        guard followGate.finishDocH > 0, followGate.anchorMaxY > 0 else { return }
        let offset = sv.contentView.bounds.origin.y
        let clipH = sv.contentView.bounds.height
        guard abs(offset - followGate.finishOffset) < 60 else { return }
        let stuck = Self.stuckBottom(offset: offset, finishOffset: followGate.finishOffset,
                                     docHeight: doc.bounds.height, clipHeight: clipH)
        let trueMaxY = Self.anchorTrueMaxY(anchorMaxY: followGate.anchorMaxY,
                                           offset: offset, clipHeight: clipH)
        guard stuck || Self.pastTrueEnd(offset: offset, trueMaxY: trueMaxY) else { return }
        guard let firstID = chat.messages.first?.id else { return }
        scrollProxy?.scrollTo(firstID, anchor: .top)
        // 0.4초: 위쪽 실측이 끝난 뒤 하단으로 (바로 이으면 실측이 뭉개짐).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.jumpToBottom()
            self.refreshFinishMark()
        }
        logger.info(feature: "스크롤", "스윕 복구")
    }

    /// 최종 확정 (T-208): 7초 시점 고착 가드 절대 점프. 스윕 후 착지 교정.
    func finalVerifyJump() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        guard !chat.streaming, !chat.preparing else { return }
        guard !pinnedToBottom else { return }
        guard followGate.finishDocH > 0 else { return }
        guard Self.stuckBottom(offset: sv.contentView.bounds.origin.y,
                               finishOffset: followGate.finishOffset,
                               docHeight: doc.bounds.height,
                               clipHeight: sv.contentView.bounds.height) else { return }
        jumpToBottom()
        refreshFinishMark()
        logger.info(feature: "스크롤", "최종 확정 → 하단")
    }

    /// 앵커 재수렴 (T-206): 핀ON인데 오프셋이 앵커 실측 끝을 초과하면 실측으로 복귀.
    /// AppKit 문서 높이(추정 팽창)와 앵커(실측)가 어긋난 사각지대 담당. 핀 가드 없음.
    /// T-210 calm 임계 40: 하이라이트 확정 등 미세 변동에는 무동작 (출렁 방지).
    func recoverPastTrueEnd() {
        guard let sv = chatScrollView, sv.documentView != nil else { return }
        guard !chat.streaming, !chat.preparing else { return }
        guard followGate.finishDocH > 0, followGate.anchorMaxY > 0 else { return }
        let offset = sv.contentView.bounds.origin.y
        guard abs(offset - followGate.finishOffset) < 60 else { return }
        let trueMaxY = Self.anchorTrueMaxY(anchorMaxY: followGate.anchorMaxY,
                                           offset: offset,
                                           clipHeight: sv.contentView.bounds.height)
        guard Self.pastTrueEnd(offset: offset, trueMaxY: trueMaxY, threshold: 40) else { return }
        sv.contentView.setBoundsOrigin(NSPoint(x: 0, y: trueMaxY))
        sv.reflectScrolledClipView(sv.contentView)
        reconcilePin()
        refreshFinishMark()
        logger.info(feature: "스크롤", "앵커 재수렴 → 하단")
    }

    /// 자 불일치 진단 (T-207): AppKit 높이와 앵커 실측이 크게 어긋나면 로그만.
    /// 동작 변경 없음 (포인터 교체·추정 붕괴 증거 수집용).
    func diagnoseRulerMismatch() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        guard followGate.anchorMaxY > 0 else { return }
        let offset = sv.contentView.bounds.origin.y
        let clipH = sv.contentView.bounds.height
        let appMaxY = max(0, doc.bounds.height - clipH)
        let trueMaxY = Self.anchorTrueMaxY(anchorMaxY: followGate.anchorMaxY,
                                           offset: offset, clipHeight: clipH)
        guard abs(appMaxY - trueMaxY) > 1000 else { return }
        logger.info(feature: "스크롤", "자 불일치 문서=\(Int(appMaxY)) 실측=\(Int(trueMaxY))")
    }
}
