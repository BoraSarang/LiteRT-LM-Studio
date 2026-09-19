import XCTest
@testable import LiteRTLMStudio

/// 모델 관리 테스트군 (T-232, PLAN_v47).
final class LiteRTLMStudioModelTests: XCTestCase {
    /// 다운로드 URL·개명: resolve 규칙+`.part` 왕복.
    func testModelDownloadURLs() {
        XCTAssertEqual(ModelDownload.fileURL(repo: "org/repo", file: "m.litertlm")?.absoluteString,
                       "https://huggingface.co/org/repo/resolve/main/m.litertlm")
        XCTAssertEqual(ModelDownload.partName(for: "m.litertlm"), "m.litertlm.part")
        XCTAssertEqual(ModelDownload.finalName(part: "m.litertlm.part"), "m.litertlm")
        XCTAssertEqual(ModelDownload.finalName(part: "m.litertlm"), "m.litertlm")
        XCTAssertEqual(ModelDownload.repoTreeURL(repo: "org/repo")?.absoluteString,
                       "https://huggingface.co/org/repo/tree/main")
        XCTAssertFalse(ModelDownload.presets().isEmpty)
    }

    /// 진행률·ETA·표기: 0 경계+포맷.
    func testModelDownloadProgress() {
        XCTAssertNil(ModelDownload.progress(received: 0, total: nil))
        XCTAssertNil(ModelDownload.progress(received: 10, total: 0))
        XCTAssertEqual(ModelDownload.progress(received: 50, total: 100), 0.5)
        XCTAssertNil(ModelDownload.etaSeconds(elapsed: 10, progress: 0))
        XCTAssertEqual(ModelDownload.etaSeconds(elapsed: 10, progress: 0.5), 10)
        XCTAssertEqual(ModelDownload.formatBytes(500), "500 B")
        XCTAssertEqual(ModelDownload.formatBytes(2048), "2 KB")
        XCTAssertEqual(ModelDownload.formatBytes(5 * 1024 * 1024), "5 MB")
        XCTAssertEqual(ModelDownload.formatDuration(65), "1:05")
        XCTAssertEqual(ModelDownload.formatDuration(3665), "1:01:05")
        XCTAssertTrue(ModelDownload.statusLine(received: 50, total: 100, elapsed: 10).contains("50%"))
        XCTAssertNil(ModelDownload.averageSpeed(received: 100, elapsed: 0.5))
        XCTAssertNil(ModelDownload.averageSpeed(received: 0, elapsed: 10))
        XCTAssertEqual(ModelDownload.averageSpeed(received: 100, elapsed: 10), 10)
        XCTAssertTrue(ModelDownload.statusLine(received: 100, total: 200, elapsed: 10).contains("/s"))
    }

    /// HF API 형제 파일 파싱: `.litertlm`만.
    func testLitertlmSiblings() {
        let json = Data("""
        {"siblings": [{"rfilename": "a.litertlm"}, {"rfilename": "b.task"},
        {"rfilename": "c.litertlm"}, {"rfilename": "README.md"}]}
        """.utf8)
        XCTAssertEqual(ModelDownload.litertlmSiblings(from: json), ["a.litertlm", "c.litertlm"])
        XCTAssertTrue(ModelDownload.litertlmSiblings(from: Data("{}".utf8)).isEmpty)
    }

    /// 스테이징 상태·캐시: 설치>미설치, TTL 경계.
    func testStageStateAndCache() {
        let ids: Set<String> = ["gemma4-e2b"]
        XCTAssertEqual(ModelStore.stageState(fileName: "g.litertlm", installedIDs: ids,
                                             mapping: ["g.litertlm": FileMapping(localID: "gemma4-e2b")]),
                       .installed(localID: "gemma4-e2b"))
        XCTAssertEqual(ModelStore.stageState(fileName: "gemma4-e2b.litertlm", installedIDs: ids,
                                             mapping: [:]),
                       .installed(localID: "gemma4-e2b"))
        XCTAssertEqual(ModelStore.stageState(fileName: "new.litertlm", installedIDs: ids,
                                             mapping: [:]),
                       .downloadedUninstalled)
        XCTAssertFalse(ModelStore.isCacheValid(since: nil))
        XCTAssertTrue(ModelStore.isCacheValid(since: Date()))
        let old = Date(timeIntervalSinceNow: -120)
        XCTAssertFalse(ModelStore.isCacheValid(since: old))
    }

    /// 스테이징 스캔: 임시 디렉토리 왕복, `.part` 제외.
    func testScanStaging() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("x".utf8).write(to: dir.appendingPathComponent("b.litertlm"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("a.litertlm"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("a.litertlm.part"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("note.txt"))
        let found = ModelStore.scanStaging(at: dir).map(\.fileName)
        XCTAssertEqual(found, ["a.litertlm", "b.litertlm"])
    }

    /// 파일 결정: 목록 우선·비면 직접입력 (T-233).
    func testResolveFile() {
        XCTAssertEqual(ModelDownload.resolveFile(siblings: ["a.litertlm"], fileIndex: 0,
                                                 customFile: "b.litertlm"), "a.litertlm")
        XCTAssertEqual(ModelDownload.resolveFile(siblings: ["a.litertlm"], fileIndex: 9,
                                                 customFile: "b.litertlm"), "b.litertlm")
        XCTAssertEqual(ModelDownload.resolveFile(siblings: [], fileIndex: 0,
                                                 customFile: "  b.litertlm  "), "b.litertlm")
        XCTAssertTrue(ModelDownload.resolveFile(siblings: [], fileIndex: 0, customFile: "  ").isEmpty)
    }

    /// 토큰 헤더: 비면 없음 (T-233).
    func testAuthHeader() {
        XCTAssertNil(ModelDownload.authHeader(token: ""))
        XCTAssertNil(ModelDownload.authHeader(token: "   "))
        XCTAssertEqual(ModelDownload.authHeader(token: "hf_abc"), "Bearer hf_abc")
    }

    /// 중복 시작 가드: 진행 중 같은 파일만 차단 (T-233).
    func testHasActiveDownload() {
        let items = [(fileName: "a.litertlm", active: true), (fileName: "b.litertlm", active: false)]
        XCTAssertTrue(ModelDownload.hasActiveDownload(items, fileName: "a.litertlm"))
        XCTAssertFalse(ModelDownload.hasActiveDownload(items, fileName: "b.litertlm"))
        XCTAssertFalse(ModelDownload.hasActiveDownload(items, fileName: "c.litertlm"))
        XCTAssertFalse(ModelDownload.hasActiveDownload([], fileName: "a.litertlm"))
    }

    /// 카탈로그 목록 파싱 (T-234): id·likes·downloads·태그.
    func testCatalogParseList() {
        let json = Data("""
        [{"modelId": "org/gemma-x", "likes": 10, "downloads": 2000,
        "pipeline_tag": "text-generation", "createdAt": "2026-01-01T00:00:00.000Z"},
        {"id": "org/qwen-y", "likes": 0, "downloads": 0}]
        """.utf8)
        let entries = ModelCatalog.parseList(json)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].repo, "org/gemma-x")
        XCTAssertEqual(entries[0].pipelineTag, "text-generation")
        XCTAssertEqual(entries[1].repo, "org/qwen-y")
        XCTAssertTrue(ModelCatalog.parseList(Data("[]".utf8)).isEmpty)
    }

    /// 카탈로그 상세 파싱 (T-234): 형제 `.litertlm`만.
    func testCatalogParseDetail() {
        let json = Data("""
        {"modelId": "org/m", "likes": 5, "downloads": 100,
        "lastModified": "2026-09-01T00:00:00.000Z",
        "siblings": [{"rfilename": "m.litertlm"}, {"rfilename": "m.task"}]}
        """.utf8)
        let entry = ModelCatalog.parseDetail(repo: "org/m", data: json)
        XCTAssertEqual(entry?.siblings, ["m.litertlm"])
        XCTAssertNil(ModelCatalog.parseDetail(repo: "org/m", data: Data("{}".utf8))?.lastModified)
    }

    /// 뱃지·패밀리 판정 (T-234).
    func testCatalogBadgesAndFamily() {
        XCTAssertEqual(ModelCatalog.badges(pipelineTag: "image-text-to-text"), [.vision])
        XCTAssertEqual(ModelCatalog.badges(pipelineTag: "text-to-speech"), [.tts])
        XCTAssertEqual(ModelCatalog.badges(pipelineTag: "automatic-speech-recognition"), [.audio])
        XCTAssertEqual(ModelCatalog.badges(pipelineTag: "text-generation"), [.text])
        XCTAssertEqual(ModelCatalog.badges(pipelineTag: nil), [.text])
        XCTAssertEqual(ModelCatalog.family(of: "litert-community/gemma-x"), .gemma)
        XCTAssertEqual(ModelCatalog.family(of: "litert-community/Qwen3-4B"), .qwen)
        XCTAssertEqual(ModelCatalog.family(of: "org/phi-x"), .other)
    }

    /// 검색 URL·페이지 커서 (T-234).
    func testCatalogSearchURL() {
        let url = ModelCatalog.searchURL(query: "qwen", sort: .likes, cursor: nil)
        let str = url?.absoluteString ?? ""
        XCTAssertTrue(str.contains("filter=litert-lm"))
        XCTAssertTrue(str.contains("sort=likes"))
        XCTAssertTrue(str.contains("search=qwen"))
        XCTAssertEqual(CatalogSort.updated.apiValue, "lastModified")
        let link = "<https://huggingface.co/api/models?cursor=abc123>; rel=\"next\""
        XCTAssertEqual(ModelCatalog.nextCursor(linkHeader: link), "abc123")
        XCTAssertNil(ModelCatalog.nextCursor(linkHeader: nil))
    }

    /// 표기·규모·용량합 (T-234).
    func testCatalogFormatting() {
        XCTAssertEqual(ModelCatalog.prettyCount(999), "999")
        XCTAssertEqual(ModelCatalog.prettyCount(1500), "1.5K")
        XCTAssertEqual(ModelCatalog.prettyCount(1_140_146), "1.1M")
        XCTAssertEqual(ModelCatalog.paramsHint(repo: "org/gemma-4-12B-it"), "12B")
        XCTAssertEqual(ModelCatalog.paramsHint(repo: "org/model-0.6B-x"), "0.6B")
        XCTAssertNil(ModelCatalog.paramsHint(repo: "org/noname"))
        XCTAssertEqual(ModelCatalog.daysAgo(iso: nil), nil)
        XCTAssertEqual(ModelStore.totalBytes([StagedEntry(fileName: "a", sizeBytes: 10),
                                              StagedEntry(fileName: "b", sizeBytes: 20)]), 30)
        XCTAssertEqual(ModelCatalog.recommendedModels().count, 8)
        let statEntry = CatalogEntry(repo: "org/m", likes: 5, downloads: 1500)
        XCTAssertTrue(CatalogBrowserView.statLine(entry: statEntry).contains("1.5K"))
    }

    /// HTML 태그 스트립·링크 파일명 (T-237).
    func testStripHTMLAndLink() {
        XCTAssertEqual(NativeMarkdown.stripHTMLTags("<td><p>hello</p></td>"), "hello")
        XCTAssertEqual(NativeMarkdown.stripHTMLTags("<br>"), "")
        XCTAssertEqual(NativeMarkdown.htmlCellText("<td>138 tk/s</td>"), "138 tk/s")
        XCTAssertEqual(
            NativeMarkdown.htmlCellText(
                "<td><a href=\"https://huggingface.co/org/m/resolve/main/M_mprefill.task\">🔗</a></td>"),
            "M_mprefill.task")
    }

    /// HTML 표 구간 변환 (T-237): tr 단위·th 헤더.
    func testHtmlTableBlocks() {
        let doc = """
        <table>
        <tr><th>양자화</th><th>속도</th></tr>
        <tr><td>dynamic_int4</td><td>138 tk/s</td></tr>
        </table>
        """
        let blocks = NativeMarkdown.parseProse(doc)
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let rows, let header) = blocks[0] else {
            return XCTFail("표 블록 기대")
        }
        XCTAssertTrue(header)
        XCTAssertEqual(rows, [["양자화", "속도"], ["dynamic_int4", "138 tk/s"]])
    }

    /// 혼합 문서: 파이프 표 불변+HTML 표+일반 문단 (T-237).
    func testMixedTablesUnchanged() {
        let doc = "| a | b |\n|---|---|\n| 1 | 2 |\n\n<table>\n<tr><td>x</td></tr>\n</table>\n\n끝"
        let blocks = NativeMarkdown.parseProse(doc)
        let tables = blocks.compactMap { b -> [[String]]? in
            guard case .table(let rows, _) = b else { return nil }
            return rows
        }
        XCTAssertEqual(tables.count, 2)
        XCTAssertTrue(blocks.contains(.paragraph(text: "끝")))
    }

    /// 멀티라인 HTML 블록 제거 (T-331): svg 통째로 버리고 앞뒤 문단 유지.
    func testMultilineHtmlBlockSkipped() {
        let doc = """
        앞 문단
        <svg xmlns="http://www.w3.org/2000/svg" height="72px"
        viewBox="0 -960 960 960" width="72px"
        fill="currentColor"><path d="M320-120v-40l80-80H160q-33
        0-56.5-23.5T80-320v-440q0-33
        23.5-56.5T160-840h640q33 0 56.5 23.5T880-760v440q0
        33-23.5 56.5T800-240H560l80
        80v40H320ZM160-440h640v-320H160v320Zm0 0v-320
        320Z"/></svg>
        뒤 문단
        """
        let blocks = NativeMarkdown.parseProse(doc)
        let texts = blocks.compactMap { b -> String? in
            guard case .paragraph(let text) = b else { return nil }
            return text
        }.joined(separator: "\n")
        XCTAssertTrue(texts.contains("앞 문단"))
        XCTAssertTrue(texts.contains("뒤 문단"))
        XCTAssertFalse(texts.contains("svg"))
        XCTAssertFalse(texts.contains("w3.org"))
        XCTAssertFalse(texts.contains("M320"))
    }

    /// 한 줄 태그·비태그 기존 동작 유지 (T-331).
    func testSingleLineTagUnchanged() {
        XCTAssertEqual(NativeMarkdown.htmlTagName("<svg"), "svg")
        XCTAssertEqual(NativeMarkdown.htmlTagName("</div>"), "div")
        XCTAssertNil(NativeMarkdown.htmlTagName("<3"))
        let blocks = NativeMarkdown.parseProse("<3\n\n<div>hi</div>")
        XCTAssertTrue(blocks.contains(.paragraph(text: "<3")))
        XCTAssertTrue(blocks.contains(.paragraph(text: "hi")))
    }

    /// 파일명 → 검색어 정제 (T-251).
    func testSearchStem() {
        XCTAssertEqual(ModelCatalog.searchStem(fileName: "qwen3_4b_mixed_int4.litertlm"), "qwen3 4b")
        XCTAssertEqual(ModelCatalog.searchStem(fileName: "gemma-4-E2B-it.litertlm"), "gemma 4 E2B")
        XCTAssertEqual(ModelCatalog.searchStem(fileName: "qwen3_asr_0.6b_5s_i8.litertlm"), "qwen3 asr 0.6b")
        XCTAssertEqual(ModelCatalog.searchStem(fileName: "m.litertlm"), "m")
    }

    /// 용량 헤더 파싱 (T-239): x-linked-size·Range.
    func testLinkedSizeAndRange() {
        XCTAssertEqual(ModelDownload.linkedSize(headers: ["X-Linked-Size": "2588147712"]), 2588147712)
        XCTAssertEqual(ModelDownload.linkedSize(headers: ["x-linked-size": " 100 "]), 100)
        XCTAssertNil(ModelDownload.linkedSize(headers: ["Content-Length": "10"]))
        XCTAssertEqual(ModelDownload.rangeTotal(contentRange: "bytes 0-0/12345"), 12345)
        XCTAssertNil(ModelDownload.rangeTotal(contentRange: nil))
        XCTAssertNil(ModelDownload.rangeTotal(contentRange: "none"))
        // 140B 사례: 302 본문 길이는 크기가 아님.
        XCTAssertEqual(ModelDownload.sizeFromHead(status: 302, linked: 2588147712,
                                                  contentLength: 140), 2588147712)
        XCTAssertNil(ModelDownload.sizeFromHead(status: 302, linked: nil, contentLength: 140))
        XCTAssertEqual(ModelDownload.sizeFromHead(status: 200, linked: nil,
                                                  contentLength: 140), 140)
        XCTAssertNil(ModelDownload.sizeFromHead(status: 200, linked: nil, contentLength: -1))
    }

    /// HTTP 상태 문구 (T-242): 401/403 게이트 안내.
    func testHttpErrorMessage() {
        XCTAssertTrue(ModelDownload.httpErrorMessage(status: 401).contains("승인 필요"))
        XCTAssertTrue(ModelDownload.httpErrorMessage(status: 403).contains("승인 필요"))
        XCTAssertTrue(ModelDownload.httpErrorMessage(status: 404).contains("404"))
        XCTAssertEqual(ModelDownload.httpErrorMessage(status: 500), "HTTP 500")
    }

    /// 이어받기 판정·헤더·바 클램프 (T-246/T-248).
    func testResumeAndClamp() {
        XCTAssertEqual(ModelDownload.resumeRangeHeader(existing: 123), "bytes=123-")
        XCTAssertEqual(ModelDownload.resumeRangeHeader(existing: -5), "bytes=0-")
        XCTAssertEqual(ModelDownload.resumeAction(status: 206), .append)
        XCTAssertEqual(ModelDownload.resumeAction(status: 200), .restart)
        XCTAssertEqual(ModelDownload.resumeAction(status: 404), .fail)
        XCTAssertEqual(ModelDownload.clamp01(-0.5), 0)
        XCTAssertEqual(ModelDownload.clamp01(1.5), 1)
        XCTAssertEqual(ModelDownload.clamp01(0.62), 0.62, accuracy: 0.001)
    }

    /// 하이라이트 만료 판정 (T-247).
    func testHighlightExpiry() {
        let setAt = Date(timeIntervalSinceNow: -5)
        XCTAssertTrue(ModelManagerView.shouldClearHighlight(setAt: setAt))
        XCTAssertFalse(ModelManagerView.shouldClearHighlight(setAt: Date()))
    }

    /// 매핑 퍼지·스테이징 파일 찾기 (T-250).
    func testPurgeAndStagedFile() {
        let map = ["a.litertlm": FileMapping(localID: "m1"),
                   "b.litertlm": FileMapping(localID: "m2")]
        XCTAssertEqual(ModelStore.purgeMapping(map, installedIDs: ["m1"]),
                       ["a.litertlm": FileMapping(localID: "m1")])
        let staged = [StagedEntry(fileName: "a.litertlm"), StagedEntry(fileName: "m2.litertlm")]
        XCTAssertEqual(ModelStore.stagedFileForModel(id: "m1", mapping: map, staged: staged),
                       "a.litertlm")
        XCTAssertEqual(ModelStore.stagedFileForModel(id: "m2", mapping: [:], staged: staged),
                       "m2.litertlm")
        XCTAssertNil(ModelStore.stagedFileForModel(id: "m9", mapping: map, staged: staged))
        XCTAssertNil(ModelStore.stagedFileForModel(id: "m1", mapping: map, staged: []))
    }

    /// 파일 stem (T-253).
    func testFileStem() {
        XCTAssertEqual(ModelDownload.fileStem("gemma-3n-E4B-it-int4.litertlm"), "gemma-3n-E4B-it-int4")
        XCTAssertEqual(ModelDownload.fileStem("a.b.litertlm"), "a.b")
        XCTAssertEqual(ModelDownload.fileStem("plain"), "plain")
    }

    /// 설치 가능 판정 (T-254).
    func testIsInstallableFile() {
        XCTAssertTrue(ModelStore.isInstallableFile(name: "m.litertlm"))
        XCTAssertFalse(ModelStore.isInstallableFile(name: "m.litertlm.part"))
        XCTAssertFalse(ModelStore.isInstallableFile(name: "m.task"))
        XCTAssertFalse(ModelStore.isInstallableFile(name: ""))
    }

    /// 온보딩 버전 파싱·최소비교 (T-257).
    func testOnboardingGate() {
        XCTAssertEqual(OnboardingGate.parseVersion("litert-lm, version 0.17.0"), "0.17.0")
        XCTAssertEqual(OnboardingGate.parseVersion("uv 0.11.29 (Homebrew)"), "0.11.29")
        XCTAssertNil(OnboardingGate.parseVersion("없음"))
        XCTAssertTrue(OnboardingGate.meetsMinimum("0.17.0"))
        XCTAssertTrue(OnboardingGate.meetsMinimum("0.14.0"))
        XCTAssertFalse(OnboardingGate.meetsMinimum("0.13.9"))
        XCTAssertFalse(OnboardingGate.meetsMinimum(nil))
        XCTAssertFalse(OnboardingGate.meetsMinimum("없음"))
    }
}
