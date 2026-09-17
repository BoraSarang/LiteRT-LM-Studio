import SwiftUI

// MARK: - T-218 AI 분석 프롬프트·작업 (순수, 테스트 가능)

/// 분석 프롬프트 조립 (순수, 테스트 가능 — 화면 "프롬프트 보기"와 동일 문구).
struct BenchmarkAnalyzer {
    static func prompt(record: BenchmarkRecord, avgDuration: TimeInterval?) -> String {
        let met = record.metrics
        let resultJSON = """
            {"model":"\(record.modelID)","route":"\(record.route.title)",\
            "initTime":\(fmt(met?.initTime)),"ttft":\(fmt(met?.ttft)),\
            "prefillSpeed":\(fmt(met?.prefillSpeed)),"decodeSpeed":\(fmt(met?.decodeSpeed)),\
            "prefillTokens":\(met?.prefillTokens ?? 0),"decodeTokens":\(met?.decodeTokens ?? 0),\
            "durationSec":\(String(format: "%.0f", record.durationSec)),"status":"\(record.status.title)"}
            """
        let avgJSON: String
        if let avg = avgDuration {
            avgJSON = "{\"avgDurationSec\":\(String(format: "%.0f", avg))}"
        } else {
            avgJSON = "\"없음\""
        }
        return """
            당신은 온디바이스 LLM 성능 분석가입니다. 아래 벤치마크 JSON을 한국어로 분석하세요.
            출력은 마크다운, 4섹션 고정.
            - ## 요약 (3줄)
            - ## 지표 해석 (TTFT·prefill·decode·init 각각 체감 기준)
            - ## 이전 기록과 비교 (avg 대비 증감 %, 없으면 단독 평가)
            - ## 개선 제안 (구체 3개: 짧게 답 요청, KV 재사용, GPU/CPU 설정 확인).
            과장 금지, 숫자는 소수1자리, 불확실하면 "측정 1회라 단정 불가"라고 명시.

            [이번 결과]
            \(resultJSON)

            [최근 같은 모델 평균 (최대 5건)]
            \(avgJSON)
            """
    }

    private static func fmt(_ v: Double?) -> String { String(format: "%.1f", v ?? 0) }
}

extension BenchmarkStore {
    /// 분석 작업 묶음 (T-223, 순수, 테스트 가능): 프롬프트+엔진 표기 스냅샷.
    /// 엔진 표기는 측정한 경로 기준 (T-227).
    struct AnalysisJob: Equatable {
        var prompt: String
        var engineLabel: String

        nonisolated static func make(record: BenchmarkRecord, avgDuration: TimeInterval?,
                                     modelDisplay: String) -> AnalysisJob {
            AnalysisJob(prompt: BenchmarkAnalyzer.prompt(record: record, avgDuration: avgDuration),
                        engineLabel: "\(modelDisplay)·\(record.route.title)")
        }
    }
}

// MARK: - T-218/T-223/T-224 분석 섹션 (기록 슬롯별 표시+복사)

extension BenchmarkWindowView {
    func analysisSection(record: BenchmarkRecord?,
                         metrics: BenchmarkStore.Metrics) -> some View {
        let rec = analysisTarget(record: record, metrics: metrics)
        let slotID = record?.id
        let shown = shownAnalysis(slotID: slotID)
        let busy = store.analyzing && store.analyzingSlotID == slotID
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("AI 분석").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("측정 \(rec.route.title) · 분석 \(shownEngine(slotID: slotID))")
                    .font(DS.captionFont).foregroundStyle(.secondary)
                Button {
                    PasteboardUtil.copy(shown)
                    copyFlag.mark()
                } label: {
                    Image(systemName: copyFlag.copied ? "checkmark" : "square.on.square")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(shown.isEmpty)
                .help("분석 결과 복사")
            }
            if busy {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                    Text("분석 중…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else if !shown.isEmpty {
                MarkdownView(text: shown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button("분석 시작") {
                    let avg = BenchmarkHistoryStore.averageDuration(history.records, modelID: rec.modelID)
                    store.analyze(record: rec, avgDuration: avg, chat: chat, slotID: slotID)
                }
                .disabled(analysisDisabled(for: rec) || store.analyzing)
                .help("측정한 경로의 모델로 결과를 해석하고 개선안을 제안합니다.")
            }
            if let err = store.analysisError {
                Text(err).font(.system(size: 12)).foregroundStyle(.red)
            }
            DisclosureGroup("분석 프롬프트 보기", isExpanded: $showPrompt) {
                Text(promptPreview(rec))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(DS.captionFont)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBox(padding: 10, background: Color(.textBackgroundColor).opacity(0.5), stroked: false)
    }

    /// T-224: 슬롯별 표시 분석문 (기록 슬롯 or 라이브).
    private func shownAnalysis(slotID: BenchmarkRecord.ID?) -> String {
        if let slotID { return store.analysisCache[slotID] ?? "" }
        return store.analysisMarkdown
    }

    /// T-223: 슬롯별 분석 엔진 표기 (없으면 현재 채팅 엔진).
    private func shownEngine(slotID: BenchmarkRecord.ID?) -> String {
        if let slotID, let label = store.analysisEngineByRecord[slotID], !label.isEmpty {
            return label
        }
        if slotID == nil, !store.analysisEngineLabel.isEmpty {
            return store.analysisEngineLabel
        }
        return "\(ModelAlias.display(id: chat.model))·\(chat.route.title)"
    }

    private func analysisTarget(record: BenchmarkRecord?,
                                metrics: BenchmarkStore.Metrics) -> BenchmarkRecord {
        record ?? BenchmarkRecord(
            modelID: selectedModelID.isEmpty ? (store.pendingModelID ?? "") : selectedModelID,
            route: selectedRoute, metrics: metrics,
            durationSec: store.elapsed, status: .done)
    }

    /// T-227: 앱 내 엔진 기록은 해당 모델로 준비된 엔진이 있어야 시작 가능.
    private func analysisDisabled(for rec: BenchmarkRecord) -> Bool {
        rec.route == .native && chat.inferenceEngine?.preparedModelID != rec.modelID
    }

    private func promptPreview(_ rec: BenchmarkRecord) -> String {
        let avg = BenchmarkHistoryStore.averageDuration(history.records, modelID: rec.modelID)
        return BenchmarkAnalyzer.prompt(record: rec, avgDuration: avg)
    }
}
