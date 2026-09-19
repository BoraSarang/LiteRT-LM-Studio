import SwiftUI

/// 색 토큰 (T-318, PLAN_v96): Primary Blue #0A84FF 고정 외 Success/Warning/Error.
/// 라이트/다크 동일값 (사용자 결정, DESIGN 시맨틱 예외 — AGENTS.local.md 기록).
enum DSColor {
    static let primary = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
    static let success = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    static let warning = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
    static let error = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
}
