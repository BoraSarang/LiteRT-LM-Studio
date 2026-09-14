import AppKit
import ServiceManagement
import SwiftUI

/// 앱 전역 공유 서비스 (메인 창·메뉴바가 같은 인스턴스 사용).
@MainActor
final class AppServices: ObservableObject {
    let daemon = DaemonManager()
    let monitor = SystemMonitor()

    private let logger = DebugLogger.shared

    init() {
        Self.migrateLegacyDefaults()
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
        let keys = ["appearance", "inspectorVisible", "launchAtLogin", "quitStopsDaemon",
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

@main
struct LiteRTLMStudioApp: App {
    @StateObject private var services = AppServices()
    @AppStorage("showInDock") private var showInDock = false

    // 주의: init에서 NSApp 호출 금지 (테스트 부트스트랩 크래시).
    // 정책 적용은 ContentView.task + 설정 토글에서 수행.
    var body: some Scene {
        // 단일 창: openWindow(id:)가 기존 창을 앞으로 올림 (중복 생성 방지).
        Window("LiteRT-LM Studio", id: "main") {
            ContentView(daemon: services.daemon, monitor: services.monitor)
                .frame(minWidth: 1000, minHeight: 640)
                .background {
                    WindowAccessor { $0?.setFrameAutosaveName("LiteRTLMStudioMain") }
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
        Settings { SettingsView() }
    }
}

/// 메뉴바 아이콘: 칩 템플릿 + 상태 점 (Ollama식).
struct MenuBarLabel: View {
    @EnvironmentObject var services: AppServices

    var body: some View {
        HStack(spacing: 4) {
            if let chip = NSImage(named: "MenuBarChip") {
                Image(nsImage: chip)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "brain")
            }
            Circle().fill(MenuStatus.dotColor(for: services.daemon.status))
                .frame(width: 7, height: 7)
        }
    }
}

/// 상태→색 매핑 (순수, 테스트 가능).
enum MenuStatus {
    static func dotColor(for status: DaemonManager.Status) -> Color {
        switch status {
        case .running: .green
        case .starting: .orange
        case .failed: .red
        case .stopped: .gray
        }
    }

    static func dotKey(for status: DaemonManager.Status) -> String {
        switch status {
        case .running: "green"
        case .starting: "orange"
        case .failed: "red"
        case .stopped: "gray"
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var services: AppServices
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine).foregroundStyle(.secondary)
        Button("메인 창 열기") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if services.daemon.status == .running {
            if services.daemon.external {
                Button("외부 연결 끊기") { services.daemon.stop() }
            } else {
                Button("서버 중지") { services.daemon.stop() }
            }
        } else {
            Button("서버 시작") { Task { await services.daemon.start() } }
                .disabled(services.daemon.status == .starting)
        }
        Divider()
        Button("하단 패널 토글") { deliver(.toggleLogPanel) }
        Button("디버그 패널") {
            openWindow(id: "debug")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        SettingsLink(label: { Text("설정…") })
        Button("정보") {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("종료") { services.quit() }
    }

    /// 창이 닫혀 있어도 동작 보장: 먼저 열고 ContentView 부착 후 전달.
    private func deliver(_ name: Notification.Name) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    private var statusLine: String {        switch services.daemon.status {
        case .running: "● 실행 중\(services.daemon.external ? " (외부)" : "") · :9379"
        case .starting: "◌ 시작 중…"
        case .failed: "● 실패 — 로그 확인"
        case .stopped: "○ 중지됨"
        }
    }
}

final class ChatHolder: ObservableObject {}

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

extension Notification.Name {
    static let newChat = Notification.Name("newChat")
    static let openAbout = Notification.Name("openAbout")
    static let chatZoomIn = Notification.Name("chatZoomIn")
    static let chatZoomOut = Notification.Name("chatZoomOut")
    static let chatZoomReset = Notification.Name("chatZoomReset")
    static let serverStart = Notification.Name("serverStart")
    static let serverStop = Notification.Name("serverStop")
    static let toggleDebug = Notification.Name("toggleDebug")
    static let toggleInspector = Notification.Name("toggleInspector")
    static let toggleLogPanel = Notification.Name("toggleLogPanel")
}

struct SettingsView: View {
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("quitStopsDaemon") private var quitStopsDaemon = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.system.rawValue
    @State private var loginError: String?

    var body: some View {
        TabView {
            Form {
                Picker("외관", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }.pickerStyle(.segmented)
                    .onChange(of: appearanceRaw) { _, raw in
                        AppearanceMode.apply(AppearanceMode(rawValue: raw) ?? .system)
                    }
                    .help("시스템 추종 또는 강제 라이트/다크. 마크다운·차트도 함께 바뀝니다.")
                Toggle("Dock에 아이콘 보이기", isOn: $showInDock)
                    .onChange(of: showInDock) { _, dock in
                        NSApp.setActivationPolicy(dock ? .regular : .accessory)
                        if dock { NSApp.activate(ignoringOtherApps: true) }
                    }
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLoginItem(on) }
                Toggle("앱 종료 시 데몬도 함께 종료", isOn: $quitStopsDaemon)
                    .help("끄면 앱을 닫아도 데몬이 남아 다음 실행 때 바로 씁니다. 터미널 데몬은 항상 유지됩니다.")
                if let err = loginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Text("포트는 127.0.0.1:9379 고정, 모델은 ~/.litert-lm/models 참조.")
                    .font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).padding()
                .tabItem { Label("일반", systemImage: "gear") }
        }.frame(minWidth: 580, minHeight: 420)
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
            DebugLogger.shared.info(feature: "로그인항목", on ? "등록" : "해제")
        } catch {
            loginError = "로그인 항목 변경 실패: \(error.localizedDescription)"
            launchAtLogin = !on
        }
    }
}
