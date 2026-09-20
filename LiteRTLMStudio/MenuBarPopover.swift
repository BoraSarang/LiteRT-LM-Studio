import AppKit
import SwiftUI

/// 메뉴바 팝오버 (T-355): 상태 카드 + 빠른 동작 + 최근 채팅방. Etchost의 수동 NSPopover 패턴을 따른다.
/// 씬 밖(NSHostingController)이라 `@Environment(\.openWindow)` 대신 노티를 쓴다.
/// `daemon`·`chat`·`nativeEngine`을 직접 구독 — AppServices는 중첩 ObservableObject 변경을 전파하지 않는다.
/// 상태 카드·토글 버튼 모두 현재 전송 경로(서버/앱 내 엔진)를 따른다.
struct MenuBarPopover: View {
    @EnvironmentObject var services: AppServices
    @EnvironmentObject var daemon: DaemonManager
    @EnvironmentObject var chat: ChatStore
    @EnvironmentObject var nativeEngine: NativeEngine
    @EnvironmentObject var releases: ReleaseNotes

    private static let recentLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusCard
            Divider()
            actions
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
    }

    // MARK: - 상태 카드

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(MenuStatus.dotColor(route: chat.route, daemon: daemon.status,
                                          nativeState: nativeEngine.state))
                .frame(width: 9, height: 9)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(MenuBarRouteStatus.line(route: chat.route, daemon: daemon.status,
                                             external: daemon.external,
                                             unlinked: daemon.unlinkedRunning,
                                             nativeState: nativeEngine.state))
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// 경로 배지 + 부가 정보. 예: "앱 내 엔진 · Gemma 4 · 12B · 서버 실행 중".
    private var subtitle: String {
        var parts: [String] = [chat.route.title]
        if let uptime = MenuBarStatusText.uptimeText(since: daemon.uptimeSince), chat.route == .cli {
            parts.append(uptime)
        }
        if !chat.model.isEmpty {
            parts.append(ModelAlias.display(id: chat.model))
        }
        if chat.route == .native, daemon.status == .running {
            parts.append(L(L10n.StatusMenu.running))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 빠른 동작

    private var actions: some View {
        VStack(spacing: 6) {
            engineButton
            actionButton(L(L10n.StatusMenu.newChat), icon: "square.and.pencil") { deliver(.newChat) }
            recents
            actionButton(L(L10n.StatusMenu.openMain), icon: "macwindow") { openMainWindow() }
            actionButton(L(L10n.StatusMenu.modelManager), icon: "shippingbox") { deliver(.openModelManager) }
            Divider()
            HStack {
                SettingsLink { Text(L(L10n.StatusMenu.settings)) }
                Spacer()
                if let update = releases.appUpdate(installed: AboutView.appVersion) {
                    Button {
                        deliver(.openAbout)
                    } label: {
                        Text(L(L10n.Update.available,
                                ReleaseNotesParser.displayVersion(update.tag)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("v\(AboutView.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(L(L10n.StatusMenu.quit)) { services.quit() }
            }
        }
    }

    /// 현재 경로의 엔진/서버 토글 (T-355). 툴바 `toggleServer`와 같은 규칙.
    @ViewBuilder
    private var engineButton: some View {
        let title = MenuBarActionText.title(route: chat.route, daemon: daemon.status,
                                            external: daemon.external, nativeReady: nativeReady)
        let icon = MenuBarActionText.icon(route: chat.route, daemon: daemon.status,
                                          nativeReady: nativeReady)
        actionButton(title, icon: icon) { toggleEngine() }
            .disabled(engineBusy)
    }

    private var nativeReady: Bool { nativeEngine.preparedModelID != nil }

    /// 경로별 준비/시작 진행 중.
    private var engineBusy: Bool {
        chat.route == .native ? nativeEngine.state == .preparing : daemon.status == .starting
    }

    /// 툴바 토글(ServerActions.swift:48)과 동일한 동작.
    private func toggleEngine() {
        if chat.route == .native {
            if nativeEngine.preparedModelID != nil {
                nativeEngine.release()
            } else if nativeEngine.state != .preparing {
                Task { try? await nativeEngine.restart(modelID: chat.model) }
            }
            return
        }
        if daemon.status == .running {
            daemon.stop()
        } else {
            Task { await daemon.start() }
        }
    }

    /// 최근 채팅방 3개 (클릭 시 전환 + 메인 창 열기).
    @ViewBuilder
    private var recents: some View {
        let items = MenuBarRecents.recent(chat.sessions, limit: Self.recentLimit)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(L10n.StatusMenu.recentChats))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                ForEach(items) { session in
                    recentRow(session)
                }
            }
        }
    }

    private func recentRow(_ session: ChatStore.Session) -> some View {
        let isCurrent = chat.currentSessionID == session.id
        return Button {
            openSession(session.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "bubble.left.fill" : "bubble.left")
                    .font(.caption)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(session.displayTitle)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .background(isCurrent ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    private func actionButton(_ title: String, icon: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 창 열기 (씬 밖이라 노티 경유)
    private func openMainWindow() {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSession(_ id: UUID) {
        chat.selectSession(id)
        openMainWindow()
    }

    /// 창이 닫혀 있어도 동작 보장: 먼저 열고 ContentView 부착 후 전달.
    private func deliver(_ name: Notification.Name) {
        openMainWindow()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            NotificationCenter.default.post(name: name, object: nil)
        }
    }
}
