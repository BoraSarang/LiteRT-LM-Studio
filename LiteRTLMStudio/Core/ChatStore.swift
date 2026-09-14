import Foundation

/// OpenAI 호환 /v1/chat/completions 스트리밍 채팅 (PLAN_v3 T-032 세션/영속).
@MainActor
final class ChatStore: ObservableObject {
    struct Message: Identifiable, Codable {
        var id = UUID()
        let role: String
        var text: String
        var perf: String?
        var isError = false
    }

    struct Session: Identifiable, Codable {
        var id = UUID()
        var title: String
        var updatedAt = Date()
        var createdAt = Date() // T-058 생성일 정렬용
        var pinned = false // T-058 고정
        var customTitle: String? // T-058 이름 변경 (nil=자동)

        /// 표시 제목: 사용자 지정 우선 (T-058).
        var displayTitle: String {
            if let c = customTitle,
               !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c }
            return title
        }

        enum CodingKeys: String, CodingKey {
            case id, title, updatedAt, createdAt, pinned, customTitle
        }

        init(id: UUID = UUID(), title: String, updatedAt: Date = Date(),
             createdAt: Date = Date(), pinned: Bool = false, customTitle: String? = nil) {
            self.id = id
            self.title = title
            self.updatedAt = updatedAt
            self.createdAt = createdAt
            self.pinned = pinned
            self.customTitle = customTitle
        }

        /// 구 JSON 호환 디코딩 (T-058): 신필드 없으면 기본값.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
            createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? updatedAt
            pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
            customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
        }
    }

    /// 채팅 정렬 (T-058): 설정 저장 키 "sessionSort".
    enum SessionSort: String, CaseIterable {
        case recent, name, created

        var title: String {
            switch self {
            case .recent: "최근 순"
            case .name: "이름 순"
            case .created: "생성 순"
            }
        }
    }

    /// 정렬 표시 목록 (순수, 테스트 가능, T-058): 고정 우선, 동률은 최근.
    nonisolated static func sortedSessions(_ sessions: [Session], by order: SessionSort) -> [Session] {
        sessions.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            switch order {
            case .recent: return a.updatedAt > b.updatedAt
            case .name:
                return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
            case .created: return a.createdAt > b.createdAt
            }
        }
    }

    struct Payload: Codable {
        var sessions: [Session]
        var transcripts: [UUID: [Message]]
    }

    @Published var sessions: [Session] = []
    @Published var currentSessionID: UUID?
    @Published var messages: [Message] = []
    @Published var streaming = false
    @Published var preparing = false // 첫 토큰 전 엔진 준비 상태
    @Published var lastError: String?

    var baseURL = URL(string: "http://127.0.0.1:9379")!
    var model = "gemma4-12b"
    var temperature = 0.7

    private var currentTask: Task<Void, Never>?
    private let logger = DebugLogger.shared
    private let storageURL: URL

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let (url, migrated) = Self.resolvedStorageURL()
            self.storageURL = url
            if migrated {
                logger.info(feature: "채팅기록", "구 기록 이사 완료")
            }
        }
        load()
        if sessions.isEmpty { newSession() }
        logger.info(feature: "채팅기록", "채팅 \(sessions.count)개 복원")
    }

    /// 저장 경로 확정 (T-060): 신 디렉터리 + 구 기록 1회 이사.
    nonisolated static func resolvedStorageURL() -> (URL, Bool) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let next = base.appendingPathComponent("LiteRTLMStudio", isDirectory: true)
        let prev = base.appendingPathComponent("LiteRTLM-Manager", isDirectory: true)
        try? FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        let dst = next.appendingPathComponent("chat-history.json")
        let src = prev.appendingPathComponent("chat-history.json")
        var migrated = false
        if !FileManager.default.fileExists(atPath: dst.path),
           FileManager.default.fileExists(atPath: src.path) {
            try? FileManager.default.moveItem(at: src, to: dst)
            migrated = FileManager.default.fileExists(atPath: dst.path)
        }
        return (dst, migrated)
    }

    func send(_ prompt: String, image: (data: Data, mime: String)? = nil) {
        logger.info(feature: "채팅전송", "model=\(model) len=\(prompt.count) image=\(image != nil)")
        messages.append(Message(role: "user", text: prompt))
        messages.append(Message(role: "assistant", text: ""))
        refreshTitle()
        touchSession()
        save()
        streaming = true
        preparing = true
        let idx = messages.count - 1
        let started = Date()
        var firstTokenAt: Date?
        currentTask = Task {
            do {
                var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
                req.httpMethod = "POST"
                req.timeoutInterval = 300 // Vision 추론은 수 분 가능
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let history = messages.dropLast(2).map { ["role": $0.role, "content": $0.text] }
                let userContent: Any
                if let image {
                    let b64 = image.data.base64EncodedString()
                    userContent = [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:\(image.mime);base64,\(b64)"]],
                    ]
                } else {
                    userContent = prompt
                }
                let historyPlus = history + [["role": "user", "content": userContent]]
                req.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": model, "messages": historyPlus,
                    "temperature": temperature, "stream": true,
                ])
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                var acc = ""
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String
                    else { continue }
                    if firstTokenAt == nil {
                        firstTokenAt = Date()
                        preparing = false
                        let ttft = firstTokenAt!.timeIntervalSince(started)
                        logger.perf(feature: "채팅전송", "첫 토큰 TTFT=\(String(format: "%.1f", ttft))s")
                    }
                    acc += content
                    messages[idx].text = acc
                }
                let elapsed = Date().timeIntervalSince(started)
                let est = acc.count / max(1, Int(elapsed * 4))
                messages[idx].perf = String(format: "%.1fs · 약 %d tok/s", elapsed, est)
                logger.perf(feature: "채팅전송", "완료 elapsed=\(String(format: "%.1f", elapsed))s chars=\(acc.count)")
            } catch is CancellationError {
                logger.info(feature: "채팅중단", "사용자 중단")
            } catch {
                lastError = "E-MAC-NET-0005"
                messages[idx].text = "요청 실패: 서버 상태를 확인해 주세요. (E-MAC-NET-0005)"
                messages[idx].isError = true
                logger.error(code: "E-MAC-NET-0005", feature: "채팅전송", "\(error)")
            }
            preparing = false
            streaming = false
            save()
        }
    }

    func stop() {
        currentTask?.cancel()
        preparing = false
        streaming = false
    }

    /// 마지막 사용자 프롬프트 (순수 조회, 재시도용).
    func lastUserPrompt() -> String? {
        messages.last(where: { $0.role == "user" })?.text
    }

    /// 마지막 요청 재시도: 꼬리(user+assistant) 제거 후 마지막 프롬프트 재전송 (중복 표시 없음).
    func retry() {
        guard !streaming else { return }
        logger.info(feature: "채팅재시도", "마지막 프롬프트 재전송")
        if messages.last?.role == "assistant" { messages.removeLast() }
        guard messages.last?.role == "user", let prompt = messages.last?.text else { return }
        messages.removeLast()
        send(prompt)
    }

    func clear() { newSession() }

    // MARK: - 세션/영속 (T-032)

    /// 현재 버퍼를 보관하고 새 세션 시작.
    func newSession() {
        persistCurrent()
        let session = Session(title: "새 채팅")
        sessions.insert(session, at: 0)
        currentSessionID = session.id
        messages = []
        save()
        logger.info(feature: "채팅기록", "새 채팅 (총 \(sessions.count)개)")
    }

    /// 세션 전환 (스트리밍 중에는 호출 금지 — 호출 측에서 비활성화).
    func selectSession(_ id: UUID) {
        guard id != currentSessionID, !streaming else { return }
        persistCurrent()
        currentSessionID = id
        messages = transcripts()[id] ?? []
        logger.info(feature: "채팅기록", "채팅 전환")
    }

    /// 고정 토글 (T-058).
    func togglePin(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].pinned.toggle()
        save()
        logger.info(feature: "채팅기록", sessions[idx].pinned ? "고정" : "고정 해제")
    }

    /// 이름 변경 (T-058): 빈 값은 자동 제목으로 복귀.
    func renameSession(_ id: UUID, title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[idx].customTitle = t.isEmpty ? nil : t
        sessions[idx].updatedAt = Date()
        save()
        logger.info(feature: "채팅기록", "이름 변경")
    }

    /// 세션 삭제. 현재 세션을 지우면 최신 세션으로 이동 (없으면 새로 생성).
    func deleteSession(_ id: UUID) {
        var payload = loadPayload() ?? Payload(sessions: [], transcripts: [:])
        payload.sessions.removeAll { $0.id == id }
        payload.transcripts.removeValue(forKey: id)
        sessions = payload.sessions
        if currentSessionID == id {
            if let next = sessions.first {
                currentSessionID = next.id
                messages = payload.transcripts[next.id] ?? []
            } else {
                persist(payload: payload)
                newSession()
                return
            }
        }
        persist(payload: payload)
        logger.info(feature: "채팅기록", "채팅 삭제 (잔여 \(sessions.count)개)")
    }

    /// 첫 사용자 메시지로 무제 세션 제목 자동 지정 (순수 조회+적용, 테스트 가능).
    /// 사용자 지정 이름이 있으면 손대지 않음 (T-058).
    func refreshTitle() {
        guard let id = currentSessionID,
              let idx = sessions.firstIndex(where: { $0.id == id }),
              sessions[idx].title == "새 채팅",
              sessions[idx].customTitle == nil,
              let first = messages.first(where: { $0.role == "user" }) else { return }
        sessions[idx].title = String(first.text.prefix(20))
        sessions[idx].updatedAt = Date()
    }

    /// 활동 시각 갱신 (T-058, 최근순 정렬용).
    private func touchSession() {
        guard let id = currentSessionID,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].updatedAt = Date()
    }

    private func transcripts() -> [UUID: [Message]] {
        loadPayload()?.transcripts ?? [:]
    }

    private func persistCurrent() {
        guard let id = currentSessionID else { return }
        var payload = loadPayload() ?? Payload(sessions: sessions, transcripts: [:])
        payload.sessions = sessions
        payload.transcripts[id] = messages
        persist(payload: payload)
    }

    private func save() {
        persistCurrent()
    }

    private func load() {
        guard let payload = loadPayload() else { return }
        sessions = payload.sessions
        if let first = sessions.first {
            currentSessionID = first.id
            messages = payload.transcripts[first.id] ?? []
        }
    }

    private func loadPayload() -> Payload? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private func persist(payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
