import AppKit
import SwiftUI

/// 하단 패널 본체: chatPane 하단·입력바 위 (T-039, 사이드바 제외).
/// T-094 터미널 개편: 입력창 동일 박스+서버 로그 전용 행+시스템 가로 3칸+자동스크롤+복사/지우기+시각.
struct BottomPanelView: View {
    @ObservedObject var daemon: DaemonManager
    @ObservedObject var monitor: SystemMonitor
    @Binding var logTab: Int
    var onClose: () -> Void
    var onTakeover: () -> Void
    @State private var selection = Set<Int>()
    @StateObject private var copyFlag = CopyFlag()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $logTab) {
                    Text(L(L10n.Panel.serverLog)).tag(0)
                    Text(L(L10n.Panel.system)).tag(1)
                }.pickerStyle(.segmented).frame(width: 160)
                Text(L(daemon.external ? L10n.Panel.externalDaemon : L10n.Panel.appDaemon))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                // T-100 헤더 자리 유지: 복사 3종 상시 배치 + 조건 opacity (시스템 탭에서도 X 위치·높이 고정)
                HStack(spacing: 8) {
                    Button(L(copyFlag.copied ? L10n.Panel.copied : L10n.Panel.copySelection)) {
                        copyTargets(selectionOrAll)
                    }
                        .help(L(L10n.Panel.copySelectionHelp))
                    Button(L(L10n.Panel.copyAll)) { copyTargets(daemon.logLines) }
                        .help(L(L10n.Panel.copyAllHelp))
                    Button(L(L10n.Panel.clear)) { daemon.clearLog(); selection.removeAll() }
                        .help(L(L10n.Panel.clearHelp))
                }
                .opacity(showLogActions ? 1 : 0)
                .disabled(!showLogActions)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }.buttonStyle(.plain).help(L(L10n.Panel.closeHelp))
            }
            // T-100 탭 전환 고정: 콘텐츠 영역 동일 지오메트리 (서버 List 풀필 vs 시스템 셀 밑단 일치)
            Group {
            if logTab == 0 {
                if daemon.external {
                    // 외부 데몬 로그는 수집 불가 → 안내 + 인수.
                    VStack(spacing: 8) {
                        ContentUnavailableView(
                            L(L10n.Panel.externalLogTitle),
                            systemImage: "terminal",
                            description: Text(L(L10n.Panel.externalLogDetail))
                        )
                        Button(L(L10n.Panel.takeover)) { onTakeover() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if daemon.logLines.isEmpty {
                    ContentUnavailableView(
                        L(L10n.Panel.noLogTitle),
                        systemImage: "terminal",
                        description: Text(L(L10n.Panel.noLogDetail))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        List(selection: $selection) {
                            ForEach(Array(daemon.logLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .onAppear {
                            guard !daemon.logLines.isEmpty else { return }
                            proxy.scrollTo(daemon.logLines.count - 1, anchor: .bottom)
                        }
                        .onChange(of: daemon.logLines.count) { old, n in
                            if n < old {
                                selection.removeAll() // 상한 trim 시 오프셋 어긋남 방지
                            } else if n > 0 {
                                proxy.scrollTo(n - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    SystemCellView(title: "CPU",
                                   value: String(format: "%.0f%%", monitor.cpu),
                                   history: monitor.cpuHistory, color: .blue,
                                    popoverRows: SystemMetersView.cpuPopoverRows(
                                        sys: monitor.cpuSystem, user: monitor.cpuUser)
                                        .enumerated().map { i, r in
                                            MeterRow(color: [.red, .blue, .primary][i],
                                                     label: r.label, value: r.value)
                                        })
                    .frame(maxHeight: .infinity)
                    SystemCellView(title: "RAM",
                                   value: String(format: "%.0f%%", SystemMetersView.ramUsedPct(
                                       usedGB: monitor.ramUsedGB, totalGB: monitor.ramTotalGB)),
                                   history: monitor.ramHistory, color: .yellow,
                                    popoverRows: SystemMetersView.ramPopoverRows(
                                        app: monitor.ramAppGB, wired: monitor.ramWiredGB,
                                        comp: monitor.ramCompGB, cache: monitor.ramInactiveGB)
                                        .enumerated().map { i, r in
                                            MeterRow(color: [.yellow, .red, .blue, .secondary][i],
                                                     label: r.label, value: r.value)
                                        })
                    .frame(maxHeight: .infinity)
                    SystemCellView(title: "GPU",
                                   value: monitor.gpu.map { String(format: "%.0f%%", $0) } ?? "–",
                                   history: monitor.gpuHistory, color: .purple,
                                   popoverRows: [])
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // T-100 시스템 셀 영역 풀필 (List 밑단과 일치)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // T-100 콘텐츠 영역 통일
        }
        .cardBox()
        .frame(height: DS.bottomBoxHeight) // T-095 입력창 접힘 높이와 동일
    }

    private var showLogActions: Bool {
        logTab == 0 && !daemon.external && !daemon.logLines.isEmpty
    }

    private var selectionOrAll: [String] {
        selection.isEmpty ? daemon.logLines : selection.sorted().compactMap {
            $0 < daemon.logLines.count ? daemon.logLines[$0] : nil
        }
    }

    private func copyTargets(_ lines: [String]) {
        PasteboardUtil.copy(lines.joined(separator: "\n"))
        copyFlag.mark()
    }
}

/// 시스템 미니 셀 (T-094 가로 3칸, T-096 호버 팝오버): 제목+값+미니 차트.
struct SystemCellView: View {
    let title: String
    let value: String
    let history: [Double]
    let color: Color
    let popoverRows: [MeterRow]
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                Text(value).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            HistoryLineChart(history: history, color: color)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(.rect(cornerRadius: 8))
        .frame(maxWidth: .infinity)
        .onHover { hovering = $0 }
        .popover(isPresented: Binding(
            get: { hovering && !popoverRows.isEmpty },
            set: { hovering = $0 }
        ), arrowEdge: .top) {
            MeterPopover(rows: popoverRows)
        }
    }
}
