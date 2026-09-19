import XCTest
@testable import LiteRTLMStudio

/// 모델 영속 테스트군 (T-249/T-252 분리: 파일 길이 분산).
final class LiteRTLMStudioModelIOTests: LiteRTLMStudioTestCase {
    /// 매핑 구 호환 디코드 (T-252): 문자열·객체·왕복.
    func testFileMappingCompat() throws {
        let legacy = try JSONDecoder().decode([String: FileMapping].self,
                                              from: Data("{\"a\": \"m1\"}".utf8))
        XCTAssertEqual(legacy, ["a": FileMapping(localID: "m1")])
        let modern = try JSONDecoder().decode(
            [String: FileMapping].self,
            from: Data("{\"a\": {\"localID\": \"m1\", \"repo\": \"org/m\"}}".utf8))
        XCTAssertEqual(modern["a"]?.repo, "org/m")
        let round = try JSONDecoder().decode(
            [String: FileMapping].self,
            from: try JSONEncoder().encode(["a": FileMapping(localID: "m1", repo: "org/m")]))
        XCTAssertEqual(round["a"], FileMapping(localID: "m1", repo: "org/m"))
    }

    /// 큐 코덱·토큰 미포함·복원 필터·고아 판정 (T-249).
    func testQueuePersistence() throws {
        let records = [QueuedDownload(repo: "org/m", file: "m.litertlm", localID: "m1")]
        let data = try JSONEncoder().encode(records)
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("token") ?? true)
        let decoded = try JSONDecoder().decode([QueuedDownload].self, from: data)
        XCTAssertEqual(decoded, records)
        XCTAssertEqual(DownloadCenter.pendingRecords(records, existingFinals: []).count, 1)
        XCTAssertTrue(DownloadCenter.pendingRecords(records,
                                                    existingFinals: ["m.litertlm"]).isEmpty)
        XCTAssertEqual(DownloadCenter.orphanFinals(partFiles: ["a.litertlm", "b.litertlm"],
                                                    queuedFiles: ["a.litertlm"]),
                       ["b.litertlm"])
    }
}
