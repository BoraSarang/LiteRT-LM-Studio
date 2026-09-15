import AppKit
import CryptoKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let scheme: MarkdownScheme
    let isStreaming: Bool
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌
    var containerWidth: CGFloat = 0 // T-090 리사이즈 관측
    @Binding var height: CGFloat
    @Binding var rendered: Bool // T-110 첫 페인트 신호 (행 페이드인용)

    func makeNSView(context: Context) -> NoScrollWKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "heightChange")
        config.userContentController.add(context.coordinator, name: "jsError")
        config.userContentController.add(context.coordinator, name: "renderState")
        let web = NoScrollWKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        context.coordinator.heightBinding = $height
        context.coordinator.renderedBinding = $rendered // T-110
        context.coordinator.webView = web
        context.coordinator.scheme = scheme
        context.coordinator.lastIsStreaming = isStreaming
        web.loadHTMLString(MarkdownPage.template(scheme: scheme), baseURL: nil)
        return web
    }

    func updateNSView(_ web: NoScrollWKWebView, context: Context) {
        let c = context.coordinator
        c.heightBinding = $height
        c.renderedBinding = $rendered // T-110
        c.lastMarkdown = markdown
        c.lastScale = Double(fontScale)
        Self.trackWidth(web: web, containerWidth: containerWidth,
                        height: height, heightBinding: $height, coordinator: c)
        Self.render(web: web, markdown: markdown, scheme: scheme,
                    isStreaming: isStreaming, coordinator: c)
        Self.applyScaleIfNeeded(web: web, coordinator: c)
    }

    /// 너비 추적 (T-090/T-091, T-126 분리): 여유 확보 후 디바운스 재측정.
    static func trackWidth(
        web: NoScrollWKWebView,
        containerWidth: CGFloat,
        height: CGFloat,
        heightBinding: Binding<CGFloat>,
        coordinator c: Coordinator
    ) {
        if c.lastWidth == 0 { c.lastWidth = containerWidth } // T-091 최초 너비 기록
        // 너비 변경 → 여유 확보 후 디바운스 재측정 (T-090, 잘림 방지).
        guard widthChanged(old: c.lastWidth, new: containerWidth) else { return }
        c.lastWidth = containerWidth
        if height > 0 {
            // 뷰 갱신 중 변경 회피: 다음 런루프에 여유 확보.
            let hb = heightBinding
            let cur = height
            DispatchQueue.main.async { hb.wrappedValue = cur * 1.2 }
        }
        c.widthWork?.cancel()
        let work = DispatchWorkItem { [weak web] in
            web?.evaluateJavaScript("postHeight()", completionHandler: nil)
            // T-091 정착 확인: 리플로우 완료 후 한 번 더 (stale 측정 굳음 방지).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak web] in
                web?.evaluateJavaScript("postHeight()", completionHandler: nil)
            }
        }
        c.widthWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// 렌더 분기 (T-051 상태머신 적용, T-126 분리).
    static func render(
        web: NoScrollWKWebView,
        markdown: String,
        scheme: MarkdownScheme,
        isStreaming: Bool,
        coordinator c: Coordinator
    ) {
        let streamingEnded = c.lastIsStreaming && !isStreaming
        switch resolveAction(schemeChanged: c.scheme != scheme,
                             streamingEnded: streamingEnded,
                             isStreaming: isStreaming,
                             loaded: c.loaded,
                             applied: c.appliedMarkdown,
                             markdown: markdown) {
        case .reload:
            // 외관 전환: 템플릿 재로드 후 대기 본문 적용 (T-041)
            c.scheme = scheme
            c.loaded = false
            c.streamingInit = false
            c.appliedMarkdown = ""
            c.appliedScale = 0 // T-070 재로드 후 스케일 재적용
            c.pendingMarkdown = markdown
            c.lastIsStreaming = isStreaming
            web.loadHTMLString(MarkdownPage.template(scheme: scheme), baseURL: nil)
        case .finishFull:
            // 스트리밍 종료: 원문 확정 렌더 (T-051, 빈 finalize는 텍스트 폴백이라 표 풀림)
            c.lastIsStreaming = false
            c.pendingMarkdown = nil
            apply(web: web, markdown: markdown, streaming: false, coordinator: c)
        case .append:
            c.lastIsStreaming = true
            c.pendingMarkdown = nil
            apply(web: web, markdown: markdown, streaming: true, coordinator: c)
        case .fullSet:
            c.lastIsStreaming = isStreaming
            c.pendingMarkdown = nil
            apply(web: web, markdown: markdown, streaming: false, coordinator: c)
        case .wait:
            c.lastIsStreaming = isStreaming
            if !c.loaded { c.pendingMarkdown = markdown }
        }
    }

    /// 폰트 줌 반영 (T-070, T-126 분리): 리로드 없이 CSS 변수만 교체 + 높이 재측정.
    static func applyScaleIfNeeded(web: NoScrollWKWebView, coordinator c: Coordinator) {
        guard c.loaded, c.appliedScale != c.lastScale else { return }
        c.appliedScale = c.lastScale
        runJS(web, "setFontScale(\(fontPx(c.lastScale)))")
    }

    /// 줌 스케일 → 기준 px (순수, 테스트 가능, T-070): 14px 기준 0.7~2.0 클램프.
    nonisolated static func fontPx(_ scale: Double) -> Double {
        14 * min(2.0, max(0.7, scale))
    }

    /// 너비 변경 판정 (순수, 테스트 가능, T-090): 첫 관측 제외, 1pt 초과.
    nonisolated static func widthChanged(old: CGFloat, new: CGFloat,
                                         epsilon: CGFloat = 1) -> Bool {
        old > 0 && abs(new - old) > epsilon
    }

    /// 렌더 동작 (T-051).
    enum RenderAction: Equatable {
        case reload
        case finishFull
        case append
        case fullSet
        case wait
    }

    /// 상태머신 (순수, 테스트 가능, T-051).
    nonisolated static func resolveAction(schemeChanged: Bool, streamingEnded: Bool,
                                          isStreaming: Bool, loaded: Bool,
                                          applied: String, markdown: String) -> RenderAction {
        if schemeChanged { return .reload }
        if streamingEnded { return .finishFull }
        guard needsFlush(loaded: loaded, applied: applied, html: markdown) else { return .wait }
        return isStreaming ? .append : .fullSet
    }

    /// 적용 판정 (순수, 테스트 가능).
    nonisolated static func needsFlush(loaded: Bool, applied: String, html: String) -> Bool {
        loaded && applied != html
    }

    /// 빈 렌더 재시도 판정 (순수, 테스트 가능, T-056): 보고된 빈 화면 + 원문 있음 + 미재시도.
    nonisolated static func shouldRetryEmpty(reportedEmpty: Bool, markdownEmpty: Bool,
                                             alreadyRetried: Bool) -> Bool {
        reportedEmpty && !markdownEmpty && !alreadyRetried
    }

    /// JS 문자열 리터럴 (순수, 테스트 가능): JSON 인코딩 후 양끝 따옴표 제거.
    nonisolated static func jsLiteral(_ s: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              var lit = String(data: data, encoding: .utf8) else { return nil }
        lit.removeFirst()
        lit.removeLast()
        return lit
    }

    static func apply(web: WKWebView, markdown: String, streaming: Bool, coordinator: Coordinator) {
        coordinator.appliedMarkdown = markdown
        coordinator.lastMarkdown = markdown
        guard let lit = jsLiteral(markdown) else { return }
        if streaming {
            // 리로드 사이 append 보호: 컨테이너 초기화 보장 (T-050).
            if !coordinator.streamingInit {
                coordinator.streamingInit = true
                Self.runJS(web, "initStreaming('content')")
            }
            Self.runJS(web, "appendChunk(\(lit))")
        } else {
            Self.runJS(web, "setBody(\(lit))")
        }
    }

    /// JS 실행 + 실패 로깅 (T-052): 조용한 실패를 DebugPanel에 노출.
    nonisolated static func runJS(_ web: WKWebView, _ script: String) {
        web.evaluateJavaScript(script) { _, error in
            if let error {
                DebugLogger.shared.error(code: "E-MAC-UI-0001", feature: "마크다운",
                                         "JS 실패: \(error.localizedDescription)")
            }
        }
    }

    /// 실측 높이 → 프레임 높이 (순수, 테스트 가능): 올림+반올림 여유 2pt (T-049 마진 정리 후 축소).
    nonisolated static func fittedHeight(_ raw: Double) -> CGFloat {
        raw > 0 ? ceil(raw + 2) : 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
}
