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

    /// 자간 적용 본문 Text (T-174): 크기별 0.015em tracking 통일. 코드는 제외.
    func bodyText(_ s: String, size: CGFloat, weight: Font.Weight = .regular) -> Text {
        Text(NativeMarkdown.styled(s, size: size, weight: weight))
            .tracking(NativeMarkdown.tracking(for: size))
    }

    /// 문단 렌더: 줄 블록별 표시 (T-151/T-152).
    /// T-194: 스트리밍 중 미완성 `**` 마커는 표시 제외 (깜빡임 방지, 코드 제외).
    func proseBody(_ p: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // T-194: 스트리밍 중 미완성 `**` 마커는 표시 제외 (깜빡임 방지).
            let prose = isStreaming ? NativeMarkdown.hidePendingStrong(p) : p
            return ForEach(Array(NativeMarkdown.parseProse(prose).enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let level, let t):
                    bodyText(t, size: (22 - CGFloat(level) * 2) * fontScale, weight: .bold)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .bullet(let t, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        bodyText(t, size: 14 * fontScale)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 12 + CGFloat(indent) * 14) // T-164 최상위도 기본 인덴트
                case .ordered(let n, let t, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n).").foregroundStyle(.secondary)
                        bodyText(t, size: 14 * fontScale)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 12 + CGFloat(indent) * 14) // T-164 최상위도 기본 인덴트
                case .table(let rows, let header):
                    tableBody(rows: rows, header: header)
                case .hr:
                    Divider()
                case .quote(let t): // T-169 인용: 좌측 바 + secondary 본문
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.secondary)
                            .frame(width: 3)
                        bodyText(t, size: 14 * fontScale)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .blank:
                    Spacer().frame(height: 6)
                case .paragraph(let t):
                    if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        bodyText(t, size: 14 * fontScale)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// 실제 표 렌더 (T-152/T-161/T-163): 테두리 상자 + 행/열 1px 실선 + 셀 패딩.
    /// Divider 축 의존 제거 (Grid 셀 안에서 가로로 눕는 버그) — 열 구분선은 명시 폭 Rectangle.
    func tableBody(rows: [[String]], header: Bool) -> some View {
        let cols = max(1, rows.map(\.count).max() ?? 1)
        let padded = rows.map { r in r + Array(repeating: "", count: max(0, cols - r.count)) }
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(padded.enumerated()), id: \.offset) { ri, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { ci, cell in
                        bodyText(cell, size: 13 * fontScale,
                                     weight: (header && ri == 0) ? .semibold : .regular)
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .gridCellAnchor(.leading)
                        if ci < cols - 1 {
                            Rectangle().fill(.separator).frame(width: 1)
                        }
                    }
                }
                if ri < padded.count - 1 || (header && ri == 0) {
                    GridRow {
                        Rectangle()
                            .fill(.separator)
                            .frame(height: 1)
                            .gridCellUnsizedAxes(.horizontal)
                            .gridCellColumns(cols * 2 - 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.textBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
    }

    /// 코드 블록 렌더 (T-158/T-160): 첫 페인트는 단색, 하이라이트는 비동기 승격.
    func codeBody(_ c: String) -> some View {
        let part = NativeMarkdown.splitCode(c)
        return CodeBlockView(code: part.body, lang: part.lang,
                             dark: scheme != .light, fontSize: 13 * fontScale,
                             isStreaming: isStreaming)
    }

    /// 인라인 서식 텍스트: 실패 시 원문 폴백 (빈 화면 방지).
    func inlineText(_ s: String) -> some View {
        if let attr = NativeMarkdown.attributed(s) {
            return Text(attr).textSelection(.enabled)
        }
        return Text(s).textSelection(.enabled)
    }
}

/// 코드 블록 뷰 (T-160/T-196/T-197): 언어 헤더+복사 버튼 (구 렌더러 동등).
/// 첫 페인트는 단색 등폭으로 즉시 그리고, 하이라이트는 직렬 큐에서 비동기 승격.
/// T-196: 스트리밍 중엔 작업 키 고정 → flush마다 JS 하이라이트가 쌓여
/// CPU 100%·자동 추종 기아를 내던 문제 해소. 완료 후 최종 코드로 1회만 승격.
/// T-197: 스트리밍 중엔 항상 평문 (첫 페인트 빈 코드의 빈 하이라이트가
/// 스트림 내내 고착되어 코드가 안 보이던 역효과 수정).
struct CodeBlockView: View {
    let code: String
    let lang: String?
    let dark: Bool
    let fontSize: CGFloat
    let isStreaming: Bool
    @StateObject private var copyFlag = CopyFlag()
    @State private var highlighted: AttributedString?
    @State private var highlightedCode: String?

    /// 하이라이트 작업 키 (순수, 테스트 가능, T-196).
    nonisolated static func highlightTaskID(code: String, isStreaming: Bool) -> String {
        isStreaming ? "streaming" : code
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(lang?.isEmpty == false ? lang! : "code")
                    .font(DS.captionFont).foregroundStyle(.secondary)
                Spacer()
                Button(copyFlag.copied ? "복사됨" : "복사") {
                    PasteboardUtil.copy(code)
                    copyFlag.mark()
                }
                .buttonStyle(.plain)
                .font(DS.captionFont).foregroundStyle(.secondary)
                .help("코드 복사").hoverTip("코드 복사")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            Divider()
            Group {
                if isStreaming {
                    Text(code).font(.system(size: fontSize, design: .monospaced))
                } else if let highlighted {
                    Text(highlighted)
                } else {
                    Text(code).font(.system(size: fontSize, design: .monospaced))
                }
            }
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.textBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) } // T-159 코드 상자 경계
        .task(id: Self.highlightTaskID(code: code, isStreaming: isStreaming)) {
            guard !isStreaming, highlightedCode != code else { return }
            let snapshot = code
            if let attr = await CodeHighlighter.highlightAsync(code: code, lang: lang,
                                                               dark: dark, fontSize: fontSize),
                !Task.isCancelled, snapshot == code {
                highlighted = attr
                highlightedCode = snapshot
            }
        }
    }
}
