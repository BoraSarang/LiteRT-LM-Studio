import Foundation

/// 도구 표시 정보 (T-271): 설정 도구 탭 목록용.
/// 표시 문자열은 키에서 조회한다 (T-362). 키는 도구 이름 기반 시맨틱 키
/// (`tools.<name>.title` / `tools.<name>.detail`)라 문구를 고쳐도 키가 흔들리지 않는다.
struct ToolInfo: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case basic, web, system, mcp

        var titleKey: L10nKey {
            switch self {
            case .basic: return L10n.Tools.categoryBasic
            case .web: return L10n.Tools.categoryWeb
            case .system: return L10n.Tools.categorySystem
            case .mcp: return L10n.Tools.categoryMcp
            }
        }

        var title: String { L(titleKey) }
    }

    let name: String
    let category: Category
    var id: String { name }

    var titleKey: L10nKey { L10nKey("tools.\(name).title") }
    var detailKey: L10nKey { L10nKey("tools.\(name).detail") }
    var title: String { L(titleKey) }
    var detail: String { L(detailKey) }
}

/// 도구 카탈로그 (T-271): 등록 도구 전수+개별 ON/OFF 저장소.
/// 새 Tool 추가 시 여기에 1행 추가하고 카탈로그에 `tools.<name>.title/detail`을 넣는다.
enum ToolCatalog {
    nonisolated static var keyPrefix: String { "toolEnabled." }

    /// 전체 목록 (표시 순서).
    nonisolated static var all: [ToolInfo] {
        [
            ToolInfo(name: GetTimeTool.name, category: .basic),
            ToolInfo(name: CalculatorTool.name, category: .basic),
            ToolInfo(name: WebSearchTool.name, category: .web),
            ToolInfo(name: WebFetchTool.name, category: .web),
            ToolInfo(name: RunShellTool.name, category: .system),
            ToolInfo(name: SaveCodeTool.name, category: .system),
            ToolInfo(name: ReadFileTool.name, category: .system),
            ToolInfo(name: GetSystemInfoTool.name, category: .system),
            ToolInfo(name: ReadClipboardTool.name, category: .system),
            ToolInfo(name: ListCalendarEventsTool.name, category: .system),
            ToolInfo(name: ListRemindersTool.name, category: .system),
            ToolInfo(name: WriteClipboardTool.name, category: .system),
            ToolInfo(name: OpenURLTool.name, category: .system),
            ToolInfo(name: RunShortcutTool.name, category: .system),
            ToolInfo(name: AddReminderTool.name, category: .system),
            ToolInfo(name: AddCalendarEventTool.name, category: .system),
            ToolInfo(name: DeleteReminderTool.name, category: .system),
            ToolInfo(name: DeleteCalendarEventTool.name, category: .system),
            ToolInfo(name: MCPListToolsTool.name, category: .mcp),
            ToolInfo(name: MCPCallTool.name, category: .mcp)
        ]
    }

    /// 개별 활성화 여부 (기본 켜짐, 테스트 가능).
    nonisolated static func isEnabled(_ name: String,
                                      defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: keyPrefix + name) == nil
            || defaults.bool(forKey: keyPrefix + name)
    }

    /// 개별 ON/OFF 저장 (테스트 가능).
    nonisolated static func setEnabled(_ name: String, _ on: Bool,
                                       defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: keyPrefix + name)
    }

    /// 표시명 (T-271): UI에선 내부 도구명을 보여주지 않는다. 미등록은 원문 폴백.
    nonisolated static func title(for name: String) -> String {
        guard let info = all.first(where: { $0.name == name }) else { return name }
        return L(info.titleKey)
    }
}
