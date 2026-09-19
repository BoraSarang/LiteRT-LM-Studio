import Foundation

// MARK: - T-222 배터리·MTP 상태 (pmset 읽기+한 줄 문구, 순수 분리)

/// 배터리 상태 (`pmset -g batt` 읽기).
struct BatteryStatus: Equatable {
    var percent: Int
    var discharging: Bool

    /// `pmset -g batt` 출력 파싱 (순수, 테스트 가능).
    /// 예: " -InternalBattery-0 (id=1)\t10%; discharging; 1:23 remaining present: true"
    nonisolated static func parse(_ out: String) -> BatteryStatus? {
        guard let found = out.range(of: #"(\d+)%"#, options: .regularExpression) else { return nil }
        guard let pct = Int(out[found].dropLast()) else { return nil }
        let lower = out.lowercased()
        let discharging: Bool
        if lower.contains("discharging") {
            discharging = true
        } else if lower.contains("charging") || lower.contains("charged") {
            discharging = false
        } else {
            return nil
        }
        return BatteryStatus(percent: pct, discharging: discharging)
    }

    /// pmset 실행 읽기 (실패하면 nil).
    nonisolated static func read() async -> BatteryStatus? {
        let (out, code) = await UvManager.runProcess("/usr/bin/pmset", args: ["-g", "batt"], timeout: 5)
        guard code == 0 else { return nil }
        return parse(out)
    }

    /// 전원·MTP 상태 한 줄 (순수, 테스트 가능): (문구, 경고 여부).
    /// 경고 = MTP 켬 또는 방전 중 20% 이하.
    nonisolated static func powerLine(mtp: Bool?, battery: BatteryStatus?) -> (String, Bool) {
        var parts: [String] = []
        if let mtp {
            parts.append(L(mtp ? L10n.Power.mtpLimited : L10n.Power.mtpOff))
        } else {
            parts.append(L(L10n.Power.mtpUnset))
        }
        if let battery {
            let state = battery.discharging ? L(L10n.Power.discharging) : L(L10n.Power.charging)
            parts.append(L(L10n.Power.battery, state, battery.percent))
        }
        let warn = mtp == true || (battery?.discharging == true && (battery?.percent ?? 100) <= 20)
        return (parts.joined(separator: " · "), warn)
    }
}
