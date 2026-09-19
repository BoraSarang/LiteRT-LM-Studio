import SwiftUI

/// 서체 토큰 (T-318, PLAN_v96): SF 기반, 코드·로그는 모노.
enum DSType {
    static let title: Font = .system(size: 17, weight: .semibold)
    static let heading: Font = .system(size: 13, weight: .semibold)
    static let body: Font = .system(size: 13)
    static let callout: Font = .system(size: 12)
    static let caption: Font = .system(size: 11)
    static let mono: Font = .system(size: 12, design: .monospaced)
}
