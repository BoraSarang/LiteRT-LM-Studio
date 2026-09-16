import Foundation

/// 전역 단일 권한 (T-228, PLAN_v45): Off / Ask every time / Allow all.
/// 게이트 대상: 채팅 전송 + 모델 삭제 (가져오기는 훅만).
enum GlobalPermission: String, CaseIterable {
    case off
    case ask
    case allowAll

    var title: String {
        switch self {
        case .off: return "사용 안 함"
        case .ask: return "매번 묻기"
        case .allowAll: return "모두 허용"
        }
    }

    /// 순수 게이트 판정 (테스트 가능).
    /// - off: 항상 차단, ask: 확인됨일 때만 허용, allowAll: 항상 허용.
    nonisolated static func allows(_ permission: GlobalPermission, confirmed: Bool) -> Bool {
        switch permission {
        case .off: return false
        case .ask: return confirmed
        case .allowAll: return true
        }
    }

    /// 확인 다이얼로그가 필요한지 (ask만 true).
    nonisolated static func needsConfirm(_ permission: GlobalPermission) -> Bool {
        permission == .ask
    }

    static func current(_ defaults: UserDefaults = .standard) -> GlobalPermission {
        GlobalPermission(rawValue: defaults.string(forKey: "globalPermission") ?? "") ?? .ask
    }
}
