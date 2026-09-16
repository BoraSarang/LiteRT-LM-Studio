import Foundation

/// 생성 파라미터 확장 (T-176): 요청 바디 조립 + 옵션 묶음.
extension ChatStore {
    /// 채팅 요청 생성 (T-126 분리, 테스트 가능): 히스토리+이미지 페이로드 조립.
    /// T-268: extraHistory(tool 턴)+tools(tool_choice auto) 추가.
    func chatRequest(prompt: String, image: ChatImage? = nil,
                     extraHistory: [[String: Any]] = []) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = 300 // Vision 추론은 수 분 가능
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let windowed = Self.windowedHistory(Array(messages.dropLast(2)),
                                              turns: HistoryWindow.currentTurns())
        let history = windowed.map { ["role": $0.role, "content": $0.text] }
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
        // top_k는 OpenAI 비표준이라 config 기본으로만 (T-176).
        var body: [String: Any] = [
            "model": model, "messages": historyPlus,
            "temperature": temperature, "top_p": topP, "stream": true
        ]
        // T-268: 도구 등록 시 스키마 전송 (Off면 생략, 모델이 호출 불가).
        let localTools = LocalTools.registered()
        if !localTools.isEmpty,
           let schemaData = ToolManager(tools: localTools).toolsJsonDescription.data(using: .utf8),
           let schema = try? JSONSerialization.jsonObject(with: schemaData) {
            body["tools"] = schema
            body["tool_choice"] = "auto"
        }
        if let maxTokens { body["max_tokens"] = maxTokens }
        if let seed { body["seed"] = seed }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 현재 생성 옵션 묶음 (T-176): 네이티브 어댑터 전달용.
    func generationOptions() -> GenerationOptions {
        GenerationOptions(temperature: temperature, topK: topK, topP: topP, seed: seed,
                          maxTokens: maxTokens, thinkingEnabled: thinkingEnabled,
                          thinkingBudget: thinkingBudget, systemPrompt: systemPrompt)
    }
}
