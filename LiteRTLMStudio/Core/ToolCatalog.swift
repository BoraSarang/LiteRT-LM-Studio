import Foundation

/// 도구 표시 정보 (T-271): 설정 도구 탭 목록용.
struct ToolInfo: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case basic = "기본"
        case web = "웹"
        case system = "시스템"
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
                     detail: "최신 정보 검색 (wigolo 우선 폴백)", category: .web),
            ToolInfo(name: WebFetchTool.name, title: "페이지 가져오기",
                     detail: "URL 본문 읽기", category: .web),
            ToolInfo(name: RunShellTool.name, title: "셸 실행",
                     detail: "명령 실행 (삭제·관리자 차단)", category: .system),
            ToolInfo(name: SaveCodeTool.name, title: "코드 저장",
                     detail: "작업폴더에 파일 저장", category: .system),
            ToolInfo(name: ReadFileTool.name, title: "파일 읽기",
                     detail: "작업폴더 파일 읽기", category: .system)
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
}
