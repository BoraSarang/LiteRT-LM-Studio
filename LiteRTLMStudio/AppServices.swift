import AppKit
import ServiceManagement
import SwiftUI

/// 앱 전역 공유 서비스 (메인 창·메뉴바가 같은 인스턴스 사용).
@MainActor
final class AppServices: ObservableObject {
    let daemon = DaemonManager()
    let monitor = SystemMonitor()
    let nativeEngine = NativeEngine()
    /// T-216/T-217: 벤치마크 창·사이드바가 공유하는 단일 인스턴스 (창 닫아도 유지).
    let bench = BenchmarkStore()
    let benchHistory = BenchmarkHistoryStore()
    /// T-233: 다운로드 진행 보관 (관리 창 닫아도 유지·재오픈 시 표시).
    let downloads = DownloadCenter()
    /// T-216: 벤치마크 창에서 모델 목록·현재 채팅 모델(분석용)을 공유.
    let chat = ChatStore()
    let models = ModelStore()
    /// T-262: 새소식 누적 캐시 (웰컴 빈 화면이 공유, 창 닫아도 유지).
    let releases = ReleaseNotes()

    private let logger = DebugLogger.shared

    init() {
        Self.migrateLegacyDefaults()
        chat.inferenceEngine = nativeEngine
        // Dock 메뉴 종료 등 모든 종료 경로에서 데몬 정리.
        // willTerminate 퇴출 중에는 런루프가 돌지 않으므로 동기 실행 필수 (Task 비동기는 실행 보장 없음).
        // queue:nil = 게시 스레드(항상 메인)에서 동기 전달.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
    }

    /// 구 번들 설정 이사 (T-060, 1회): UserDefaults는 번들ID 기준이라 개명 시 초기화됨.
    /// SceneStorage 2종(selectedModelID·logPanelVisible)은 이사 불가, 로그인 항목은 설정 재토글.
    nonisolated static func migrateLegacyDefaults() {
        let keys = ["appearance", "engineMode", "inspectorVisible", "launchAtLogin", "quitStopsDaemon",
                    "sessionSort", "showBackend", "showGenerate", "showInDock", "showSystem"]
        let old = UserDefaults(suiteName: "com.borasarang.litertlm-manager")
        var moved = false
        for k in keys {
            if UserDefaults.standard.object(forKey: k) == nil, let v = old?.object(forKey: k) {
                UserDefaults.standard.set(v, forKey: k)
                moved = true
            }
        }
        if moved {
            DebugLogger.shared.info(feature: "앱시작", "구 설정 이사 완료")
        }
    }

    /// 종료 시 데몬 정리. 외부(터미널) 데몬은 건드리지 않는다.
    func shutdown() {
        guard Self.shouldStopDaemon(stopOnQuit: stopOnQuit,
                                    external: daemon.external,
                                    status: daemon.status) else {
            logger.info(feature: "앱종료", "데몬 유지 (외부=\(daemon.external))")
            return
        }
        logger.info(feature: "앱종료", "앱 소유 데몬 종료 후 앱 종료")
        daemon.stop()
    }

    /// 설정 직접 읽기 (@AppStorage 래퍼 대신 — 종료 경로에서 최신값 보장, 미설정 시 true).
    private var stopOnQuit: Bool {
        UserDefaults.standard.object(forKey: "quitStopsDaemon") as? Bool ?? true
    }

    /// 종료 정리 판정 (순수, 테스트 가능).
    nonisolated static func shouldStopDaemon(stopOnQuit: Bool, external: Bool,
                                             status: DaemonManager.Status) -> Bool {
        stopOnQuit && !external && status == .running
    }

    func quit() {
        shutdown()
        NSApp.terminate(nil)
    }
}
