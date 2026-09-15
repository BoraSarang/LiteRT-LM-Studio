import SwiftUI

/// 강제 외관 (T-041 수동 전환 대응, 미지정은 시스템 추종).
/// T-150 네이티브 전환 후 외관은 시맨틱 컬러로 처리라 값만 유지 (API 호환).
enum MarkdownScheme: String {
    case auto
    case light
    case dark
}

/// 마크다운 네이티브 렌더 (T-150/T-152, WKWebView 제거).
/// - 블록 분리 후 블록별 전체 파싱 (개행은 블록 경계로 보존, marked breaks:false와 동일)
/// - 호출 API는 기존과 동일 (text/scheme/isStreaming/fontScale)이라 호출부 변경 없음
struct MarkdownView: View, Equatable {
    let text: String
    var scheme: MarkdownScheme = .auto
    var isStreaming: Bool = false
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.scheme == rhs.scheme && lhs.isStreaming == rhs.isStreaming
            && lhs.fontScale == rhs.fontScale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(NativeMarkdown.splitFences(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let p):
                    proseBody(p)
                case .code(let c):
                    codeBody(c)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 문단 렌더: 줄 블록별 표시 (T-151/T-152).
    func proseBody(_ p: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(NativeMarkdown.parseProse(p).enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let level, let t):
                    Text(NativeMarkdown.styled(t, size: (22 - CGFloat(level) * 2) * fontScale,
                                               weight: .bold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .bullet(let t, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(NativeMarkdown.styled(t, size: 14 * fontScale))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(indent) * 14)
                case .ordered(let n, let t, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n).")
                        Text(NativeMarkdown.styled(t, size: 14 * fontScale))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(indent) * 14)
                case .table(let rows, let header):
                    tableBody(rows: rows, header: header)
                case .hr:
                    Divider()
                case .blank:
                    Spacer().frame(height: 6)
                case .paragraph(let t):
                    if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(NativeMarkdown.styled(t, size: 14 * fontScale))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// 실제 표 렌더 (T-152): 헤더 볼드 + 구분선 + 열 맞춤 Grid.
    func tableBody(rows: [[String]], header: Bool) -> some View {
        let cols = max(1, rows.map(\.count).max() ?? 1)
        let padded = rows.map { r in r + Array(repeating: "", count: max(0, cols - r.count)) }
        return VStack(alignment: .leading, spacing: 2) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(Array(padded.enumerated()), id: \.offset) { ri, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(NativeMarkdown.styled(cell, size: 13 * fontScale,
                                                       weight: (header && ri == 0) ? .bold : .regular))
                                .textSelection(.enabled)
                                .gridCellAnchor(.leading)
                        }
                    }
                    if header, ri == 0 {
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
        }
    }

    /// 코드 블록 렌더 (T-158): Highlightr 색상, 실패 시 단색 등폭 폴백.
    func codeBody(_ c: String) -> some View {
        let part = NativeMarkdown.splitCode(c)
        let size = 13 * fontScale
        let dark = scheme != .light
        let content: Text
        if let attr = CodeHighlighter.highlight(code: part.body, lang: part.lang,
                                                dark: dark, fontSize: size) {
            content = Text(attr)
        } else {
            content = Text(part.body).font(.system(size: size, design: .monospaced))
        }
        return content
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.textBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
    }

    /// 인라인 서식 텍스트: 실패 시 원문 폴백 (빈 화면 방지).
    func inlineText(_ s: String) -> some View {
        if let attr = NativeMarkdown.attributed(s) {
            return Text(attr).textSelection(.enabled)
        }
        return Text(s).textSelection(.enabled)
    }
}
