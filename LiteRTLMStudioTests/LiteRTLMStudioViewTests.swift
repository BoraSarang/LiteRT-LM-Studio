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

    /// 마크다운 네이티브 렌더 (T-150/T-151): 외관값·줌 매핑·펜스/줄블록 분리·개행 보존.
    func testMarkdownNativeEngine() {
        XCTAssertEqual(MarkdownScheme.auto.rawValue, "auto")
        XCTAssertEqual(NativeMarkdown.splitFences("a```b```c"),
                       [.prose("a"), .code("b"), .prose("c")])
        XCTAssertNotNil(NativeMarkdown.attributed("**굵게** 확인"))
        let empty = try? AttributedString(markdown: "")
        XCTAssertNotNil(empty)
        // T-151 줄블록: 제목·목록·표·문단 분류 + 단일 개행 보존.
        XCTAssertEqual(NativeMarkdown.parseProse("# 제목\n본문"),
                       [.heading(level: 1, text: "제목"), .paragraph(text: "본문")])
        XCTAssertEqual(NativeMarkdown.parseProse("- a\n2. b"),
                       [.bullet(text: "a", indent: 0), .ordered(index: 2, text: "b", indent: 0)])
        XCTAssertEqual(NativeMarkdown.parseProse("    - nested"),
                       [.bullet(text: "nested", indent: 2)])
        XCTAssertEqual(NativeMarkdown.parseProse("| a |\n|---|\n| 1 |"),
                       [.table(rows: [["a"], ["1"]], header: true)])
    }

    /// 빈줄 수렴+언어 태그 (T-155/T-156).
    func testBlankCollapseAndLangTag() {
        XCTAssertEqual(NativeMarkdown.parseProse("a\n\n\nb"),
                       [.paragraph(text: "a"), .blank, .paragraph(text: "b")])
        XCTAssertEqual(NativeMarkdown.parseProse("\n\na"), [.paragraph(text: "a")])
        XCTAssertEqual(NativeMarkdown.parseProse("a\n\n"), [.paragraph(text: "a")])
        XCTAssertEqual(NativeMarkdown.stripLangTag("swift\nlet a = 1\n"), "let a = 1")
        XCTAssertEqual(NativeMarkdown.stripLangTag("그냥 코드"), "그냥 코드")
    }

    /// 표 구분선 다열 회귀 (T-157, 구구단 원문 71~76행) + 비동기 하이라이트 (T-160).
    func testTableDelimiterMultiline() async {
        XCTAssertTrue(NativeMarkdown.isTableDelimiter("| :--- | :--- | :--- |"))
        XCTAssertTrue(NativeMarkdown.isTableDelimiter("|---|---|"))
        XCTAssertFalse(NativeMarkdown.isTableDelimiter("| a | b |"))
        XCTAssertFalse(NativeMarkdown.isTableDelimiter("| ::: | --- |"))
        XCTAssertEqual(
            NativeMarkdown.parseProse("| 특징 | C 언어 | C++ |\n| :--- | :--- | :--- |\n| **헤더** | `<stdio.h>` | x |"),
            [.table(rows: [["특징", "C 언어", "C++"],
                           ["**헤더**", "`<stdio.h>`", "x"]], header: true)])
        // T-158 코드 언어 분리 + 하이라이트 엔진.
        XCTAssertEqual(NativeMarkdown.splitCode("cpp\nint x;\n").lang, "cpp")
        XCTAssertEqual(NativeMarkdown.splitCode("cpp\nint x;\n").body, "int x;")
        XCTAssertNil(NativeMarkdown.splitCode("그냥 코드").lang)
        XCTAssertTrue(CodeHighlighter.available())
        let hl = CodeHighlighter.highlight(code: "int main() { return 0; }", lang: "cpp",
                                           dark: true, fontSize: 13)
        XCTAssertNotNil(hl)
        XCTAssertTrue(String(hl?.characters ?? AttributedString("").characters).contains("main"))
        // T-160 비동기 하이라이트 + 캐시 키.
        let asyncHL = await CodeHighlighter.highlightAsync(code: "int x = 1;", lang: "cpp",
                                                           dark: true, fontSize: 13)
        XCTAssertNotNil(asyncHL)
        XCTAssertEqual(CodeHighlighter.cacheKey(code: "a", lang: "cpp", dark: true, fontSize: 13),
                       CodeHighlighter.cacheKey(code: "a", lang: "cpp", dark: true, fontSize: 13))
        XCTAssertNotEqual(CodeHighlighter.cacheKey(code: "a", lang: "cpp", dark: true, fontSize: 13),
                          CodeHighlighter.cacheKey(code: "b", lang: "cpp", dark: true, fontSize: 13))
    }

    /// 인용·인라인코드 색 (T-169).
    func testQuoteAndCodeColor() {
        XCTAssertEqual(NativeMarkdown.parseProse("> 인용문"),
                       [.quote(text: "인용문")])
        XCTAssertEqual(NativeMarkdown.parseProse(">> 중첩"), [.quote(text: "중첩")])
        let coded = NativeMarkdown.styled("보기 `let a = 1` 끝", size: 14)
        var foundPink = false
        for run in coded.runs {
            if run.inlinePresentationIntent?.contains(.code) == true,
               run.foregroundColor == .pink {
                foundPink = true
            }
        }
        XCTAssertTrue(foundPink)
    }
    /// 기존 서식 회귀 묶음 (T-152/T-154).
    func testLegacyMarkdownFormatting() {
        // T-152 서식 완성: 구분선·한글볼드 정규화·서식 내장.
        XCTAssertEqual(NativeMarkdown.parseProse("위\n---\n아래"),
                       [.paragraph(text: "위"), .hr, .paragraph(text: "아래")])
        XCTAssertTrue(NativeMarkdown.isHR("***"))
        XCTAssertFalse(NativeMarkdown.isHR("--"))
        XCTAssertEqual(NativeMarkdown.normalizeStrong("** ㅌㅌㅌ ** 확인"), "**ㅌㅌㅌ** 확인")
        XCTAssertEqual(NativeMarkdown.normalizeStrong("**굵게** 확인"), "**굵게** 확인")
        let strong = NativeMarkdown.styled("**굵게** 확인", size: 14)
        var foundBold = false
        for run in strong.runs {
            if let v = run.inlinePresentationIntent, v.contains(.stronglyEmphasized) {
                foundBold = true
            }
        }
        XCTAssertTrue(foundBold)
        // T-154 수동 bold: 괄호 포함·불균등 처리.
        XCTAssertEqual(NativeMarkdown.splitStrong("a **x** b"),
                       [NativeMarkdown.StrongSeg(text: "a ", bold: false),
                        NativeMarkdown.StrongSeg(text: "x", bold: true),
                        NativeMarkdown.StrongSeg(text: " b", bold: false)])
        XCTAssertEqual(NativeMarkdown.splitStrong("닫히지 않은 ** 하나"),
                       [NativeMarkdown.StrongSeg(text: "닫히지 않은 ** 하나", bold: false)])
        let paren = NativeMarkdown.styled("**Gemma-2-27B (4-bit 버전)**을 시도", size: 14)
        var parenBold = false
        for run in paren.runs {
            if let v = run.inlinePresentationIntent, v.contains(.stronglyEmphasized) {
                parenBold = true
            }
        }
        XCTAssertTrue(parenBold)
    }

    /// 정보 창 라이브러리 목록 무결성 (T-150): JS 벤더 제거로 빈 목록.
    func testAboutLibraries() {
        XCTAssertTrue(AboutLibraries.all.isEmpty)
    }

    /// 폰트 줌 스텝·px 매핑 (T-070): 0.7~2.0 클램프, 14px 기준.
    func testChatZoom() {
        XCTAssertEqual(ContentView.steppedZoom(1.0, step: 0.1), 1.1, accuracy: 0.0001)
        XCTAssertEqual(ContentView.steppedZoom(2.0, step: 0.1), 2.0, accuracy: 0.0001)
        XCTAssertEqual(ContentView.steppedZoom(0.7, step: -0.1), 0.7, accuracy: 0.0001)
        XCTAssertEqual(ContentView.steppedZoom(1.0, step: -0.5), 0.7, accuracy: 0.0001)
        XCTAssertEqual(NativeMarkdown.fontPx(1.0), 14.0, accuracy: 0.0001)
        XCTAssertEqual(NativeMarkdown.fontPx(3.0), 28.0, accuracy: 0.0001)
        XCTAssertEqual(NativeMarkdown.fontPx(0.1), 9.8, accuracy: 0.0001)
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
        XCTAssertEqual(NativeMarkdown.fontPx(1.5), 21.0, accuracy: 0.0001)
    }
}
