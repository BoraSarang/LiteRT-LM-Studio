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

    // MARK: - 공용 날짜 표시 (T-379 DateFormatter 중복 제거)

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 EEEE"
        return f
    }()

    private static let todayToolFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 EEEE HH시 mm분"
        return f
    }()

    nonisolated static func shortDateTime(_ date: Date) -> String {
        lock.withLock { shortDateFormatter.string(from: date) }
    }

    /// 시스템 프롬프트용 날짜 블록 (timeZone 주입 가능, 순수 호출부).
    nonisolated static func koreanDayBlock(now: Date = Date(),
                                            timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = timeZone
        f.dateFormat = "yyyy년 M월 d일 EEEE"
        return f.string(from: now)
    }

    nonisolated static func koreanDateTimeNow() -> String {
        lock.withLock { todayToolFormatter.string(from: Date()) }
    }
}
