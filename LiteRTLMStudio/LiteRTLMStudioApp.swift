import AppKit
import SwiftUI

/// 메인 창 프레임 autosave 이름·타이틀 (T-339: AppDelegate가 표시 전 창을 식별·복원하는 데 사용).
let mainWindowFrameName = "LiteRTLMStudioMain"
let mainWindowTitle = "LiteRT-LM Studio"

@main
struct LiteRTLMStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var services: AppServices
    @StateObject private var language = LanguageManager.shared // T-361 언어 설정
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("onboardingDone") private var onboardingDone = false

    init() {
        // T-314: 스토어 생성 전에 앱 데이터 홈(`~/.litert-lm-studio`)으로 1회 이사.
        // NSApp 호출이 아니라 FS 작업이라 App.init에서 안전.
        StudioMigrator.runIfNeeded()
        _services = StateObject(wrappedValue: AppServices())
    }

    // 주의: init에서 NSApp 호출 금지 (테스트 부트스트랩 크래시).
    // 정책 적용은 ContentView.task + 설정 토글에서 수행.
    var body: some Scene {
        // 단일 창: openWindow(id:)가 기존 창을 앞으로 올림 (중복 생성 방지).
        Window("LiteRT-LM Studio", id: "main") {
            // T-257 온보딩 게이트: 미통과 시 랜딩, 통과 후 메인.
            Group {
                if onboardingDone {
                    ContentView(models: services.models, daemon: services.daemon, monitor: services.monitor,
                                nativeEngine: services.nativeEngine, chat: services.chat,
                                bench: services.bench, benchHistory: services.benchHistory,
                                releases: services.releases,
                                config: services.config)
                        .frame(minWidth: 900, minHeight: 640) // UI-P0: 분할·소형 화면 축소 허용
                } else {
                    LandingView(done: $onboardingDone)
                }
            }
            // T-355: 메뉴바 팝오버(씬 밖)는 openWindow 환경을 못 쓰므로 노티로 창을 연다.
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .languageAware(language) // T-361 언어 전환 즉시 반영
        }
        .defaultSize(width: 1340, height: 800) // T-092 계산치: 사이드바 220+열 768+여백 32+인스펙터 320
        .windowToolbarStyle(.unified)
        // 디버그 별도 윈도우 (T-053): 시트 대신 독립 창.
        Window(L(L10n.App.debugPanel), id: "debug") {
            DebugPanelView()
                .frame(minWidth: 680, minHeight: 420)
        }
        .defaultSize(width: 760, height: 500)
        // 벤치마크 별도 윈도우 (T-216): 시트 대신 독립 창 (모델·모드 선택+히스토리).
        Window(L(L10n.App.benchmark), id: "benchmark") {
            BenchmarkWindowView(store: services.bench, history: services.benchHistory,
                                models: services.models, chat: services.chat)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 960, height: 640)
        // 모델 관리 별도창 (T-232): 가져오기·목록·설치·삭제·이름변경.
        Window(L(L10n.App.modelManager), id: "modelManager") {
            ModelManagerView(models: services.models, center: services.downloads)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1080, height: 700)
        // 정보 창 (T-068, TubeKeep AboutView 구조).
        Window(L(L10n.App.about), id: "about") {
            AboutView(releases: services.releases)
        }
        .defaultSize(width: 560, height: 360)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L(L10n.App.aboutItem)) {
                    NotificationCenter.default.post(name: .openAbout, object: nil)
                }
                Divider()
                Button(L(L10n.Update.check)) {
                    // 정보 창을 열고 뜰 시간을 준 뒤 자동 확인 (팝오버 deliver 패턴과 동일).
                    NotificationCenter.default.post(name: .openAbout, object: nil)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        NotificationCenter.default.post(name: .checkAppUpdate, object: nil)
                    }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button(L(L10n.App.newChat)) { NotificationCenter.default.post(name: .newChat, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu(L(L10n.App.serverMenu)) {
                Button(L(L10n.App.serverStart)) { NotificationCenter.default.post(name: .serverStart, object: nil) }
                    .keyboardShortcut("r", modifiers: .command)
                Button(L(L10n.App.serverStop)) { NotificationCenter.default.post(name: .serverStop, object: nil) }
                    .keyboardShortcut(".", modifiers: .command)
            }
            CommandMenu(L(L10n.App.viewMenu)) {
                Button(L(L10n.App.zoomIn)) { NotificationCenter.default.post(name: .chatZoomIn, object: nil) }
                    .keyboardShortcut("+", modifiers: .command)
                Button(L(L10n.App.zoomOut)) { NotificationCenter.default.post(name: .chatZoomOut, object: nil) }
                    .keyboardShortcut("-", modifiers: .command)
                Button(L(L10n.App.zoomReset)) { NotificationCenter.default.post(name: .chatZoomReset, object: nil) }
                    .keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button(L(L10n.App.toggleInspector)) {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                Button(L(L10n.App.toggleLogPanel)) {
                    NotificationCenter.default.post(name: .toggleLogPanel, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)
                Button(L(L10n.App.debugPanel)) { NotificationCenter.default.post(name: .toggleDebug, object: nil) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appTermination) {
                Button(L(L10n.App.quit)) { services.quit() }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        // T-355: MenuBarExtra 대신 AppDelegate가 수동 NSStatusItem+NSPopover를 소유 (StatusItemController).
        // T-358: 설정 창은 내용 폭(600)에 맞춰 고정 — 넓은 기본 폭에서 그룹 폼이 가운데 정렬돼
        // 좌우 여백이 상하보다 커 보이던 문제 제거.
        Settings { SettingsView().languageAware(language) }
            .windowResizability(.contentSize)
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

/// T-339: 첫 창 프레임 복원 타이밍 처방.
/// SwiftUI `Window` 씬은 `defaultSize` 기준 중앙에 창을 띄운 뒤, 뷰 트리 복원(NSViewRepresentable)이
/// 표시 이후에 실행되어 "중앙 → 저장 위치" 점프가 생긴다. T-337/T-338의 뷰 트리 방식은 이 타이밍을
/// 이기지 못했다. AppKit 런치 단계(표시 전)에서 창을 잡아 autosave 프레임을 적용한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// T-355: 메뉴바 상태 아이템 (앱 수명 동안 유지).
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApp.windows.first(where: { $0.title == mainWindowTitle })
                ?? NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) {
            window.setFrameAutosaveName(mainWindowFrameName)
        }
        // 메뉴바: 앱이 소유한 공유 서비스로 생성 (창을 닫아도 유지).
        if let services = AppServices.shared {
            statusController = StatusItemController(services: services)
        }
        // 창이 숨겨진 상태에서도 팝오버의 "메인 창 열기"가 동작하도록 AppKit에서도 처리.
        NotificationCenter.default.addObserver(
            forName: .openMainWindow, object: nil, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                NSApp.windows.first { $0.title == mainWindowTitle }?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
