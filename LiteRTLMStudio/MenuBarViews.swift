import AppKit
import SwiftUI

/// 메뉴바 아이콘: 칩 템플릿 + 상태 점 (Ollama식).
/// T-355: `daemon`·`chat`·`nativeEngine`을 직접 구독 — AppServices는 중첩 ObservableObject
/// 변경을 전파하지 않는다. 점 색은 현재 전송 경로(서버/앱 내 엔진)를 따른다.
struct MenuBarLabel: View {
    @EnvironmentObject var daemon: DaemonManager
    @EnvironmentObject var chat: ChatStore
    @EnvironmentObject var nativeEngine: NativeEngine

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
            Circle().fill(MenuStatus.dotColor(route: chat.route, daemon: daemon.status,
                                              nativeState: nativeEngine.state))
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

    /// 전송 경로 기준 색 (T-355): 서버=데몬 상태, 앱 내 엔진=엔진 상태.
    static func dotColor(route: EngineMode, daemon: DaemonManager.Status,
                         nativeState: NativeEngine.State) -> Color {
        switch route {
        case .cli: dotColor(for: daemon)
        case .native: dotColor(for: nativeState)
        }
    }

    static func dotKey(route: EngineMode, daemon: DaemonManager.Status,
                       nativeState: NativeEngine.State) -> String {
        switch route {
        case .cli: dotKey(for: daemon)
        case .native: dotKey(for: nativeState)
        }
    }

    private static func dotColor(for state: NativeEngine.State) -> Color {
        switch state {
        case .ready: .green
        case .preparing: .orange
        case .failed: .red
        case .idle: .gray
        }
    }

    private static func dotKey(for state: NativeEngine.State) -> String {
        switch state {
        case .ready: "green"
        case .preparing: "orange"
        case .failed: "red"
        case .idle: "gray"
        }
    }
}

/// 팝오버·툴팁 문구 (순수, 테스트 가능, T-355).
enum MenuBarStatusText {
    /// 상태 한 줄 (기존 MenuBarView 문구 승계).
    static func line(status: DaemonManager.Status, external: Bool, unlinked: Bool) -> String {
        switch status {
        case .running:
            let base = L(external ? L10n.MenuBar.runningExternal : L10n.MenuBar.running)
            return "\(base) · :\(DaemonManager.port)"
        case .starting:
            return L(L10n.MenuBar.starting)
        case .failed:
            return L(L10n.MenuBar.failed)
        case .stopped:
            return L(unlinked ? L10n.MenuBar.unlinked : L10n.MenuBar.stopped)
        }
    }

    /// 메뉴바 버튼 툴팁 (앱 이름 + 상태).
    static func tooltip(status: DaemonManager.Status, external: Bool, unlinked: Bool) -> String {
        L(L10n.MenuBar.tooltip, line(status: status, external: external, unlinked: unlinked))
    }

    /// 가동 시간 (nil이면 미표시). 초→분→시간 단위로 축약.
    static func uptimeText(since: Date?, now: Date = Date()) -> String? {
        guard let since else { return nil }
        let secs = max(0, Int(now.timeIntervalSince(since)))
        let (hours, minutes, seconds) = (secs / 3600, (secs % 3600) / 60, secs % 60)
        if hours > 0 { return L(L10n.MenuBar.uptimeHours, hours, minutes) }
        if minutes > 0 { return L(L10n.MenuBar.uptimeMinutes, minutes, seconds) }
        return L(L10n.MenuBar.uptimeSeconds, seconds)
    }
}

/// 현재 전송 경로 기준 상태 문구 (순수, 테스트 가능, T-355): 서버/앱 내 엔진 구분.
enum MenuBarRouteStatus {
    /// 상태 카드·툴팁 한 줄.
    static func line(route: EngineMode, daemon: DaemonManager.Status, external: Bool,
                     unlinked: Bool, nativeState: NativeEngine.State) -> String {
        switch route {
        case .cli:
            return MenuBarStatusText.line(status: daemon, external: external, unlinked: unlinked)
        case .native:
            switch nativeState {
            case .ready: return L(L10n.MenuBar.routeNativeReady)
            case .preparing: return L(L10n.MenuBar.routeNativePreparing)
            case .failed: return L(L10n.MenuBar.routeNativeFailed)
            case .idle: return L(L10n.MenuBar.routeNativeIdle)
            }
        }
    }

    static func tooltip(route: EngineMode, daemon: DaemonManager.Status, external: Bool,
                        unlinked: Bool, nativeState: NativeEngine.State) -> String {
        L(L10n.MenuBar.tooltip, line(route: route, daemon: daemon, external: external,
                                     unlinked: unlinked, nativeState: nativeState))
    }
}

/// 엔진/서버 토글 버튼 문구·아이콘 (순수, 테스트 가능, T-355).
/// 툴바 `toggleServer`(ServerActions.swift)와 같은 경로 규칙을 따른다.
enum MenuBarActionText {
    static func title(route: EngineMode, daemon: DaemonManager.Status,
                      external: Bool, nativeReady: Bool) -> String {
        switch route {
        case .native:
            return L(nativeReady ? L10n.MenuBar.actionStopNative : L10n.MenuBar.actionStartNative)
        case .cli:
            if daemon == .running {
                return L(external ? L10n.MenuBar.actionDisconnectExternal : L10n.MenuBar.actionStopServer)
            }
            return L(L10n.MenuBar.actionStartServer)
        }
    }

    static func icon(route: EngineMode, daemon: DaemonManager.Status,
                     nativeReady: Bool) -> String {
        switch route {
        case .native: return nativeReady ? "stop.fill" : "play.fill"
        case .cli: return daemon == .running ? "stop.fill" : "play.fill"
        }
    }
}

/// 최근 채팅방 선별 (순수, 테스트 가능, T-355).
enum MenuBarRecents {
    /// 최근 갱신 순 상위 limit개.
    static func recent(_ sessions: [ChatStore.Session], limit: Int) -> [ChatStore.Session] {
        Array(sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(max(0, limit)))
    }
}
