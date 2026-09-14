import AppKit
import SwiftUI

/// DebugPanel: 별도 윈도우 (T-053). 네이티브 List 선택 (T-057, Web Island 참고).
struct DebugPanelView: View {
    @StateObject private var logger = DebugLogger.shared
    @State private var filter: DebugLogger.Level?
    @State private var query = ""
    @State private var selection = Set<UUID>()
    @State private var follow = true
    @State private var atBottom = true
    @State private var viewportHeight: CGFloat = 400
    @State private var matchIndex = 0
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    private nonisolated static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// 시간 문자열 (T-053/T-057): HH:mm:ss.SSS.
    nonisolated static func timeString(_ date: Date) -> String {
        timeFormatter.string(from: date)
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
        if let filter { parts.append("레벨 \(filter.rawValue)") }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { parts.append("검색 '\(q)'") }
        if parts.isEmpty { return Text("조건을 바꾸어 보세요.") }
        return Text(parts.joined(separator: " · ") + " 조건에 맞는 로그가 없어요.")
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("검색", text: $query)
                        .textFieldStyle(.roundedBorder).frame(width: 150)
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(rows.isEmpty ? "0건" : "\(matchIndex + 1)/\(rows.count)건")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 52, alignment: .leading)
                        Button("이전") { jumpMatch(-1, proxy: proxy) }.disabled(rows.isEmpty)
                        Button("다음") { jumpMatch(1, proxy: proxy) }.disabled(rows.isEmpty)
                    }
                    Spacer()
                    Toggle("자동 스크롤", isOn: $follow).toggleStyle(.switch).controlSize(.small)
                    Picker("레벨", selection: $filter) {
                        Text("전체").tag(nil as DebugLogger.Level?)
                        ForEach(DebugLogger.Level.allCases, id: \.self) {
                            Text($0.rawValue).tag($0 as DebugLogger.Level?)
                        }
                    }.pickerStyle(.menu).frame(width: 110)
                }.padding(12)
                HStack(spacing: 8) {
                    Button(copied ? "복사됨" : "선택 복사") { copySelection() }
                        .help("선택한 행 복사 (선택 없으면 표시 전체)")
                    Button("전체 복사") { copyAll() }
                        .help("필터·검색 무관 전체 로그 복사")
                    Spacer()
                    Button("지우기") { logger.clear(); selection.removeAll() }
                    Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
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
                                Text("[\(e.feature)]").font(.system(size: 11)).foregroundStyle(.secondary)
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
                            Button("맨 아래로") {
                                if let last = rows.last?.id {
                                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(12)
                            .help("최신 로그로 이동")
                        }
                    }
                case .noLogs:
                    ContentUnavailableView(
                        "아직 로그가 없어요",
                        systemImage: "tray",
                        description: Text("앱을 사용하시면 여기에 쌓입니다.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .noMatch:
                    ContentUnavailableView(
                        "일치하는 로그가 없어요",
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
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    /// 전체 복사 (T-086): 필터·검색 무관 저장 전체.
    private func copyAll() {
        copy(entries: logger.entries)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func color(for l: DebugLogger.Level) -> Color {
        switch l { case .info: .blue; case .error: .red; case .perf: .orange; case .cache: .green }
    }

    private func copy(entries: [DebugLogger.Entry]) {
        let s = entries.map {
            "[\(Self.timeString($0.date))] [\($0.level.rawValue)] [\($0.feature)] \($0.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
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
