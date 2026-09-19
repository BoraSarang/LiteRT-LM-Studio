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
            return "● 실행 중\(external ? " (외부)" : "") · :\(DaemonManager.port)"
        case .starting:
            return "◌ 시작 중…"
        case .failed:
            return "● 실패 — 로그 확인"
        case .stopped:
            return unlinked ? "● 외부 실행 중 (미연결)" : "○ 중지됨"
        }
    }

    /// 메뉴바 버튼 툴팁 (앱 이름 + 상태).
    static func tooltip(status: DaemonManager.Status, external: Bool, unlinked: Bool) -> String {
        "LiteRT-LM Studio — \(line(status: status, external: external, unlinked: unlinked))"
    }

    /// 가동 시간 (nil이면 미표시). 초→분→시간 단위로 축약.
    static func uptimeText(since: Date?, now: Date = Date()) -> String? {
        guard let since else { return nil }
        let secs = max(0, Int(now.timeIntervalSince(since)))
        let (hours, minutes, seconds) = (secs / 3600, (secs % 3600) / 60, secs % 60)
        if hours > 0 { return String(format: "가동 %d시간 %02d분", hours, minutes) }
        if minutes > 0 { return String(format: "가동 %d분 %02d초", minutes, seconds) }
        return "가동 \(seconds)초"
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
            case .ready: return "● 앱 내 엔진 · 준비됨"
            case .preparing: return "◌ 앱 내 엔진 · 준비 중…"
            case .failed: return "● 앱 내 엔진 · 실패 — 로그 확인"
            case .idle: return "○ 앱 내 엔진 · 준비 안 됨"
            }
        }
    }

    static func tooltip(route: EngineMode, daemon: DaemonManager.Status, external: Bool,
                        unlinked: Bool, nativeState: NativeEngine.State) -> String {
        "LiteRT-LM Studio — " + line(route: route, daemon: daemon, external: external,
                                     unlinked: unlinked, nativeState: nativeState)
    }
}

/// 엔진/서버 토글 버튼 문구·아이콘 (순수, 테스트 가능, T-355).
/// 툴바 `toggleServer`(ServerActions.swift)와 같은 경로 규칙을 따른다.
enum MenuBarActionText {
    static func title(route: EngineMode, daemon: DaemonManager.Status,
                      external: Bool, nativeReady: Bool) -> String {
        switch route {
        case .native:
            return nativeReady ? "앱 내 엔진 중지" : "앱 내 엔진 준비"
        case .cli:
            if daemon == .running { return external ? "외부 연결 끊기" : "서버 중지" }
            return "서버 시작"
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
