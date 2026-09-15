import SwiftUI

/// 강제 외관 (T-041 수동 전환 대응, 미지정은 시스템 추종).
/// T-150 네이티브 전환 후 외관은 시맨틱 컬러로 처리라 값만 유지 (API 호환).
enum MarkdownScheme: String {
    case auto
    case light
    case dark
}

/// 마크다운 네이티브 렌더 (T-150, WKWebView 제거).
/// - 본문: AttributedString 파싱 + SwiftUI Text (높이 동기 결정, JS push 없음)
/// - 코드 블록: 펜스 분리 후 등폭 텍스트 (구문색은 미지원, fazm 폴백과 동일)
/// - 호출 API는 기존과 동일 (text/scheme/isStreaming/fontScale)이라 호출부 변경 없음
struct MarkdownView: View, Equatable {
    let text: String
    var scheme: MarkdownScheme = .auto
    var isStreaming: Bool = false
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌

    /// 렌더 블록 (순수, 테스트 가능, T-150): 펜스 안/밖 분리.
    enum Block: Equatable {
        case prose(String)
        case code(String)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.scheme == rhs.scheme && lhs.isStreaming == rhs.isStreaming
            && lhs.fontScale == rhs.fontScale
    }

    /// 펜스 코드 블록 분리 (순수, 테스트 가능, T-150): ``` 울타리 기준 교대 분할.
    nonisolated static func splitFences(_ s: String) -> [Block] {
        let parts = s.components(separatedBy: "```")
        return parts.enumerated().map { i, part in
            i.isMultiple(of: 2) ? .prose(part) : .code(part)
        }
    }

    /// 본문 AttributedString 변환 (T-150): 실패 시 nil → 호출 측 원문 폴백.
    nonisolated static func attributed(_ s: String) -> AttributedString? {
        try? AttributedString(markdown: s)
    }

    /// 줌 스케일 → 기준 px (순수, 테스트 가능, T-070, 기존 MarkdownWebView.fontPx 이관).
    nonisolated static func fontPx(_ scale: Double) -> Double {
        14 * min(2.0, max(0.7, scale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.splitFences(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let p):
                    if let attr = Self.attributed(p) {
                        Text(attr)
                            .font(.system(size: 14 * fontScale))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !p.isEmpty {
                        Text(p)
                            .font(.system(size: 14 * fontScale))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .code(let c):
                    Text(c.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 13 * fontScale, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.textBackgroundColor))
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
