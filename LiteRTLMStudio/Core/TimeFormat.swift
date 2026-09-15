import Foundation

/// 시간 포맷 단일 진입점 (T-114).
/// Daemon 로그(HH:mm:ss) + DebugPanel(HH:mm:ss.SSS) 중복 제거용.
/// 기존 공개 API(`DaemonManager.logTimeString`, `DebugPanelView.timeString`)는 래퍼로 유지.
enum TimeFormat {
    private static let lock = NSLock() // T-127 DateFormatter 비스레드안전 보호
    private static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private static let debugFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    nonisolated static func logTime(_ date: Date) -> String {
        lock.withLock { logFormatter.string(from: date) }
    }

    nonisolated static func debugTime(_ date: Date) -> String {
        lock.withLock { debugFormatter.string(from: date) }
    }
}
