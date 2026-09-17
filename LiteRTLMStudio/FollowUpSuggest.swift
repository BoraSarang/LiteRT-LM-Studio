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

    /// LLM 요청 프롬프트 (순수, 테스트 가능, T-291): 마지막 Q/A 1턴만.
    /// T-292 작업 축소: Q 1000자·A 800자 (prefill 단축).
    /// 후속 5초 단축: Q 600자·A 500자로 축소 (질문 3개 생성에 충분).
    nonisolated static func prompt(question: String, answer: String) -> String {
        let q = String(question.prefix(600))
        let a = String(answer.prefix(500))
        return """
        다음 대화를 읽고 사용자가 이어서 물을 만한 후속질문 3개를 각 25자 이내로 한 줄에 하나씩 써줘. \
        번호나 설명 없이 질문만.
        질문: \(q)
        답변: \(a)
        """
    }

    /// LLM 응답 파싱 (순수, 테스트 가능, T-291): 번호/불릿/따옴표/JSON 배열 수용,
    /// 빈 제거·중복 제거·30자 절단. 0건이면 빈 배열 (호출 측이 휴리스틱 폴백).
    nonisolated static func parseFollowUps(from text: String, max count: Int = 3) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return cleanFollowUps(arr, max: count)
        }
        let lines = trimmed.components(separatedBy: .newlines)
        let stripped = lines.map { stripFollowUpMarker($0) }
        return cleanFollowUps(stripped, max: count)
    }

    /// 행 머리 마커 제거 (순수, T-291): "1." "1)" "- " "* " "• " + 겹따옴표.
    nonisolated static func stripFollowUpMarker(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’「」"))
            .trimmingCharacters(in: .whitespaces)
        if let r = s.range(of: #"^\d+\s*[.\)\:\-、]\s*"#, options: .regularExpression) {
            s = String(s[r.upperBound...])
        } else if let r = s.range(of: #"^[-*•·▪▶–]\s+"#, options: .regularExpression) {
            s = String(s[r.upperBound...])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// 후속질문 정리 (순수, T-291): 빈 제거·중복 제거·30자 절단.
    nonisolated static func cleanFollowUps(_ lines: [String], max count: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in lines {
            let cut = String(line.prefix(30)).trimmingCharacters(in: .whitespaces)
            guard cut.count >= 2, seen.insert(cut).inserted else { continue }
            out.append(cut)
            if out.count >= count { break }
        }
        return out
    }

    /// 선행 결과 재호출 판정 (순수, 테스트 가능, T-292):
    /// 스냅샷 이후 답변이 300자 초과 또는 절반 초과로 자랐으면 재호출.
    nonisolated static func needsRefire(snapshot: Int, final: Int) -> Bool {
        final - snapshot > max(300, snapshot / 2)
    }

    /// T-292 후속 선행 조건 (순수, 테스트 가능): 서버 route만 스트리밍 중 300자 도달.
    /// 네이티브는 Engine 동시 추론 미검증이라 완료 후 호출 유지.
    nonisolated static func shouldPrefetch(route: EngineMode, streaming: Bool, role: String,
                                           isError: Bool, count: Int) -> Bool {
        route == .cli && streaming && role == "assistant" && !isError && count >= 300
    }

    /// 후속질문 질문문 (순수, 테스트 가능, T-291): 대상 응답 직전 마지막 사용자 발화.
    nonisolated static func questionBefore(messages: [ChatStore.Message], id: UUID) -> String {
        var q = ""
        for msg in messages {
            if msg.id == id { break }
            if msg.role == "user" { q = msg.text }
        }
        return q
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

    /// 후속질문 출력 상한: 3개×25자+번호 ≈ 50토큰이면 충분. 100→64로 디코드 시간 단축.
    nonisolated static var followUpMaxTokens: Int { 64 }

    /// 3개 완성 확인 (순수, 테스트 가능): 비어있지 않은 줄 3개+마지막 줄 8자 이상이면 중단.
    nonisolated static func hasEnoughQuestions(_ acc: String) -> Bool {
        let lines = acc.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !stripFollowUpMarker($0).isEmpty }
        guard nonEmpty.count >= 3 else { return false }
        return stripFollowUpMarker(lines.last ?? "").count >= 8
    }
}

/// 후속질문 LLM 상태 (T-291): 메시지별 lazy 1회 호출, 현재 채팅 경로 그대로.
/// 실패·파싱 0건은 조용히 휴리스틱 폴백 (호출 측이 chips 비어있음으로 판정).
@MainActor
final class FollowUpStore: ObservableObject {
    @Published private(set) var messageID: UUID?
    @Published private(set) var loading = false
    @Published private(set) var chips: [String] = []
    private var snapshotLen: Int?
    private var task: Task<Void, Never>?
    private let logger = DebugLogger.shared

    /// 요청 1회 (중복 가드): 같은 방 ID면 재요청 안 함. 선행·완료 공용.
    func request(messageID: UUID, question: String, answer: String, chat: ChatStore) {
        if self.messageID == messageID && (loading || !chips.isEmpty) { return }
        cancel()
        self.messageID = messageID
        chips = []
        snapshotLen = answer.count
        loading = true
        let prompt = FollowUpSuggest.prompt(question: question, answer: answer)
        let started = Date()
        let kind = chat.streaming ? "선행 요청" : "LLM 요청"
        logger.info(feature: "후속질문", "\(kind) (\(chat.route.title))")
        task = Task { [weak self] in
            let result: String?
            if chat.route == .native, let engine = chat.inferenceEngine {
                result = await Self.fetchNative(engine: engine, modelID: chat.model,
                                                prompt: prompt)
            } else {
                result = await Self.fetchServer(baseURL: chat.baseURL, model: chat.model,
                                                prompt: prompt)
            }
            guard let self, !Task.isCancelled, self.messageID == messageID else { return }
            let elapsed = Date().timeIntervalSince(started)
            let parsed = result.map { FollowUpSuggest.parseFollowUps(from: $0) } ?? []
            self.loading = false
            if parsed.isEmpty {
                self.logger.info(feature: "후속질문",
                                 "실패·휴리스틱 폴백 (\(String(format: "%.1f", elapsed))s)")
            } else {
                self.chips = parsed
                self.logger.info(feature: "후속질문",
                                 "완료 \(parsed.count)개 (\(String(format: "%.1f", elapsed))s)")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        loading = false
    }

    /// 완료 시점 확정 (T-292): 선행 결과가 드리프트 없으면 유지, 자랐으면 재호출.
    /// 선행 진행 중인데 이미 드리프트면 취소 후 새로 호출. 선행 실패분은 자연 재시도.
    func finalize(messageID: UUID, question: String, answer: String, chat: ChatStore) {
        if self.messageID == messageID, let snap = snapshotLen {
            if loading {
                if FollowUpSuggest.needsRefire(snapshot: snap, final: answer.count) {
                    logger.info(feature: "후속질문", "선행 취소·재호출 (드리프트)")
                    cancel()
                    chips = []
                    request(messageID: messageID, question: question,
                            answer: answer, chat: chat)
                }
                return
            }
            if !chips.isEmpty {
                if !FollowUpSuggest.needsRefire(snapshot: snap, final: answer.count) {
                    logger.info(feature: "후속질문", "선행 유지 (드리프트 없음)")
                    return
                }
                logger.info(feature: "후속질문", "재호출 (드리프트)")
                chips = []
            }
        }
        request(messageID: messageID, question: question, answer: answer, chat: chat)
    }

    /// 서버 1회성 비스트림 호출 (T-291): tools·extras 제외, 마지막 Q/A만.
    static func fetchServer(baseURL: URL, model: String, prompt: String) async -> String? {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system",
                 "content": "너는 이어질 질문을 제안하는 도우미다. 후속질문만 출력한다."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7, "max_tokens": 100, "stream": false
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { return nil }
        return content
    }

    /// 앱 내 엔진 1회성 호출 (T-291): 본 대화와 분리된 1회성 대화로 생성.
    /// 후속 프롬프트("질문 3개만")를 메인 대화에서 돌리면 지시·짧은 목록이
    /// 본 대화 KV에 박혀 이후 답변이 목록처럼 짧아지는 오염 발생 → 격리 필수.
    /// 고유 sessionID로 풀에 잠시 두었다가 사용 후 즉시 제거한다.
    static func fetchNative(engine: any InferenceEngine, modelID: String,
                            prompt: String) async -> String? {
        do {
            try await engine.prepare(modelID: modelID)
        } catch { return nil }
        let opts = GenerationOptions(temperature: 0.7, maxTokens: FollowUpSuggest.followUpMaxTokens)
        let sid = "후속질문-\(UUID().uuidString)"
        defer {
            if let native = engine as? NativeEngine {
                let key = ConvKey(modelID: modelID, sessionID: sid, options: opts)
                native.conversations[key] = nil
                native.conversationAccessOrder.removeAll { $0 == key }
            }
        }
        let stream = engine.stream(prompt: prompt, image: nil, history: [],
                                   options: opts, sessionID: sid)
        var acc = ""
        do {
            for try await chunk in stream {
                if Task.isCancelled { engine.cancel(); return nil }
                acc += chunk
                if FollowUpSuggest.hasEnoughQuestions(acc) { break }
            }
        } catch { return nil }
        return acc.isEmpty ? nil : acc
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

/// 후속질문 로딩 자리 (T-291): 칩과 동일 배치의 회색 스켈레톤 3개 (폭 점프 방지).
struct FollowUpSkeletonView: View {
    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 140, height: 28)
                }
            }
        }
        .accessibilityLabel("후속 질문 생성 중")
    }
}
