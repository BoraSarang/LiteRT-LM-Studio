import Foundation

/// 생성 파라미터 확장 (T-176): 요청 바디 조립 + 옵션 묶음.
extension ChatStore {
    /// 전송 직전 과거 turns (현재 user+assistant 제외, T-149 윈도우 적용).
    func pastTurns() -> [Message] {
        Self.windowedHistory(Array(messages.dropLast(2)),
                             turns: HistoryWindow.currentTurns())
    }

    /// 턴별 히스토리 (T-347): 도구 재전송 턴은 직전 2개 Q/A(4메시지)로 축소.
    /// 도구 결과는 extraHistory에 포함되므로 정확성 유지, prefill 요량만 줄인다.
    func turnHistory(toolTurn: Bool) -> [Message] {
        toolTurn ? Array(messages.dropLast(2).suffix(4)) : pastTurns()
    }

    /// 채팅 요청 생성 (T-126 분리, 테스트 가능): 히스토리+이미지 페이로드 조립.
    /// T-268: extraHistory(tool 턴)+tools(tool_choice auto) 추가.
    /// T-347: toolTurn=true면 히스토리 축소+시스템 프롬프트 경량화 (재전송 prefill 단축).
    func chatRequest(prompt: String, image: ChatImage? = nil,
                     extraHistory: [[String: Any]] = [],
                     toolTurn: Bool = false) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = 300 // Vision 추론은 수 분 가능
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let history = turnHistory(toolTurn: toolTurn).map { ["role": $0.role, "content": $0.text] }
        let userContent: Any
        if let image {
            let b64 = image.data.base64EncodedString()
            userContent = [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:\(image.mime);base64,\(b64)"]]
            ]
        } else {
            userContent = prompt
        }
        let historyPlus = history + [["role": "user", "content": userContent]] + extraHistory
        // 이전 턴에서 도구 스키마·히스토리를 이미 봤으므로 재전송 턴은 prefill만 줄인다.
        // 정직 가드·스킬/MCP 안내는 1턴에 충분 — 도구 결과를 답으로 정리하는 2턴엔 불필요.
        let sysBlock: String
        if toolTurn {
            sysBlock = Self.currentDateBlock()
        } else {
            // T-285: 스킬+MCP 안내 + T-312: 오늘 날짜 시스템 메시지 (빈 문자열이면 생략).
            let extras = SkillsStore.extrasBlock(
                serverNames: MCPStore.shared.enabledServers.map(\.name))
            sysBlock = [Self.currentDateBlock(), Self.toolHonestyBlock(),
                        Self.parallelToolCallBlock(), extras]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        let messagesPlus: [[String: Any]] = sysBlock.isEmpty
            ? historyPlus
            : [["role": "system", "content": sysBlock]] + historyPlus
        // top_k는 OpenAI 비표준이라 config 기본으로만 (T-176).
        var body: [String: Any] = [
            "model": model, "messages": messagesPlus,
            "temperature": temperature, "top_p": topP, "stream": true
        ]
        // T-268: 도구 등록 시 스키마 전송 (Off면 생략, 모델이 호출 불가).
        let localTools = LocalTools.registered()
        if !localTools.isEmpty,
           let schemaData = ToolManager(tools: localTools).toolsJsonDescription.data(using: .utf8),
           let schema = try? JSONSerialization.jsonObject(with: schemaData) {
            body["tools"] = schema
            body["tool_choice"] = "auto"
            // T-351: 독립 도구는 한 응답에서 병렬 호출 (OpenAI 표준 필드, 무시돼도 무해).
            body["parallel_tool_calls"] = true
        }
        if let maxTokens { body["max_tokens"] = maxTokens }
        if let seed { body["seed"] = seed }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 현재 생성 옵션 묶음 (T-176): 앱 내 엔진 어댑터 전달용.
    /// T-285: 스킬+MCP 안내를 시스템 프롬프트에 합성.
    func generationOptions() -> GenerationOptions {
        let extras = SkillsStore.extrasBlock(
            serverNames: MCPStore.shared.enabledServers.map(\.name))
        let combined = [Self.currentDateBlock(), Self.toolHonestyBlock(), systemPrompt, extras]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        return GenerationOptions(temperature: temperature, topK: topK, topP: topP, seed: seed,
                                 maxTokens: maxTokens, thinkingEnabled: thinkingEnabled,
                                 thinkingBudget: thinkingBudget, systemPrompt: combined)
    }

    /// 오늘 날짜 블록 (T-312): FC(함수 호출) 미지원 모델도 날짜·요일을 알도록 시스템
    /// 프롬프트에 주입한다. 시각은 의도적으로 제외 — 분 단위로 바뀌면 대화 키
    /// (GenerationOptions)가 매 요청 달라져 KV 캐시 재사용이 깨진다. 날짜는 하루
    /// 동안 고정이라 안전하다. 순수 함수(테스트 가능).
    nonisolated static func currentDateBlock(
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return "[오늘 날짜] \(formatter.string(from: now)). "
            + "날짜·요일을 물으면 이 값을 그대로 답하세요."
    }

    /// 도구 정직 가드 (T-346): 호출 없이 성공 주장 금지. 고정 문자열이라 KV 캐시 안전.
    /// 서버·네이티브 공통으로 주입한다. 순수 함수(테스트 가능).
    nonisolated static func toolHonestyBlock() -> String {
        "[도구 정직 규칙] 클립보드 복사·일정 추가 등은 반드시 도구 호출로만 수행하세요. "
            + "도구를 호출하지 않았으면 '복사했습니다/추가했습니다/열었습니다/실행했습니다'라고 말하지 마세요. "
            + "도구가 목록에 없으면 호출을 시도하지 말고, 설정에서 해당 도구를 켜 달라고 안내하세요."
    }

    /// 도구 병렬 호출 유도 (T-351): 독립 도구를 한 응답에서 함께 호출해 왕복을 줄인다.
    /// 고정 문자열이라 KV 캐시 안전. 서버 1턴에만 주입 (재전송 턴은 생략). 순수 함수.
    nonisolated static func parallelToolCallBlock() -> String {
        "[도구 병렬 규칙] 맡은 확인을 위한 읽기 전용 도구(클립보드 읽기, 시스템 정보, "
            + "파일 읽기 등)는 서로 독립적이므로 한 응답에서 여러 도구를 함께 호출하고, "
            + "모든 결과를 받은 뒤 한 번에 요약하세요. 순차로 하나씩 호출하지 마세요."
    }
}
