import Foundation

/// 도구 표시 정보 (T-271): 설정 도구 탭 목록용.
struct ToolInfo: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case basic = "기본"
        case web = "웹"
        case system = "시스템"
        case mcp = "MCP"
    }

    let name: String
    let title: String
    let detail: String
    let category: Category
    var id: String { name }
}

/// 도구 카탈로그 (T-271): 등록 도구 전수+개별 ON/OFF 저장소.
/// 새 Tool 추가 시 여기에 1행 추가하면 설정 탭에 자동 표시.
enum ToolCatalog {
    nonisolated static var keyPrefix: String { "toolEnabled." }

    /// 전체 목록 (표시 순서).
    nonisolated static var all: [ToolInfo] {
        [
            ToolInfo(name: GetTimeTool.name, title: "현재 시각",
                     detail: "날짜·시각 안내", category: .basic),
            ToolInfo(name: CalculatorTool.name, title: "사칙계산",
                     detail: "숫자·+ - * / ( ) 수식 계산", category: .basic),
            ToolInfo(name: WebSearchTool.name, title: "웹 검색",
                     detail: "최신 정보 검색 (내장 wigolo, 설치 필요)", category: .web),
            ToolInfo(name: WebFetchTool.name, title: "페이지 가져오기",
                     detail: "URL 본문 읽기 (내장 wigolo, 설치 필요)", category: .web),
            ToolInfo(name: RunShellTool.name, title: "셸 실행",
                     detail: "명령 실행 (삭제·관리자 차단)", category: .system),
            ToolInfo(name: SaveCodeTool.name, title: "코드 저장",
                     detail: "작업폴더에 파일 저장", category: .system),
            ToolInfo(name: ReadFileTool.name, title: "파일 읽기",
                     detail: "작업폴더 파일 읽기", category: .system),
            ToolInfo(name: GetSystemInfoTool.name, title: "시스템 정보",
                     detail: "메모리·CPU·디스크 상태 조회", category: .system),
            ToolInfo(name: ReadClipboardTool.name, title: "클립보드 읽기",
                     detail: "복사된 텍스트 읽기", category: .system),
            ToolInfo(name: ListCalendarEventsTool.name, title: "일정 조회",
                     detail: "캘린더 일정 보기 (권한 필요)", category: .system),
            ToolInfo(name: ListRemindersTool.name, title: "미리 알림 조회",
                     detail: "미리 알림 보기 (권한 필요)", category: .system),
            ToolInfo(name: WriteClipboardTool.name, title: "클립보드 쓰기",
                     detail: "텍스트를 클립보드에 복사", category: .system),
            ToolInfo(name: OpenURLTool.name, title: "URL 열기",
                     detail: "http·https 주소를 브라우저로 열기", category: .system),
            ToolInfo(name: RunShortcutTool.name, title: "단축어 실행",
                     detail: "허용 목록의 Shortcuts 실행", category: .system),
            ToolInfo(name: AddReminderTool.name, title: "미리 알림 추가",
                     detail: "한국어 시간 표현으로 미리 알림 추가", category: .system),
            ToolInfo(name: AddCalendarEventTool.name, title: "일정 추가",
                     detail: "한국어 시간 표현으로 일정 추가", category: .system),
            ToolInfo(name: DeleteReminderTool.name, title: "미리 알림 삭제",
                     detail: "제목으로 미리 알림 삭제", category: .system),
            ToolInfo(name: DeleteCalendarEventTool.name, title: "일정 삭제",
                     detail: "제목(·날짜)으로 일정 삭제", category: .system),
            ToolInfo(name: MCPListToolsTool.name, title: "MCP 목록",
                     detail: "MCP 서버 도구 목록 조회", category: .mcp),
            ToolInfo(name: MCPCallTool.name, title: "MCP 호출",
                     detail: "MCP 서버 도구 실행", category: .mcp)
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

    /// 한글 표시명 (T-348): UI에선 영어 도구명을 보여주지 않는다. 미등록은 원문 폴백.
    nonisolated static func title(for name: String) -> String {
        all.first { $0.name == name }?.title ?? name
    }
}
