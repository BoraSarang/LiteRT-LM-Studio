import Foundation

/// 채팅 검색 결과 1건 (T-263): 방+메시지 위치+미리보기.
struct ChatSearchHit: Identifiable, Hashable, Sendable {
    var id: String { "\(sessionID.uuidString)-\(messageID.uuidString)" }
    let sessionID: UUID
    let sessionTitle: String
    let messageID: UUID
    let role: String
    let preview: String
    let matchedAt: Date
}

/// 한글 자소 매칭 (T-264, 순수·테스트 가능): 초성·혼용·띄어쓰기 무시.
/// 외부 라이브러리 없음 (유니코드 분해 직접 구현, 오프라인 안전).
enum KoreanMatch {
    /// 19초성표 (U+3131 ㄱ ~ U+314E ㅎ 순서).
    nonisolated static var choseongTable: [Character] {
        ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ",
         "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    }

    /// 한 글자의 초성 (순수): 완성형 음절은 분해, 호환 자모 초성은 그대로, 그 외 nil.
    nonisolated static func choseong(of ch: Character) -> Character? {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return nil }
        let v = scalar.value
        if v >= 0xAC00, v <= 0xD7A3 {
            return choseongTable[Int((v - 0xAC00) / (21 * 28))]
        }
        if choseongTable.contains(ch) { return ch }
        return nil
    }

    /// 질의가 초성 자모인지 (순수).
    nonisolated static func isChoseong(_ ch: Character) -> Bool {
        choseongTable.contains(ch)
    }

    /// 자소 단위 동등 (순수): 질의 자가 초성이면 텍스트 음절 초성과 비교,
    /// 완성형이면 소문자 동등 비교.
    nonisolated static func charsEqual(textCh: Character, queryCh: Character) -> Bool {
        if isChoseong(queryCh) {
            return choseong(of: textCh) == queryCh
        }
        return String(textCh).lowercased() == String(queryCh).lowercased()
    }

    /// 매칭 여부 (순수): 정규 contains → 공백 제거 contains → 슬라이딩 자소 비교.
    nonisolated static func matches(text: String, query: String) -> Bool {
        let lower = text.lowercased()
        let q = query.lowercased()
        if lower.range(of: q) != nil { return true }
        let flat = lower.filter { !$0.isWhitespace }
        let flatQ = q.filter { !$0.isWhitespace }
        if !flatQ.isEmpty, flat.contains(flatQ) { return true }
        return choseongWindow(in: text, query: query) != nil
    }

    /// 매칭 범위 (순수): 미리보기 중심용, 없으면 nil.
    nonisolated static func matchRange(in text: String, query: String) -> Range<String.Index>? {
        let lower = text.lowercased()
        let q = query.lowercased()
        if let range = lower.range(of: q) {
            return range
        }
        return choseongWindow(in: text, query: query)
    }

    /// 초성 슬라이딩 윈도우 (순수): 질의 길이만큼 창을 밀며 자소 비교.
    nonisolated static func choseongWindow(in text: String, query: String) -> Range<String.Index>? {
        let tChars = Array(text)
        let qChars = Array(query)
        guard !qChars.isEmpty, tChars.count >= qChars.count else { return nil }
        // 초성 1개라도 없으면 초성 경로 제외 (일반 contains는 위에서 처리).
        guard qChars.contains(where: isChoseong) else { return nil }
        for start in 0 ... (tChars.count - qChars.count) {
            var ok = true
            for offset in qChars.indices where ok {
                ok = charsEqual(textCh: tChars[start + offset], queryCh: qChars[offset])
            }
            if ok {
                let lo = text.index(text.startIndex, offsetBy: start)
                let hi = text.index(lo, offsetBy: qChars.count)
                return lo ..< hi
            }
        }
        return nil
    }
}

/// 전체 세션 채팅 검색 (T-263, 순수·테스트 가능).
/// T-264: 매칭 판정은 KoreanMatch (초성·혼용·띄어쓰기 무시).
enum ChatSearch {
    nonisolated static var maxHits: Int { 8 }
    nonisolated static var minLength: Int { 2 }
    nonisolated static var context: Int { 20 }

    /// 질의 포함 메시지 검색 (대소문자 무시, 2자 미만 빈 배열, 방 최신순).
    nonisolated static func search(
        query: String,
        sessions: [ChatStore.Session],
        transcripts: [UUID: [ChatStore.Message]]
    ) -> [ChatSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= minLength else { return [] }
        var hits: [ChatSearchHit] = []
        let ordered = ChatStore.sortedSessions(sessions, by: .recent)
        for session in ordered {
            guard let msgs = transcripts[session.id] else { continue }
            for msg in msgs where KoreanMatch.matches(text: msg.text, query: q) {
                hits.append(ChatSearchHit(
                    sessionID: session.id,
                    sessionTitle: session.displayTitle,
                    messageID: msg.id,
                    role: msg.role,
                    preview: Self.contextPreview(msg.text, query: q),
                    matchedAt: session.updatedAt
                ))
                if hits.count >= maxHits { return hits }
            }
        }
        return hits
    }

    /// 매칭 문맥 미리보기 (순수): 일치 위치 앞뒤 20자, 앞뒤 잘림은 … 표기.
    /// T-264: 초성·공백 무시 매칭 범위도 중심으로 사용.
    nonisolated static func contextPreview(_ text: String, query: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = KoreanMatch.matchRange(in: flat, query: query) else {
            return String(flat.prefix(60))
        }
        let lo = flat.index(range.lowerBound, offsetBy: -context, limitedBy: flat.startIndex)
            ?? flat.startIndex
        let hi = flat.index(range.upperBound, offsetBy: context, limitedBy: flat.endIndex)
            ?? flat.endIndex
        var out = String(flat[lo ..< hi]).trimmingCharacters(in: .whitespaces)
        if lo > flat.startIndex { out = "…" + out }
        if hi < flat.endIndex { out += "…" }
        return out
    }
}
