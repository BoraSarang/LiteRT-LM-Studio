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
            Text("기록").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                Text("필터").font(DS.captionFont).foregroundStyle(.secondary)
                Picker("", selection: $filterModel) {
                    Text("전체 기록").tag("전체 기록")
                    ForEach(modelIDs, id: \.self) { id in
                        Text(ModelAlias.display(id: id)).tag(id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if filteredRecords.isEmpty {
                ContentUnavailableView("기록이 없어요", systemImage: "gauge.with.dots.needle.0.percent",
                                       description: Text("측정을 시작하면 결과가 여기에 쌓여요."))
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
                        Button("삭제", role: .destructive) { history.remove(rec.id) }
                    }
                }
                .listStyle(.sidebar)
            }
            HStack {
                Spacer()
                Button("전체 지우기") { history.clear() }
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
                            "측정 전이에요", systemImage: "play.circle",
                            description: Text("모델과 모드를 고르고 측정을 시작하세요."))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
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
                DisclosureGroup("원문 출력") { recordLogView(record.logTail) }
            } else {
                DisclosureGroup("원문 출력") { logSection }
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
                Text("소요 \(BenchmarkStore.elapsedText(rec.durationSec))")
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
            Text("새 측정").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Picker("모델", selection: $selectedModelID) {
                    ForEach(modelIDs, id: \.self) { id in
                        Text(ModelAlias.display(id: id)).tag(id)
                    }
                }
                .pickerStyle(.menu).frame(maxWidth: 220)
                Picker("모드", selection: $selectedRoute) {
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
                        .help("MTP(추측적 디코딩)가 켜져 있거나 배터리가 20% 이하로 방전 중이면 측정값이 흔들릴 수 있어요.")
                    Image(systemName: "info.circle")
                        .font(DS.captionFont).foregroundStyle(.secondary)
                        .help("배터리 절약 모드에서는 추측적 디코딩(MTP) 가속이 제한됩니다")
                }
            } else {
                Text(powerStatus.text)
                    .font(DS.captionFont).foregroundStyle(.secondary)
                    .help("MTP는 기본 꺼짐. 켜면 가속되지만 측정값이 달라질 수 있어요.")
            }
            if selectedRoute == .cli {
                Label(cliWarningText, systemImage: "exclamationmark.triangle")
                    .font(DS.captionFont).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                if store.running {
                    Button("중지") { store.cancel() }.keyboardShortcut(".", modifiers: .command)
                } else {
                    Button("측정 시작") {
                        history.selectedRecordID = nil // T-221: 새 측정 시작 시 선택 해제
                        store.prepare(modelID: selectedModelID, route: selectedRoute)
                        store.start()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedModelID.isEmpty)
                }
                if store.running {
                    Text("경과 \(BenchmarkStore.elapsedText(store.elapsed))")
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
        "\(store.stage.title) 진행 중… · 경과 \(BenchmarkStore.elapsedText(store.elapsed))"
    }

    private var cliWarningText: String {
        "CLI는 12B급에서 워밍업 10분을 넘기면 타임아웃될 수 있어요. "
            + "중지(⌘.) 후 앱 내 엔진으로 시도해 보세요."
    }

    private var measureProgressText: String {
        "반복 \(store.currentIter)/\(store.totalIter) 측정 중… · "
            + "경과 \(BenchmarkStore.elapsedText(store.elapsed))"
    }

    private func resultSummary(_ met: BenchmarkStore.Metrics) -> String {
        "백엔드 \(met.backend) · 프리필 \(met.prefillTokens)토큰 · 디코드 \(met.decodeTokens)토큰"
    }

    private func emptyRecordText(_ rec: BenchmarkRecord) -> String {
        rec.status == .cancelled
            ? "사용자 중단으로 결과가 없어요." : "실패로 결과가 없어요. 로그를 확인해 주세요."
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
                Text("저장된 원문이 없어요 (이전 버전 기록).")
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
            BarMark(x: .value("구간", "입력 처리"), y: .value("초당 토큰", met.prefillSpeed))
                .annotation(position: .top) {
                    Text(String(format: "%.1f", met.prefillSpeed))
                        .font(DS.captionFont).foregroundStyle(.secondary)
                }
            BarMark(x: .value("구간", "답 생성"), y: .value("초당 토큰", met.decodeSpeed))
                .annotation(position: .top) {
                    Text(String(format: "%.1f", met.decodeSpeed))
                        .font(DS.captionFont).foregroundStyle(.secondary)
                }
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
        guard let met = rec.metrics else { return "기록 없음" }
        return String(format: "%.1f 토큰/초", met.decodeSpeed)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
