import Foundation

// MARK: - HTML 표 처리 (T-237 분리: 파일 길이 분산)

extension NativeMarkdown {
    /// HTML 표 줄 소비 (T-237): 해당하면 누적하고 true.
    nonisolated static func consumeHtmlLine(_ t: String, acc: inout ProseAccumulator) -> Bool {
        guard acc.htmlRows != nil || t.lowercased().contains("<table") else { return false }
        accumulateHtmlLine(t, acc: &acc)
        return true
    }

    /// 단독 HTML 태그 줄 소비 (T-237): 태그 벗기고 텍스트만 누적하고 true.
    nonisolated static func consumeTagLine(_ line: String, _ t: String,
                                           acc: inout ProseAccumulator) -> Bool {
        guard t.hasPrefix("<") else { return false }
        let stripped = stripHTMLTags(t)
        guard !stripped.isEmpty else { return true }
        flushTable(acc: &acc)
        flushBlank(acc: &acc)
        acc.pending.append(stripped)
        return true
    }

    /// HTML 태그 제거 (순수, T-237): `<...>` 삭제 후 공백 수렴.
    nonisolated static func stripHTMLTags(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "<[^>]+>") else { return s }
        let range = NSRange(s.startIndex..., in: s)
        let stripped = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        return stripped.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .split(separator: "\t", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HTML 셀 1칸 텍스트 (순수, T-237): 보이는 글 우선, 아이콘만 있으면 링크 파일명.
    nonisolated static func htmlCellText(_ cellHTML: String) -> String {
        let visible = stripHTMLTags(cellHTML)
        if visible.count > 1 { return visible }
        if let href = htmlLinkTarget(cellHTML) {
            let base = href.split(separator: "?").first.map(String.init) ?? href
            if let name = base.split(separator: "/").last, !name.isEmpty { return String(name) }
        }
        return visible
    }

    /// `href="..."` 추출 (순수, T-237).
    nonisolated static func htmlLinkTarget(_ s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"href=["']([^"']+)["']"#,
                                                options: .caseInsensitive) else { return nil }
        let ns = s as NSString
        guard let match = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// HTML 표 1행 누적 (T-237): `<tr>` 단위로 끊고 `<td>/<th>` 셀 추출.
    nonisolated static func accumulateHtmlLine(_ t: String, acc: inout ProseAccumulator) {
        let lower = t.lowercased()
        if acc.htmlRows == nil {
            flushPara(acc: &acc)
            flushTable(acc: &acc)
            acc.htmlRows = []
            acc.htmlCurrent = []
            acc.htmlHeader = false
        }
        if lower.contains("<th") { acc.htmlHeader = true }
        for cell in htmlRowCells(t) {
            acc.htmlCurrent.append(htmlCellText(cell))
        }
        if lower.contains("</tr>") || lower.contains("</table>") {
            if !acc.htmlCurrent.allSatisfy(\.isEmpty) {
                acc.htmlRows?.append(acc.htmlCurrent)
            }
            acc.htmlCurrent = []
        }
        if lower.contains("</table>") {
            flushHtmlTable(acc: &acc)
        }
    }

    /// 줄 안 `<td>/<th>` 칸 원문 추출 (순수, T-237).
    nonisolated static func htmlRowCells(_ line: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "<t[hd][^>]*>(.*?)</t[hd]>",
                                                options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }
        let ns = line as NSString
        return re.matches(in: line, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    /// HTML 표 확정 배출 (T-237).
    nonisolated static func flushHtmlTable(acc: inout ProseAccumulator) {
        guard acc.htmlRows != nil else { return }
        if !acc.htmlCurrent.allSatisfy(\.isEmpty) {
            acc.htmlRows?.append(acc.htmlCurrent)
        }
        let rows = (acc.htmlRows ?? []).filter { !$0.allSatisfy(\.isEmpty) }
        if !rows.isEmpty {
            acc.out.append(.table(rows: rows, header: acc.htmlHeader))
        }
        acc.htmlRows = nil
        acc.htmlCurrent = []
        acc.htmlHeader = false
    }

}
