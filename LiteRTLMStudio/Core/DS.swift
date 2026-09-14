import AppKit
import SwiftUI

/// 디자인 토큰 (T-041, LiteRTLM 규모 경량): 간격·radius·폰트 중앙화.
/// AIModelTalk 통째 이식 대신 현재 사용값만 고정.
enum DS {
    static let gap: CGFloat = 12
    static let bubbleRadius: CGFloat = 10
    static let cardRadius: CGFloat = 10
    static let bodyFont: Font = .system(size: 14)
    static let captionFont: Font = .system(size: 11)
    static let footnoteFont: Font = .system(size: 12)
    static let chatMaxWidth: CGFloat = 768 // T-091 메시지 열 최대폭 (중앙 정렬)
    static let bottomBoxHeight: CGFloat = 144 // T-096 터미널=시스템 높이 (3셀 수납)
}

/// 수동 외관 (T-041): 시스템 추종 기본 + 라이트/다크 강제.
/// 저장 키 "appearance" (`AppStorage`, 재실행 유지).
enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: "시스템"
        case .light: "라이트"
        case .dark: "다크"
        }
    }

    /// 웹뷰용 scheme 매핑 (순수, 테스트 가능).
    /// 웹뷰 CSS 미디어쿼리는 시스템을 보므로 강제 모드만 명시 전달.
    var markdownScheme: MarkdownScheme {
        switch self {
        case .system: .auto
        case .light: .light
        case .dark: .dark
        }
    }

    /// NSApp 적용값 (nil = 시스템 추종, 순수, 테스트 가능).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// 실효 scheme (T-042, 순수, 테스트 가능).
    /// 시스템 모드면 현재 다크 여부를 명시로 풀어서 WKWebView에 전달 (auto 토큰 오해석 방지).
    nonisolated static func effectiveScheme(mode: AppearanceMode, systemDark: Bool) -> MarkdownScheme {
        switch mode {
        case .system: systemDark ? .dark : .light
        case .light: .light
        case .dark: .dark
        }
    }

    /// 화면 표시 이후에만 호출 (App.init 금지).
    static func apply(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
        DebugLogger.shared.info(feature: "외관", "수동 전환: \(mode.title)")
    }
}
