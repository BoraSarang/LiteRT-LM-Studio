import Foundation

/// ~/.litert-lm/config.json 관리. serve는 OpenAI 요청에 백엔드 지정이 없어
/// config로만 GPU/Vision/MTP를 지정할 수 있다.
/// 초안(draft) → 적용/취소 패턴: UI는 draft만 건드리고, 적용하기 때 디스크 저장.
/// 쓰기 전 .bak 백업. 테스트용 경로 주입 가능.
@MainActor
final class ConfigStore: ObservableObject {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".litert-lm/config.json")
    }

    let configURL: URL

    /// 디스크에 저장된 값.
    @Published var appliedBackend = "gpu"
    @Published var appliedVision = "gpu"
    @Published var appliedMTP = false // T-222 기본 OFF (발열·배터리, 명시된 모델만 켬)
    @Published var appliedAudio = "cpu" // T-175
    @Published var appliedThreads = "" // T-175 빈칸=자동
    @Published var appliedCache = "disk" // T-175 disk/memory/no
    @Published var appliedKV = "" // T-175 빈칸=모델 기본
    @Published var appliedThinking = false // T-175 모델별 thinking 기본값
    @Published var appliedBudget = "" // T-175 빈칸=무제한(-1)
    @Published var appliedPrecision = "" // T-177 빈칸=모델 내장
    /// UI 편집 중인 초안.
    @Published var draftBackend = "gpu"
    @Published var draftVision = "gpu"
    @Published var draftMTP = false // T-222 기본 OFF
    @Published var draftAudio = "cpu"
    @Published var draftThreads = ""
    @Published var draftCache = "disk"
    @Published var draftKV = ""
    @Published var draftThinking = false
    @Published var draftBudget = ""
    @Published var draftPrecision = ""

    @Published var configExists = false
    @Published var externalRestartPending = false

    private let logger = DebugLogger.shared

    init(configURL: URL? = nil) {
        self.configURL = configURL ?? Self.defaultURL
    }

var hasChanges: Bool {
        draftBackend != appliedBackend || draftVision != appliedVision || draftMTP != appliedMTP
            || draftAudio != appliedAudio || draftThreads != appliedThreads
            || draftCache != appliedCache || draftKV != appliedKV
            || draftThinking != appliedThinking || draftBudget != appliedBudget
            || draftPrecision != appliedPrecision
    }

    /// JSON 파일 읽기 공용 (T-299): 읽기 5곳의 Data+파싱 반복 제거.
    nonisolated static func jsonDict(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    /// 숫자 초안 → config 값 (순수, 테스트 가능, T-175): 빈칸·비숫자·하한 미달이면 nil(키 삭제).
    nonisolated static func intOrNil(_ s: String, min: Int) -> Int? {
        guard let v = Int(s.trimmingCharacters(in: .whitespaces)), v >= min else { return nil }
        return v
    }

    /// Thinking 예산 초안 → config 값 (순수, 테스트 가능, T-175): 빈칸·비숫자는 -1(무제한).
    nonisolated static func budgetOrUnlimited(_ s: String) -> Int {
        let v = Int(s.trimmingCharacters(in: .whitespaces)) ?? -1
        return max(-1, v)
    }

    /// “LLM cpu→gpu · MTP 끔→켬” 형식 변경 요약.
    var diffSummary: String {
        var parts: [String] = []
        if draftBackend != appliedBackend { parts.append("LLM \(appliedBackend)→\(draftBackend)") }
        if draftVision != appliedVision { parts.append("Vision \(appliedVision)→\(draftVision)") }
        if draftMTP != appliedMTP {
            let on = L(L10n.Config.on)
            let off = L(L10n.Config.off)
            parts.append(L(L10n.Config.mtp, appliedMTP ? on : off, draftMTP ? on : off))
        }
        if draftAudio != appliedAudio { parts.append("Audio \(appliedAudio)→\(draftAudio)") }
        if draftThreads != appliedThreads {
            let before = appliedThreads.isEmpty ? L(L10n.Config.auto) : appliedThreads
            let after = draftThreads.isEmpty ? L(L10n.Config.auto) : draftThreads
            parts.append(L(L10n.Config.threads, before, after))
        }
        if draftCache != appliedCache { parts.append(L(L10n.Config.cache, appliedCache, draftCache)) }
        if draftKV != appliedKV {
            let before = appliedKV.isEmpty ? L(L10n.Config.defaultValue) : appliedKV
            let after = draftKV.isEmpty ? L(L10n.Config.defaultValue) : draftKV
            parts.append(L(L10n.Config.kv, before, after))
        }
        if draftThinking != appliedThinking {
            let on = L(L10n.Config.on)
            let off = L(L10n.Config.off)
            parts.append(L(L10n.Config.thinking, appliedThinking ? on : off, draftThinking ? on : off))
        }
        if draftBudget != appliedBudget {
            let before = appliedBudget.isEmpty ? L(L10n.Config.unlimited) : appliedBudget
            let after = draftBudget.isEmpty ? L(L10n.Config.unlimited) : draftBudget
            parts.append(L(L10n.Config.budget, before, after))
        }
        if draftPrecision != appliedPrecision {
            let before = appliedPrecision.isEmpty ? L(L10n.Config.builtin) : appliedPrecision
            let after = draftPrecision.isEmpty ? L(L10n.Config.builtin) : draftPrecision
            parts.append(L(L10n.Config.precision, before, after))
        }
        return parts.joined(separator: " · ")
    }

    var summary: String {
        var s = "LLM \(appliedBackend) · Vision \(appliedVision)\(appliedMTP ? " · MTP" : "")"
        if appliedAudio != "cpu" { s += " · Audio \(appliedAudio)" }
        if !appliedKV.isEmpty { s += " · KV \(appliedKV)" }
        return s
    }

    /// 기존 파일의 다른 키는 보존하면서 읽는다. applied와 draft를 함께 채운다.
    func load(modelID: String) {
        logger.info(feature: "설정조회", "config.json 읽기")
        guard let json = Self.jsonDict(at: configURL) else {
            configExists = false
            logger.info(feature: "설정조회", "config 없음 → 엔진 기본값(CPU) 동작 중")
            return
        }
        configExists = true
        if let def = json["default"] as? [String: Any] {
            appliedBackend = def["backend"] as? String ?? appliedBackend
            appliedVision = def["vision_backend"] as? String ?? appliedVision
            appliedAudio = def["audio_backend"] as? String ?? appliedAudio
            appliedCache = def["cache"] as? String ?? appliedCache
            appliedPrecision = def["activation_data_type"] as? String ?? appliedPrecision
            if let t = def["cpu_thread_count"] as? Int { appliedThreads = "\(t)" }
            if let k = def["max_num_tokens"] as? Int { appliedKV = "\(k)" }
        }
        if let models = json["models"] as? [String: Any],
           let one = models[modelID] as? [String: Any] {
            if let spec = one["speculative_decoding"] as? Bool { appliedMTP = spec } else { appliedMTP = false }
            if let th = one["thinking"] as? Bool { appliedThinking = th } else { appliedThinking = false }
            let budget = one["thinking_budget"] as? Int
            appliedBudget = budget == nil ? "" : (budget == -1 ? "" : "\(budget!)")
        } else {
            appliedMTP = false
            appliedThinking = false
            appliedBudget = ""
        }
        revert()
    }

    /// 초안을 버리고 적용값으로 되돌린다 (디스크 불변).
    func revert() {
        draftBackend = appliedBackend
        draftVision = appliedVision
        draftMTP = appliedMTP
        draftAudio = appliedAudio
        draftThreads = appliedThreads
        draftCache = appliedCache
        draftKV = appliedKV
        draftThinking = appliedThinking
        draftBudget = appliedBudget
        draftPrecision = appliedPrecision
        logger.info(feature: "설정취소", "초안 되돌림")
    }

    /// 모델 MTP 저장값 조회 (T-222, 벤치마크 창 표시용): 명시 없으면 nil (기본 OFF).
    static func savedMTP(modelID: String, configURL: URL? = nil) -> Bool? {
        let url = configURL ?? Self.defaultURL
        guard let json = jsonDict(at: url),
              let models = json["models"] as? [String: Any],
              let one = models[modelID] as? [String: Any],
              let spec = one["speculative_decoding"] as? Bool
        else { return nil }
        return spec
    }

    /// max_num_tokens 값 읽기: 없으면 nil (엔진·모델 기본값 사용).
    @MainActor
    static func maxNumTokensValue(from url: URL) -> Int? {
        guard let json = jsonDict(at: url),
              let def = json["default"] as? [String: Any],
              let k = def["max_num_tokens"] as? Int
        else { return nil }
        return k
    }

    /// default 섹션 쓰기 (T-175 분리): 빈칸 숫자키는 삭제 (엔진 기본 복귀).
    private func writeDefaults(into def: inout [String: Any]) {
        def["backend"] = draftBackend
        def["vision_backend"] = draftVision
        def["audio_backend"] = draftAudio
        def["cache"] = draftCache
        // 빈칸이면 키 삭제 (엔진 기본값으로 복귀).
        if draftPrecision.isEmpty {
            def.removeValue(forKey: "activation_data_type")
        } else {
            def["activation_data_type"] = draftPrecision
        }
        if let t = Self.intOrNil(draftThreads, min: 1) {
            def["cpu_thread_count"] = t
        } else {
            def.removeValue(forKey: "cpu_thread_count")
        }
        // 빈칸이면 키 삭제 (엔진·모델 기본값으로 복귀).
        if let k = Self.intOrNil(draftKV, min: 1) {
            def["max_num_tokens"] = k
        } else {
            def.removeValue(forKey: "max_num_tokens")
        }
        // 구 max_prefix_turns 키 1회 정리 (세션키 방식으로 대체되어 미사용).
        def.removeValue(forKey: "max_prefix_turns")
    }

    /// models 섹션 쓰기 (T-175 분리).
    private func writeModel(into models: inout [String: Any], modelID: String) {
        var one = models[modelID] as? [String: Any] ?? [:]
        one["speculative_decoding"] = draftMTP
        one["thinking"] = draftThinking
        one["thinking_budget"] = Self.budgetOrUnlimited(draftBudget)
        models[modelID] = one
    }

    /// 초안을 디스크에 적용한다. 성공 시 applied 갱신, true 반환.
    @discardableResult
    func apply(modelID: String) -> Bool {
        let summary = diffSummary
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let old = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = old
            let bak = configURL.appendingPathExtension("bak")
            if !FileManager.default.fileExists(atPath: bak.path) {
                try? data.write(to: bak)
            }
        }
        var def = json["default"] as? [String: Any] ?? [:]
        writeDefaults(into: &def)
        json["default"] = def
        var models = json["models"] as? [String: Any] ?? [:]
        writeModel(into: &models, modelID: modelID)
        json["models"] = models
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
            configExists = true
            appliedBackend = draftBackend
            appliedVision = draftVision
            appliedMTP = draftMTP
            appliedAudio = draftAudio
            appliedThreads = draftThreads
            appliedCache = draftCache
            appliedKV = draftKV
            appliedThinking = draftThinking
            appliedBudget = draftBudget
            appliedPrecision = draftPrecision
            logger.info(feature: "설정적용", "config 저장 완료 (\(summary.isEmpty ? "변경 없음" : summary))")
            return true
        } catch {
            logger.error(code: "E-MAC-STOR-0009", feature: "설정적용", "config 쓰기 실패: \(error)")
            return false
        }
    }
}
