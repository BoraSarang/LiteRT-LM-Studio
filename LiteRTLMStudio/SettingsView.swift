import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("quitStopsDaemon") private var quitStopsDaemon = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("engineMode") private var engineModeRaw = EngineMode.cli.rawValue
    @AppStorage("historyTurns") private var historyTurns = HistoryWindow.unlimited.rawValue
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
                Picker("추론 엔진", selection: $engineModeRaw) {
                    ForEach(EngineMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }.pickerStyle(.segmented)
                    .help("CLI 데몬(서버 경유) 또는 네이티브(프로세스 내 직접 추론). 처음 네이티브 전송 때 엔진을 초기화합니다.")
                    .onChange(of: engineModeRaw) { _, raw in
                        DebugLogger.shared.info(
                            feature: "엔진모드",
                            "전환: \((EngineMode(rawValue: raw) ?? .cli).title)")
                    }
                Picker("대화 기록 전송", selection: $historyTurns) {
                    ForEach(HistoryWindow.allCases, id: \.rawValue) { w in
                        Text(w.title).tag(w.rawValue)
                    }
                }.pickerStyle(.segmented)
                    .help("매 전송에 포함할 과거 대화 범위. 짧을수록 빠르지만 앞부분 맥락이 잘립니다. 제한 없음은 기존 그대로 전부 전송합니다.")
                    .onChange(of: historyTurns) { _, raw in
                        DebugLogger.shared.info(
                            feature: "히스토리범위",
                            "전환: \((HistoryWindow(rawValue: raw) ?? .unlimited).title)")
                    }
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
