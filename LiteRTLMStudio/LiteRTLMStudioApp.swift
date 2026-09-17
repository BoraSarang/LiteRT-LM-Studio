import AppKit
import SwiftUI

@main
struct LiteRTLMStudioApp: App {
    @StateObject private var services = AppServices()
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("onboardingDone") private var onboardingDone = false

    // 주의: init에서 NSApp 호출 금지 (테스트 부트스트랩 크래시).
    // 정책 적용은 ContentView.task + 설정 토글에서 수행.
    var body: some Scene {
        // 단일 창: openWindow(id:)가 기존 창을 앞으로 올림 (중복 생성 방지).
        Window("LiteRT-LM Studio", id: "main") {
            // T-257 온보딩 게이트: 미통과 시 랜딩, 통과 후 메인.
            if onboardingDone {
                ContentView(models: services.models, daemon: services.daemon, monitor: services.monitor,
                            nativeEngine: services.nativeEngine, chat: services.chat,
                            bench: services.bench, benchHistory: services.benchHistory,
                            releases: services.releases,
                            wigolo: services.wigolo, config: services.config)
                    .frame(minWidth: 1000, minHeight: 640)
                    .background {
                        WindowAccessor { $0?.setFrameAutosaveName("LiteRTLMStudioMain") }
                    }
            } else {
                LandingView(done: $onboardingDone)
            }
        }
        .defaultSize(width: 1340, height: 800) // T-092 계산치: 사이드바 220+열 768+여백 32+인스펙터 320
        .windowToolbarStyle(.unified)
        // 디버그 별도 윈도우 (T-053): 시트 대신 독립 창.
        Window("디버그 패널", id: "debug") {
            DebugPanelView()
                .frame(minWidth: 680, minHeight: 420)
        }
        .defaultSize(width: 760, height: 500)
        // 벤치마크 별도 윈도우 (T-216): 시트 대신 독립 창 (모델·모드 선택+히스토리).
        Window("벤치마크", id: "benchmark") {
            BenchmarkWindowView(store: services.bench, history: services.benchHistory,
                                models: services.models, chat: services.chat)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 960, height: 640)
        // 모델 관리 별도창 (T-232): 가져오기·목록·설치·삭제·이름변경.
        Window("모델 관리", id: "modelManager") {
            ModelManagerView(models: services.models, center: services.downloads)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1080, height: 700)
        // 정보 창 (T-068, TubeKeep AboutView 구조).
        Window("정보", id: "about") {
            AboutView()
        }
        .defaultSize(width: 560, height: 460)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("LiteRT-LM Studio 정보") {
                    NotificationCenter.default.post(name: .openAbout, object: nil)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("새 채팅") { NotificationCenter.default.post(name: .newChat, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("서버") {
                Button("서버 시작") { NotificationCenter.default.post(name: .serverStart, object: nil) }
                    .keyboardShortcut("r", modifiers: .command)
                Button("서버 중지") { NotificationCenter.default.post(name: .serverStop, object: nil) }
                    .keyboardShortcut(".", modifiers: .command)
            }
            CommandMenu("보기") {
                Button("확대") { NotificationCenter.default.post(name: .chatZoomIn, object: nil) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("축소") { NotificationCenter.default.post(name: .chatZoomOut, object: nil) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("실제 크기") { NotificationCenter.default.post(name: .chatZoomReset, object: nil) }
                    .keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("인스펙터 토글") { NotificationCenter.default.post(name: .toggleInspector, object: nil) }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Button("하단 패널 토글") { NotificationCenter.default.post(name: .toggleLogPanel, object: nil) }
                    .keyboardShortcut("j", modifiers: .command)
                Button("디버그 패널") { NotificationCenter.default.post(name: .toggleDebug, object: nil) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appTermination) {
                Button("LiteRT-LM Studio 종료") { services.quit() }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        MenuBarExtra {
            MenuBarView()
                .environmentObject(services)
        } label: {
            MenuBarLabel()
                .environmentObject(services)
        }
        .menuBarExtraStyle(.menu)
        Settings { SettingsView(wigolo: services.wigolo, config: services.config) }
    }
}

/// 윈도우 타이틀 동기화 (T-142): 좌측 타이틀=현재 채팅방. title 변경 때만 NSWindow.title 갱신.
struct WindowTitleSync: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.last != title else { return }
        context.coordinator.last = title
        DispatchQueue.main.async { [weak nsView, title] in
            guard let window = nsView?.window, window.title != title else { return }
            window.title = title
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var last = ""
    }
}

/// NSWindow 포착 (T-092): 프레임 자동 저장용. 최초 1회만 적용.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.done else { return }
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            window.setFrameAutosaveName("LiteRTLMStudioMain")
            coordinator.done = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var done = false
    }
}
