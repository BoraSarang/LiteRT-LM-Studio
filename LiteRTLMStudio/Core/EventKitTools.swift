import EventKit
import Foundation

/// EventKit 접근 브리지 (T-270): 권한 요청·조회·생성.
enum EventKitBridge {
    static let store = EKEventStore()

    static var permissionMessage: String {
        "권한이 없어 실행할 수 없습니다. 시스템 설정 > 개인정보 보호 및 보안에서 캘린더·미리 알림 접근을 허용해 주세요."
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일(EEEE) HH:mm"
        return formatter
    }()

    static func requestEvents() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestFullAccessToEvents { granted, _ in cont.resume(returning: granted) }
        }
    }

    static func requestReminders() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestFullAccessToReminders { granted, _ in cont.resume(returning: granted) }
        }
    }

    static func upcomingEvents(days: Int, now: Date = Date()) -> String {
        let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else { return "앞으로 \(days)일 안에 일정이 없습니다." }
        return events.prefix(30).map { event in
            "\(dayFormatter.string(from: event.startDate)) \(event.title ?? "(제목 없음)")"
        }.joined(separator: "\n")
    }

    static func reminders(includeCompleted: Bool) async -> String {
        let predicate = store.predicateForReminders(in: nil)
        let items: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result ?? [])
            }
        }
        let filtered = items.filter { includeCompleted || !$0.isCompleted }
        guard !filtered.isEmpty else {
            return includeCompleted ? "미리 알림이 없습니다." : "미완료 미리 알림이 없습니다."
        }
        return filtered.prefix(30).map { reminder in
            let due = reminder.dueDateComponents
                .flatMap { Calendar.current.date(from: $0) }
                .map { " · \(dayFormatter.string(from: $0))" } ?? ""
            return "\(reminder.title ?? "(제목 없음)")\(due)"
        }.joined(separator: "\n")
    }

    static func addReminder(title: String, notes: String?, due: Date) -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = store.defaultCalendarForNewReminders()
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: due)
        do {
            try store.save(reminder, commit: true)
            return "미리 알림 추가됨: \(title) · \(dayFormatter.string(from: due))"
        } catch {
            return "미리 알림 추가 실패: \(error.localizedDescription)"
        }
    }

    static func addEvent(title: String, start: Date, minutes: Int, notes: String?) -> String {
        guard let calendar = store.defaultCalendarForNewEvents else {
            return "일정 추가 실패: 기본 캘린더가 없습니다."
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.calendar = calendar
        event.startDate = start
        event.endDate = Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? start
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return "일정 추가됨: \(title) · \(dayFormatter.string(from: start))"
        } catch {
            return "일정 추가 실패: \(error.localizedDescription)"
        }
    }
}

/// 날짜 표현 해석 공용 (T-270): 실패 시 E-MAC-VALID-0017.
enum SystemToolDates {
    static func resolve(_ text: String) -> Date? {
        KoreanDateParser.parse(text)
    }

    static func failureMessage(_ text: String) -> String {
        "날짜를 이해하지 못했습니다: '\(text)'. '내일 오후 3시'처럼 말해 주세요."
    }

    static func logFailure(_ text: String) {
        DebugLogger.shared.error(code: "E-MAC-VALID-0017", feature: "시스템도구",
                                 "날짜 해석 실패: \(text)")
    }
}

/// 캘린더 일정 조회 도구 (T-270): 권한 필요, 부작용 없음.
struct ListCalendarEventsTool: Tool {
    static let name = "list_calendar_events"
    static let description = "앞으로 며칠 안의 캘린더 일정을 조회합니다."

    @ToolParam(description: "조회할 일수 (기본 7)")
    var days = 7

    func run() async throws -> Any {
        let span = min(max(days, 1), 60)
        return await LocalTools.runTolled(toolName: Self.name, detail: "앞으로 \(span)일 일정 조회") {
            guard await EventKitBridge.requestEvents() else {
                DebugLogger.shared.error(code: "E-MAC-PERM-0016", feature: "시스템도구",
                                         "캘린더 권한 거부")
                return EventKitBridge.permissionMessage
            }
            return EventKitBridge.upcomingEvents(days: span)
        }
    }
}

/// 미리 알림 조회 도구 (T-270): 권한 필요, 부작용 없음.
struct ListRemindersTool: Tool {
    static let name = "list_reminders"
    static let description = "미리 알림(Reminders) 목록을 조회합니다."

    @ToolParam(description: "완료된 항목도 포함할지 (기본 false)")
    var includeCompleted = false

    func run() async throws -> Any {
        let include = includeCompleted
        return await LocalTools.runTolled(toolName: Self.name, detail: "미리 알림 조회") {
            guard await EventKitBridge.requestReminders() else {
                DebugLogger.shared.error(code: "E-MAC-PERM-0016", feature: "시스템도구",
                                         "미리 알림 권한 거부")
                return EventKitBridge.permissionMessage
            }
            return await EventKitBridge.reminders(includeCompleted: include)
        }
    }
}

/// 미리 알림 추가 도구 (T-270): 권한+게이트 승인 필요.
struct AddReminderTool: Tool {
    static let name = "add_reminder"
    static let description = "미리 알림(Reminders)을 추가합니다. '내일 오후 3시' 같은 한국어 시간 표현을 씁니다."

    @ToolParam(description: "미리 알림 내용")
    var title = ""

    @ToolParam(description: "언제 (예: 내일 오후 3시, 다음 주 월요일 오전 9시)")
    var when = ""

    @ToolParam(description: "메모 (선택)")
    var notes: String?

    func run() async throws -> Any {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "미리 알림 내용이 비어 있습니다." }
        let rawWhen = when
        guard let due = SystemToolDates.resolve(rawWhen) else {
            SystemToolDates.logFailure(rawWhen)
            return SystemToolDates.failureMessage(rawWhen)
        }
        let note = notes
        let detail = "미리 알림 추가: \(name) · \(EventKitBridge.dayFormatter.string(from: due))"
        return await LocalTools.runTolled(toolName: Self.name, detail: detail) {
            guard await EventKitBridge.requestReminders() else {
                DebugLogger.shared.error(code: "E-MAC-PERM-0016", feature: "시스템도구",
                                         "미리 알림 권한 거부")
                return EventKitBridge.permissionMessage
            }
            return EventKitBridge.addReminder(title: name, notes: note, due: due)
        }
    }
}

/// 캘린더 일정 추가 도구 (T-270): 권한+게이트 승인 필요.
struct AddCalendarEventTool: Tool {
    static let name = "add_calendar_event"
    static let description = "캘린더 일정을 추가합니다. '내일 오후 3시' 같은 한국어 시간 표현을 씁니다."

    @ToolParam(description: "일정 제목")
    var title = ""

    @ToolParam(description: "시작 시각 (예: 내일 오후 3시)")
    var when = ""

    @ToolParam(description: "길이(분). 기본 60")
    var durationMinutes = 60

    @ToolParam(description: "메모 (선택)")
    var notes: String?

    func run() async throws -> Any {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "일정 제목이 비어 있습니다." }
        let rawWhen = when
        guard let start = SystemToolDates.resolve(rawWhen) else {
            SystemToolDates.logFailure(rawWhen)
            return SystemToolDates.failureMessage(rawWhen)
        }
        let minutes = min(max(durationMinutes, 5), 24 * 60)
        let note = notes
        let detail = "일정 추가: \(name) · \(EventKitBridge.dayFormatter.string(from: start))"
        return await LocalTools.runTolled(toolName: Self.name, detail: detail) {
            guard await EventKitBridge.requestEvents() else {
                DebugLogger.shared.error(code: "E-MAC-PERM-0016", feature: "시스템도구",
                                         "캘린더 권한 거부")
                return EventKitBridge.permissionMessage
            }
            return EventKitBridge.addEvent(title: name, start: start,
                                           minutes: minutes, notes: note)
        }
    }
}
