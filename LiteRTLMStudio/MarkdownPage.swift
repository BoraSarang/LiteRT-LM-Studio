import AppKit
import CryptoKit
import SwiftUI
import WebKit

/// 마크다운 엔진 번들 (T-050, AIModelTalk 이식, 아티팩트 제외).
/// 파싱 marked + 하이라이트 highlight.js + 커스텀 렌더러/CSS. 전부 번들 내장(오프라인).
enum MarkdownPage {
    private static let cacheLock = NSLock() // T-119 높이보고(JS 스레드)·조회(메인) 경합 방지
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
        cacheLock.withLock {
            heightCache[heightKey(markdown: markdown, scheme: scheme, fontScale: fontScale, width: width)]
        }
    }

    nonisolated static func storeHeight(_ h: CGFloat, markdown: String, scheme: MarkdownScheme,
                                        fontScale: Double, width: CGFloat) {
        let key = heightKey(markdown: markdown, scheme: scheme, fontScale: fontScale, width: width)
        cacheLock.withLock {
            if heightCache[key] == nil {
                heightOrder.append(key)
                if heightOrder.count > heightCap, !heightOrder.isEmpty {
                    heightCache.removeValue(forKey: heightOrder.removeFirst())
                }
            }
            heightCache[key] = h
        }
    }

    static var heightCacheAgnostic: [String: CGFloat] = loadPersistedAgnostic() // T-107/108 진입 초기 프레임용
    static var heightOrderAgnostic: [String] = [] // FIFO 퇴출용
    static let agnosticPersistKey = "mdHeightCacheAgnosticV1" // T-108 영속 키
    static var lastPaintAt = Date.distantPast // T-112 진입 종료 게이트용 (마지막 높이 보고 시각)

    /// 안정 해시 앞 16자 (순수, 테스트 가능, T-108): 실행마다 바뀌는 hashValue 대신 영속 키용.
    nonisolated static func stableHashPrefix(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// 너비 무관 캐시 키 (순수, 테스트 가능, T-107): 텍스트+외관+스케일만.
    nonisolated static func heightKeyAgnostic(
        markdown: String,
        scheme: MarkdownScheme,
        fontScale: Double
    ) -> String {
        "\(stableHashPrefix(markdown))_\(themeName(for: scheme))_\(fontScale)"
    }

    /// 너비 무관 조회 (순수 조회, T-107): 진입 초기 프레임용.
    nonisolated static func cachedHeightAgnostic(
        markdown: String,
        scheme: MarkdownScheme,
        fontScale: Double
    ) -> CGFloat? {
        cacheLock.withLock {
            heightCacheAgnostic[heightKeyAgnostic(markdown: markdown, scheme: scheme,
                                                 fontScale: fontScale)]
        }
    }

    /// 너비 무관 저장 (T-107): 실측 시 버킷 키와 병행 저장.
    /// T-108 영속 write-through (UserDefaults는 메모리 기록+시스템 동기화라 스트리밍 중에도 부담 없음).
    nonisolated static func storeHeightAgnostic(_ h: CGFloat, markdown: String, scheme: MarkdownScheme,
                                                fontScale: Double) {
        let key = heightKeyAgnostic(markdown: markdown, scheme: scheme, fontScale: fontScale)
        cacheLock.withLock {
            if heightCacheAgnostic[key] == nil {
                heightOrderAgnostic.append(key)
                if heightOrderAgnostic.count > heightCap, !heightOrderAgnostic.isEmpty {
                    heightCacheAgnostic.removeValue(forKey: heightOrderAgnostic.removeFirst())
                }
            }
            heightCacheAgnostic[key] = h
        }
        persistAgnostic()
    }

    /// 영속 저장 (T-108): Double 변환 후 UserDefaults.
    nonisolated static func persistAgnostic() {
        let plain = heightCacheAgnostic.mapValues { Double($0) }
        UserDefaults.standard.set(plain, forKey: agnosticPersistKey)
    }

    /// 영속 로드 (T-108): 실행 시작 1회. 없으면 빈 사전.
    nonisolated static func loadPersistedAgnostic() -> [String: CGFloat] {
        guard let plain = UserDefaults.standard.dictionary(forKey: agnosticPersistKey)
                as? [String: Double] else { return [:] }
        return plain.mapValues { CGFloat($0) }
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
        if let cached = cacheLock.withLock({ resourceCache[key] }) { return cached }
        let bundle = Bundle.main.url(forResource: name, withExtension: ext) != nil
            ? Bundle.main : Bundle(for: MarkdownWebView.Coordinator.self)
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        cacheLock.withLock { resourceCache[key] = content }
        return content
    }

    /// 엔진 부트스트랩 템플릿 (T-050). 아티팩트 호출 제외.
    nonisolated static func template(scheme: MarkdownScheme = .auto) -> String {
        templateHead(theme: themeName(for: scheme))
            + vendorScripts()
            + templateInlineScript()
            + """
            </script>
            </body></html>
            """
    }

    /// head 부 (T-126 분리): 테마+메타+CSS.
    nonisolated static func templateHead(theme: String) -> String {
        """
        <!DOCTYPE html><html data-theme="\(theme)"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>\(loadResource("markdown", ext: "css"))</style>
        </head><body oncontextmenu="return false">
        <div class="markdown-body" id="content"></div>

        """
    }

    /// 벤더 스크립트 부 (T-126 분리): marked+highlight.js+렌더러.
    nonisolated static func vendorScripts() -> String {
        [loadResource("marked.min", ext: "js"),
         loadResource("highlight.min", ext: "js"),
         loadResource("markdown-renderer", ext: "js")]
            .map { "<script>\($0)</script>" }.joined(separator: "\n") + "\n"
    }

    /// 인라인 스크립트 부 (T-126 분리): 높이 push+줌+본문적용+검증.
    nonisolated static func templateInlineScript() -> String {
        """
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
            renderFullTwoPhase(md); // T-111 2단계 페인트 (선표시+지연 하이라이트)
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
