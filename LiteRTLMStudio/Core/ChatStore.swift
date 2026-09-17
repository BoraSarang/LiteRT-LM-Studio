import Foundation

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

    private var currentTask: Task<Void, Never>?
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
        route = EngineMode(rawValue: routeDefaults.string(forKey: "engineMode") ?? "") ?? .cli
        load()
        if sessions.isEmpty { startDraft() }
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
        if startNativeIfNeeded(prompt: prompt, image: image, idx: idx, started: started) { return }
        currentTask = Task {
            do {
                try await self.runServerTurns(prompt: prompt, image: image, idx: idx, started: started)
                let elapsed = Date().timeIntervalSince(started)
                let chars = messages[idx].text.count
                messages[idx].perf = Self.perfLine(chars: chars, elapsed: elapsed)
                messages[idx].finishedAt = Date() // T-077 완료 시각 기록
                logger.perf(feature: "채팅전송", "완료 elapsed=\(String(format: "%.1f", elapsed))s chars=\(chars)")
            } catch is CancellationError {
                logger.info(feature: "채팅중단", "사용자 중단")
            } catch {
                self.requestFailed(at: idx, error: error)
            }
            preparing = false
            streaming = false
            save()
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

    /// 요청 실패 반영 (T-127 분리): 에러 버블+시각+로그.
    func requestFailed(at idx: Int, error: Error) {
        lastError = "E-MAC-NET-0005"
        messages[idx].text = "요청 실패: 서버 상태를 확인해 주세요. (E-MAC-NET-0005)"
        messages[idx].isError = true
        messages[idx].finishedAt = Date() // T-077 실패 시각도 기록
        logger.error(code: "E-MAC-NET-0005", feature: "채팅전송", "\(error)")
    }

    /// PERF 뱃지 문구 (순수, 테스트 가능, T-126): "12.3s · 약 15 tok/s".
    nonisolated static func perfLine(chars: Int, elapsed: TimeInterval) -> String {
        let est = chars / max(1, Int(elapsed * 4))
        return String(format: "%.1fs · 약 %d tok/s", elapsed, est)
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

    /// 마지막 요청 재시도: 꼬리(user+assistant) 제거 후 마지막 프롬프트 재전송 (중복 표시 없음).
    func retry() {
        guard !streaming else { return }
        logger.info(feature: "채팅재시도", "마지막 프롬프트 재전송")
        if messages.last?.role == "assistant" { messages.removeLast() }
        guard messages.last?.role == "user", let prompt = messages.last?.text else { return }
        messages.removeLast()
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
