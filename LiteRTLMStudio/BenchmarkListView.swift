import SwiftUI

/// 사이드바 벤치마크 목록: 채팅식 새 벤치마크 + 전체 선택행 + 삭제 (T-225).
/// 선택은 history.selectedRecordID 공유 (창과 동기).
struct BenchmarkListView: View {
    @ObservedObject var history: BenchmarkHistoryStore
    @ObservedObject var bench: BenchmarkStore
    @ObservedObject var chat: ChatStore
    @State private var hoverID: BenchmarkRecord.ID?

    var body: some View {
        Section {
            newBenchmarkButton
            ForEach(history.records) { rec in
                benchmarkRow(rec)
            }
        } header: {
            listHeader
        }
    }

    /// 새 벤치마크 버튼 (채팅식): 선택 해제+현재 모델·경로 예약 후 창 열기.
    /// 선택 틴트 없음 (T-235, 새 채팅 규칙과 통일: 평상시 fill 없음).
    private var newBenchmarkButton: some View {
        Button {
            history.selectedRecordID = nil
            bench.prepare(modelID: chat.model, route: chat.route)
            NotificationCenter.default.post(name: .openBenchmark, object: nil)
        } label: {
            HStack {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                Text(L(L10n.Benchmark.newBenchmark)).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(bench.running)
        .help(L(L10n.Benchmark.newBenchmarkHelp))
    }

    /// 섹션 헤더: 제목+건수.
    private var listHeader: some View {
        HStack {
            Text(L(L10n.Benchmark.heading)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Text("\(history.records.count)")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.trailing, 16)
    }

    /// 기록 1행: 상태점+전체 틴트+호버 메뉴 (채팅식).
    private func benchmarkRow(_ rec: BenchmarkRecord) -> some View {
        let selected = rec.id == history.selectedRecordID
        return HStack(spacing: 8) {
            Circle().fill(statusColor(rec.status)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(ModelAlias.display(id: rec.modelID))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                Text("\(rec.route.title) · \(rec.status.title) · \(speedText(rec))")
                    .font(DS.captionFont).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if hoverID == rec.id || selected {
                Menu {
                    Button(L(L10n.Benchmark.delete), systemImage: "trash", role: .destructive) {
                        history.remove(rec.id)
                    }
                    .disabled(bench.running)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help(L(L10n.Benchmark.menu))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8).fill(DSColor.primary.opacity(0.15))
            }
        }
        .contentShape(Rectangle())
        .help(ModelAlias.display(id: rec.modelID))
        .onTapGesture {
            history.selectedRecordID = rec.id
            NotificationCenter.default.post(name: .openBenchmark, object: nil)
        }
        .onHover { hoverID = $0 ? rec.id : nil }
        .contextMenu {
            Button(L(L10n.Benchmark.delete), systemImage: "trash", role: .destructive) {
                history.remove(rec.id)
            }
            .disabled(bench.running)
        }
        .opacity(bench.running ? 0.7 : 1)
    }

    private func statusColor(_ status: BenchmarkStatus) -> Color {
        switch status {
        case .done: DSColor.success
        case .cancelled: DSColor.warning
        case .failed: DSColor.error
        }
    }

    private func speedText(_ rec: BenchmarkRecord) -> String {
        guard let met = rec.metrics else { return L(L10n.Benchmark.noRecord) }
        return L(L10n.Benchmark.perSecond, met.decodeSpeed)
    }
}
