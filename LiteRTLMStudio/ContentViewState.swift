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
        let modelID = selectedModelID ?? models.models.first?.id ?? "gemma4-12b"
        config.load(modelID: modelID)
        if await daemon.isHealthy() {
            daemon.status = .running
            daemon.external = true
        }
        chat.model = selectedModelID ?? chat.model
        wireBenchmark()
        monitor.start()
        monitor.daemonRunning = daemon.status == .running
        daemon.beginPolling()
        // Dock 정책·외관은 화면 표시 이후 적용 (App.init 시점 호출 금지).
        NSApp.setActivationPolicy(UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory)
        AppearanceMode.apply(appearanceMode)
        logger.info(feature: "앱시작", "상태 복원 완료")
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
