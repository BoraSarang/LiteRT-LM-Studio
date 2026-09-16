import Foundation

/// 한국어 상대 날짜 파서 (T-270, 순수·테스트 가능).
/// 모델 출력 절대 날짜는 불신, 상대 표현만 시스템 시계로 계산 (private-agent 교훈).
/// 과거 결과는 미래로 전진 (알람 의미론): 당일 시간 경과 → +1일, 당일 요일 경과 → +7일.
enum KoreanDateParser {
    /// 요일 (일~토).
    nonisolated static var weekdays: [String: Int] {
        ["일": 0, "월": 1, "화": 2, "수": 3, "목": 4, "금": 5, "토": 6]
    }

    /// 파싱 (순수): nil이면 E-MAC-VALID-0017.
    nonisolated static func parse(_ text: String, now: Date = Date(),
                                  calendar: Calendar = .current) -> Date? {
        let baseDay: Int
        let weekdayTarget: Int?
        if let w = weekdayOf(text) {
            weekdayTarget = w
            if text.contains("다음 주") || text.contains("다음주") {
                baseDay = daysToNextWeek(weekday: w, now: now, calendar: calendar)
            } else {
                baseDay = daysToWeekday(weekday: w, now: now, calendar: calendar)
            }
        } else if text.contains("주말") {
            weekdayTarget = 6
            baseDay = daysToWeekday(weekday: 6, now: now, calendar: calendar)
        } else {
            weekdayTarget = nil
            baseDay = dayOffset(text)
        }
        guard let time = timeOf(text) else { return nil }
        guard var date = calendar.date(byAdding: .day, value: baseDay, to: startOfDay(now, calendar: calendar)) else {
            return nil
        }
        date = calendar.date(bySettingHour: time.hour, minute: time.minute,
                             second: 0, of: date) ?? date
        if weekdayTarget != nil {
            // 당일 요일+경과 시간 → +7일 (요일 유지).
            if baseDay == 0, date <= now {
                date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
            }
        } else if !isExplicitFuture(text) {
            // 시간만·오늘 + 경과 → +1일.
            if date <= now {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
        }
        return date
    }

    /// 요일 추출 (순수): "월요일·월욜·월" 모두 인식.
    nonisolated static func weekdayOf(_ text: String) -> Int? {
        for (key, value) in weekdays where text.contains(key + "요일") || text.contains(key + "욜") {
            return value
        }
        // 단일 자는 "주" 맥락에서만 (오탐 방지: "다음 주 월").
        if text.contains("주") {
            for (key, value) in weekdays where text.contains("주 " + key) || text.contains("주" + key) {
                return value
            }
        }
        return nil
    }

    /// 상대 일수 (순수): 오늘·내일·모레·글피·N일 후·다음 달(30일).
    nonisolated static func dayOffset(_ text: String) -> Int {
        if text.contains("모레") { return 2 }
        if text.contains("글피") { return 3 }
        if text.contains("내일") { return 1 }
        if text.contains("다음 달") || text.contains("다음달") { return 30 }
        if let n = firstNumber(before: ["일 후", "일 뒤"], in: text) { return n }
        return 0
    }

    /// 명시 미래 여부 (순수): 롤포워드 제외 대상.
    nonisolated static func isExplicitFuture(_ text: String) -> Bool {
        text.contains("내일") || text.contains("모레") || text.contains("글피")
            || text.contains("다음 주") || text.contains("다음주") || text.contains("다음 달")
            || text.contains("다음달") || firstNumber(before: ["일 후", "일 뒤"], in: text) != nil
    }

    /// 시각 추출 (순수): 오전/오후·시·분/반·H:mm. 없으면 09:00.
    nonisolated static func timeOf(_ text: String) -> (hour: Int, minute: Int)? {
        if let match = firstMatch(#"(\d{1,2}):(\d{2})"#, in: text), match.count == 2,
           let h = Int(match[0]), let m = Int(match[1]), h < 24, m < 60 {
            return (h, m)
        }
        guard let match = firstMatch(#"(\d{1,2})\s*시"#, in: text),
              let raw = Int(match[0]), raw <= 23 else {
            return text.contains("시") ? nil : (9, 0)
        }
        var hour = raw
        let minute: Int
        if text.contains("반") { minute = 30 } else {
            minute = firstMatch(#"(\d{1,2})\s*분"#, in: text).flatMap { Int($0[0]) } ?? 0
        }
        guard minute < 60 else { return nil }
        let head = String(text.prefix(text.range(of: "\(raw)시")?.lowerBound ?? text.endIndex))
        if head.contains("오후") || head.contains("저녁") || head.contains("밤") {
            if hour < 12 { hour += 12 }
        } else if head.contains("오전") || head.contains("아침") || head.contains("새벽") {
            if hour == 12 { hour = 0 }
        }
        return (hour, minute)
    }

    /// 이번 주 해당 요일까지 일수 (순수): 당일 포함 0.
    nonisolated static func daysToWeekday(weekday: Int, now: Date,
                                          calendar: Calendar = .current) -> Int {
        let current = (calendar.component(.weekday, from: now) + 6) % 7 // 일=0
        return (weekday - current + 7) % 7
    }

    /// 다음 주 해당 요일까지 일수 (순수): 최소 7일.
    nonisolated static func daysToNextWeek(weekday: Int, now: Date,
                                           calendar: Calendar = .current) -> Int {
        let current = (calendar.component(.weekday, from: now) + 6) % 7 // 월=0
        let target = (weekday + 6) % 7
        return (target - current + 7) % 7 + 7
    }

    /// 키워드 앞 숫자 (순수).
    nonisolated static func firstNumber(before keywords: [String], in text: String) -> Int? {
        for key in keywords {
            guard let range = text.range(of: key) else { continue }
            let head = String(text[..<range.lowerBound])
            if let match = lastMatch(#"(\d+)"#, in: head), let n = Int(match[0]) {
                return n
            }
        }
        return nil
    }

    /// 자정 기준일 (순수).
    nonisolated static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 정규식 전체 캡처 (순수).
    nonisolated static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1 ..< m.numberOfRanges).compactMap { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) }
        }
    }

    /// 정규식 마지막 캡처 (순수).
    nonisolated static func lastMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let m = matches.last else { return nil }
        return (1 ..< m.numberOfRanges).compactMap { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) }
        }
    }
}
