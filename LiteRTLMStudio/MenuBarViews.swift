import AppKit
import SwiftUI

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
