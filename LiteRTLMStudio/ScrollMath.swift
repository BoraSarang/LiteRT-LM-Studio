import Foundation

/// 채팅 스크롤 순수 연산 모음 (T-084 파일 길이 관리용 분리).
/// 호출부는 `ContentView.xxx` 그대로 (extension이라 테스트 무영향).
extension ContentView {
    /// Sticky-Pin 판정 (순수, 테스트 가능): 하단 앵커가 뷰포트 안에 있으면 고정.
    static func isPinnedToBottom(bottomMaxY: CGFloat, viewportHeight: CGFloat,
                                 threshold: CGFloat = 60) -> Bool {
        bottomMaxY <= viewportHeight + threshold
    }

    /// 추종 발사 판정 (순수, 테스트 가능, T-044):
    /// 고정 상태라도 직전 발사 0.4s 이내거나 휠 제스처 0.8s 이내면 건너뜀 (사용자 읽기 우선).
    nonisolated static func shouldFollow(pinned: Bool, now: Date, lastFollow: Date, lastWheel: Date,
                                         followInterval: TimeInterval = 0.4,
                                         wheelPause: TimeInterval = 0.8) -> Bool {
        pinned
            && now.timeIntervalSince(lastFollow) >= followInterval
            && now.timeIntervalSince(lastWheel) >= wheelPause
    }

    /// 세션 전환 점프 대상 (순수, 테스트 가능, T-046).
    /// 같은 세션 + 휠 없음 + 마지막 메시지 있음일 때만 대상 반환.
    nonisolated static func switchJumpTarget(sessionID: UUID?, currentID: UUID?,
                                             lastMessageID: UUID?,
                                             wheeledSinceSwitch: Bool) -> UUID? {
        guard !wheeledSinceSwitch, sessionID == currentID, let lastMessageID else { return nil }
        return lastMessageID
    }

    /// 폰트 줌 클램프 (순수, 테스트 가능, T-070): 0.7~2.0.
    nonisolated static func clampedZoom(_ s: Double) -> Double {
        min(2.0, max(0.7, s))
    }

    /// 폰트 줌 스텝 (순수, 테스트 가능, T-070): 소수점 먼지 방지 반올림.
    nonisolated static func steppedZoom(_ s: Double, step: Double) -> Double {
        clampedZoom((s * 10).rounded() / 10 + step)
    }

    /// 클램프 목표 (순수, 테스트 가능, T-054): [0, 최대] 구간으로 제한.
    nonisolated static func clampedTargetY(target: CGFloat, docHeight: CGFloat,
                                           clipHeight: CGFloat) -> CGFloat {
        min(max(0, target), max(0, docHeight - clipHeight))
    }

    /// 하단 목표 오프셋 (순수, 테스트 가능, T-047): 문서−클립, 음수 방지.
    nonisolated static func bottomTargetY(docHeight: CGFloat, clipHeight: CGFloat) -> CGFloat {
        max(0, docHeight - clipHeight)
    }

    /// AppKit 실측 하단 판정 (순수, 테스트 가능, T-047).
    nonisolated static func isAtBottomOffset(offset: CGFloat, content: CGFloat, container: CGFloat,
                                             threshold: CGFloat = 60) -> Bool {
        offset >= max(0, content - container) - threshold
    }

    /// 내용 증가 판정 (순수, 테스트 가능, T-048): 0.5pt 초과 성장일 때만 추종.
    nonisolated static func contentGrew(current: CGFloat, last: CGFloat,
                                        threshold: CGFloat = 0.5) -> Bool {
        current > last + threshold
    }

    /// 진입 수렴 판정 (순수, 테스트 가능, T-079):
    /// 스크롤 여지(120 초과)가 있고 하단에 닿았을 때만 성공.
    nonisolated static func entryConverged(offsetY: CGFloat, docHeight: CGFloat,
                                          clipHeight: CGFloat, minScrollable: CGFloat = 120,
                                          threshold: CGFloat = 60) -> Bool {
        let maxY = max(0, docHeight - clipHeight)
        return maxY > minScrollable && offsetY >= maxY - threshold
    }

    /// 문서 높이 안정 판정 (순수, 테스트 가능, T-080): 최근 3회 1pt 이내.
    nonisolated static func docStable(_ heights: [CGFloat], samples: Int = 3,
                                      epsilon: CGFloat = 1) -> Bool {
        guard heights.count >= samples else { return false }
        let tail = heights.suffix(samples)
        return (tail.max() ?? 0) - (tail.min() ?? 0) <= epsilon
    }

    /// 휠 누적 판정 (순수, 테스트 가능, T-080): 임계 초과 시에만 시각 기록.
    nonisolated static func wheelStamp(accum: CGFloat, delta: CGFloat,
                                       threshold: CGFloat = 8) -> (stamp: Bool, accum: CGFloat) {
        let next = accum + abs(delta)
        return next >= threshold ? (true, 0) : (false, next)
    }
}
