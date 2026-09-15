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

    private func withNativeMode(_ body: () -> Void) {
        let key = "engineMode"
        let prev = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set("native", forKey: key)
        defer {
            if let prev {
                UserDefaults.standard.set(prev, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        body()
    }

    /// 네이티브 매핑 (T-132): 지표·단계·종료 상태.
    func testNativeBenchmarkMapping() async {
        let store = BenchmarkStore()
        store.nativeBenchmark = { _ in
            EngineBenchmark(initTime: 1.5, ttft: 2.5, prefillTokens: 10,
                            prefillSpeed: 20, decodeTokens: 30, decodeSpeed: 15)
        }
        withNativeMode {
            store.run(modelID: "m")
        }
        await waitDone(store)
        XCTAssertFalse(store.running)
        XCTAssertEqual(store.stage, .done)
        let met = try? XCTUnwrap(store.metrics)
        XCTAssertEqual(met?.backend, "네이티브 GPU")
        XCTAssertEqual(met?.prefillSpeed ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(met?.decodeSpeed ?? -1, 15, accuracy: 0.0001)
        XCTAssertEqual(met?.initTime ?? -1, 1.5, accuracy: 0.0001)
        XCTAssertEqual(met?.ttft ?? -1, 2.5, accuracy: 0.0001)
        XCTAssertEqual(met?.prefillTokens, 10)
        XCTAssertEqual(met?.decodeTokens, 30)
    }

    /// 네이티브 실패 (T-132): 실행 중 해제+초기 단계 복귀.
    func testNativeBenchmarkFailure() async {
        struct Boom: Error {}
        let store = BenchmarkStore()
        store.nativeBenchmark = { _ in throw Boom() }
        withNativeMode {
            store.run(modelID: "m")
        }
        await waitDone(store)
        XCTAssertFalse(store.running)
        XCTAssertNil(store.metrics)
        XCTAssertEqual(store.stage, .initEngine)
    }
}
