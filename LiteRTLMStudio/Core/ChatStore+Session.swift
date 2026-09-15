import Foundation

 extension ChatStore {
    // MARK: - 세션/영속 (T-032)

    /// 현재 방 ID 저장 키 (T-136): 보기만 한 방도 복원되게 전환 때마다 기록.
    nonisolated static var currentIDKey: String { "currentSessionID" }

    /// 현재 방 ID 저장 (T-136, 테스트 가능: defaults 주입).
    nonisolated static func saveCurrentID(_ id: UUID?, to defaults: UserDefaults = .standard) {
        if let id {
            defaults.set(id.uuidString, forKey: currentIDKey)
        } else {
            defaults.removeObject(forKey: currentIDKey)
        }
    }

    /// 저장된 방 ID 조회 (T-136, 테스트 가능).
    nonisolated static func loadCurrentID(from defaults: UserDefaults = .standard) -> UUID? {
        guard let raw = defaults.string(forKey: currentIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    /// 드래프트 시작 (T-137): 방을 만들지 않고 빈 화면으로. 첫 전송 시 방 생성.
    /// 이미 드래프트면 무시.
    func startDraft() {
        guard currentSessionID != nil || !messages.isEmpty else { return }
        persistCurrent()
        currentSessionID = nil
        messages = []
        Self.saveCurrentID(nil)
        logger.info(feature: "채팅기록", "새 채팅 초안")
    }

    /// 전송용 방 확보 (T-137, 테스트 가능): 드래프트면 방 생성 후 ID 반환.
    @discardableResult
    func ensureSessionForSend() -> UUID? {
        if let id = currentSessionID,
           sessions.contains(where: { $0.id == id }) { return id }
        persistCurrent()
        let session = Session(title: "새 채팅")
        sessions.insert(session, at: 0)
        currentSessionID = session.id
        save()
        Self.saveCurrentID(session.id)
        logger.info(feature: "채팅기록", "첫 전송으로 방 생성 (총 \(sessions.count)개)")
        return session.id
    }

    /// 세션 전환 (스트리밍 중에는 호출 금지 — 호출 측에서 비활성화).
    func selectSession(_ id: UUID) {
        guard id != currentSessionID, !streaming else { return }
        persistCurrent()
        currentSessionID = id
        messages = transcripts()[id] ?? []
        Self.saveCurrentID(id)
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
                startDraft()
                return
            }
        }
        Self.saveCurrentID(currentSessionID)
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
     func touchSession() {
        guard let id = currentSessionID,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].updatedAt = Date()
    }

     func transcripts() -> [UUID: [Message]] {
        loadPayload()?.transcripts ?? [:]
    }

     func persistCurrent() {
        guard let id = currentSessionID else { return }
        var payload = loadPayload() ?? Payload(sessions: sessions, transcripts: [:])
        payload.sessions = sessions
        payload.transcripts[id] = messages
        persist(payload: payload)
    }

     func save() {
        persistCurrent()
    }

     /// 복원 대상 (순수, 테스트 가능, T-134): 최근 사용 세션 (생성순 선두 아님).
    nonisolated static func mostRecentSessionID(_ sessions: [Session]) -> UUID? {
        sessions.max(by: { $0.updatedAt < $1.updatedAt })?.id
    }

    func load() {
        guard let payload = loadPayload() else { return }
        sessions = payload.sessions
        // 저장된 방 우선, 없으면 최근 사용 (T-136/T-134).
        if let saved = Self.loadCurrentID(), sessions.contains(where: { $0.id == saved }) {
            currentSessionID = saved
            messages = payload.transcripts[saved] ?? []
        } else if let id = Self.mostRecentSessionID(sessions) {
            currentSessionID = id
            messages = payload.transcripts[id] ?? []
        }
    }

     func loadPayload() -> Payload? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

     func persist(payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
