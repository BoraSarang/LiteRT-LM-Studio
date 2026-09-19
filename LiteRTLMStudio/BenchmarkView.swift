import Charts
import Combine
import SwiftUI

/// 벤치마크 별도창 (T-216/T-217/T-218): 모델·모드 선택+수동 시작, 히스토리, AI 분석.
/// 정렬 규칙: 데이터 있음 좌측·상단, 빈 히스토리는 중앙 문구.
/// 섹션 본문은 BenchmarkWindowSections.swift (파일 길이 분산).
struct BenchmarkWindowView: View {
    @ObservedObject var store: BenchmarkStore
    @ObservedObject var history: BenchmarkHistoryStore
    @ObservedObject var models: ModelStore
    @ObservedObject var chat: ChatStore

    // T-222: 섹션 파일에서 접근하므로 internal.
    @State var selectedModelID = ""
    @State var selectedRoute: EngineMode = .cli
    @State var filterModel = BenchmarkHistoryStore.allModelsToken
    @State var showPrompt = false
    @State var mtpOn: Bool?
    @State var battery: BatteryStatus?
    @StateObject var copyFlag = CopyFlag() // T-223 분석 복사 피드백

    var body: some View {
        HSplitView {
            historyPane
                .frame(width: 264)
                .padding(.trailing, 8)
                .background(Color(nsColor: .controlBackgroundColor))
            measurePane
                .frame(maxWidth: .infinity)
                .padding(.leading, 8)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .padding(16)
        .task {
            if selectedModelID.isEmpty {
                selectedModelID = store.pendingModelID ?? chat.model
            }
            selectedRoute = store.pendingRoute
            refreshPower()
            await models.refreshIfEmpty()
        }
        .onChange(of: store.pendingModelID) { _, v in
            if let v, !v.isEmpty { selectedModelID = v }
        }
        .onChange(of: selectedModelID) { _, v in
            if !store.running { store.prepare(modelID: v, route: selectedRoute) }
            refreshPower()
        }
        .onChange(of: selectedRoute) { _, v in
            if !store.running, !selectedModelID.isEmpty { store.prepare(modelID: selectedModelID, route: v) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openBenchmark)) { n in
            // T-221/T-225: 사이드바에서 넘긴 기록 선택 (nil이면 기존 선택 유지).
            if let id = n.object as? BenchmarkRecord.ID { history.selectedRecordID = id }
        }
        .onChange(of: history.selectedRecordID) { _, _ in
            // T-224: 기록을 바꾸면 이전 분석 에러는 지운다 (결과는 슬롯별 유지).
            store.analysisError = nil
        }
    }
}
