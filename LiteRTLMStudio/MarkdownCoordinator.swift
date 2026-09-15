import AppKit
import SwiftUI
import WebKit

extension MarkdownWebView {
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
        var renderedBinding: Binding<Bool>? // T-110 첫 페인트 신호
        var didSignalRender = false // T-110 마운트당 1회 (스트리밍 재렌더 제외)
        weak var webView: NoScrollWKWebView?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "jsError":
                reportJsError(message.body)
                return
            case "renderState":
                handleRenderState(message.body)
                return
            case "heightChange":
                break
            default:
                return
            }
            guard let raw = Self.heightNumber(message.body) else { return }
            applyHeight(raw)
        }

        /// 높이 메시지 숫자 추출 (T-126 분리, Double·NSNumber 양 대응).
        nonisolated static func heightNumber(_ body: Any) -> Double? {
            if let d = body as? Double { return d }
            return (body as? NSNumber)?.doubleValue
        }

        /// JS 에러 보고 (T-052, T-126 분리): 폴백 표시 + 원문 유지.
        private func reportJsError(_ body: Any) {
            if let detail = body as? String {
                DebugLogger.shared.error(code: "E-MAC-UI-0001", feature: "마크다운",
                                         "렌더 실패: \(detail)")
            }
        }

        /// 빈 렌더 검증 보고 처리 (T-056, T-126 분리): 원인 불문 자동 재시도 1회.
        private func handleRenderState(_ body: Any) {
            guard let dict = body as? [String: Any],
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
        }

        /// 높이 반영 (T-083/T-107/T-110/T-112, T-126 분리): 캐시+페인트 증거+바인딩.
        private func applyHeight(_ raw: Double) {
            let h = MarkdownWebView.fittedHeight(raw)
            guard h > 0 else { return }
            // T-083 높이 캐시 저장 (다음 진입 초기 프레임용, 실측 너비 버킷).
            // T-107 너비 무관 키로 병행 저장 (진입 조회용. 폭 변경 오차는 T-090 재측정이 교정).
            MarkdownPage.storeHeight(h, markdown: appliedMarkdown, scheme: scheme,
                                     fontScale: lastScale, width: lastWidth)
            MarkdownPage.storeHeightAgnostic(h, markdown: appliedMarkdown, scheme: scheme,
                                             fontScale: lastScale)
            MarkdownPage.lastPaintAt = Date() // T-112 페인트 증거 (진입 조기종료 방지)
            // T-110 첫 페인트 신호 (행 페이드인, 마운트당 1회).
            if !didSignalRender {
                didSignalRender = true
                DispatchQueue.main.async { self.renderedBinding?.wrappedValue = true }
            }
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
