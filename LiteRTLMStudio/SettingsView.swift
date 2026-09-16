import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("quitStopsDaemon") private var quitStopsDaemon = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("historyTurns") private var historyTurns = HistoryWindow.unlimited.rawValue
    @AppStorage("benchmarkRetention") private var benchmarkRetention = BenchmarkRetention.ten.rawValue
    @AppStorage("globalPermission") private var permissionRaw = GlobalPermission.ask.rawValue
    @AppStorage("chatOutlineEnabled") private var outlineEnabled = true // T-258 대화 목차
    @AppStorage("followUpEnabled") private var followUpEnabled = true // T-261 후속질문 칩
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
                Text("전송 경로(서버·앱 내 엔진)는 채팅 입력창의 피커에서 매번 선택합니다.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Picker("벤치마크 기록 보관", selection: $benchmarkRetention) {
                    ForEach(BenchmarkRetention.allCases, id: \.rawValue) { r in
                        Text(r.title).tag(r.rawValue)
                    }
                }.pickerStyle(.segmented)
                    .help("벤치마크 히스토리 최대 보관 수. 초과분은 오래된 것부터 삭제됩니다.")
                    .onChange(of: benchmarkRetention) { _, raw in
                        DebugLogger.shared.info(
                            feature: "벤치마크",
                            "보관 전환: \((BenchmarkRetention(rawValue: raw) ?? .ten).title)")
                    }
                Picker("권한", selection: $permissionRaw) {
                    ForEach(GlobalPermission.allCases, id: \.rawValue) { p in
                        Text(p.title).tag(p.rawValue)
                    }
                }.pickerStyle(.segmented)
                    .help("모델 삭제·가져오기·설치에 적용되는 전역 권한. 사용 안 함=차단, 매번 묻기=확인 후 실행, 모두 허용=바로 실행. 채팅 전송은 항상 허용.")
                    .onChange(of: permissionRaw) { _, raw in
                        DebugLogger.shared.info(
                            feature: "권한",
                            "전환: \((GlobalPermission(rawValue: raw) ?? .ask).title)")
                    }
                if let err = loginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Text("포트는 127.0.0.1:9379 고정, 모델은 ~/.litert-lm/models 참조.")
                    .font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).padding()
                .tabItem { Label("일반", systemImage: "gear") }
            Form {
                Toggle("대화 목차 사용", isOn: $outlineEnabled)
                    .help("채팅 우측 중앙에 질문 목록 플로팅. 끄면 숨겨집니다.")
                    .onChange(of: outlineEnabled) { _, on in
                        DebugLogger.shared.info(feature: "대화목차", on ? "켜짐" : "꺼짐")
                    }
                Toggle("후속 질문 사용", isOn: $followUpEnabled)
                    .help("응답 완료 후 관련 질문 3~4개를 어시스턴트 아래 우측에 표시. 끄면 숨겨집니다.")
                    .onChange(of: followUpEnabled) { _, on in
                        DebugLogger.shared.info(feature: "후속질문", on ? "켜짐" : "꺼짐")
                    }
            }.formStyle(.grouped).padding()
                .tabItem { Label("채팅", systemImage: "bubble.left.and.bubble.right") }
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
