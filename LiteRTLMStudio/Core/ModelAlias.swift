import Foundation

/// 모델 표시명: 사용자 별칭 > 자동 예쁘게 > 원 ID.
/// 별칭은 표시용이라 ID·config를 건드리지 않는다 (데몬·설정 무결).
enum ModelAlias {
    private static func key(_ id: String) -> String { "alias.\(id)" }

    /// `gemma4-12b` → “Gemma 4 · 12B”.
    static func pretty(id: String) -> String {
        let pattern = #"^([A-Za-z]+)(\d*)-(\d+)([bBmM])$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let found = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
              found.numberOfRanges == 5,
              let r1 = Range(found.range(at: 1), in: id),
              let r3 = Range(found.range(at: 3), in: id),
              let r4 = Range(found.range(at: 4), in: id)
        else { return id }
        let family = String(id[r1]).capitalized
        let gen = Range(found.range(at: 2), in: id).map { String(id[$0]) } ?? ""
        let size = String(id[r3]) + String(id[r4]).uppercased()
        return "\(family)\(gen.isEmpty ? "" : " \(gen)") · \(size)"
    }

    static func display(id: String) -> String {
        let alias = UserDefaults.standard.string(forKey: key(id))?.trimmingCharacters(in: .whitespaces)
        if let alias, !alias.isEmpty { return alias }
        return pretty(id: id)
    }

    /// 모달리티 한글 표기 (T-334, 순수): "Text Vision Audio" → "텍스트·이미지·음성".
    nonisolated static func modalitiesKorean(_ raw: String) -> String {
        let map = ["text": "텍스트", "vision": "이미지", "audio": "음성"]
        let parts = raw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let converted = parts.map { map[$0.lowercased()] ?? $0 }
        guard !converted.isEmpty else { return raw }
        return converted.joined(separator: "·")
    }

    static func setAlias(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(id))
        } else {
            UserDefaults.standard.set(trimmed, forKey: key(id))
        }
    }
}
