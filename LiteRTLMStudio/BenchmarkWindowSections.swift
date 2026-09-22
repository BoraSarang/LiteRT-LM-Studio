import Charts
import Combine
import SwiftUI

// MARK: - 벤치마크 창 섹션 (T-222 분리: 파일 길이 분산)

extension BenchmarkWindowView {
    var modelIDs: [String] { models.models.map(\.id) }

    var filteredRecords: [BenchmarkRecord] {
        BenchmarkHistoryStore.filtered(history.records, modelID: filterModel)
    }

    var selectedRecord: BenchmarkRecord? {
        if let id = history.selectedRecordID {
            return history.records.first(where: { $0.id == id })
        }
        return nil
    }

    var avgDuration: TimeInterval? {
        guard !selectedModelID.isEmpty else { return nil }
        return BenchmarkHistoryStore.averageDuration(history.records, modelID: selectedModelID)
    }

    // MARK: - 좌측 히스토리

    var historyPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(L10n.Benchmark.records)).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                Text(L(L10n.Benchmark.filter)).font(DS.captionFont).foregroundStyle(.secondary)
                Picker("", selection: $filterModel) {
                    Text(L(L10n.Benchmark.allRecords)).tag(BenchmarkHistoryStore.allModelsToken)
                    ForEach(modelIDs, id: \.self) { id in
                        Text(ModelAlias.display(id: id)).tag(id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if filteredRecords.isEmpty {
                ContentUnavailableView(L(L10n.Benchmark.noRecordsTitle),
                                       systemImage: "gauge.with.dots.needle.0.percent",
                                       description: Text(L(L10n.Benchmark.noRecordsDesc)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredRecords, selection: $history.selectedRecordID) { rec in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(statusColor(rec.status)).frame(width: 7, height: 7)
                            Text(ModelAlias.display(id: rec.modelID))
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1).truncationMode(.tail)
                            Spacer()
                            Text(shortDate(rec.date)).font(DS.captionFont).foregroundStyle(.secondary)
                        }
                        Text("\(rec.route.title) · \(rec.status.title) · \(speedText(rec))")
                            .font(DS.captionFont).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                        if rec.status == .failed {
                            Text(failureReason(rec))
                                .font(DS.captionFont).foregroundStyle(.red)
                                .lineLimit(2).truncationMode(.tail)
                        }
                    }
                    .tag(rec.id)
                    .help(ModelAlias.display(id: rec.modelID))
                    .contextMenu {
                        Button(L(L10n.Benchmark.delete), role: .destructive) { history.remove(rec.id) }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            HStack {
                Spacer()
                Button(L(L10n.Benchmark.clearAll)) { history.clear() }
                    .buttonStyle(.link).font(DS.captionFont)
                    .disabled(history.records.isEmpty)
            }
        }
    }

    // MARK: - 우측 측정+결과

    /// T-226: 새 측정 영역은 상단 고정, 결과만 아래에서 스크롤.
    var measurePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            setupSection
                .padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.running {
                        runningSection
                    } else if let rec = selectedRecord {
                        // T-221: 명시적 선택이 최우선 (라이브 metrics가 있어도 기록 표시).
                        recordSection(rec)
                    } else if let met = store.metrics, store.stage == .done {
                        resultSection(met, record: nil)
                    } else if let rec = history.records.first {
                        recordSection(rec)
                    } else {
                        ContentUnavailableView(
                            L(L10n.Benchmark.beforeMeasureTitle), systemImage: "play.circle",
                            description: Text(L(L10n.Benchmark.beforeMeasureDesc)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 12) // T-335 맨 아래 잘림 방지
            }
        }
    }

    func resultSection(_ met: BenchmarkStore.Metrics, record: BenchmarkRecord?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(resultSummary(met))
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
            analysisSection(record: record, metrics: met)
            if let record {
                DisclosureGroup(L(L10n.Benchmark.rawOutput)) { recordLogView(record.logTail) }
            } else {
                DisclosureGroup(L(L10n.Benchmark.rawOutput)) { logSection }
            }
        }
    }

    func recordSection(_ rec: BenchmarkRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(statusColor(rec.status)).frame(width: 7, height: 7)
                Text("\(ModelAlias.display(id: rec.modelID)) · \(rec.route.title) · \(rec.status.title)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(L(L10n.Benchmark.elapsed, BenchmarkStore.elapsedText(rec.durationSec)))
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            if let met = rec.metrics {
                resultSection(met, record: rec)
            } else {
                Text(emptyRecordText(rec))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                recordLogView(rec.logTail)
            }
        }
    }
}

// MARK: - 공용 조각·문구 (타입 본문 길이 분산)

extension BenchmarkWindowView {
    /// T-222: MTP·배터리 상태 갱신 (MTP는 파일 직독, 배터리는 pmset).
    func refreshPower() {
        mtpOn = selectedModelID.isEmpty ? nil : ConfigStore.savedMTP(modelID: selectedModelID)
        Task { battery = await BatteryStatus.read() }
    }

    private var powerStatus: (text: String, warn: Bool) {
        BatteryStatus.powerLine(mtp: mtpOn, battery: battery)
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(L10n.Benchmark.newMeasurement)).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Picker(L(L10n.Benchmark.modelPicker), selection: $selectedModelID) {
                    ForEach(modelIDs, id: \.self) { id in
                        Text(ModelAlias.display(id: id)).tag(id)
                    }
                }
                .pickerStyle(.menu).frame(maxWidth: 220)
                Picker(L(L10n.Benchmark.modePicker), selection: $selectedRoute) {
                    ForEach(EngineMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented).frame(maxWidth: 200)
            }
            Text(BenchmarkStore.estimateText(route: selectedRoute, avgDuration: avgDuration))
                .font(DS.captionFont).foregroundStyle(.secondary)
            if powerStatus.warn {
                HStack(spacing: 4) {
                    Label(powerStatus.text, systemImage: "exclamationmark.triangle")
                        .font(DS.captionFont).foregroundStyle(.orange)
                        .help(L(L10n.Benchmark.mtpUnstableHelp))
                    Image(systemName: "info.circle")
                        .font(DS.captionFont).foregroundStyle(.secondary)
                        .help(L(L10n.Benchmark.batteryHelp))
                }
            } else {
                Text(powerStatus.text)
                    .font(DS.captionFont).foregroundStyle(.secondary)
                    .help(L(L10n.Benchmark.mtpHelp))
            }
            if selectedRoute == .cli {
                Label(cliWarningText, systemImage: "exclamationmark.triangle")
                    .font(DS.captionFont).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                if store.running {
                    Button(L(L10n.Benchmark.stop)) { store.cancel() }.keyboardShortcut(".", modifiers: .command)
                } else {
                    Button(L(L10n.Benchmark.startMeasure)) {
                        history.selectedRecordID = nil // T-221: 새 측정 시작 시 선택 해제
                        store.prepare(modelID: selectedModelID, route: selectedRoute)
                        store.start()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedModelID.isEmpty)
                }
                if store.running {
                    Text(L(L10n.Benchmark.elapsedShort, BenchmarkStore.elapsedText(store.elapsed)))
                        .font(DS.captionFont).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(BenchmarkStore.Stage.allCases, id: \.self) { step in
                    stageChip(step)
                    if step != .done { stageChevron }
                }
            }
            if store.stage == .measure {
                Text(measureProgressText)
                    .font(DS.captionFont).foregroundStyle(.secondary)
            } else {
                Text(stageProgressText)
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            if let met = store.metrics, met.decodeSpeed > 0 {
                miniChart(met)
            }
            logSection
        }
    }

    private var stageProgressText: String {
        L(L10n.Benchmark.stageProgress, store.stage.title, BenchmarkStore.elapsedText(store.elapsed))
    }

    private var cliWarningText: String {
        L(L10n.Benchmark.cliTimeout)
    }

    private var measureProgressText: String {
        L(L10n.Benchmark.iterProgress, store.currentIter, store.totalIter, BenchmarkStore.elapsedText(store.elapsed))
    }

    private func resultSummary(_ met: BenchmarkStore.Metrics) -> String {
        L(L10n.Benchmark.backendSummary, met.backend, met.prefillTokens, met.decodeTokens)
    }

    private func emptyRecordText(_ rec: BenchmarkRecord) -> String {
        rec.status == .cancelled
            ? L(L10n.Benchmark.cancelledNoResult) : L(L10n.Benchmark.failedNoResult)
    }

    /// 실패 사유 1줄 (T-320): 로그 꼬리 첫 줄, 없으면 상태 문구.
    private func failureReason(_ rec: BenchmarkRecord) -> String {
        if let line = rec.logTail.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return String(line.prefix(120))
        }
        return emptyRecordText(rec)
    }

    /// T-224: 기록별 원문 로그 (없으면 안내).
    private func recordLogView(_ logs: [String]) -> some View {
        Group {
            if logs.isEmpty {
                Text(L(L10n.Benchmark.noSavedLog))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(logs.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 100, maxHeight: 200)
            }
        }
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

    private func miniChart(_ met: BenchmarkStore.Metrics) -> some View {
        Chart {
            BarMark(x: .value(L(L10n.Benchmark.chartSection), L(L10n.Benchmark.chartPrefill)),
                    y: .value(L(L10n.Benchmark.chartPerSecond), met.prefillSpeed))
                .annotation(position: .top) {
                    Text(String(format: "%.1f", met.prefillSpeed))
                        .font(DS.captionFont).foregroundStyle(.secondary)
                }
            BarMark(x: .value(L(L10n.Benchmark.chartSection), L(L10n.Benchmark.chartDecode)),
                    y: .value(L(L10n.Benchmark.chartPerSecond), met.decodeSpeed))
                .annotation(position: .top) {
                    Text(String(format: "%.1f", met.decodeSpeed))
                        .font(DS.captionFont).foregroundStyle(.secondary)
                }
        }
        .chartYAxisLabel(L(L10n.Benchmark.chartPerSecond))
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
        .frame(minHeight: 100, maxHeight: 200)
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

    private func shortDate(_ date: Date) -> String {
        TimeFormat.shortDateTime(date)
    }
}
