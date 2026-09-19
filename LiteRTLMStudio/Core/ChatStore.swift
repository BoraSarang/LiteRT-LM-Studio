import Foundation

/// 세션 코딩 키 (T-289: 타입 중첩 깊이 해소 — `Session` 밖 파일 스코프).
private enum SessionCodingKeys: String, CodingKey {
    case id, title, updatedAt, createdAt, pinned, customTitle
}

/// OpenAI 호환 /v1/chat/completions 스트리밍 채팅 (PLAN_v3 T-032 세션/영속).
@MainActor
final class ChatStore: ObservableObject {
    /// 첨부 이미지 (T-127): Vision 전송용. (data, mime) 튜플 대신 명명 타입.
    struct ChatImage {
        let data: Data
        let mime: String
    }

    struct Message: Identifiable, Codable {
        var id = UUID()
        let role: String
        var text: String
        var perf: String?
        var isError = false
        var finishedAt: Date? // T-077 응답 완료 시각 (nil=완료 전·구 기록)
        var thinking: String? // T-266 생각 과정 (nil=없음·구 기록)
        var toolCalls: [ToolCallRecord]? // T-266 도구 호출 (nil=없음·구 기록)
        var startedAt: Date? // T-345 전송 시작 시각 (대기 경과 표시용, 구 기록 nil)
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
            let c = try decoder.container(keyedBy: SessionCodingKeys.self)
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
            case .recent: L(L10n.Session.sortRecent)
            case .name: L(L10n.Session.sortName)
            case .created: L(L10n.Session.sortCreated)
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
    @Published var currentSessionID: UUID? {
        // T-302 첫터치 프리필: 방 전환·복구·생성 시점에 엔진 준비를 미리 진행.
        // 방 KV 프리필은 전송 옵션 확정 후라 제외 — prepare 선행만으로 init 구간 제거.
        didSet { warmupForNextSend() }
    }
    @Published var messages: [Message] = []
    @Published var streaming = false
    @Published var preparing = false // 첫 토큰 전 엔진 준비 상태
    @Published var lastError: String?
    /// 첫터치 프리필 토글 (T-302, 기본 OFF): UserDefaults "prefillWarmup".
    @Published var prefillWarmupEnabled: Bool {
        didSet { warmupDefaults.set(prefillWarmupEnabled, forKey: Self.prefillWarmupKey) }
    }
    private var warmupDefaults: UserDefaults = .standard
    /// T-302 예열 진행 Task (동일 모듈 확장 파일에서 접근 — internal 유지).
    var warmupTask: Task<Void, Never>?

    var baseURL = URL(string: "http://127.0.0.1:9379")!
    /// 선택 모델 ID (T-340): 하드코딩 기본값 제거 — AppServices가 저장된 선택값으로 시드한다.
    /// 옛 기본값 `gemma4-12b`가 남아 실행 시 없는 모델을 초기화하던 결함 차단.
    var model = ""
    var temperature = 1.0 // T-176 모델 내장·Gallery 대조 (기존 0.7)
    var topK = 64 // T-176 describe 실측
    var topP = 0.95 // T-176 describe 실측
    var maxTokens: Int? // T-176 nil=무제한
    var seed: Int? // T-176 nil=랜덤
    var systemPrompt = "" // T-176 앱 내 엔진만 유효
    var thinkingEnabled = false // T-176 지원 모델만 UI 활성
    var thinkingBudget = -1 // T-176 -1=무제한
    /// 전송 경로 (T-186): 입력창 피커가 소유. 초기값은 기존 전역 설정 1회 승계.
    /// 변경 시 routeDefaults에도 저장해 재실행 후 초기값으로 쓴다.
    /// T-275: 저장소 주입 — 단위 테스트가 실 UserDefaults를 덮지 않게 분리.
    var routeDefaults: UserDefaults = .standard
    @Published var route: EngineMode = .cli {
        didSet { routeDefaults.set(route.rawValue, forKey: "engineMode") }
    }
    /// 앱 내 엔진 준비 여부 (T-186): 엔진 주입+모델 초기화 완료.
    var nativePrepared: Bool { inferenceEngine?.preparedModelID != nil }
    /// 앱 내 엔진 엔진 주입 (T-130, nil이면 CLI 전용). ContentView가 AppServices에서 연결.
    var inferenceEngine: (any InferenceEngine)?

    var currentTask: Task<Void, Never>? // T-344: 서버 워치독이 스톨 시 취소 (Stream 확장 접근)
    /// 스톨 자동 복구 주입 (T-345, AppServices): 앱 소유 데몬 재시작, 성공 시 true.
    var restartDaemon: (() async -> Bool)?
    let logger = DebugLogger.shared
    let storageURL: URL

    init(storageURL: URL? = nil, routeDefaults: UserDefaults = .standard) {
        self.routeDefaults = routeDefaults
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let (url, migrated) = Self.resolvedStorageURL()
            self.storageURL = url
            if migrated {
                logger.info(feature: "채팅기록", "구 기록 이사 완료")
            }
        }
        // T-302: 토글 저장소는 routeDefaults와 동일 주입 (테스트 분리), @AppStorage와 .standard 공유.
        warmupDefaults = routeDefaults
        prefillWarmupEnabled = routeDefaults.bool(forKey: Self.prefillWarmupKey)
        route = EngineMode(rawValue: routeDefaults.string(forKey: "engineMode") ?? "") ?? .cli
        load()
        if sessions.isEmpty { startDraft() }
        logger.info(feature: "채팅기록", "채팅 \(sessions.count)개 복원")
    }

    /// 저장 경로 확정 (T-060 구 번들 이사 + T-314 신 홈 통합).
    nonisolated static func resolvedStorageURL() -> (URL, Bool) {
        let dst = StudioPaths.chatHistoryURL
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let appSupport = base.appendingPathComponent("LiteRTLMStudio/chat-history.json")
        let legacyManager = base.appendingPathComponent("LiteRTLM-Manager/chat-history.json")
        // T-060: 구 번들(LiteRTLM-Manager) → App Support 1회 이사.
        if !FileManager.default.fileExists(atPath: appSupport.path),
           FileManager.default.fileExists(atPath: legacyManager.path) {
            try? FileManager.default.createDirectory(at: appSupport.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: legacyManager, to: appSupport)
        }
        // T-314: 마이그레이터 미실행·실패 대비 폴백 (구 경로 → 신 홈 복사, 원본 유지).
        var migrated = false
        if !FileManager.default.fileExists(atPath: dst.path) {
            let src = FileManager.default.fileExists(atPath: appSupport.path) ? appSupport : legacyManager
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.copyItem(at: src, to: dst)
                migrated = FileManager.default.fileExists(atPath: dst.path)
            }
        }
        return (dst, migrated)
    }

    func send(_ prompt: String, image: ChatImage? = nil) {
        logger.info(feature: "채팅전송", "model=\(model) len=\(prompt.count) image=\(image != nil)")
        guard ensureSessionForSend() != nil else { return }
        messages.append(Message(role: "user", text: prompt))
        messages.append(Message(role: "assistant", text: ""))
        refreshTitle()
        touchSession()
        save()
        streaming = true
        preparing = true
        let idx = messages.count - 1
        let started = Date()
        messages[idx].startedAt = started // T-345: 대기 경과 표시 기준
        if startNativeIfNeeded(prompt: prompt, image: image, idx: idx, started: started) { return }
        currentTask = Task {
            await self.runServerSend(prompt: prompt, image: image, idx: idx, started: started)
        }
    }

    /// SSE 한 줄 적용·누적 상태는 ChatStore+Stream 분리 (T-266, 본문 길이 관리).

    /// 앱 내 엔진 분기 시도 (T-137): 해당하면 작업 예약 후 true.
    /// T-185부터 미준비면 자동 초기화 대신 안내하고 true (CLI 폴백 없음, 수동 실행).
    @discardableResult
    func startNativeIfNeeded(prompt: String, image: ChatImage?, idx: Int, started: Date) -> Bool {
        guard usesNative(), let engine = inferenceEngine else { return false }
        guard engine.preparedModelID != nil else {
            noticeNativeNotReady(at: idx)
            return true
        }
        currentTask = Task { await self.runNative(engine: engine, prompt: prompt,
                                                  image: image, idx: idx, started: started) }
        return true
    }

    /// 앱 내 엔진 미준비 안내 (T-185): 전송 소비, 에러코드 없음 (실패 아님).
    func noticeNativeNotReady(at idx: Int) {
        messages[idx].text = "앱 내 엔진이 준비되지 않았습니다. "
            + "사이드바 엔진 행의 실행 버튼을 눌러 준비한 뒤 다시 전송해 주세요."
        messages[idx].isError = true
        messages[idx].finishedAt = Date()
        preparing = false
        streaming = false
        logger.info(feature: "채팅전송", "앱 내 엔진 미준비 — 전송 차단")
        save()
    }

    /// 서버 무응답 타임아웃 반영 (T-344 분리): 60초 무수신 시 스톨 확정.
    func requestTimedOut(at idx: Int) {
        lastError = "E-MAC-NET-0006"
        messages[idx].text = "서버 응답이 60초간 없어 중단했습니다. "
            + "데몬 상태를 확인한 뒤 다시 시도해 주세요. (E-MAC-NET-0006)"
        messages[idx].isError = true
        messages[idx].finishedAt = Date()
        logger.error(code: "E-MAC-NET-0006", feature: "채팅전송", "서버 스톨 타임아웃")
    }

    /// 요청 실패 반영 (T-127 분리): 에러 버블+시각+로그.
    func requestFailed(at idx: Int, error: Error) {
        lastError = "E-MAC-NET-0005"
        messages[idx].text = "요청 실패: 서버 상태를 확인해 주세요. (E-MAC-NET-0005)"
        messages[idx].isError = true
        messages[idx].finishedAt = Date() // T-077 실패 시각도 기록
        logger.error(code: "E-MAC-NET-0005", feature: "채팅전송", "\(error)")
    }

    /// PERF 뱃지 문구 (순수, 테스트 가능, T-126): "12.3s · 약 15 토큰/초".
    nonisolated static func perfLine(chars: Int, elapsed: TimeInterval) -> String {
        let est = chars / max(1, Int(elapsed * 4))
        return String(format: "%.1fs · 약 %d 토큰/초", elapsed, est)
    }

    /// 스트리밍 화면 갱신 판정 (순수, 테스트 가능, T-148): 0.1초 간격으로 묶음 처리.
    /// 토큰마다 @Published를 쏘면 본문 전체가 다시 계산되어 CPU를 먹으므로 묶음 갱신.
    nonisolated static func shouldFlushText(now: Date, lastFlush: Date,
                                            interval: TimeInterval = 0.1) -> Bool {
        now.timeIntervalSince(lastFlush) >= interval
    }

    /// 전송 히스토리 윈도우 (순수, 테스트 가능, T-149): turns<=0이면 전량(기존 동작).
    nonisolated static func windowedHistory(_ messages: [Message], turns: Int) -> [Message] {
        guard turns > 0 else { return messages }
        return Array(messages.suffix(2 * turns))
    }

    func stop() {
        currentTask?.cancel()
        inferenceEngine?.cancel()
        preparing = false
        streaming = false
    }

    /// 마지막 사용자 프롬프트 (순수 조회, 재시도용).
    func lastUserPrompt() -> String? {
        messages.last(where: { $0.role == "user" })?.text
    }

    /// 앱 내 엔진 방 KV 제거 (T-301): 기록이 잘리는 경로(재시도·재작성)에서
    /// 남은 Conversation을 버려 잘린 기록이 재생성을 오염시키는 것을 방지.
    /// CLI는 매 요청이 전체 기록 재전송이라 불필요.
    func evictNativeSession() {
        guard usesNative() else { return }
        inferenceEngine?.evictSession(modelID: model, sessionID: currentSessionID?.uuidString ?? "")
    }

    /// 마지막 요청 재시도: 꼬리(user+assistant) 제거 후 마지막 프롬프트 재전송 (중복 표시 없음).
    func retry() {
        guard !streaming else { return }
        logger.info(feature: "채팅재시도", "마지막 프롬프트 재전송")
        if messages.last?.role == "assistant" { messages.removeLast() }
        guard messages.last?.role == "user", let prompt = messages.last?.text else { return }
        messages.removeLast()
        evictNativeSession()
        send(prompt)
    }

    func clear() { startDraft() }

}

/// SSE 한 줄 파서 (T-119, 순수): `send` 스트리밍 루프와 동일 판정. Codable 구조체 기반.
enum ChatSSEParser {
    /// 종료 마커 (`data: [DONE]`, 앞뒤 공백 허용).
    nonisolated static func isDone(_ line: String) -> Bool {
        guard line.hasPrefix("data:") else { return false }
        return line.dropFirst(5).trimmingCharacters(in: .whitespaces) == "[DONE]"
    }

    /// 델타 텍스트 추출. 비SSE 줄·종료 마커·파싱 실패는 nil (호출 측에서 종료 판정 후 건너뜀).
    nonisolated static func content(from line: String) -> String? {
        guard let data = payloadData(from: line),
              let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data),
              let text = chunk.choices?.first?.delta?.content
        else { return nil }
        return text
    }

    /// SSE 페이로드 추출 (T-266): `data:` 이후 JSON 바이트, 종료 마커·비SSE는 nil.
    nonisolated static func payloadData(from line: String) -> Data? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]" else { return nil }
        return payload.data(using: .utf8)
    }
}

/// SSE 청크 디코딩 모델 (T-119, 파일 스코프: nesting 린트 회피).
private struct ChatDelta: Decodable {
    var content: String?
}

/// SSE 청크 디코딩 모델 (T-119, 파일 스코프: nesting 린트 회피).
private struct ChatChoice: Decodable {
    var delta: ChatDelta?
}

/// SSE 청크 디코딩 모델 (T-119, 파일 스코프: nesting 린트 회피).
private struct ChatChunk: Decodable {
    var choices: [ChatChoice]?
}
