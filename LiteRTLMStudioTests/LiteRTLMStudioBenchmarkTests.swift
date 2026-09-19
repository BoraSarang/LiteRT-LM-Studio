import AppKit
import XCTest
@testable import LiteRTLMStudio

/// 벤치마크 회귀군 (T-132): 네이티브 분기·매핑·실패.
@MainActor
final class LiteRTLMStudioBenchmarkTests: XCTestCase {
    private func waitDone(_ store: BenchmarkStore, timeout: TimeInterval = 10) async {
        let end = Date().addingTimeInterval(timeout)
        while store.running, Date() < end {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// 네이티브 매핑 (T-132/T-186): 지표·단계·종료 상태. 경로는 route 지정.
    func testNativeBenchmarkMapping() async {
        let store = BenchmarkStore()
        store.nativeBenchmark = { _ in
            EngineBenchmark(initTime: 1.5, ttft: 2.5, prefillTokens: 10,
                            prefillSpeed: 20, decodeTokens: 30, decodeSpeed: 15)
        }
        store.route = .native
        store.run(modelID: "m")
        await waitDone(store)
        XCTAssertFalse(store.running)
        XCTAssertEqual(store.stage, .done)
        let met = try? XCTUnwrap(store.metrics)
        XCTAssertEqual(met?.backend, "앱 내 엔진 GPU")
        XCTAssertEqual(met?.prefillSpeed ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(met?.decodeSpeed ?? -1, 15, accuracy: 0.0001)
        XCTAssertEqual(met?.initTime ?? -1, 1.5, accuracy: 0.0001)
        XCTAssertEqual(met?.ttft ?? -1, 2.5, accuracy: 0.0001)
        XCTAssertEqual(met?.prefillTokens, 10)
        XCTAssertEqual(met?.decodeTokens, 30)
    }

    /// 네이티브 실패 (T-132/T-186): 실행 중 해제+초기 단계 복귀.
    func testNativeBenchmarkFailure() async {
        struct Boom: Error {}
        let store = BenchmarkStore()
        store.nativeBenchmark = { _ in throw Boom() }
        store.route = .native
        store.run(modelID: "m")
        await waitDone(store)
        XCTAssertFalse(store.running)
        XCTAssertNil(store.metrics)
        XCTAssertEqual(store.stage, .initEngine)
    }

    /// T-216: prepare는 자동 실행하지 않고 대기만.
    func testPrepareDoesNotAutoStart() {
        let store = BenchmarkStore()
        store.prepare(modelID: "m", route: .cli)
        XCTAssertFalse(store.running)
        XCTAssertEqual(store.pendingModelID, "m")
        XCTAssertEqual(store.pendingRoute, .cli)
    }

    /// T-216: 예상 소요 문구 (초회 고정 + 평균 기반).
    func testEstimateText() {
        XCTAssertTrue(BenchmarkStore.estimateText(route: .native, avgDuration: nil).contains("1~3분"))
        XCTAssertTrue(BenchmarkStore.estimateText(route: .cli, avgDuration: nil).contains("10분"))
        let avg = BenchmarkStore.estimateText(route: .native, avgDuration: 120)
        XCTAssertTrue(avg.contains("이전 기록 평균"))
    }

    /// T-216: 경과 표기.
    func testElapsedText() {
        XCTAssertEqual(BenchmarkStore.elapsedText(12), "12초")
        XCTAssertEqual(BenchmarkStore.elapsedText(90), "1분 30초")
    }

    /// T-216: 중지는 즉시 상태를 내린다.
    func testCancelStopsImmediately() async {
        let store = BenchmarkStore()
        store.nativeBenchmark = { _ in
            try? await Task.sleep(for: .milliseconds(500))
            return EngineBenchmark()
        }
        store.route = .native
        store.run(modelID: "m")
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(store.running)
        store.cancel()
        XCTAssertFalse(store.running)
        XCTAssertTrue(store.logLines.contains("— 사용자 중단 —"))
        await waitDone(store)
    }

    /// T-217: 보관 수 cap (10/50/100/무제한).
    func testHistoryCap() {
        let recs = (0..<15).map { i in
            BenchmarkRecord(modelID: "m\(i)", route: .cli, metrics: nil,
                            durationSec: 10, status: .done)
        }
        XCTAssertEqual(BenchmarkHistoryStore.capped(recs, retention: .ten).count, 10)
        XCTAssertEqual(BenchmarkHistoryStore.capped(recs, retention: .fifty).count, 15)
        XCTAssertEqual(BenchmarkHistoryStore.capped(recs, retention: .unlimited).count, 15)
        XCTAssertEqual(BenchmarkRetention.current(), .ten)
    }

    /// T-217: 모델 필터 + 기록 요약.
    func testHistoryFilterAndSummary() {
        let a = BenchmarkRecord(modelID: "a", route: .native,
                                metrics: BenchmarkStore.Metrics(decodeSpeed: 12.3),
                                durationSec: 60, status: .done)
        let b = BenchmarkRecord(modelID: "b", route: .cli, metrics: nil,
                                durationSec: 5, status: .cancelled)
        XCTAssertEqual(BenchmarkHistoryStore.filtered([a, b], modelID: "전체 기록").count, 2)
        XCTAssertEqual(BenchmarkHistoryStore.filtered([a, b], modelID: "a").count, 1)
        XCTAssertTrue(a.summary.contains("a"))
        XCTAssertEqual(BenchmarkHistoryStore.averageDuration([a, b], modelID: "a"), 60)
        XCTAssertNil(BenchmarkHistoryStore.averageDuration([a, b], modelID: "없음"))
    }

    /// T-218: 분석 프롬프트 4섹션 고정.
    func testAnalyzerPromptSections() {
        let rec = BenchmarkRecord(modelID: "m", route: .native,
                                  metrics: BenchmarkStore.Metrics(),
                                  durationSec: 90, status: .done)
        let prompt = BenchmarkAnalyzer.prompt(record: rec, avgDuration: nil)
        XCTAssertTrue(prompt.contains("## 요약"))
        XCTAssertTrue(prompt.contains("## 지표 해석"))
        XCTAssertTrue(prompt.contains("## 이전 기록과 비교"))
        XCTAssertTrue(prompt.contains("## 개선 제안"))
        XCTAssertTrue(prompt.contains("\"없음\""))
    }

    /// T-221: 상세 우선순위 — 실행 중 > 명시적 선택 > 라이브 완료 > 최신 기록 > 빈 상태.
    func testDetailModePriority() {
        XCTAssertEqual(BenchmarkDetailMode.resolve(running: true, hasSelection: true,
                                                   liveDone: true, hasHistory: true), .running)
        // 버그 재현: 라이브 metrics가 있어도 명시적 선택이 이긴다.
        XCTAssertEqual(BenchmarkDetailMode.resolve(running: false, hasSelection: true,
                                                   liveDone: true, hasHistory: true), .selected)
        XCTAssertEqual(BenchmarkDetailMode.resolve(running: false, hasSelection: false,
                                                   liveDone: true, hasHistory: true), .live)
        // 중단 후 부분 metrics(liveDone=false)여도 기록이 보인다.
        XCTAssertEqual(BenchmarkDetailMode.resolve(running: false, hasSelection: false,
                                                   liveDone: false, hasHistory: true), .latest)
        XCTAssertEqual(BenchmarkDetailMode.resolve(running: false, hasSelection: false,
                                                   liveDone: false, hasHistory: false), .empty)
    }

    /// T-222: MTP 기본 OFF (명시된 모델만 켬).
    func testMTPDefaultOff() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bench-mtp-\(UUID().uuidString).json")
        let store = ConfigStore(configURL: tmp)
        XCTAssertFalse(store.appliedMTP)
        XCTAssertFalse(store.draftMTP)
        XCTAssertNil(ConfigStore.savedMTP(modelID: "m", configURL: tmp))
    }

    /// T-222: 배터리 파싱.
    func testBatteryParse() {
        let dis = BatteryStatus.parse(
            " -InternalBattery-0 (id=1)\t10%; discharging; 1:23 remaining present: true")
        XCTAssertEqual(dis, BatteryStatus(percent: 10, discharging: true))
        let chg = BatteryStatus.parse(" -InternalBattery-0\t85%; charging; present: true")
        XCTAssertEqual(chg, BatteryStatus(percent: 85, discharging: false))
        XCTAssertNil(BatteryStatus.parse("No batteries"))
    }

    /// T-222: 전원·MTP 한 줄 (MTP 켬 또는 20% 이하 방전 시 경고).
    func testPowerLine() {
        let (t1, w1) = BatteryStatus.powerLine(mtp: true, battery: nil)
        XCTAssertTrue(w1)
        XCTAssertTrue(t1.contains("MTP 켬"))
        let (t2, w2) = BatteryStatus.powerLine(
            mtp: false, battery: BatteryStatus(percent: 10, discharging: true))
        XCTAssertTrue(w2)
        XCTAssertTrue(t2.contains("10%"))
        let (_, w3) = BatteryStatus.powerLine(
            mtp: false, battery: BatteryStatus(percent: 80, discharging: false))
        XCTAssertFalse(w3)
        let (t4, w4) = BatteryStatus.powerLine(mtp: nil, battery: nil)
        XCTAssertFalse(w4)
        XCTAssertTrue(t4.contains("기본 끔"))
    }

    /// T-223/T-227: 분석 작업 스냅샷 (프롬프트+측정 경로 엔진 표기).
    func testAnalysisJob() {
        let rec = BenchmarkRecord(modelID: "m", route: .native,
                                  metrics: BenchmarkStore.Metrics(),
                                  durationSec: 90, status: .done)
        let job = BenchmarkStore.AnalysisJob.make(record: rec, avgDuration: nil,
                                                  modelDisplay: "M")
        XCTAssertEqual(job.engineLabel, "M·앱 내 엔진")
        XCTAssertTrue(job.prompt.contains("## 요약"))
    }

    /// T-224: 기록 로그 꼬리 왕복 + 구 JSON 호환.
    func testRecordLogTail() throws {
        let rec = BenchmarkRecord(modelID: "m", route: .cli, metrics: nil,
                                  durationSec: 5, status: .cancelled, logTail: ["a", "b"])
        let data = try JSONEncoder().encode(rec)
        let back = try JSONDecoder().decode(BenchmarkRecord.self, from: data)
        XCTAssertEqual(back.logTail, ["a", "b"])
        let oldJSON = """
            {"id":"\(UUID().uuidString)","modelID":"m","route":"cli",\
            "durationSec":5,"status":"done"}
            """.data(using: .utf8)!
        let old = try JSONDecoder().decode(BenchmarkRecord.self, from: oldJSON)
        XCTAssertEqual(old.logTail, [])
        XCTAssertNil(old.metrics)
    }
}
