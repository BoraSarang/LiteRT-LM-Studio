import Foundation

/// 명령 1건 (T-263 고정 6종 + T-326 벤치 2종): id 기준 실행.
struct PaletteCommand: Identifiable, Hashable {
    let id: String
    let title: String
    let hint: String
    var icon: String = ""
    var detail: String = ""
}

/// 최근 사용 명령 (T-326, UserDefaults 영속, 테스트 주입 가능).
enum PaletteRecents {
    static let key = "paletteRecents"
    static let maxStored = 10
    static let maxShown = 5

    nonisolated static func load(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    nonisolated static func record(_ id: String, to defaults: UserDefaults = .standard) {
        var ids = load(from: defaults).filter { $0 != id }
        ids.insert(id, at: 0)
        defaults.set(Array(ids.prefix(maxStored)), forKey: key)
    }

    nonisolated static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// 최근 명령 최대 5건 (기록 없으면 빈 배열, 사라진 id 제외).
    nonisolated static func recentCommands(all: [PaletteCommand],
                                           defaults: UserDefaults = .standard) -> [PaletteCommand] {
        let ids = load(from: defaults)
        guard !ids.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }.prefix(maxShown).map { $0 }
    }
}

/// 팔레트 행 (T-263): 명령+채팅 단일 선택 공간.
enum PaletteRow: Identifiable, Hashable {
    case command(PaletteCommand)
    case hit(ChatSearchHit)

    var id: String {
        switch self {
        case .command(let cmd): return "cmd-\(cmd.id)"
        case .hit(let hit): return "hit-\(hit.id)"
        }
    }
}
