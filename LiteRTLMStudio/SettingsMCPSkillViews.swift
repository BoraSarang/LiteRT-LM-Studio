import AppKit
import SwiftUI

/// 설정 MCP·스킬 탭 분리 (T-285, T-288 본문 길이 관리).
extension SettingsView {
    /// MCP 서버 탭.
    var mcpTab: some View {
        Form {
            if mcp.servers.isEmpty {
                Text(L(L10n.MCP.emptyServers))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(mcp.servers) { srv in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle().fill(mcpDot(srv)).frame(width: 8, height: 8)
                        Text(srv.name).font(.system(size: 13, weight: .medium))
                        Text(srv.transport == .stdio ? "stdio" : "SSE")
                            .font(DS.captionFont).foregroundStyle(.tertiary)
                        Spacer()
                        Toggle("", isOn: mcpBinding(for: srv.id)).labelsHidden()
                        Button(L(L10n.MCP.test)) { Task { await runMCPTest(srv) } }
                            .controlSize(.small)
                        Button(L(L10n.MCP.delete), role: .destructive) { mcp.remove(id: srv.id) }
                            .controlSize(.small)
                    }
                    Text(mcpDetail(srv)).font(DS.captionFont).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if let result = mcpTestResult[srv.id] {
                        Text(result).font(DS.captionFont).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button(L(L10n.MCP.addServer)) { mcpDraft = MCPServerConfig(name: "") ; showMCPAdd = true }
            }
            Text(L(L10n.MCP.addNote))
                .font(.caption).foregroundStyle(.secondary)
        }.dsSettingsForm()
            .tabItem { Label("MCP", systemImage: "server.rack") }
    }

    /// 스킬 탭 (T-315: 외부 루트·임포트 추가).
    var skillsTab: some View {
        Form {
            if skills.isEmpty {
                Text(L(L10n.MCP.noSkillMD))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(skills) { skill in
                HStack(spacing: 8) {
                    Toggle(skill.name, isOn: skillBinding(for: skill.name))
                        .help(skill.blurb)
                    if let src = skill.source {
                        Text(src.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                            .help(skill.root)
                    }
                }
            }
            if !skillRoots.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(L10n.MCP.externalRoots)).font(DS.captionFont).foregroundStyle(.secondary)
                    ForEach(skillRoots, id: \.self) { root in
                        HStack(spacing: 6) {
                            Text(root).font(DS.captionFont).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(L(L10n.MCP.remove)) {
                                SkillsStore.removeRoot(root)
                                reloadSkills()
                            }.controlSize(.small)
                        }
                    }
                }
            }
            HStack {
                Button(L(L10n.MCP.openFolder)) {
                    NSWorkspace.shared.open(SkillsStore.skillsDir())
                }
                Button(L(L10n.MCP.addFolder)) { pickSkillRoot() }
                Button(L(L10n.MCP.importButton)) {
                    skillCandidates = SkillsStore.importCandidates()
                    showSkillsImport = true
                }
                Button(L(L10n.MCP.refresh)) { reloadSkills() }
                Spacer()
            }
            Text(L(L10n.MCP.prefixNote))
                .font(.caption).foregroundStyle(.secondary)
        }.dsSettingsForm()
            .tabItem { Label(L(L10n.MCP.tab), systemImage: "sparkles") }
            .sheet(isPresented: $showSkillsImport) {
                SkillsImportSheet(
                    candidates: $skillCandidates,
                    onImport: { c in
                        SkillsStore.importSkill(c)
                        skillCandidates = SkillsStore.importCandidates()
                        reloadSkills()
                    },
                    onRefresh: {
                        skillCandidates = SkillsStore.importCandidates()
                    },
                    onClose: { showSkillsImport = false })
            }
    }

    /// 외부 스킬 폴더 선택 (T-315).
    func pickSkillRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L(L10n.MCP.addButton)
        panel.message = L(L10n.MCP.pickFolderMessage)
        if panel.runModal() == .OK, let url = panel.url {
            SkillsStore.addRoot(url.path)
            reloadSkills()
        }
    }

    /// MCP 토글 바인딩 (T-285).
    func mcpBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { mcp.servers.first(where: { $0.id == id })?.enabled ?? false },
                set: { mcp.setEnabled(id: id, $0) })
    }

    /// MCP 상태점 (T-285): 켜짐+실행 가능이면 초록.
    func mcpDot(_ srv: MCPServerConfig) -> Color {
        (!srv.enabled || !srv.isRunnable) ? .gray : .green
    }

    /// MCP 부제 (T-285): 명령 또는 URL.
    func mcpDetail(_ srv: MCPServerConfig) -> String {
        srv.transport == .stdio
            ? ([srv.command] + srv.args).joined(separator: " ")
            : srv.url
    }

    /// MCP 연결 테스트 (T-285).
    func runMCPTest(_ srv: MCPServerConfig) async {
        mcpTestResult[srv.id] = L(L10n.MCP.checking)
        mcpTestResult[srv.id] = await mcp.testConnection(srv)
    }

    /// 스킬 목록 새로고침 (T-285, T-315: 외부 루트 포함).
    func reloadSkills() {
        skills = SkillsStore.list()
        skillRoots = SkillsStore.extraRoots().map { $0.path }
        DebugLogger.shared.info(feature: "스킬",
                                "새로고침: \(skills.count)개 (외부 루트 \(skillRoots.count))")
    }

    /// 스킬 토글 바인딩 (T-285).
    func skillBinding(for name: String) -> Binding<Bool> {
        Binding(get: { skills.first(where: { $0.name == name })?.enabled
                ?? SkillsStore.isEnabled(name) },
                set: {
                    SkillsStore.setEnabled(name, $0)
                    reloadSkills()
                    DebugLogger.shared.info(feature: "스킬", "\(name) \($0 ? "켜짐" : "꺼짐")")
                })
    }
}

/// 설정 웹(Exa) 행 분리 (T-325, T-352): 본문 길이 분산.
extension SettingsView {
    /// Exa 상태·키 입력 행 (T-352): 키 저장+발급 링크+테스트.
    var exaRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(webSearchEnabled && !exaApiKey.isEmpty ? DSColor.success : .secondary)
                    .frame(width: 8, height: 8)
                Text(L(exaApiKey.isEmpty ? L10n.MCP.keyMissing : L10n.MCP.keySet))
                    .font(.system(size: 12))
                Spacer()
                Link(L(L10n.MCP.getKey), destination: URL(string: "https://dashboard.exa.ai")!)
                    .font(.system(size: 12))
                Button(L(L10n.MCP.test)) { testExa() }
                    .controlSize(.small)
                    .disabled(exaApiKey.isEmpty)
            }
            SecureField(L(L10n.MCP.keyPlaceholder), text: $exaApiKey)
                .textFieldStyle(.roundedBorder)
            if let result = exaTestResult {
                Text(result).font(.caption)
                    .foregroundStyle(result.hasPrefix(L(L10n.MCP.successPrefix)) ? Color.secondary : Color.red)
            }
            Text(L(L10n.MCP.keyFooter))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Exa 키 실검색 테스트 (T-352): 1건 조회, 결과 요약 표시.
    private func testExa() {
        exaTestResult = L(L10n.MCP.checking)
        DebugLogger.shared.info(feature: "웹검색", "Exa 키 테스트 시작")
        Task {
            do {
                let hits = try await WebSearch.search(query: "Swift programming", maxResults: 1)
                exaTestResult = hits.isEmpty
                    ? L(L10n.MCP.emptyResult)
                    : L(L10n.MCP.success, hits[0].title, hits[0].url)
            } catch {
                exaTestResult = L(L10n.MCP.failure, error.localizedDescription)
                DebugLogger.shared.error(code: "E-MAC-NET-0015", feature: "웹검색",
                                         "Exa 키 테스트 실패: \(error.localizedDescription)")
            }
        }
    }
}

/// MCP 서버 추가 시트 (T-285).
struct MCPAddSheet: View {
    @Binding var draft: MCPServerConfig
    var onSave: () -> Void
    var onCancel: () -> Void
    @State private var argsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(L10n.MCP.addTitle)).font(.system(size: 13, weight: .semibold))
            TextField(L(L10n.MCP.namePlaceholder), text: $draft.name)
                .textFieldStyle(.roundedBorder)
            Picker(L(L10n.MCP.transport), selection: $draft.transport) {
                Text(L(L10n.MCP.stdio)).tag(MCPServerConfig.Transport.stdio)
                Text(L(L10n.MCP.sse)).tag(MCPServerConfig.Transport.sse)
            }.pickerStyle(.segmented)
            if draft.transport == .stdio {
                TextField(L(L10n.MCP.commandPlaceholder), text: $draft.command)
                    .textFieldStyle(.roundedBorder)
                TextField(L(L10n.MCP.argsPlaceholder), text: $argsText)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(L(L10n.MCP.urlPlaceholder), text: $draft.url)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button(L(L10n.MCP.cancel), action: onCancel)
                Button(L(L10n.MCP.save)) {
                    draft.args = argsText.split(separator: " ").map(String.init)
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(16).frame(width: 420)
            .onAppear {
                argsText = draft.args.joined(separator: " ")
            }
    }
}
