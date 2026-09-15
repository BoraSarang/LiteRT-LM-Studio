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
/// - 폰트는 AttributedString에 내장 (Text 뒤 `.font()`는 볼드 특성을 덮어서 사용 금지, T-152)
/// - 코드 블록: 펜스 분리 후 등폭 텍스트 (구문색 미지원, fazm 폴백과 동일)
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

    /// 문단 내 줄 블록 (순수, 테스트 가능, T-151/T-152).
    enum ProseBlock: Equatable {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case ordered(index: Int, text: String)
        case table(rows: [[String]], header: Bool)
        case hr
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

    /// 한글 볼드 정규화 (순수, 테스트 가능, T-152): 구 marked koreanStrong 확장 동등.
    /// `**...**` 단위로 안쪽 공백만 제거 (`** ㅌㅌㅌ **` → `**ㅌㅌㅌ**`). 바깥 공백은 유지.
    nonisolated static func normalizeStrong(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\*\*([^*]+?)\*\*(?!\*)"#) else {
            return s
        }
        var r = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: r.length)).reversed() {
            let inner = r.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !inner.isEmpty else { continue }
            r = r.replacingCharacters(in: m.range, with: "**\(inner)**") as NSString
        }
        return r as String
    }

    /// 서식 내장 파싱 (T-152): 블록 전체 파싱 + 크기·굵기·등폭을 run에 직접 기록.
    /// View 뒤 `.font()`는 볼드 특성을 덮으므로 폰트는 여기에서만 지정한다.
    nonisolated static func styled(_ s: String, size: CGFloat, weight: Font.Weight = .regular)
        -> AttributedString {
        var base = (try? AttributedString(markdown: normalizeStrong(s)))
            ?? AttributedString(s)
        for run in base.runs {
            var f = Font.system(size: size, weight: weight, design: .default)
            if let v = run.inlinePresentationIntent {
                if v.contains(.stronglyEmphasized) { f = f.bold() }
                if v.contains(.emphasized) { f = f.italic() }
                if v.contains(.code) {
                    f = Font.system(size: size, weight: weight, design: .monospaced)
                }
            }
            base[run.range].font = f
        }
        return base
    }

    /// 문단 줄 분류 (순수, 테스트 가능, T-151/T-152): 제목·목록·표·구분선·문단 판정.
    nonisolated static func parseProse(_ s: String) -> [ProseBlock] {
        var out: [ProseBlock] = []
        var pending: [String] = []
        var rows: [[String]] = []
        var header = false
        func flushPara() {
            guard !pending.isEmpty else { return }
            out.append(.paragraph(text: pending.joined(separator: "\n")))
            pending = []
        }
        func flushTable() {
            guard !rows.isEmpty else { return }
            out.append(.table(rows: rows, header: header))
            rows = []
            header = false
        }
        for line in s.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                flushPara()
                flushTable()
            } else if isHR(t) {
                flushPara()
                flushTable()
                out.append(.hr)
            } else if let h = headingOf(t) {
                flushPara()
                flushTable()
                out.append(h)
            } else if t.hasPrefix("|"), t.hasSuffix("|") {
                flushPara()
                if isTableDelimiter(t) {
                    if !rows.isEmpty { header = true }
                } else {
                    rows.append(tableCells(t))
                }
            } else if let b = bulletOf(t) {
                flushPara()
                flushTable()
                out.append(b)
            } else {
                flushTable()
                pending.append(line)
            }
        }
        flushPara()
        flushTable()
        return out
    }

    /// 구분선 `---`/`***`/`___` 3개 이상 (순수, 테스트 가능, T-152).
    nonisolated static func isHR(_ t: String) -> Bool {
        guard t.count >= 3 else { return false }
        let set = CharacterSet(charactersIn: "-*_ ")
        guard t.unicodeScalars.allSatisfy({ set.contains($0) }) else { return false }
        let marks = t.filter { $0 != " " }
        guard marks.count >= 3, let first = marks.first else { return false }
        return marks.allSatisfy { $0 == first } && first != " "
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

    /// 문단 렌더: 줄 블록별 표시 (T-151/T-152).
    func proseBody(_ p: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(Self.parseProse(p).enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let level, let t):
                    Text(Self.styled(t, size: (22 - CGFloat(level) * 2) * fontScale,
                                     weight: .bold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(Self.styled(t, size: 14 * fontScale))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .ordered(let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n).")
                        Text(Self.styled(t, size: 14 * fontScale))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .table(let rows, let header):
                    tableBody(rows: rows, header: header)
                case .hr:
                    Divider()
                case .paragraph(let t):
                    if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(Self.styled(t, size: 14 * fontScale))
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
                            Text(Self.styled(cell, size: 13 * fontScale,
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

    /// 인라인 서식 텍스트: 실패 시 원문 폴백 (빈 화면 방지).
    func inlineText(_ s: String) -> some View {
        if let attr = Self.attributed(s) {
            return Text(attr).textSelection(.enabled)
        }
        return Text(s).textSelection(.enabled)
    }
}
