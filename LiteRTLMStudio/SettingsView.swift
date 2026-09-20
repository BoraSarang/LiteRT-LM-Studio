import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("quitStopsDaemon") private var quitStopsDaemon = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("historyTurns") private var historyTurns = HistoryWindow.turns10.rawValue
    @AppStorage("benchmarkRetention") private var benchmarkRetention = BenchmarkRetention.ten.rawValue
    @AppStorage("globalPermission") private var permissionRaw = GlobalPermission.ask.rawValue
    @AppStorage("chatOutlineEnabled") private var outlineEnabled = true // T-258 대화 목차
    @AppStorage("followUpEnabled") private var followUpEnabled = true // T-261 후속질문 칩
    @AppStorage("webSearchEnabled") var webSearchEnabled = true // T-269 웹 검색 도구
    @AppStorage("exaApiKey") var exaApiKey = "" // T-352 Exa 검색 API 키
    @AppStorage("prefillWarmup") private var prefillWarmup = false // T-302 첫터치 프리필
    @AppStorage("workspaceRoot") private var workspaceRoot = "" // T-272 작업폴더 (빈값=기본값)
    @AppStorage("chatFontScale") private var chatFontScale = 1.0 // T-359 채팅 글자 크기
    @AppStorage("updateFrequency") private var updateFrequencyRaw =
        UpdateCheckFrequency.weekly.rawValue // 앱 업데이트 확인 주기
    @AppStorage("sessionSort") private var sessionSortRaw = ChatStore.SessionSort.recent.rawValue // T-359 세션 정렬
    @State private var toolFlags: [String: Bool] = [:] // T-271 도구 개별 ON/OFF
    @ObservedObject var mcp = MCPStore.shared // T-285 MCP 서버 목록
    @State var skills: [SkillInfo] = [] // T-285 스킬 목록
    @State var skillRoots: [String] = [] // T-315 외부 스킬 루트
    @State var skillCandidates: [SkillsStore.ImportCandidate] = [] // T-315 임포트 후보
    @State var showSkillsImport = false // T-315 임포트 시트
    @State var showMCPAdd = false // T-285 서버 추가 시트
    @State var mcpDraft = MCPServerConfig(name: "") // T-285 입력 초안
    @State var mcpTestResult: [UUID: String] = [:] // T-285 연결 결과
    @State private var loginError: String?
    @State var exaTestResult: String? // T-352 키 테스트 결과
    @ObservedObject private var language = LanguageManager.shared // T-361 언어 설정

    var body: some View {
        TabView {
            Form {
                DSSection(L(L10n.Settings.generalAppearance)) {
                DSSegmented(L(L10n.Settings.themeMode), selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                    .onChange(of: appearanceRaw) { _, raw in
                        AppearanceMode.apply(AppearanceMode(rawValue: raw) ?? .system)
                    }
                    .help(L(L10n.Settings.themeModeHelp))
                DSSegmented(L(L10n.Settings.generalLanguage), selection: $language.selection) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                    .help(L(L10n.Settings.generalLanguageHelp))
                Toggle(L(L10n.Settings.showInDock), isOn: $showInDock)
                    .onChange(of: showInDock) { _, dock in
                        NSApp.setActivationPolicy(dock ? .regular : .accessory)
                        if dock { NSApp.activate(ignoringOtherApps: true) }
                    }
                Toggle(L(L10n.Settings.launchAtLogin), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLoginItem(on) }
                if let err = loginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                }
                DSSection(L(L10n.Settings.systemSection)) {
                Toggle(L(L10n.Settings.quitStopsDaemon), isOn: $quitStopsDaemon)
                    .help(L(L10n.Settings.quitStopsDaemonHelp))
                DSSegmented(L(L10n.Update.frequency), selection: $updateFrequencyRaw) {
                    ForEach(UpdateCheckFrequency.allCases, id: \.rawValue) { f in
                        Text(f.title).tag(f.rawValue)
                    }
                }
                Toggle(L(L10n.Settings.prefillWarmup), isOn: $prefillWarmup)
                    .help(L(L10n.Settings.prefillWarmupHelp))
                    .onChange(of: prefillWarmup) { _, on in
                        DebugLogger.shared.info(feature: "프리필", on ? "켜짐" : "꺼짐")
                    }
                HStack(spacing: 4) {
                    Text(L(L10n.Settings.routeNote))
                        .font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "info.circle")
                        .font(.caption).foregroundStyle(.tertiary)
                        .help(L(L10n.Settings.routeNoteHelp))
                }
                Text(L(L10n.Settings.serverNote))
                    .font(.caption).foregroundStyle(.secondary)
                }
                DSSection(L(L10n.Settings.advancedSection)) {
                DSSegmented(L(L10n.Settings.benchmarkRetention), selection: $benchmarkRetention) {
                    ForEach(BenchmarkRetention.allCases, id: \.rawValue) { r in
                        Text(r.title).tag(r.rawValue)
                    }
                }
                    .help(L(L10n.Settings.benchmarkRetentionHelp))
                    .onChange(of: benchmarkRetention) { _, raw in
                        DebugLogger.shared.info(
                            feature: "벤치마크",
                            "보관 전환: \((BenchmarkRetention(rawValue: raw) ?? .ten).title)")
                    }
                }
                DSSection(L(L10n.Settings.permissionSection)) {
                DSSegmented(L(L10n.Settings.permission), selection: $permissionRaw) {
                    ForEach(GlobalPermission.allCases, id: \.rawValue) { p in
                        Text(p.title).tag(p.rawValue)
                    }
                }
                    .help(L(L10n.Settings.permissionHelp))
                    .onChange(of: permissionRaw) { _, raw in
                        DebugLogger.shared.info(
                            feature: "권한",
                            "전환: \((GlobalPermission(rawValue: raw) ?? .ask).title)")
                    }
                }
            }.dsSettingsForm()
            .tabItem { Label(L(L10n.Settings.generalTab), systemImage: "gear") }
            Form {
                DSSection(L(L10n.Settings.displaySection)) {
                Toggle(L(L10n.Settings.outlineEnabled), isOn: $outlineEnabled)
                    .help(L(L10n.Settings.outlineEnabledHelp))
                    .onChange(of: outlineEnabled) { _, on in
                        DebugLogger.shared.info(feature: "대화목차", on ? "켜짐" : "꺼짐")
                    }
                Toggle(L(L10n.Settings.followUpEnabled), isOn: $followUpEnabled)
                    .help(L(L10n.Settings.followUpEnabledHelp))
                    .onChange(of: followUpEnabled) { _, on in
                        DebugLogger.shared.info(feature: "후속질문", on ? "켜짐" : "꺼짐")
                    }
                HStack(spacing: 8) {
                    Text(L(L10n.Settings.chatFontSize))
                    Slider(value: $chatFontScale, in: 0.7...2.0, step: 0.1)
                    Text("\(Int((chatFontScale * 100).rounded()))%").monospacedDigit().frame(width: 44)
                    Button(L(L10n.Settings.defaultButton)) { chatFontScale = 1.0 }
                        .controlSize(.small)
                        .disabled(chatFontScale == 1.0)
                }
                .help(L(L10n.Settings.chatFontSizeHelp))
                DSSegmented(L(L10n.Settings.sessionSort), selection: $sessionSortRaw) {
                    ForEach(ChatStore.SessionSort.allCases, id: \.self) { order in
                        Text(order.title).tag(order.rawValue)
                    }
                }
                    .help(L(L10n.Settings.sessionSortHelp))
                }
                DSSection(L(L10n.Settings.behaviorSection)) {
                DSSegmented(L(L10n.Settings.historyTurns), selection: $historyTurns) {
                    ForEach(HistoryWindow.allCases, id: \.rawValue) { w in
                        Text(w.title).tag(w.rawValue)
                    }
                }
                    .help(L(L10n.Settings.historyTurnsHelp))
                    .onChange(of: historyTurns) { _, raw in
                        DebugLogger.shared.info(
                            feature: "히스토리범위",
                            "전환: \((HistoryWindow(rawValue: raw) ?? .unlimited).title)")
                    }
                }
            }.dsSettingsForm()
                .tabItem { Label(L(L10n.Settings.chatTab), systemImage: "bubble.left.and.bubble.right") }
            Form {
                ForEach(ToolInfo.Category.allCases, id: \.rawValue) { category in
                    Section(category.title) {
                        ForEach(ToolCatalog.all.filter { $0.category == category }) { info in
                            Toggle(info.title, isOn: toolBinding(for: info.name))
                                .help(info.detail)
                        }
                        if category == .web {
                            Toggle(L(L10n.Settings.webTools), isOn: $webSearchEnabled)
                                .help(L(L10n.Settings.webToolsHelp))
                                .onChange(of: webSearchEnabled) { _, on in
                                    DebugLogger.shared.info(feature: "웹검색", on ? "켜짐" : "꺼짐")
                                }
                            exaRows
                        }
                    }
                }
                ShortcutsAllowlistSection() // T-270
                Text(L(L10n.Settings.toolsDisabledNote))
                    .font(.caption).foregroundStyle(.secondary)
                Section(L(L10n.Settings.fileShell)) {
                    HStack(spacing: 8) {
                        let folder = workspaceRoot.isEmpty
                            ? L(L10n.Settings.workspaceDefault) : workspaceRoot
                        Text(L(L10n.Settings.workspace, folder))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button(L(L10n.Settings.selectButton)) { pickWorkspace() }
                        if !workspaceRoot.isEmpty {
                            Button(L(L10n.Settings.workspaceDefault)) { workspaceRoot = "" }
                        }
                    }.help(L(L10n.Settings.workspaceHelp))
                }
            }.dsSettingsForm()
                .tabItem { Label(L(L10n.Settings.toolsTab), systemImage: "wrench") }
            mcpTab
            skillsTab
        }.frame(minWidth: 600, maxWidth: 600, minHeight: 420)
            .onAppear {
                reloadToolFlags(); reloadSkills()
            }
            .sheet(isPresented: $showMCPAdd) {
                MCPAddSheet(draft: $mcpDraft) {
                    mcp.upsert(mcpDraft)
                    showMCPAdd = false
                } onCancel: {
                    showMCPAdd = false
                }
            }
    }

    /// 도구 개별 토글 바인딩 (T-271): UserDefaults 저장+로그.
    private func toolBinding(for name: String) -> Binding<Bool> {
        Binding(get: { toolFlags[name] ?? ToolCatalog.isEnabled(name) },
                set: {
                    ToolCatalog.setEnabled(name, $0)
                    toolFlags[name] = $0
                    DebugLogger.shared.info(feature: "도구설정", "\(name) \($0 ? "켜짐" : "꺼짐")")
                })
    }

    /// 저장된 플래그 일괄 로드.
    private func reloadToolFlags() {
        toolFlags = Dictionary(uniqueKeysWithValues:
            ToolCatalog.all.map { ($0.name, ToolCatalog.isEnabled($0.name)) })
    }

    /// 작업폴더 선택 (T-272): NSOpenPanel 폴더 1개.
    private func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspaceRoot = url.path
        DebugLogger.shared.info(feature: "도구설정", "작업폴더: \(url.path)")
    }

    private func setLoginItem(_ on: Bool) {        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
            DebugLogger.shared.info(feature: "로그인항목", on ? "등록" : "해제")
        } catch {
            loginError = L(L10n.Settings.loginItemError, error.localizedDescription)
            launchAtLogin = !on
        }
    }
}

/// 외부 스킬 가져오기 시트 (T-315): 검색·출처 뱃지·일괄 선택·새로고침.
struct SkillsImportSheet: View {
    @Binding var candidates: [SkillsStore.ImportCandidate]
    var onImport: (SkillsStore.ImportCandidate) -> Void
    var onRefresh: () -> Void
    var onClose: () -> Void
    @State private var selected: Set<String> = []
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(L10n.SkillImport.title)).font(.system(size: 13, weight: .semibold))

            // 검색 필드
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
                TextField(L(L10n.SkillImport.searchPlaceholder), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if filteredCandidates.isEmpty {
                Text(candidates.isEmpty
                     ? L(L10n.SkillImport.emptyAll)
                     : L(L10n.SkillImport.emptyQuery, searchText))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                // 헤더: 카운트 + 액션
                let installedCount = candidates.filter { $0.installed }.count
                HStack {
                    Text(L(L10n.SkillImport.counts, candidates.count, filteredCandidates.count, installedCount))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L(L10n.SkillImport.selectAll)) {
                        selected = Set(filteredCandidates.filter { !$0.installed }.map { $0.id })
                    }.controlSize(.small)
                    Button(L(L10n.SkillImport.deselectAll)) { selected.removeAll() }.controlSize(.small)
                    Button(action: onRefresh) {
                        Label(L(L10n.SkillImport.refresh), systemImage: "arrow.clockwise")
                    }.controlSize(.small)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredCandidates) { c in
                            HStack(alignment: .top, spacing: 8) {
                                Toggle("", isOn: binding(for: c))
                                    .labelsHidden()
                                    .disabled(c.installed)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        // 출처 뱃지
                                        Text(c.source.label)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                        Text(c.name).font(.system(size: 12, weight: .medium))
                                        if c.installed {
                                            Text(L(L10n.SkillImport.installed)).font(DS.captionFont)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if !c.blurb.isEmpty {
                                        Text(c.blurb).font(DS.captionFont)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.tail)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }.frame(maxHeight: 300)
            }

            HStack {
                Spacer()
                Button(L(L10n.SkillImport.close), action: onClose)
                Button(L(L10n.SkillImport.importButton)) {
                    for c in filteredCandidates where selected.contains(c.id) { onImport(c) }
                    selected.removeAll()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
        }.padding(16).frame(width: 520)
    }

    private var filteredCandidates: [SkillsStore.ImportCandidate] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.blurb.localizedCaseInsensitiveContains(q)
        }
    }

    /// 후보 선택 바인딩 (이미 설치된 항목은 제외).
    private func binding(for c: SkillsStore.ImportCandidate) -> Binding<Bool> {
        Binding(get: { selected.contains(c.id) },
                set: { on in
                    if on { selected.insert(c.id) } else { selected.remove(c.id) }
                })
    }
}
