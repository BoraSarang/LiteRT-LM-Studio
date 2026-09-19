import Foundation

/// 앱 내 엔진 벤치마크 확장 (준비·측정·정리 단계, T-216).
/// T-360: 파일 길이 관리를 위해 `NativeEngine.swift`에서 분리.
extension NativeEngine {
    /// 벤치마크 측정 (T-132): 고정 프롬프트 1턴 실측 후 BenchmarkInfo 매핑.
    /// CLI `benchmark`(256/256 고정)와 조건이 달라 근사 비교용.
    func benchmark(modelID: String) async throws -> EngineBenchmark {
        try await benchmarkWithProgress(modelID: modelID, onStage: { _ in })
    }

    /// 벤치마크 측정 + 진행 알림 (T-216): prepare→측정→정리 단계를 콜백으로 전달.
    /// 오버로드 대신 별도 이름 (동명 오버로드가 타입 추론을 무겁게 함).
    func benchmarkWithProgress(modelID: String,
                               onStage: @escaping (BenchmarkPhase) -> Void) async throws -> EngineBenchmark {
        onStage(.preparing)
        try await prepare(modelID: modelID)
        guard let engine = engines[modelID] else { throw EngineError.notReady }
        do {
            let conversation = try await engine.createConversation()
            onStage(.measuring)
            let prompt = Message("Describe Seoul in three sentences.")
            for try await _ in conversation.sendMessageStream(prompt) {
                try Task.checkCancellation()
            }
            onStage(.summarizing)
            let info = try conversation.getBenchmarkInfo()
            DebugLogger.shared.perf(feature: "앱내벤치",
                                    "완료 prefill=\(info.lastPrefillTokensPerSecond) "
                                    + "decode=\(info.lastDecodeTokensPerSecond)")
            return EngineBenchmark(
                initTime: info.initTimeInSecond,
                ttft: info.timeToFirstTokenInSecond,
                prefillTokens: info.lastPrefillTokenCount,
                prefillSpeed: info.lastPrefillTokensPerSecond,
                decodeTokens: info.lastDecodeTokenCount,
                decodeSpeed: info.lastDecodeTokensPerSecond
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EngineError.inferenceFailed("\(error)")
        }
    }
}
