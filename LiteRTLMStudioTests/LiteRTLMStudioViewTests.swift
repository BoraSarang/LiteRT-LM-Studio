import AppKit
import XCTest
@testable import LiteRTLMStudio

/// 뷰·표시 테스트군 (T-060 파일 분리).
final class LiteRTLMStudioViewTests: XCTestCase {
    /// Sticky-Pin 판정: 앵커가 뷰포트 안이면 고정 (T-031).
    func testPinnedToBottom() {
        XCTAssertTrue(ContentView.isPinnedToBottom(bottomMaxY: 600, viewportHeight: 600))
        XCTAssertTrue(ContentView.isPinnedToBottom(bottomMaxY: 650, viewportHeight: 600))
        XCTAssertFalse(ContentView.isPinnedToBottom(bottomMaxY: 700, viewportHeight: 600))
    }

    /// 마크다운 엔진 부트스트랩: marked+hljs+렌더러+CSS 내장, 외관 매핑 (T-050).
    /// 빈 화면 방지: try/catch 폴백+에러 보고 고리 (T-052).
    func testMarkdownEngineBootstrap() {
        let dark = MarkdownPage.template(scheme: .dark)
        XCTAssertTrue(dark.contains("renderMarkdown"))
        XCTAssertTrue(dark.contains("marked"))
        XCTAssertTrue(dark.contains("copyCode"))
        XCTAssertTrue(dark.contains(".markdown-body"))
        XCTAssertTrue(dark.contains("data-theme=\"dark\""))
        XCTAssertTrue(dark.contains("try {"))
        XCTAssertTrue(dark.contains("window.onerror"))
        XCTAssertTrue(dark.contains("jsError"))
        XCTAssertTrue(dark.contains("verifyRender"))
        XCTAssertTrue(dark.contains("renderState"))
        XCTAssertTrue(dark.contains("koreanStrong")) // T-066 한글 볼드 확장
        XCTAssertTrue(dark.contains("v18.0.13")) // T-067 marked 핀
        XCTAssertTrue(dark.contains("v11.12.0")) // T-067 highlight.js 핀
        XCTAssertTrue(dark.contains(".hljs-keyword")) // T-069 토큰 팔레트
        XCTAssertTrue(dark.contains("--hl-base")) // T-069 테마 변수
        XCTAssertTrue(dark.contains("letter-spacing: 0.015em")) // T-075 본문 자간
        XCTAssertTrue(MarkdownPage.template(scheme: .light).contains("data-theme=\"light\""))
        XCTAssertTrue(MarkdownPage.template(scheme: .auto).contains("data-theme=\"system\""))
        XCTAssertEqual(MarkdownPage.themeName(for: .auto), "system")
    }

    /// JS 문자열 리터럴: 따옴표 포함·내부 이스케이프 (T-050).
    func testJsLiteral() {
        XCTAssertEqual(MarkdownWebView.jsLiteral("a\"b"), "\"a\\\"b\"")
        XCTAssertTrue(MarkdownWebView.jsLiteral("줄\n바꿈")!.contains("\\n"))
    }

    /// 정보 창 라이브러리 목록 무결성 (T-068): 번들 벤더와 버전 핀 일치.
    func testAboutLibraries() {
        XCTAssertEqual(AboutLibraries.all.count, 2)
        let marked = AboutLibraries.all[0]
        XCTAssertEqual(marked.name, "marked")
        XCTAssertEqual(marked.version, "v18.0.13")
        XCTAssertEqual(URL(string: marked.url)?.host, "github.com")
        let hljs = AboutLibraries.all[1]
        XCTAssertEqual(hljs.name, "highlight.js")
        XCTAssertEqual(hljs.version, "v11.12.0")
        XCTAssertEqual(URL(string: hljs.url)?.host, "github.com")
    }

    /// 폰트 줌 스텝·px 매핑 (T-070): 0.7~2.0 클램프, 14px 기준.
    func testChatZoom() {
        XCTAssertEqual(ContentView.steppedZoom(1.0, step: 0.1), 1.1, accuracy: 0.0001)
        XCTAssertEqual(ContentView.steppedZoom(2.0, step: 0.1), 2.0, accuracy: 0.0001)
        XCTAssertEqual(ContentView.steppedZoom(0.7, step: -0.1), 0.7, accuracy: 0.0001)
        XCTAssertEqual(ContentView.steppedZoom(1.0, step: -0.5), 0.7, accuracy: 0.0001)
        XCTAssertEqual(MarkdownWebView.fontPx(1.0), 14.0, accuracy: 0.0001)
        XCTAssertEqual(MarkdownWebView.fontPx(3.0), 28.0, accuracy: 0.0001)
        XCTAssertEqual(MarkdownWebView.fontPx(0.1), 9.8, accuracy: 0.0001)
    }

    /// 인스펙터 섹션 타이틀 (T-072): 3종 고정, 중복 없음.
    func testInspectorTitles() {
        XCTAssertEqual(InspectorTitle.all, ["시스템 현황", "실행 설정", "생성 설정"])
        XCTAssertEqual(Set(InspectorTitle.all).count, 3)
    }

    /// 회귀: 툴바 SF Symbol 실렌더 가능 (외부 link.badge.minus 링 현상 방지).
    func testToolbarSymbolsResolve() {
        for name in ["play.fill", "stop.fill", "terminal", "command", "sidebar.right",
                     "gauge", "server.rack", "wand.and.stars"] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(name) 확인")
        }
    }

    /// 인스펙터 섹션 가시성: 하나라도 켜지면 컬럼 표시, 전체 off면 2분할.
    func testAnySectionVisible() {
        XCTAssertTrue(ContentView.anyVisible(true, false, false))
        XCTAssertTrue(ContentView.anyVisible(false, false, true))
        XCTAssertFalse(ContentView.anyVisible(false, false, false))
    }

    /// 컬럼 표시 결정: 마스터 off면 섹션과 무관하게 숨김.
    func testInspectorColumnShown() {
        XCTAssertTrue(ContentView.columnShown(columnOn: true, sections: true, false, false))
        XCTAssertFalse(ContentView.columnShown(columnOn: true, sections: false, false, false))
        XCTAssertFalse(ContentView.columnShown(columnOn: false, sections: true, true, true))
    }

    // MARK: - T-150 스파이크: 네이티브(AttributedString) 동등성 4종 (의존성 추가 없음)

    /// 표 파싱: GFM 표가 throw 없이 변환되고 셀 텍스트 보존.
    func testNativeSpikeTable() throws {
        let md = "| 이름 | 값 |\n|---|---|\n| 가 | 1 |"
        let attr = try AttributedString(markdown: md)
        let plain = String(attr.characters)
        XCTAssertTrue(plain.contains("이름") && plain.contains("가"))
    }

    /// 코드 파싱: 펜스·인라인 코드가 throw 없이 변환되고 내용 보존.
    func testNativeSpikeCode() throws {
        let md = "```swift\nlet a = 1\n```\n인라인 `code` 확인"
        let attr = try AttributedString(markdown: md)
        let plain = String(attr.characters)
        XCTAssertTrue(plain.contains("let a = 1") && plain.contains("code"))
    }

    /// 한글 볼드 파싱 (T-066 케이스): 조사 직결·안쪽 공백이 throw 없이 변환되고 본문 보존.
    func testNativeSpikeKoreanBold() throws {
        for md in ["**\"강조\"**이며 계속", "** ㅌㅌㅌ ** 확인"] {
            let attr = try AttributedString(markdown: md)
            XCTAssertFalse(String(attr.characters).isEmpty)
        }
    }

    /// 스트리밍 미완성 + 줌: 닫히지 않은 볼드도 throw 없이 처리, px 매핑은 기존 헬퍼와 일치.
    func testNativeSpikeStreamingAndZoom() throws {
        let partial = try? AttributedString(markdown: "**미완성 볼드")
        XCTAssertNotNil(partial)
        XCTAssertEqual(MarkdownWebView.fontPx(1.5), 21.0, accuracy: 0.0001)
    }
}
