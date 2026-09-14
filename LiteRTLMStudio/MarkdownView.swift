import AppKit
import SwiftUI
import WebKit

/// 강제 외관 (T-041 수동 전환 대응, 미지정은 시스템 추종).
enum MarkdownScheme: String {
    case auto
    case light
    case dark
}

/// 읽기 전용 렌더용 WKWebView: 세로 휠은 상위 채팅 스크롤로 포워딩, 가로(코드블록)는 내부 처리 (T-037).
final class NoScrollWKWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.deltaY) >= abs(event.deltaX) else {
            super.scrollWheel(with: event)
            return
        }
        var responder: NSResponder? = nextResponder
        while let current = responder {
            if let scrollView = current as? NSScrollView {
                scrollView.scrollWheel(with: event)
                return
            }
            responder = current.nextResponder
        }
        superview?.scrollWheel(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }
}

/// 마크다운 읽기 전용 렌더 (PLAN_v3 T-029, AGENTS.local 예외 승인).
/// - 엔진: marked+highlight.js+커스텀 렌더러/CSS 번들 내장 (T-050, AIModelTalk 이식, 아티팩트 제외)
/// - 템플릿 1회 로드 후 본문만 JS로 교체 (스트리밍 리로드 없음)
/// - 스크롤 없음: 높이 push + 상위 ScrollView가 스크롤
/// - Equatable (T-045): 본문·외관·스트리밍 동일하면 갱신 건너뜀
/// 마크다운 너비 관측 키 (T-090, 입력바 미러 패턴): 리사이즈 재측정용.
private struct MarkdownWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct MarkdownView: View, Equatable {
    let text: String
    var scheme: MarkdownScheme = .auto
    var isStreaming: Bool = false
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌
    @State private var height: CGFloat = 24
    @State private var containerWidth: CGFloat = 0 // T-090 리사이즈 관측

    init(text: String, scheme: MarkdownScheme = .auto, isStreaming: Bool = false,
         fontScale: CGFloat = 1.0) {
        self.text = text
        self.scheme = scheme
        self.isStreaming = isStreaming
        self.fontScale = fontScale
        // T-083 높이 캐시: 진입 초기 프레임을 실측 근사치로 (24pt 플레이스홀더 충격 완화).
        // 너비 미확정이라 버킷 0 (미스 유도, 안전 방향, T-091).
        _height = State(initialValue: MarkdownPage.cachedHeight(markdown: text, scheme: scheme,
                                                                fontScale: Double(fontScale),
                                                                width: 0) ?? 24)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.scheme == rhs.scheme && lhs.isStreaming == rhs.isStreaming
            && lhs.fontScale == rhs.fontScale
    }

    var body: some View {
        MarkdownWebView(markdown: text, scheme: scheme, isStreaming: isStreaming,
                        fontScale: fontScale, containerWidth: containerWidth, height: $height)
            .frame(height: height)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: MarkdownWidthKey.self, value: geo.size.width)
                }
            }
            .onPreferenceChange(MarkdownWidthKey.self) { containerWidth = $0 }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let scheme: MarkdownScheme
    let isStreaming: Bool
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌
    var containerWidth: CGFloat = 0 // T-090 리사이즈 관측
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> NoScrollWKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "heightChange")
        config.userContentController.add(context.coordinator, name: "jsError")
        config.userContentController.add(context.coordinator, name: "renderState")
        let web = NoScrollWKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        context.coordinator.heightBinding = $height
        context.coordinator.webView = web
        context.coordinator.scheme = scheme
        context.coordinator.lastIsStreaming = isStreaming
        web.loadHTMLString(MarkdownPage.template(scheme: scheme), baseURL: nil)
        return web
    }

    func updateNSView(_ web: NoScrollWKWebView, context: Context) {
        let c = context.coordinator
        c.heightBinding = $height
        c.lastMarkdown = markdown
        c.lastScale = Double(fontScale)
        if c.lastWidth == 0 { c.lastWidth = containerWidth } // T-091 최초 너비 기록
        // 너비 변경 → 여유 확보 후 디바운스 재측정 (T-090, 잘림 방지).
        if Self.widthChanged(old: c.lastWidth, new: containerWidth) {
            c.lastWidth = containerWidth
            if height > 0 {
                // 뷰 갱신 중 변경 회피: 다음 런루프에 여유 확보.
                let hb = $height
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
        let streamingEnded = c.lastIsStreaming && !isStreaming
        switch Self.resolveAction(schemeChanged: c.scheme != scheme,
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
            Self.apply(web: web, markdown: markdown, streaming: false, coordinator: c)
        case .append:
            c.lastIsStreaming = true
            c.pendingMarkdown = nil
            Self.apply(web: web, markdown: markdown, streaming: true, coordinator: c)
        case .fullSet:
            c.lastIsStreaming = isStreaming
            c.pendingMarkdown = nil
            Self.apply(web: web, markdown: markdown, streaming: false, coordinator: c)
        case .wait:
            c.lastIsStreaming = isStreaming
            if !c.loaded { c.pendingMarkdown = markdown }
        }
        // 폰트 줌 (T-070): 리로드 없이 CSS 변수만 교체 + 높이 재측정.
        if c.loaded, c.appliedScale != c.lastScale {
            c.appliedScale = c.lastScale
            Self.runJS(web, "setFontScale(\(Self.fontPx(c.lastScale)))")
        }
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loaded = false
        var appliedMarkdown = ""
        var pendingMarkdown: String?
        var lastMarkdown = ""
        var emptyRetryFor: String? // T-056 빈 렌더 재시도한 본문 (중복 방지)
        var scheme: MarkdownScheme = .auto
        var lastIsStreaming = false
        var streamingInit = false
        var appliedScale = 0.0 // T-070 웹뷰에 반영된 스케일
        var lastScale = 1.0 // T-070 최신 스케일
        var lastWidth: CGFloat = 0 // T-090 최신 너비
        var widthWork: DispatchWorkItem? // T-090 디바운스 재측정
        var heightBinding: Binding<CGFloat>?
        weak var webView: NoScrollWKWebView?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "jsError":
                // 렌더 실패 보고 (T-052): JS 폴백 표시 + 원문 유지.
                if let detail = message.body as? String {
                    DebugLogger.shared.error(code: "E-MAC-UI-0001", feature: "마크다운",
                                             "렌더 실패: \(detail)")
                }
                return
            case "renderState":
                // 빈 렌더 검증 보고 (T-056): 원인 불문 자동 재시도 1회.
                guard let dict = message.body as? [String: Any],
                      let empty = dict["empty"] as? Bool else { return }
                let blocks = (dict["blocks"] as? NSNumber)?.intValue ?? 0
                let mdEmpty = lastMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                guard MarkdownWebView.shouldRetryEmpty(reportedEmpty: empty, markdownEmpty: mdEmpty,
                                                         alreadyRetried: emptyRetryFor == appliedMarkdown) else {
                    if empty {
                        DebugLogger.shared.error(code: "E-MAC-UI-0003", feature: "마크다운",
                                                 "빈 렌더 지속 (\(blocks)블록)")
                    }
                    return
                }
                emptyRetryFor = appliedMarkdown
                DebugLogger.shared.info(feature: "마크다운", "빈 렌더 감지 — 재시도")
                if let web = webView {
                    MarkdownWebView.apply(web: web, markdown: appliedMarkdown,
                                          streaming: false, coordinator: self)
                }
                return
            case "heightChange":
                break
            default:
                return
            }
            let raw: Double
            if let d = message.body as? Double {
                raw = d
            } else if let n = message.body as? NSNumber {
                raw = n.doubleValue
            } else {
                return
            }
            let h = MarkdownWebView.fittedHeight(raw)
            guard h > 0 else { return }
            // T-083 높이 캐시 저장 (다음 진입 초기 프레임용, 실측 너비 버킷).
            MarkdownPage.storeHeight(h, markdown: appliedMarkdown, scheme: scheme,
                                     fontScale: lastScale, width: lastWidth)
            DispatchQueue.main.async {
                let cur = self.heightBinding?.wrappedValue ?? 0
                if abs(h - cur) > 1 { self.heightBinding?.wrappedValue = h }
            }
        }

        func webView(_ web: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                DebugLogger.shared.info(feature: "링크", "외부 열기: \(url.absoluteString)")
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webViewWebContentProcessDidTerminate(_ web: WKWebView) {
            // 프로세스 사망 자동 복구 (T-052): 빈 화면 방치 금지.
            DebugLogger.shared.error(code: "E-MAC-UI-0002", feature: "마크다운", "프로세스 종료 — 재로드")
            reloadForRecovery(web)
        }

        func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // 로드 실패 복구 (T-056): 취소(대체 로드)는 정상 경로라 제외.
            let ns = error as NSError
            guard !(ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) else { return }
            DebugLogger.shared.error(code: "E-MAC-UI-0001", feature: "마크다운",
                                     "로드 실패: \(error.localizedDescription)")
            reloadForRecovery(web)
        }

        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            let ns = error as NSError
            guard !(ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) else { return }
            DebugLogger.shared.error(code: "E-MAC-UI-0001", feature: "마크다운",
                                     "로드 실패: \(error.localizedDescription)")
            reloadForRecovery(web)
        }

        /// 템플릿 재로드 복구 (T-056 공용): 대기 본문 유지 후 재적용은 didFinish가 담당.
        private func reloadForRecovery(_ web: WKWebView) {
            loaded = false
            streamingInit = false
            appliedMarkdown = ""
            appliedScale = 0 // T-070 재로드 후 스케일 재적용
            if pendingMarkdown == nil { pendingMarkdown = lastMarkdown.isEmpty ? nil : lastMarkdown }
            web.loadHTMLString(MarkdownPage.template(scheme: scheme), baseURL: nil)
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            // 로드 직후 스케일 동기화 (T-070): 초기값도 template 기본과 다르면 적용.
            if appliedScale != lastScale {
                appliedScale = lastScale
                MarkdownWebView.runJS(web, "setFontScale(\(MarkdownWebView.fontPx(lastScale)))")
            }
            if let pending = pendingMarkdown, pending != appliedMarkdown {
                pendingMarkdown = nil
                MarkdownWebView.apply(web: web, markdown: pending,
                                      streaming: lastIsStreaming, coordinator: self)
                // 폴백 측정 병행 (T-080): 적용 후에도 직접 측정 (early-return 제거).
            }
            // 높이 push 유실 대비 폴백 1회 측정 (T-050).
            web.evaluateJavaScript("document.getElementById('content').scrollHeight") { value, _ in
                let raw: Double
                if let d = value as? Double {
                    raw = d
                } else if let n = value as? NSNumber {
                    raw = n.doubleValue
                } else {
                    return
                }
                let h = MarkdownWebView.fittedHeight(raw)
                guard h > 0 else { return }
                DispatchQueue.main.async {
                    let cur = self.heightBinding?.wrappedValue ?? 0
                    if abs(h - cur) > 1 { self.heightBinding?.wrappedValue = h }
                }
            }
        }
    }
}

/// 마크다운 엔진 번들 (T-050, AIModelTalk 이식, 아티팩트 제외).
/// 파싱 marked + 하이라이트 highlight.js + 커스텀 렌더러/CSS. 전부 번들 내장(오프라인).
enum MarkdownPage {
    static var resourceCache: [String: String] = [:]
    static var heightCache: [String: CGFloat] = [:] // T-083 실측 높이 캐시
    static var heightOrder: [String] = [] // FIFO 퇴출용
    static let heightCap = 500

    /// 높이 캐시 키 (순수, 테스트 가능, T-083, T-091 너비 버킷): 텍스트+외관+스케일+너비.
    /// 너비 미확정(0)은 버킷 0 (미스 유도, 안전 방향).
    nonisolated static func heightKey(markdown: String, scheme: MarkdownScheme,
                                      fontScale: Double, width: CGFloat) -> String {
        "\(markdown.hashValue)_\(themeName(for: scheme))_\(fontScale)_\(widthBucket(width))"
    }

    /// 너비 버킷 (순수, 테스트 가능, T-091): 100pt 단위.
    nonisolated static func widthBucket(_ width: CGFloat) -> Int {
        width > 0 ? Int(width / 100) : 0
    }

    nonisolated static func cachedHeight(markdown: String, scheme: MarkdownScheme,
                                         fontScale: Double, width: CGFloat) -> CGFloat? {
        heightCache[heightKey(markdown: markdown, scheme: scheme, fontScale: fontScale, width: width)]
    }

    nonisolated static func storeHeight(_ h: CGFloat, markdown: String, scheme: MarkdownScheme,
                                        fontScale: Double, width: CGFloat) {
        let key = heightKey(markdown: markdown, scheme: scheme, fontScale: fontScale, width: width)
        if heightCache[key] == nil {
            heightOrder.append(key)
            if heightOrder.count > heightCap, !heightOrder.isEmpty {
                heightCache.removeValue(forKey: heightOrder.removeFirst())
            }
        }
        heightCache[key] = h
    }

    /// data-theme 값 (순수, 테스트 가능): auto→system.
    nonisolated static func themeName(for scheme: MarkdownScheme) -> String {
        switch scheme {
        case .auto: "system"
        case .light: "light"
        case .dark: "dark"
        }
    }

    /// 번들 리소스 로드+캐시 (T-050). 테스트 호스트 대비 main→클래스 번들 폴백.
    nonisolated static func loadResource(_ name: String, ext: String) -> String {
        let key = "\(name).\(ext)"
        if let cached = resourceCache[key] { return cached }
        let bundle = Bundle.main.url(forResource: name, withExtension: ext) != nil
            ? Bundle.main : Bundle(for: MarkdownWebView.Coordinator.self)
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        resourceCache[key] = content
        return content
    }

    /// 엔진 부트스트랩 템플릿 (T-050). 아티팩트 호출 제외.
    nonisolated static func template(scheme: MarkdownScheme = .auto) -> String {
        let theme = themeName(for: scheme)
        let scripts = [loadResource("marked.min", ext: "js"),
                       loadResource("highlight.min", ext: "js"),
                       loadResource("markdown-renderer", ext: "js")]
            .map { "<script>\($0)</script>" }.joined(separator: "\n")
        return """
        <!DOCTYPE html><html data-theme="\(theme)"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>\(loadResource("markdown", ext: "css"))</style>
        </head><body oncontextmenu="return false">
        <div class="markdown-body" id="content"></div>
        \(scripts)
        <script>
        window.__AUTOSCROLL = false;
        function postHeight(){
          var el = document.getElementById('content');
          var h = Math.max(el.scrollHeight, el.offsetHeight, 40);
          if (window.webkit && window.webkit.messageHandlers.heightChange) {
            window.webkit.messageHandlers.heightChange.postMessage(h);
          }
        }
        function reportJsError(where, err){
          if (window.webkit && window.webkit.messageHandlers.jsError) {
            window.webkit.messageHandlers.jsError.postMessage(where + ': ' + (err && err.message ? err.message : err));
          }
        }
        window.onerror = function(msg){ reportJsError('onerror', msg); };
        // 폰트 줌 (T-070): 리로드 없이 기준 크기만 교체.
        function setFontScale(px){
          document.documentElement.style.setProperty('--md-font', px + 'px');
          postHeight();
        }
        function setBody(md){
          try {
            document.getElementById('content').innerHTML = renderMarkdown(md);
          } catch (e) {
            // 렌더 실패해도 빈 화면 금지: 이스케이프 원문 폴백 (T-052).
            reportJsError('setBody', e);
            var esc = md.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
            document.getElementById('content').innerHTML = '<pre>' + esc + '</pre>';
          }
          requestAnimationFrame(function(){
            postHeight();
            verifyRender(md);
          });
        }
        // 렌더 검증 (T-056): 내용 있는데 자식 0개면 빈 렌더로 보고.
        function verifyRender(md){
          var el = document.getElementById('content');
          var hasContent = md.replace(/\\s/g, '').length > 0;
          var empty = hasContent && (el.children.length === 0);
          if (window.webkit && window.webkit.messageHandlers.renderState) {
            window.webkit.messageHandlers.renderState.postMessage({ empty: empty, blocks: el.children.length });
          }
        }
        </script>
        </body></html>
        """
    }
}
