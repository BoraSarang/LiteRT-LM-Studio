import Foundation
import OSLog

/// DebugLogger 경유 필수 (AGENTS 4장). 모든 I/O는 이 로거를 통과한다.
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    enum Level: String, CaseIterable {
        case info = "INFO", error = "ERROR", perf = "PERF", cache = "CACHE"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let level: Level
        let feature: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []
    private let log = Logger(subsystem: "com.borasarang.litert-lm-studio", category: "app")
    private let lock = NSLock()
    /// 메모리 상한 (T-119): 최근 2000건 유지. DebugPanel·복사는 저장분 기준.

    func info(feature: String, _ message: String) { add(.info, feature: feature, message) }
    func error(code: String, feature: String, _ message: String) {
        add(.error, feature: feature, "\(code) \(message)")
    }
    func perf(feature: String, _ message: String) { add(.perf, feature: feature, message) }
    func cache(feature: String, _ message: String) { add(.cache, feature: feature, message) }

    private func add(_ level: Level, feature: String, _ message: String) {
        let entry = Entry(level: level, feature: feature, message: message)
        lock.withLock {
            entries.append(entry)
            if entries.count > 2000 { entries.removeFirst(entries.count - 2000) }
        }
        switch level {
        case .info: log.info("[\(feature, privacy: .public)] \(message, privacy: .public)")
        case .error: log.error("[\(feature, privacy: .public)] \(message, privacy: .public)")
        case .perf, .cache:
            let tag = "[\(level.rawValue)] [\(feature)]"
            log.debug("\(tag, privacy: .public) \(message, privacy: .public)")
        }
    }

    func clear() { lock.withLock { entries.removeAll() } }
}
