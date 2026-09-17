import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 상태 복원 (T-216 분리: 파일 길이 분산)

extension ContentView {

    /// T-216: 앱 시작 상태 복원 (T-126: .task 본문 분리로 타입 추론 부하 분산).
    func restoreState() async {
        await uv.refresh()
        // T-257: 중간에 uv가 사라졌으면 게이트로 복귀.
        if !uv.uvAvailable {
            onboardingDone = false
            return
        }
        await models.refresh()
        // T-279: 구 SceneStorage 선택 1회 승계 (이후 AppStorage 유지).
        if selectedModelID == nil {
            selectedModelID = legacySelectedModelID
        }
        let modelID = selectedModelID ?? models.models.first?.id ?? "gemma4-12b"
        config.load(modelID: modelID)
        if await daemon.isHealthy() {
            daemon.status = .running
            daemon.external = true
        }
        chat.model = selectedModelID ?? chat.model
        wireBenchmark()
        await wigolo.ensureRunning() // T-284: 웹검색 켜짐+설치됨이면 serve 자동 시작
        monitor.start()
        monitor.daemonRunning = daemon.status == .running
        daemon.beginPolling()
        // Dock 정책·외관은 화면 표시 이후 적용 (App.init 시점 호출 금지).
        NSApp.setActivationPolicy(UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory)
        AppearanceMode.apply(appearanceMode)
        logger.info(feature: "앱시작", "상태 복원 완료")
    }

    /// 네이티브 자동 초기화 판정 (순수, 테스트 가능, T-275):
    /// 경로 native + 모델 선택 + 미준비 + 준비 중 아님 + 전송 중 아님.
    nonisolated static func shouldAutoPrepare(route: EngineMode, modelID: String?,
                                              preparedID: String?, preparing: Bool,
                                              streaming: Bool) -> Bool {
        guard route == .native, let modelID, !modelID.isEmpty else { return false }
        guard preparedID != modelID else { return false }
        return !preparing && !streaming
    }

    /// 네이티브 자동 초기화 실행 (T-275): 경로 전환·모델 변경 시 호출.
    /// 재실행 복원 시에는 호출 안 함 (예상 밖 메모리·시간 방지).
    func autoPrepareNativeIfNeeded() {
        let modelID = selectedModelID ?? models.models.first?.id
        guard Self.shouldAutoPrepare(route: chat.route, modelID: modelID,
                                     preparedID: nativeEngine.preparedModelID,
                                     preparing: nativeEngine.state == .preparing,
                                     streaming: chat.streaming),
              let id = modelID else { return }
        logger.info(feature: "네이티브엔진", "자동 초기화 시작 (\(ModelAlias.display(id: id)))")
        Task { try? await nativeEngine.prepare(modelID: id) }
    }

    /// T-216: 벤치마크 공유 인스턴스 연결 (측정 제공자+기록 전달).
    func wireBenchmark() {
        let engine = nativeEngine
        let history = benchHistory
        bench.nativeBenchmarkStaged = { modelID, onStage in
            try await engine.benchmarkWithProgress(modelID: modelID, onStage: onStage)
        }
        bench.nativeBenchmark = { modelID in
            try await engine.benchmark(modelID: modelID)
        }
        bench.onRecord = { record in
            history.append(record, retention: BenchmarkRetention.current())
        }
    }

}
