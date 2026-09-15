import AppKit
import SwiftUI

/// 코드 하이라이트 진입점 (T-158/T-160): Highlightr 로컬 벤더 (`Vendor/Highlightr`) 래퍼.
/// - JSContext 기반 highlight.js, GitHub 라이트/다크 테마 2종 번들 내장 (오프라인)
/// - 실패 시 nil → 호출 측 단색 등폭 폴백 (빈 화면 방지)
/// - JSContext 스레드 봉인 (T-160): 비동기 경로는 전용 직렬 큐에서만 엔진 생성·사용.
///   첫 페인트는 단색으로 즉시 그리고 비동기 승격 (실행 시 빈 방 방지).
enum CodeHighlighter {
    private static let queue = DispatchQueue(label: "codehighlight") // T-160 JS 직렬 큐
    private static let cacheLock = NSLock() // T-160 캐시 경합 방지
    private static var cache: [String: AttributedString] = [:]
    private static var darkEngine: Highlightr?
    private static var lightEngine: Highlightr?

    private static func make(theme: String) -> Highlightr? {
        guard let h = Highlightr(), h.setTheme(to: theme) else { return nil }
        return h
    }

    private static func engine(dark: Bool) -> Highlightr? {
        if dark {
            if darkEngine == nil { darkEngine = make(theme: "github-dark") }
            return darkEngine
        }
        if lightEngine == nil { lightEngine = make(theme: "github") }
        return lightEngine
    }

    /// 캐시 키 (순수, 테스트 가능, T-160): 코드 해시+테마+크기.
    nonisolated static func cacheKey(code: String, lang: String?, dark: Bool,
                                     fontSize: CGFloat) -> String {
        "\(code.hashValue)_\(lang ?? "auto")_\(dark)_\(fontSize)"
    }

    /// 엔진 가용 여부 (순수 조회, 테스트 가능): 다크·라이트 중 하나라도 살아 있으면 참.
    nonisolated static func available() -> Bool {
        engine(dark: true) != nil || engine(dark: false) != nil
    }

    /// 코드 하이라이트 (T-158, 동기): 테마 색상 + 등폭 폰트 내장. 실패 시 nil.
    /// - lang: 펜스 언어 태그 (`nil`/빈값이면 자동 감지, Highlightr가 highlightAuto로 폴백)
    nonisolated static func highlight(code: String, lang: String?,
                                      dark: Bool, fontSize: CGFloat) -> AttributedString? {
        let key = cacheKey(code: code, lang: lang, dark: dark, fontSize: fontSize)
        if let hit = cacheLock.withLock({ cache[key] }) { return hit }
        let tag = (lang?.isEmpty == false) ? lang : nil
        guard let ns = engine(dark: dark)?.highlight(code, as: tag) else { return nil }
        var out = AttributedString(ns)
        for run in out.runs {
            out[run.range].font = .system(size: fontSize, design: .monospaced)
        }
        cacheLock.withLock { cache[key] = out }
        return out
    }

    /// 코드 하이라이트 (T-160, 비동기): 직렬 큐에서 수행 후 반환. 취소 시 nil.
    nonisolated static func highlightAsync(code: String, lang: String?,
                                           dark: Bool, fontSize: CGFloat) async -> AttributedString? {
        await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: highlight(code: code, lang: lang,
                                                 dark: dark, fontSize: fontSize))
            }
        }
    }
}
