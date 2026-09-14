import Foundation

/// `litert-lm benchmark` 실행·파싱. 단계 표시 + 지표 추출 (Swift Charts 표시용).
@MainActor
final class BenchmarkStore: ObservableObject {
    enum Stage: Int, CaseIterable {
        case initEngine = 0, measure, summarize, done
        var title: String {
            switch self {
            case .initEngine: "1. 엔진 초기화"
            case .measure: "2. 측정 실행"
            case .summarize: "3. 결과 정리"
            case .done: "4. 완료"
            }
        }
    }

    struct Metrics {
        var backend = "-"
        var prefillTokens = 0, decodeTokens = 0, runs = 0
        var prefillSpeed = 0.0, decodeSpeed = 0.0
        var initTime = 0.0, ttft = 0.0

        /// 숫자 이해를 돕는 한국어 해설.
        var explanation: [(String, String)] {
            [
                ("첫 토큰까지 \(fmt(ttft))초",
                 ttft < 2 ? "체감 반응이 빠릅니다. 엔터 후 바로 답이 나오기 시작해요."
                     : ttft < 10 ? "보통 수준입니다. 짧은 질문에는 충분해요."
                     : "다소 느립니다. prefill이 무거운 긴 입력에서 두드러져요."),
                ("생성 속도 초당 \(fmt(decodeSpeed))토큰",
                 decodeSpeed >= 15 ? "긴 답변도 술술 나옵니다."
                     : decodeSpeed >= 5 ? "읽는 속도와 비슷해 무난합니다."
                     : "답이 한 글자씩 끊겨 보일 수 있어요. 짧게 답해 달라고 하세요."),
                ("입력 처리 초당 \(fmt(prefillSpeed))토큰",
                 "긴 문서·이미지를 함께 보낼 때의 준비 속도입니다."),
                ("엔진 준비 \(fmt(initTime))초",
                 "첫 실행 한 번만 드는 비용입니다. 데몬이 떠 있으면 다시 안 들어요."),
            ]
        }

        private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
    }

    @Published var stage: Stage = .initEngine
    @Published var currentIter = 0
    @Published var totalIter = 1
    @Published var logLines: [String] = []
    @Published var metrics: Metrics?
    @Published var running = false

    private var process: Process?
    private let logger = DebugLogger.shared

    func run(modelID: String) {
        guard !running else { return }
        logger.info(feature: "벤치마크", "\(modelID) benchmark 시작 (기본 토큰)")
        stage = .initEngine
        currentIter = 0
        totalIter = 1
        logLines = []
        metrics = nil
        running = true
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: UvManager.litertBin)
        proc.arguments = ["benchmark", modelID]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard !text.isEmpty else { return }
            Task { @MainActor in
                self?.ingest(text)
            }
        }
        proc.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.finish(code: proc.terminationStatus)
            }
        }
        process = proc
        do {
            try proc.run()
        } catch {
            running = false
            logger.error(code: "E-MAC-NET-0004", feature: "벤치마크", "실행 실패: \(error)")
        }
    }

    func cancel() {
        process?.terminate()
        logger.info(feature: "벤치마크", "사용자 중단")
    }

    private func ingest(_ text: String) {
        let lines = text.split(separator: "\n").map(String.init)
        logLines.append(contentsOf: lines)
        if logLines.count > 300 { logLines.removeFirst(100) }
        var met = metrics ?? Metrics()
        for line in lines {
            if line.contains("Benchmarking model:") { stage = .initEngine }
            if let (cur, tot) = Self.match(line, "Running iteration (\\d+) of (\\d+)") {
                stage = .measure
                currentIter = cur
                totalIter = tot
            }
            if line.contains("Results") { stage = .summarize }
            if let val = Self.value(line, "Prefill speed:") { met.prefillSpeed = val }
            if let val = Self.value(line, "Decode speed:") { met.decodeSpeed = val }
            if let val = Self.value(line, "Init time:") { met.initTime = val }
            if let val = Self.value(line, "Time to first token:") { met.ttft = val }
            if let val = Self.int(line, "Number of tokens in prefill:") { met.prefillTokens = val }
            if let val = Self.int(line, "Number of tokens in decode:") { met.decodeTokens = val }
            if line.hasPrefix("Backend") {
                met.backend = line.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? met.backend
            }
        }
        metrics = met
    }

    private func finish(code: Int32) {
        running = false
        stage = metrics == nil ? .initEngine : .done
        if code == 0, metrics != nil {
            stage = .done
            let met = metrics!
            logger.perf(feature: "벤치마크", "완료 prefill=\(met.prefillSpeed) decode=\(met.decodeSpeed) ttft=\(met.ttft)")
        } else if code != 0 {
            logger.error(code: "E-MAC-NET-0004", feature: "벤치마크", "종료코드=\(code)")
        }
    }

    // MARK: - 관대한 정규식 파서 (출력 변형에 강하게)
    private static func match(_ line: String, _ pattern: String) -> (Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let found = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              found.numberOfRanges == 3,
              let r1 = Range(found.range(at: 1), in: line),
              let r2 = Range(found.range(at: 2), in: line)
        else { return nil }
        guard let first = Int(line[r1]), let second = Int(line[r2]) else { return nil }
        return (first, second)
    }

    private static func value(_ line: String, _ prefix: String) -> Double? {
        guard line.contains(prefix) else { return nil }
        let num = line.replacingOccurrences(of: prefix, with: "")
            .replacingOccurrences(of: "tokens/s", with: "")
            .replacingOccurrences(of: "s", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(num)
    }

    private static func int(_ line: String, _ prefix: String) -> Int? {
        guard line.contains(prefix) else { return nil }
        let num = line.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespaces)
        return Int(num)
    }
}
