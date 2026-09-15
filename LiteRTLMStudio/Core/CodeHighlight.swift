import AppKit
import SwiftUI

/// 코드 하이라이트 진입점 (T-158): Highlightr 로컬 벤더 (`Vendor/Highlightr`) 래퍼.
/// - JSContext 기반 highlight.js, GitHub 라이트/다크 테마 2종 번들 내장 (오프라인)
/// - 실패 시 nil → 호출 측 단색 등폭 폴백 (빈 화면 방지)
enum CodeHighlighter {
    private static let darkEngine: Highlightr? = make(theme: "github-dark")
    private static let lightEngine: Highlightr? = make(theme: "github")

    private static func make(theme: String) -> Highlightr? {
        guard let h = Highlightr(), h.setTheme(to: theme) else { return nil }
        return h
    }

    /// 엔진 가용 여부 (순수 조회, 테스트 가능): 다크·라이트 중 하나라도 살아 있으면 참.
    nonisolated static func available() -> Bool {
        darkEngine != nil || lightEngine != nil
    }

    /// 코드 하이라이트 (T-158): 테마 색상 + 등폭 폰트 내장. 실패 시 nil.
    /// - lang: 펜스 언어 태그 (`nil`/빈값이면 자동 감지, Highlightr가 highlightAuto로 폴백)
    nonisolated static func highlight(code: String, lang: String?,
                                      dark: Bool, fontSize: CGFloat) -> AttributedString? {
        let engine = dark ? darkEngine : lightEngine
        let tag = (lang?.isEmpty == false) ? lang : nil
        guard let ns = engine?.highlight(code, as: tag) else { return nil }
        var out = AttributedString(ns)
        for run in out.runs {
            out[run.range].font = .system(size: fontSize, design: .monospaced)
        }
        return out
    }
}
