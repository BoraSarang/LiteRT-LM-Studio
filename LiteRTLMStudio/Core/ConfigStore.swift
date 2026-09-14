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
    @Published var appliedMTP = true
    /// UI 편집 중인 초안.
    @Published var draftBackend = "gpu"
    @Published var draftVision = "gpu"
    @Published var draftMTP = true

    @Published var configExists = false
    @Published var externalRestartPending = false

    private let logger = DebugLogger.shared

    init(configURL: URL? = nil) {
        self.configURL = configURL ?? Self.defaultURL
    }

    var hasChanges: Bool {
        draftBackend != appliedBackend || draftVision != appliedVision || draftMTP != appliedMTP
    }

    /// “LLM cpu→gpu · MTP 끔→켬” 형식 변경 요약.
    var diffSummary: String {
        var parts: [String] = []
        if draftBackend != appliedBackend { parts.append("LLM \(appliedBackend)→\(draftBackend)") }
        if draftVision != appliedVision { parts.append("Vision \(appliedVision)→\(draftVision)") }
        if draftMTP != appliedMTP {
            parts.append("MTP \(appliedMTP ? "켬" : "끔")→\(draftMTP ? "켬" : "끔")")
        }
        return parts.joined(separator: " · ")
    }

    var summary: String {
        "LLM \(appliedBackend) · Vision \(appliedVision)\(appliedMTP ? " · MTP" : "")"
    }

    /// 기존 파일의 다른 키는 보존하면서 읽는다. applied와 draft를 함께 채운다.
    func load(modelID: String) {
        logger.info(feature: "설정조회", "config.json 읽기")
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            configExists = false
            logger.info(feature: "설정조회", "config 없음 → 엔진 기본값(CPU) 동작 중")
            return
        }
        configExists = true
        if let def = json["default"] as? [String: Any] {
            appliedBackend = def["backend"] as? String ?? appliedBackend
            appliedVision = def["vision_backend"] as? String ?? appliedVision
        }
        if let models = json["models"] as? [String: Any],
           let one = models[modelID] as? [String: Any],
           let spec = one["speculative_decoding"] as? Bool {
            appliedMTP = spec
        }
        revert()
    }

    /// 초안을 버리고 적용값으로 되돌린다 (디스크 불변).
    func revert() {
        draftBackend = appliedBackend
        draftVision = appliedVision
        draftMTP = appliedMTP
        logger.info(feature: "설정취소", "초안 되돌림")
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
        def["backend"] = draftBackend
        def["vision_backend"] = draftVision
        json["default"] = def
        var models = json["models"] as? [String: Any] ?? [:]
        var one = models[modelID] as? [String: Any] ?? [:]
        one["speculative_decoding"] = draftMTP
        models[modelID] = one
        json["models"] = models
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
            configExists = true
            appliedBackend = draftBackend
            appliedVision = draftVision
            appliedMTP = draftMTP
            logger.info(feature: "설정적용", "config 저장 완료 (\(summary.isEmpty ? "변경 없음" : summary))")
            return true
        } catch {
            logger.error(code: "E-MAC-STOR-0009", feature: "설정적용", "config 쓰기 실패: \(error)")
            return false
        }
    }
}
