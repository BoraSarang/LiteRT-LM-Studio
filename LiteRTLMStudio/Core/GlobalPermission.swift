import Foundation

/// 전역 단일 권한 (T-228, PLAN_v45; T-232에서 가져오기·설치로 확대; T-255 전송 제외).
/// 게이트 대상: 모델 삭제·가져오기·설치 (사용자 파괴적 액션) + 장래 모델 도구 실행.
/// 채팅 전송은 항상 허용 (실행권과 무관).
enum GlobalPermission: String, CaseIterable {
    case off
    case ask
    case allowAll

    var titleKey: L10nKey {
        switch self {
        case .off: return L10n.Permission.off
        case .ask: return L10n.Permission.ask
        case .allowAll: return L10n.Permission.allowAll
        }
    }

    var title: String { L(titleKey) }

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
