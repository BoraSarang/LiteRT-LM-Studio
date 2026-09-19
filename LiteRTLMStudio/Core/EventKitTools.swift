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

    static func addReminder(title: String, notes: String?, due: Date) throws -> String {
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
            throw ToolExecutionError.saveFailed("미리 알림 추가 실패: \(error.localizedDescription)")
        }
    }

    static func addEvent(title: String, start: Date, minutes: Int, notes: String?) throws -> String {
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw ToolExecutionError.noDefaultCalendar
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
            throw ToolExecutionError.saveFailed("일정 추가 실패: \(error.localizedDescription)")
        }
    }

    /// 일정 삭제 (T-349): 제목 일치(대소문자 무시) 항목 삭제.
    /// date가 주어지면 그 날짜의 일정만, 없으면 제목 일치 전체.
    static func deleteEvents(title: String, date: Date?, now: Date = Date()) throws -> String {
        let start = Calendar.current.date(byAdding: .day, value: -366, to: now) ?? now
        let end = Calendar.current.date(byAdding: .year, value: 5, to: now) ?? now
        let candidates = store.events(matching: store.predicateForEvents(
            withStart: start, end: end, calendars: nil
        )).filter { event in
            guard let eventTitle = event.title,
                  eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                      .caseInsensitiveCompare(title) == .orderedSame else { return false }
            guard let date else { return true }
            return Calendar.current.isDate(event.startDate, inSameDayAs: date)
        }
        guard !candidates.isEmpty else { return "해당 제목의 일정을 찾지 못했습니다." }
        let times = candidates.map { dayFormatter.string(from: $0.startDate) }
        var removed = 0
        for event in candidates {
            do {
                try store.remove(event, span: .thisEvent, commit: true)
                removed += 1
            } catch {
                throw ToolExecutionError.removeFailed("일정 삭제 실패: \(error.localizedDescription)")
            }
        }
        return "일정 삭제: \(title) \(removed)건 · \(times.joined(separator: ", "))"
    }

    /// 미리 알림 삭제 (T-349): 제목 일치 항목 삭제. 완료 항목은 skip 할 수 있다.
    static func deleteReminders(title: String, includeCompleted: Bool) async throws -> String {
        let predicate = store.predicateForReminders(in: nil)
        let items: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result ?? [])
            }
        }
        let candidates = items.filter { reminder in
            guard let reminderTitle = reminder.title,
                  reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                      .caseInsensitiveCompare(title) == .orderedSame else { return false }
            return includeCompleted || !reminder.isCompleted
        }
        guard !candidates.isEmpty else { return "해당 제목의 미리 알림을 찾지 못했습니다." }
        var removed = 0
        for reminder in candidates {
            do {
                try store.remove(reminder, commit: true)
                removed += 1
            } catch {
                throw ToolExecutionError.removeFailed("미리 알림 삭제 실패: \(error.localizedDescription)")
            }
        }
        return "미리 알림 삭제: \(title) \(removed)건"
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
                throw ToolExecutionError.calendarPermissionDenied
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
                throw ToolExecutionError.remindersPermissionDenied
            }
            return await EventKitBridge.reminders(includeCompleted: include)
        }
    }
}

/// 미리 알림 삭제 도구 (T-349): 권한+게이트 승인 필요. 제목 일치 항목 삭제.
struct DeleteReminderTool: Tool {
    static let name = "delete_reminder"
    static let description = "미리 알림(Reminders)을 삭제합니다. 제목으로 찾아 삭제합니다."

    @ToolParam(description: "삭제할 미리 알림 내용")
    var title = ""

    @ToolParam(description: "완료된 항목도 삭제 대상에 포함할지 (기본 false)")
    var includeCompleted = false

    func run() async throws -> Any {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            await ToolLedger.shared.record(toolName: Self.name, detail: title,
                                           result: "미리 알림 내용이 비어 있습니다.",
                                           denied: false, failed: true)
            return "미리 알림 내용이 비어 있습니다."
        }
        let include = includeCompleted
        let detail = "미리 알림 삭제: \(name)"
        return await LocalTools.runTolled(toolName: Self.name, detail: detail) {
            guard await EventKitBridge.requestReminders() else {
                DebugLogger.shared.error(code: "E-MAC-PERM-0016", feature: "시스템도구",
                                         "미리 알림 권한 거부")
                throw ToolExecutionError.remindersPermissionDenied
            }
            return try await EventKitBridge.deleteReminders(title: name, includeCompleted: include)
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
        guard !name.isEmpty else {
            await ToolLedger.shared.record(toolName: Self.name, detail: title,
                                           result: "미리 알림 내용이 비어 있습니다.",
                                           denied: false, failed: true)
            return "미리 알림 내용이 비어 있습니다."
        }
        let rawWhen = when
        guard let due = SystemToolDates.resolve(rawWhen) else {
            SystemToolDates.logFailure(rawWhen)
            let message = SystemToolDates.failureMessage(rawWhen)
            await ToolLedger.shared.record(toolName: Self.name, detail: rawWhen,
                                           result: message, denied: false, failed: true)
            return message
        }
        let note = notes
        let detail = "미리 알림 추가: \(name) · \(EventKitBridge.dayFormatter.string(from: due))"
        return await LocalTools.runTolled(toolName: Self.name, detail: detail) {
            guard await EventKitBridge.requestReminders() else {
                DebugLogger.shared.error(code: "E-MAC-PERM-0016", feature: "시스템도구",
                                         "미리 알림 권한 거부")
                throw ToolExecutionError.remindersPermissionDenied
            }
            return try EventKitBridge.addReminder(title: name, notes: note, due: due)
        }
    }
}

/// 캘린더 일정 삭제 도구 (T-349): 권한+게이트 승인 필요. 제목(·날짜)으로 삭제.
struct DeleteCalendarEventTool: Tool {
    static let name = "delete_calendar_event"
    static let description = "캘린더 일정을 삭제합니다. 제목으로 찾아 삭제하고, 날짜를 주면 그 날짜의 일정만 삭제합니다."

    @ToolParam(description: "삭제할 일정 제목")
    var title = ""

    @ToolParam(description: "시작 시각 (선택, 예: 내일 오후 3시). 주면 그 날짜의 일정만 삭제")
    var when: String?

    func run() async throws -> Any {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            await ToolLedger.shared.record(toolName: Self.name, detail: title,
                                           result: "일정 제목이 비어 있습니다.",
                                           denied: false, failed: true)
            return "일정 제목이 비어 있습니다."
        }
        let rawWhen = when ?? ""
        let day = rawWhen.isEmpty ? nil : SystemToolDates.resolve(rawWhen)
        if !rawWhen.isEmpty, day == nil {
            SystemToolDates.logFailure(rawWhen)
            let message = SystemToolDates.failureMessage(rawWhen)
            await ToolLedger.shared.record(toolName: Self.name, detail: rawWhen,
                                           result: message, denied: false, failed: true)
            return message
        }
        let detail = "일정 삭제: \(name)\(rawWhen.isEmpty ? "" : " · \(rawWhen)")"
        return await LocalTools.runTolled(toolName: Self.name, detail: detail) {
            guard await EventKitBridge.requestEvents() else {
                DebugLogger.shared.error(code: "E-MAC-PERM-0016", feature: "시스템도구",
                                         "캘린더 권한 거부")
                throw ToolExecutionError.calendarPermissionDenied
            }
            return try EventKitBridge.deleteEvents(title: name, date: day)
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
        guard !name.isEmpty else {
            await ToolLedger.shared.record(toolName: Self.name, detail: title,
                                           result: "일정 제목이 비어 있습니다.",
                                           denied: false, failed: true)
            return "일정 제목이 비어 있습니다."
        }
        let rawWhen = when
        guard let start = SystemToolDates.resolve(rawWhen) else {
            SystemToolDates.logFailure(rawWhen)
            let message = SystemToolDates.failureMessage(rawWhen)
            await ToolLedger.shared.record(toolName: Self.name, detail: rawWhen,
                                           result: message, denied: false, failed: true)
            return message
        }
        let minutes = min(max(durationMinutes, 5), 24 * 60)
        let note = notes
        let detail = "일정 추가: \(name) · \(EventKitBridge.dayFormatter.string(from: start))"
        return await LocalTools.runTolled(toolName: Self.name, detail: detail) {
            guard await EventKitBridge.requestEvents() else {
                DebugLogger.shared.error(code: "E-MAC-PERM-0016", feature: "시스템도구",
                                         "캘린더 권한 거부")
                throw ToolExecutionError.calendarPermissionDenied
            }
            return try EventKitBridge.addEvent(title: name, start: start,
                                               minutes: minutes, notes: note)
        }
    }
}
