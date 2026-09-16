import SwiftUI

/// 후속질문 제안 (순수, 테스트 가능, T-261): 응답 텍스트 기반 3~4개 로컬 휴리스틱.
/// LLM 추가 호출 없음 (토큰·지연 0). 영속하지 않고 표시 시점에 재계산.
enum FollowUpSuggest {
    /// 고정 템플릿 (짧은 응답·키워드 없음 폴백).
    nonisolated static var fallback: [String] {
        ["더 자세히 설명해줘", "예시 보여줘", "쉽게 요약해줘", "관련 주제 알려줘"]
    }

    /// 불용어 (키워드 추출 제외).
    nonisolated static var stopwords: Set<String> {
        ["이것", "그것", "저것", "여기", "거기", "저기", "이거", "그거", "저거",
         "것", "수", "등", "및", "또", "더", "매우", "정말", "아주",
         "이런", "그런", "저런", "대한", "통해", "위해", "경우", "때문",
         "있다", "없다", "되다", "하다", "이다", "무엇", "합니다", "입니다"]
    }

    /// 후속질문 3~4개 생성 (순수, T-261).
    nonisolated static func suggestFollowUps(for text: String, max count: Int = 4) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 100 else { return Array(fallback.prefix(count)) }
        let keys = keywords(from: trimmed, limit: 2)
        var out: [String] = []
        if let first = keys.first {
            out.append("\(first) 더 자세히 알려줘")
        }
        if keys.count > 1 {
            out.append("\(keys[1]) 예시 보여줘")
        } else {
            out.append("구체적인 예시 보여줘")
        }
        out.append("이 내용 요약해줘")
        out.append("다음에 뭘 물어보면 좋을까?")
        var seen = Set<String>()
        let clean = out.compactMap { line -> String? in
            let cut = String(line.prefix(30))
            guard !cut.isEmpty, seen.insert(cut).inserted else { return nil }
            return cut
        }
        if clean.count >= 3 { return Array(clean.prefix(count)) }
        return Array((clean + fallback).prefix(count))
    }

    /// 키워드 추출 (순수, T-261): 2자 이상·불용어 제외·빈도순 상위.
    nonisolated static func keywords(from text: String, limit: Int = 2) -> [String] {
        var freq: [String: Int] = [:]
        let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted
            .union(CharacterSet(charactersIn: " ")))
            .flatMap { $0.split(separator: " ").map(String.init) }
        for raw in tokens {
            let word = raw.trimmingCharacters(in: .punctuationCharacters)
            guard word.count >= 2, !stopwords.contains(word) else { continue }
            freq[word, default: 0] += 1
        }
        return freq.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            if $0.key.count != $1.key.count { return $0.key.count > $1.key.count }
            return $0.key < $1.key
        }.prefix(limit).map(\.key)
    }
}

/// 후속질문 칩 행 (T-261): 어시스턴트 버블 직하·우측 정렬, 클릭 즉시 전송.
struct FollowUpChipsView: View {
    let chips: [String]
    var disabled = false
    var onTap: (String) -> Void = { _ in }

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button { onTap(chip) } label: {
                        Text(chip)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("클릭하면 바로 전송")
                    .disabled(disabled)
                }
            }
        }
    }
}
