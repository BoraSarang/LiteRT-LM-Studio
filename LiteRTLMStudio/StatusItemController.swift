import AppKit
import Combine
import SwiftUI

/// 수동 NSStatusItem (T-355): 메뉴바 아이콘은 기존 SwiftUI 라벨(칩 템플릿+상태 점)을 호스팅하고,
/// 클릭 시 아이콘 **아래**에 팝오버를 띄운다. `MenuBarExtra`는 위치·형태 제어가 제한적이다.
/// (Etchost StatusItemController 패턴 이식)
@MainActor
final class StatusItemController: NSObject {
    private let services: AppServices
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    init(services: AppServices) {
        self.services = services
        super.init()
        setupStatusItem()
        setupPopover()
        observeDaemon()
    }

    // MARK: - 상태 아이템

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // 기존 MenuBarLabel(칩+상태 점)을 그대로 얹는다. 이벤트는 버튼이 받도록 통과.
        let label = MenuBarLabel()
            .environmentObject(services.daemon)
            .environmentObject(services.chat)
            .environmentObject(services.nativeEngine)
        let host = PassthroughHostingView(rootView: label)
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            host.topAnchor.constraint(equalTo: button.topAnchor),
            host.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        updateTooltip()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        let content = MenuBarPopover()
            .environmentObject(services)
            .environmentObject(services.daemon)
            .environmentObject(services.chat)
            .environmentObject(services.nativeEngine)
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - 툴팁 동기화

    /// 경로(서버/앱 내 엔진)·상태 변화를 각각 구독 (CombineLatest 3+ 튜플은 lint large_tuple 회피).
    private func observeDaemon() {
        let refresh: (Any) -> Void = { [weak self] _ in self?.updateTooltip() }
        services.daemon.$status.sink { refresh($0) }.store(in: &cancellables)
        services.daemon.$external.sink { refresh($0) }.store(in: &cancellables)
        services.chat.$route.sink { refresh($0) }.store(in: &cancellables)
        services.nativeEngine.$state.sink { refresh($0) }.store(in: &cancellables)
    }

    private func updateTooltip() {
        statusItem.button?.toolTip = MenuBarRouteStatus.tooltip(
            route: services.chat.route,
            daemon: services.daemon.status,
            external: services.daemon.external,
            unlinked: services.daemon.unlinkedRunning,
            nativeState: services.nativeEngine.state
        )
    }
}

/// 버튼 클릭을 가로채지 않는 호스팅 뷰 (아이콘만 그리고 이벤트는 NSStatusBarButton이 받게).
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
