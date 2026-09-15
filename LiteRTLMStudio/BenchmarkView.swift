import Charts
import SwiftUI

/// 벤치마크 진행 단계 + 결과 그래프 + 한국어 해설.
/// 정렬 규칙: 단계·지표·로그는 데이터 표시이므로 좌측·상단 정렬, 결과 없으면 중앙 문구.
struct BenchmarkView: View {
    @ObservedObject var store: BenchmarkStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("벤치마크").font(.system(size: 13, weight: .semibold))
                Spacer()
                if store.running {
                    Button("중지") { store.cancel() }.keyboardShortcut(".", modifiers: .command)
                } else {
                    Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
            // 1→2→3→4 단계 표시
            HStack(spacing: 8) {
                ForEach(BenchmarkStore.Stage.allCases, id: \.self) { step in
                    stageChip(step)
                    if step != .done { stageChevron }
                }
            }
            if store.stage == .measure {
                Text("반복 \(store.currentIter)/\(store.totalIter) 측정 중…")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            Divider()
            if let met = store.metrics, store.stage == .done {
                resultSection(met)
            } else if store.metrics != nil || store.running {
                // 실행 중: 현재까지 모은 지표 미리보기 + 로그
                if let met = store.metrics, met.decodeSpeed > 0 {
                    miniChart(met)
                }
                logSection
            } else {
                // 데이터 없음 → 중앙 정렬 (전역 규칙)
                ContentUnavailableView("결과가 아직 없어요", systemImage: "gauge.with.dots.needle.0.percent",
                                       description: Text("측정이 끝나면 그래프와 해설이 여기에 나와요."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 480)
    }

    private func stageChip(_ step: BenchmarkStore.Stage) -> some View {
        let done = step.rawValue < store.stage.rawValue
        let current = step == store.stage && store.running
        return HStack(spacing: 4) {
            Image(systemName: done ? "checkmark.circle.fill" : current ? "arrow.triangle.2.circlepath" : "circle")
                .foregroundStyle(done ? .green : current ? .accentColor : .secondary)
            Text(step.title).font(.system(size: 11, weight: current ? .semibold : .regular))
        }
    }

    private func resultSection(_ met: BenchmarkStore.Metrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("백엔드 \(met.backend) · 프리필 \(met.prefillTokens)토큰 · 디코드 \(met.decodeTokens)토큰")
                    .font(DS.captionFont).foregroundStyle(.secondary)
                miniChart(met)
                ForEach(met.explanation, id: \.0) { title, body in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(body).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBox(padding: 10,
                             background: Color(.textBackgroundColor).opacity(0.5),
                             stroked: false)
                }
                DisclosureGroup("원문 출력") { logSection }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func miniChart(_ met: BenchmarkStore.Metrics) -> some View {
        Chart {
            BarMark(x: .value("구간", "입력 처리"), y: .value("tok/s", met.prefillSpeed))
            BarMark(x: .value("구간", "답 생성"), y: .value("tok/s", met.decodeSpeed))
        }
        .chartYAxisLabel("초당 토큰")
        .frame(height: 140)
    }

    private var stageChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10)).foregroundStyle(.tertiary)
    }

    private var logSection: some View {
        ScrollView {
            Text(store.logLines.joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 100)
    }
}
