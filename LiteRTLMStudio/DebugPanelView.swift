import AppKit
import SwiftUI

/// DebugPanel: 별도 윈도우 (T-053). 앱 내 엔진 List 선택 (T-057, Web Island 참고).
struct DebugPanelView: View {
    @StateObject private var logger = DebugLogger.shared
    @State private var filter: DebugLogger.Level?
    @State private var query = ""
    @State private var selection = Set<UUID>()
    @State private var follow = true
    @State private var atBottom = true
    @State private var viewportHeight: CGFloat = 400
    @State private var matchIndex = 0
    @StateObject private var copyFlag = CopyFlag()
    @Environment(\.dismiss) private var dismiss

    /// 시간 문자열 (T-053/T-057): HH:mm:ss.SSS.
    nonisolated static func timeString(_ date: Date) -> String {
        TimeFormat.debugTime(date)
    }

    /// 검색 일치 (순수, 테스트 가능): 시간·레벨·기능·메시지 대상.
    nonisolated static func matches(_ e: DebugLogger.Entry, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return timeString(e.date).localizedCaseInsensitiveContains(q)
            || e.level.rawValue.localizedCaseInsensitiveContains(q)
            || e.feature.localizedCaseInsensitiveContains(q)
            || e.message.localizedCaseInsensitiveContains(q)
    }

    /// 표시 행 (순수, 테스트 가능): 레벨 필터 AND 검색.
    nonisolated static func filteredRows(_ entries: [DebugLogger.Entry],
                                         level: DebugLogger.Level?,
                                         query: String) -> [DebugLogger.Entry] {
        entries.filter { e in
            (level.map { $0 == e.level } ?? true) && matches(e, query: query)
        }
    }

    /// 검색어 하이라이트 본문 (T-053).
    nonisolated static func highlightedMessage(_ e: DebugLogger.Entry, query: String) -> AttributedString {
        var attr = AttributedString(e.message)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return attr }
        var searchFrom = e.message.startIndex
        while searchFrom < e.message.endIndex,
              let r = e.message.range(of: q, options: .caseInsensitive,
                                      range: searchFrom..<e.message.endIndex),
              let ar = Range(r, in: attr) {
            attr[ar].backgroundColor = .yellow
            searchFrom = r.upperBound
        }
        return attr
    }

    /// 빈 상태 구분 (순수, 테스트 가능, T-055).
    enum PanelEmpty: Equatable { case none, noLogs, noMatch }

    nonisolated static func emptyKind(entryCount: Int, rowCount: Int) -> PanelEmpty {
        if rowCount > 0 { return .none }
        return entryCount > 0 ? .noMatch : .noLogs
    }

    var rows: [DebugLogger.Entry] {
        Self.filteredRows(logger.entries, level: filter, query: query)
    }

    /// 빈 상태 설명: 활성 조건 표시 (T-055).
    var filterDescription: Text {
        var parts: [String] = []
        if let filter { parts.append(L(L10n.Debug.filterLevel, filter.rawValue)) }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { parts.append(L(L10n.Debug.filterQuery, q)) }
        if parts.isEmpty { return Text(L(L10n.Debug.filterHint)) }
        return Text(L(L10n.Debug.filterEmpty, parts.joined(separator: " · ")))
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField(L(L10n.Debug.search), text: $query)
                        .textFieldStyle(.roundedBorder).frame(width: 150)
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(rows.isEmpty ? L(L10n.Debug.none) : L(L10n.Debug.position, matchIndex + 1, rows.count))
                            .font(DS.captionFont).foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 52, alignment: .leading)
                        Button(L(L10n.Debug.prev)) { jumpMatch(-1, proxy: proxy) }.disabled(rows.isEmpty)
                        Button(L(L10n.Debug.next)) { jumpMatch(1, proxy: proxy) }.disabled(rows.isEmpty)
                    }
                    Spacer()
                    Toggle(L(L10n.Debug.autoScroll), isOn: $follow).toggleStyle(.switch).controlSize(.small)
                    Picker(L(L10n.Debug.level), selection: $filter) {
                        Text(L(L10n.Debug.all)).tag(nil as DebugLogger.Level?)
                        ForEach(DebugLogger.Level.allCases, id: \.self) {
                            Text($0.rawValue).tag($0 as DebugLogger.Level?)
                        }
                    }.pickerStyle(.menu).frame(width: 110)
                }.padding(12)
                HStack(spacing: 8) {
                    Button(copyFlag.copied ? L(L10n.Debug.copied) : L(L10n.Debug.copySelection)) { copySelection() }
                        .help(L(L10n.Debug.copySelectionHelp))
                    Button(L(L10n.Debug.copyAll)) { copyAll() }
                        .help(L(L10n.Debug.copyAllHelp))
                    Spacer()
                    Button(L(L10n.Debug.clear)) { logger.clear(); selection.removeAll() }
                    Button(L(L10n.Debug.close)) { dismiss() }.keyboardShortcut(.cancelAction)
                }.padding(.horizontal, 12).padding(.bottom, 8)
                Divider()
                // 빈 상태는 가로·세로 중앙 (AGENTS.local 정렬 규칙, T-055).
                switch Self.emptyKind(entryCount: logger.entries.count, rowCount: rows.count) {
                case .none:
                    List(selection: $selection) {
                        ForEach(rows) { e in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.timeString(e.date))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary).frame(width: 76, alignment: .leading)
                                Text(e.level.rawValue).font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(color(for: e.level)).frame(width: 44, alignment: .leading)
                                Text("[\(e.feature)]").font(DS.captionFont).foregroundStyle(.secondary)
                                Text(Self.highlightedMessage(e, query: query))
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .tag(e.id)
                            .id(e.id)
                        }
                        // 하단 앵커: 핀 판정용 (T-053, List末尾, 선택 제외).
                        Color.clear.frame(height: 1)
                    }
                    .listStyle(.plain)
                    .coordinateSpace(name: "debugScroll")
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: DebugBottomKey.self, value: geo.size.height)
                        }
                    }
                    .onPreferenceChange(DebugBottomKey.self) { viewportHeight = $0 }
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: DebugAnchorKey.self,
                                                   value: geo.frame(in: .named("debugScroll")).maxY)
                        }
                        .frame(width: 0, height: 0)
                    }
                    .onPreferenceChange(DebugAnchorKey.self) { maxY in
                        atBottom = maxY <= viewportHeight + 60
                    }
                    .onAppear {
                        logger.info(feature: "디버그패널", "열기")
                        // 실행 시 마지막으로 (T-053).
                        DispatchQueue.main.async {
                            if let last = rows.last?.id {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: logger.entries.count) { _, _ in
                        matchIndex = 0
                        if follow, atBottom, let last = rows.last?.id {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                    .onChange(of: query) { _, _ in matchIndex = 0 }
                    .onChange(of: filter) { _, _ in
                        matchIndex = 0
                        selection.removeAll()
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !atBottom {
                            Button(L(L10n.Debug.jumpBottom)) {
                                if let last = rows.last?.id {
                                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(12)
                            .help(L(L10n.Debug.jumpBottomHelp))
                        }
                    }
                case .noLogs:
                    ContentUnavailableView(
                        L(L10n.Debug.emptyTitle),
                        systemImage: "tray",
                        description: Text(L(L10n.Debug.emptyDetail))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .noMatch:
                    ContentUnavailableView(
                        L(L10n.Debug.noMatchTitle),
                        systemImage: "magnifyingglass",
                        description: filterDescription
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// 검색 결과 이동 (순환, T-053).
    private func jumpMatch(_ dir: Int, proxy: ScrollViewProxy) {
        guard !rows.isEmpty else { return }
        matchIndex = (matchIndex + dir + rows.count) % rows.count
        withAnimation { proxy.scrollTo(rows[matchIndex].id, anchor: .center) }
    }

    /// 선택 복사 (T-057, Web Island 참고): 선택 없으면 표시 전체.
    private func copySelection() {
        let ids = selection
        let targets = ids.isEmpty ? rows : rows.filter { ids.contains($0.id) }
        copy(entries: targets)
        copyFlag.mark()
    }

    /// 전체 복사 (T-086): 필터·검색 무관 저장 전체.
    private func copyAll() {
        copy(entries: logger.entries)
        copyFlag.mark()
    }

    private func color(for l: DebugLogger.Level) -> Color {
        switch l {
        case .info: .blue
        case .error: .red
        case .perf: .orange
        case .cache: .green
        }
    }

    private func copy(entries: [DebugLogger.Entry]) {
        let s = entries.map {
            "[\(Self.timeString($0.date))] [\($0.level.rawValue)] [\($0.feature)] \($0.message)"
        }.joined(separator: "\n")
        PasteboardUtil.copy(s)
    }
}

/// 디버그 스크롤 측정 키 (T-057): List 내부 지오메트리 전달용.
private struct DebugBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct DebugAnchorKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}
