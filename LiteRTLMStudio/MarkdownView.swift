import AppKit
import CryptoKit
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
    @State private var rendered = false // T-110 첫 페인트 전 숨김 (팝인 마스킹)

    init(text: String, scheme: MarkdownScheme = .auto, isStreaming: Bool = false,
         fontScale: CGFloat = 1.0) {
        self.text = text
        self.scheme = scheme
        self.isStreaming = isStreaming
        self.fontScale = fontScale
        // T-083 높이 캐시: 진입 초기 프레임을 실측 근사치로.
        // T-107 너비 무관 키로 조회 (버킷 키는 진입 때 절대 안 맞아서 24 고정됐던 버그 수정).
        _height = State(initialValue: MarkdownPage.cachedHeightAgnostic(markdown: text, scheme: scheme,
                                                                        fontScale: Double(fontScale)) ?? 24)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.scheme == rhs.scheme && lhs.isStreaming == rhs.isStreaming
            && lhs.fontScale == rhs.fontScale
    }

    var body: some View {
        MarkdownWebView(markdown: text, scheme: scheme, isStreaming: isStreaming,
                        fontScale: fontScale, containerWidth: containerWidth, height: $height,
                        rendered: $rendered)
            .frame(height: height)
            .opacity(rendered ? 1 : 0) // T-110 첫 페인트 페이드인 (순차 팝인 마스킹)
            .animation(.easeOut(duration: 0.25), value: rendered)
            .task { // T-110 안전망: 렌더 신호 없이 3초 지나면 강제 표시 (행 실종 방지)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                rendered = true
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: MarkdownWidthKey.self, value: geo.size.width)
                }
            }
            .onPreferenceChange(MarkdownWidthKey.self) { containerWidth = $0 }
    }
}
