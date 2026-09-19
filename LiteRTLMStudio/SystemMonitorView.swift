import Charts
import SwiftUI

/// 그래프 색 (활성 상태 보기와 동일 계열, 미세 조정용 상수).
private enum MeterColor {
    static let cpuUser = Color.blue
    static let cpuSystem = Color.red
    static let ramApp = Color.yellow
    static let ramWired = Color.red
    static let ramComp = Color.blue
}

/// 시스템 섹션 (인스펙터용): 공유 모니터 주입.
/// 활성 상태 보기식: 타이틀 위 → 그래프, 상세는 호버 팝오버. CPU 2선·RAM 3선.
/// 모니터 본체: 인스펙터·하단 패널이 공유 (샘플러 1개).
struct SystemMetersView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var cpuHover = false
    @State private var ramHover = false
    @State private var gpuHover = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(monitor.live ? .green : .gray).frame(width: 7, height: 7)
            Text(monitor.live ? "LIVE · 1초 갱신" : "중지됨")
                .font(DS.captionFont).foregroundStyle(.secondary)
            Spacer()
            Text("GPU는 순간 추정치")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .help("IOKit busy 추정치. powermetrics급 정밀도가 아닙니다.")
        }
        // T-293: 데몬 히어로 카드 완전 삭제 (양 경로 무의미). CPU/RAM/GPU 미터만 유지.
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                meterTitle(label: "CPU",
                           value: String(format: "%.0f%%", monitor.cpu),
                           help: "사용자(nice 포함)+시스템 (활성 상태 보기와 동일)")
                cpuLinesChart
                    .onHover { cpuHover = $0 }
                    .popover(isPresented: $cpuHover, arrowEdge: .top) {
                        MeterPopover(rows: cpuRows())
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                meterTitle(label: "RAM",
                           value: String(format: "%.0f%%",
                                          Self.ramUsedPct(usedGB: monitor.ramUsedGB,
                                                          totalGB: monitor.ramTotalGB)),
                           help: "App+Wired+압축 (활성 상태 보기와 동일). 비활성은 캐시된 파일로 별도 표기")
                ramLinesChart
                    .onHover { ramHover = $0 }
                    .popover(isPresented: $ramHover, arrowEdge: .top) {
                        MeterPopover(rows: ramRows())
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                meterTitle(label: "GPU",
                           value: monitor.gpu.map { String(format: "%.0f%%", $0) } ?? "–",
                           help: "IOKit 순간 추정치 (Apple Silicon)")
                miniChart(monitor.gpuHistory, color: .purple, height: 44)
                    .onHover { gpuHover = $0 }
                    .popover(isPresented: $gpuHover, arrowEdge: .top) {
                        MeterPopover(rows: [MeterRow(
                            color: .purple, label: "사용률",
                            value: monitor.gpu.map { String(format: "%.0f%%", $0) } ?? "–")])
                    }
            }
        }
    }

    /// CPU 팝오버 행 (순수, 테스트 가능, T-073).
    nonisolated static func cpuPopoverRows(sys: Double, user: Double) -> [(label: String, value: String)] {
        let idle = max(0, 100 - user - sys)
        return [("시스템", String(format: "%.0f%%", sys)),
                ("사용자", String(format: "%.0f%%", user)),
                ("유휴", String(format: "%.0f%%", idle))]
    }

    /// RAM 팝오버 행 (순수, 테스트 가능, T-073).
    nonisolated static func ramPopoverRows(app: Double, wired: Double,
                                           comp: Double, cache: Double) -> [(label: String, value: String)] {
        [("App", String(format: "%.1fGB", app)),
         ("Wired", String(format: "%.1fGB", wired)),
         ("압축", String(format: "%.1fGB", comp)),
         ("캐시", String(format: "%.1fGB", cache))]
    }

    private func cpuRows() -> [MeterRow] {
        let base = Self.cpuPopoverRows(sys: monitor.cpuSystem, user: monitor.cpuUser)
        let colors: [Color] = [.red, .blue, .primary]
        return zip(colors, base).map { MeterRow(color: $0, label: $1.label, value: $1.value) }
    }

    private func ramRows() -> [MeterRow] {
        let base = Self.ramPopoverRows(app: monitor.ramAppGB, wired: monitor.ramWiredGB,
                                       comp: monitor.ramCompGB, cache: monitor.ramInactiveGB)
        let colors: [Color] = [.yellow, .red, .blue, .secondary]
        return zip(colors, base).map { MeterRow(color: $0, label: $1.label, value: $1.value) }
    }

    private func meterTitle(label: String, value: String, help: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 4)
            Text(value).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(.tertiary)
                .help(help)
        }
    }

    /// RAM 사용률 % (순수, 테스트 가능, T-074).
    nonisolated static func ramUsedPct(usedGB: Double, totalGB: Double) -> Double {
        totalGB > 0 ? usedGB / totalGB * 100.0 : 0
    }

    /// CPU 2선 누적 스택: 시스템(아래, 빨강) + 합계=시스템+사용자(위, 파랑). X 도메인 고정.
    /// Charts 계열 분리: series+scale로 고정색 (고정 foregroundStyle만으론 첫색으로 합쳐짐).
    private var cpuLinesChart: some View {
        let user = monitor.cpuUserHistory
        let sys = monitor.cpuSystemHistory
        let n = min(user.count, sys.count)
        let base = monitor.sampleTick - n
        return Chart {
            ForEach(0 ..< n, id: \.self) { i in
                LineMark(x: .value("t", base + i),
                         y: .value("v", SystemMonitor.clamp100(sys[i])),
                         series: .value("계열", "시스템"))
                    .foregroundStyle(by: .value("계열", "시스템"))
                    .lineStyle(.init(lineWidth: 1.5))
            }
            ForEach(0 ..< n, id: \.self) { i in
                LineMark(x: .value("t", base + i),
                         y: .value("v", SystemMonitor.clamp100(sys[i] + user[i])),
                         series: .value("계열", "합계"))
                    .foregroundStyle(by: .value("계열", "합계"))
                    .lineStyle(.init(lineWidth: 1.5))
            }
        }
        .chartForegroundStyleScale(["시스템": MeterColor.cpuSystem, "합계": MeterColor.cpuUser])
        .chartLegend(.hidden) // T-073 자동 범례+수동 범례 중복 제거
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: SystemMonitor.xDomain(tick: monitor.sampleTick))
        .chartYScale(domain: 0 ... 100)
        .frame(height: 64)
    }

    /// RAM 3선 누적 스택: App(노랑) + App+Wired(빨강) + 합계(파랑).
    private var ramLinesChart: some View {
        let app = monitor.ramAppHistory
        let wired = monitor.ramWiredHistory
        let comp = monitor.ramCompHistory
        let n = min(min(app.count, wired.count), comp.count)
        let base = monitor.sampleTick - n
        return Chart {
            ForEach(0 ..< n, id: \.self) { i in
                LineMark(x: .value("t", base + i),
                         y: .value("v", SystemMonitor.clamp100(app[i])),
                         series: .value("계열", "App"))
                    .foregroundStyle(by: .value("계열", "App"))
                    .lineStyle(.init(lineWidth: 1.5))
            }
            ForEach(0 ..< n, id: \.self) { i in
                LineMark(x: .value("t", base + i),
                         y: .value("v", SystemMonitor.clamp100(app[i] + wired[i])),
                         series: .value("계열", "App+Wired"))
                    .foregroundStyle(by: .value("계열", "App+Wired"))
                    .lineStyle(.init(lineWidth: 1.5))
            }
            ForEach(0 ..< n, id: \.self) { i in
                LineMark(x: .value("t", base + i),
                         y: .value("v", SystemMonitor.clamp100(app[i] + wired[i] + comp[i])),
                         series: .value("계열", "합계"))
                    .foregroundStyle(by: .value("계열", "합계"))
                    .lineStyle(.init(lineWidth: 1.5))
            }
        }
        .chartForegroundStyleScale(["App": MeterColor.ramApp,
                                    "App+Wired": MeterColor.ramWired,
                                    "합계": MeterColor.ramComp])
        .chartLegend(.hidden) // T-073 자동 범례+수동 범례 중복 제거
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: SystemMonitor.xDomain(tick: monitor.sampleTick))
        .chartYScale(domain: 0 ... 100)
        .frame(height: 64)
    }

    private func miniChart(_ history: [Double], color: Color, height: CGFloat = 28) -> some View {
        HistoryLineChart(history: history, color: color, height: height)
    }
}

/// 팝오버 1행 (T-127): 3-튜플 대신 명명 구조체 (large_tuple 해소).
struct MeterRow {
    let color: Color
    let label: String
    let value: String
}

/// 호버 팝오버 카드 (T-073, 활성 상태 보기식): 라벨 좌·색상값 우.
struct MeterPopover: View {
    let rows: [MeterRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    Text(rows[i].label)
                    Spacer(minLength: 16)
                    Text(rows[i].value).foregroundStyle(rows[i].color)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                if i < rows.count - 1 { Divider() }
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .padding(.vertical, 4)
        .frame(width: 200)
    }
}
