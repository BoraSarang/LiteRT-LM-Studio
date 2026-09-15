import AppKit

/// 클립보드 복사 단일 진입점 (T-114).
/// UserBubble·AssistantBubble·BottomPanel·DebugPanel 4곳 중복 제거용.
enum PasteboardUtil {
    nonisolated static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
