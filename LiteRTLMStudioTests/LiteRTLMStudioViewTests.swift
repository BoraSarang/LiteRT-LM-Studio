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

    /// 펜스 통계 (T-200): 블록 수+미닫힘 여부. 스트리밍 꼬리 오분류 계측 근거.
    func testFenceStats() {
        XCTAssertEqual(NativeMarkdown.fenceStats("plain").blocks, 1)
        XCTAssertFalse(NativeMarkdown.fenceStats("plain").hasPending)
        let pending = NativeMarkdown.fenceStats("앞\n```swift\nlet a = 1")
        XCTAssertEqual(pending.blocks, 2)
        XCTAssertTrue(pending.hasPending)
        let closed = NativeMarkdown.fenceStats("앞\n```swift\nlet a = 1\n```\n뒤")
        XCTAssertEqual(closed.blocks, 3)
        XCTAssertFalse(closed.hasPending)
    }

    /// 미닫힘 펜스 분리+안정 id (T-201): 꼬리 오분류·상태 오부착 방지.
    func testPendingFenceAndStableID() {
        XCTAssertEqual(NativeMarkdown.splitFences("앞\n```swift\nlet a = 1"),
                       [.prose("앞\n"), .codePending("swift\nlet a = 1")])
        XCTAssertEqual(NativeMarkdown.splitFences("a```b```c"),
                       [.prose("a"), .code("b"), .prose("c")])
        let live = CodeBlockView.stableID(code: "let a = 1", lang: "swift",
                                          isStreaming: true, salt: 1)
        XCTAssertEqual(live, CodeBlockView.stableID(code: "let a = 1", lang: "swift",
                                                    isStreaming: true, salt: 1))
        XCTAssertNotEqual(live, CodeBlockView.stableID(code: "let a = 2", lang: "swift",
                                                       isStreaming: true, salt: 1))
        XCTAssertNotEqual(live, CodeBlockView.stableID(code: "let a = 1", lang: "swift",
                                                       isStreaming: false, salt: 1))
        XCTAssertNotEqual(live, CodeBlockView.stableID(code: "let a = 1", lang: "swift",
                                                       isStreaming: true, salt: 3))
    }

    /// 문서 붕괴·하단 고착 판정 (T-204): 종료 후 가만히 있으면 하단 보장.
    func testDocCollapsedAndStuckBottom() {
        XCTAssertTrue(ContentView.docCollapsed(finish: 14183, current: 9611))
        XCTAssertFalse(ContentView.docCollapsed(finish: 14183, current: 14000))
        XCTAssertFalse(ContentView.docCollapsed(finish: 0, current: 0))
        XCTAssertTrue(ContentView.stuckBottom(offset: 5000, finishOffset: 5000,
                                              docHeight: 10000, clipHeight: 467))
        XCTAssertFalse(ContentView.stuckBottom(offset: 9500, finishOffset: 9500,
                                               docHeight: 10000, clipHeight: 467))
        XCTAssertFalse(ContentView.stuckBottom(offset: 5000, finishOffset: 9000,
                                               docHeight: 10000, clipHeight: 467))
        XCTAssertFalse(ContentView.stuckBottom(offset: 0, finishOffset: 0,
                                               docHeight: 500, clipHeight: 467))
    }

    /// 앵커 실측 끝·초과 판정 (T-206): 핀ON 허공 고착 검출.
    func testAnchorTrueMaxY() {
        // 앵커 표시 400 + 오프셋 9000 - 클립 467 = 실측 끝 8933.
        XCTAssertEqual(ContentView.anchorTrueMaxY(anchorMaxY: 400, offset: 9000,
                                                  clipHeight: 467), 8933)
        XCTAssertTrue(ContentView.pastTrueEnd(offset: 9000, trueMaxY: 8933))
        XCTAssertFalse(ContentView.pastTrueEnd(offset: 8933, trueMaxY: 8933))
        XCTAssertFalse(ContentView.pastTrueEnd(offset: 8900, trueMaxY: 8933))
        // T-210 calm 임계 40: 잔물결 무시, 진짜 허공만.
        XCTAssertFalse(ContentView.pastTrueEnd(offset: 8972, trueMaxY: 8933, threshold: 40))
        XCTAssertTrue(ContentView.pastTrueEnd(offset: 8974, trueMaxY: 8933, threshold: 40))
    }

    /// 호버 팁 표시 판정 (T-171): 정지 유지 0.6초 이상이면 표시.
    func testHoverTipVisible() {
        XCTAssertTrue(hoverTipVisible(hovering: true, elapsed: 0.6))
        XCTAssertTrue(hoverTipVisible(hovering: true, elapsed: 1.2))
        XCTAssertFalse(hoverTipVisible(hovering: true, elapsed: 0.3))
        XCTAssertFalse(hoverTipVisible(hovering: false, elapsed: 5.0))
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

    /// 코드 스팬 꺾쇠 보존 (T-195): `` `<iostream>` ``이 HTML 태그로 삼켜지면 안 됨.
    func testCodeSpanAngleBrackets() {
        let s = String(NativeMarkdown.styled("헤더 `<iostream>` 사용", size: 14).characters)
        XCTAssertTrue(s.contains("<iostream>"), "실제: \(s)")
        let runs = NativeMarkdown.splitCodeRuns("a `<b>` c")
        XCTAssertEqual(runs.map(\.code), [false, true, false])
        XCTAssertEqual(runs[1].text, "<b>")
        let plain = NativeMarkdown.splitCodeRuns("plain")
        XCTAssertEqual(plain.count, 1)
        XCTAssertEqual(plain[0].text, "plain")
        XCTAssertFalse(plain[0].code)
        XCTAssertEqual(NativeMarkdown.decodeCodeEntities("a &amp; b"), "a & b")
    }

    /// 스트리밍 미완성 볼드 숨김 (T-194): 홀수 `**`면 마지막 마커만 제외.
    func testHidePendingStrong() {
        XCTAssertEqual(NativeMarkdown.hidePendingStrong("a **b"), "a b")
        XCTAssertEqual(NativeMarkdown.hidePendingStrong("**a** b **c"), "**a** b c")
        XCTAssertEqual(NativeMarkdown.hidePendingStrong("**a** b"), "**a** b")
        XCTAssertEqual(NativeMarkdown.hidePendingStrong("plain"), "plain")
        XCTAssertEqual(NativeMarkdown.hidePendingStrong("a ***b"), "a ***b")
    }

    /// 하이라이트 작업 키 (T-196): 스트리밍 중 고정, 완료 후 최종 코드로 1회.
    func testHighlightTaskID() {
        XCTAssertEqual(CodeBlockView.highlightTaskID(code: "abc", isStreaming: true), "streaming")
        XCTAssertEqual(CodeBlockView.highlightTaskID(code: "abc", isStreaming: false), "abc")
    }

    /// 정보 창 라이브러리 목록 무결성 (T-150): JS 벤더 제거로 빈 목록.
    func testAboutLibraries() {
        XCTAssertTrue(AboutLibraries.all.isEmpty)
    }

    /// 조각 경계 공백 보존 1 (T-184): 마침표 뒤 공백. `**` 분할 조각을
    /// 파싱할 때 경계 공백이 trim되면 "궁금하네요.CMD"처럼 붙어 보임.
    func testStyledPreservesSpaceAfterPeriod() {
        let s = String(NativeMarkdown.styled("궁금하네요. **`CMD + K`**가", size: 14).characters)
        XCTAssertTrue(s.contains(". CMD + K가"), "마침표 뒤 공백 유지, 실제: \(s)")
    }

    /// 조각 경계 공백 보존 2 (T-184): 따옴표 볼드 양쪽 공백.
    /// "제가 **\"서버가 중지됨\"** 같은"이 붙으면 안 됨.
    func testStyledPreservesSpacesAroundBold() {
        let s = String(NativeMarkdown.styled("제가 **\"서버가 중지됨\"** 같은", size: 14).characters)
        XCTAssertTrue(s.contains("제가 \""), "앞 공백 유지, 실제: \(s)")
        XCTAssertTrue(s.contains("\" 같은"), "뒤 공백 유지, 실제: \(s)")
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

    /// 자간 (T-174): 0.015em 복원, 14pt→0.21pt, 줌 스케일 연동.
    func testBodyTracking() {
        XCTAssertEqual(NativeMarkdown.tracking(for: 14), 0.21, accuracy: 0.0001)
        XCTAssertEqual(NativeMarkdown.tracking(for: 28), 0.42, accuracy: 0.0001)
        XCTAssertEqual(NativeMarkdown.tracking(for: 13), 0.195, accuracy: 0.0001)
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
