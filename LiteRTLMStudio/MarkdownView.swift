import SwiftUI

/// 강제 외관 (T-041 수동 전환 대응, 미지정은 시스템 추종).
/// T-150 네이티브 전환 후 외관은 시맨틱 컬러로 처리라 값만 유지 (API 호환).
enum MarkdownScheme: String {
    case auto
    case light
    case dark
}

/// 마크다운 네이티브 렌더 (T-150, WKWebView 제거).
/// - 본문: 줄 단위 블록 분리(제목·목록·표·문단) + 인라인 AttributedString (개행 보존)
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

    /// 문단 내 줄 블록 (순수, 테스트 가능, T-151): 개행 보존용 줄 단위 분류.
    enum ProseBlock: Equatable {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case ordered(index: Int, text: String)
        case tableRow(cells: [String], header: Bool)
        case paragraph(text: String)
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

    /// 본문 AttributedString 변환 (T-150/T-151): 인라인만 해석해 개행 보존, 실패 시 nil.
    nonisolated static func attributed(_ s: String) -> AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return try? AttributedString(markdown: s, options: options)
    }

    /// 문단 줄 분류 (순수, 테스트 가능, T-151): 제목·목록·표·문단 판정.
    nonisolated static func parseProse(_ s: String) -> [ProseBlock] {
        var out: [ProseBlock] = []
        var pending: [String] = []
        func flush() {
            guard !pending.isEmpty else { return }
            out.append(.paragraph(text: pending.joined(separator: "\n")))
            pending = []
        }
        let lines = s.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                flush()
            } else if let h = headingOf(t) {
                flush()
                out.append(h)
            } else if t.hasPrefix("|"), t.hasSuffix("|") {
                flush()
                if isTableDelimiter(t) {
                    if case .tableRow(let cells, _) = out.last {
                        out[out.count - 1] = .tableRow(cells: cells, header: true)
                    }
                } else {
                    out.append(.tableRow(cells: tableCells(t), header: false))
                }
            } else if let b = bulletOf(t) {
                flush()
                out.append(b)
            } else {
                pending.append(line)
            }
            i += 1
        }
        flush()
        return out
    }

    /// 제목 판정 `#` 1~6개 + 공백 (순수, T-151).
    nonisolated static func headingOf(_ t: String) -> ProseBlock? {
        var level = 0
        for c in t {
            guard c == "#" else { break }
            level += 1
        }
        guard (1 ... 6).contains(level), t.dropFirst(level).hasPrefix(" ") else { return nil }
        let body = t.dropFirst(level + 1).trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? nil : .heading(level: level, text: body)
    }

    /// 목록 판정 `-`/`*`/`N.` (순수, T-151).
    nonisolated static func bulletOf(_ t: String) -> ProseBlock? {
        if t.hasPrefix("- ") || t.hasPrefix("* ") {
            return .bullet(text: String(t.dropFirst(2)))
        }
        var digits = 0
        for c in t {
            guard c.isNumber else { break }
            digits += 1
        }
        if digits > 0 {
            let rest = t.dropFirst(digits)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                let num = Int(t.prefix(digits)) ?? 1
                return .ordered(index: num, text: String(rest.dropFirst(2)))
            }
        }
        return nil
    }

    /// 표 구분선 `|---|---|` 판정 (순수, T-151).
    nonisolated static func isTableDelimiter(_ t: String) -> Bool {
        let inner = t.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
        guard !inner.isEmpty else { return false }
        return inner.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
    }

    /// 표 행 셀 분리 (순수, T-151).
    nonisolated static func tableCells(_ t: String) -> [String] {
        t.split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
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
                    proseBody(p)
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

    /// 문단 렌더: 줄 블록별 표시 (T-151).
    func proseBody(_ p: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(Self.parseProse(p).enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let level, let t):
                    inlineText(t)
                        .font(.system(size: (22 - CGFloat(level) * 2) * fontScale, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").font(.system(size: 14 * fontScale))
                        inlineText(t)
                            .font(.system(size: 14 * fontScale))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .ordered(let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n).").font(.system(size: 14 * fontScale))
                        inlineText(t)
                            .font(.system(size: 14 * fontScale))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .tableRow(let cells, let header):
                    Text(cells.joined(separator: " · "))
                        .font(.system(size: 13 * fontScale, weight: header ? .bold : .regular,
                                      design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .paragraph(let t):
                    if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        inlineText(t)
                            .font(.system(size: 14 * fontScale))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// 인라인 서식 텍스트: 실패 시 원문 폴백 (빈 화면 방지).
    func inlineText(_ s: String) -> some View {
        if let attr = Self.attributed(s) {
            return Text(attr).textSelection(.enabled)
        }
        return Text(s).textSelection(.enabled)
    }
}
