import AppKit
import SwiftUI

/// 설정 MCP·스킬 탭 분리 (T-285, T-288 본문 길이 관리).
extension SettingsView {
    /// MCP 서버 탭.
    var mcpTab: some View {
        Form {
            if mcp.servers.isEmpty {
                Text("등록된 MCP 서버 없음. 추가 버튼으로 stdio·SSE 서버를 연결하세요.")
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
                        Button("테스트") { Task { await runMCPTest(srv) } }
                            .controlSize(.small)
                        Button("삭제", role: .destructive) { mcp.remove(id: srv.id) }
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
                Button("서버 추가") { mcpDraft = MCPServerConfig(name: "") ; showMCPAdd = true }
            }
            Text("외부 도구 호출은 매번 묻기 권한에서 확인 팝업이 뜹니다. stdio 명령은 직접 입력한 것만 실행됩니다.")
                .font(.caption).foregroundStyle(.secondary)
        }.dsSettingsForm()
            .tabItem { Label("MCP", systemImage: "server.rack") }
    }

    /// 스킬 탭 (T-315: 외부 루트·임포트 추가).
    var skillsTab: some View {
        Form {
            if skills.isEmpty {
                Text("SKILL.md 없음. 폴더 열기로 직접 넣거나, 가져오기로 외부 스킬을 복사하세요.")
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
                    Text("외부 스킬 폴더").font(DS.captionFont).foregroundStyle(.secondary)
                    ForEach(skillRoots, id: \.self) { root in
                        HStack(spacing: 6) {
                            Text(root).font(DS.captionFont).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("제거") {
                                SkillsStore.removeRoot(root)
                                reloadSkills()
                            }.controlSize(.small)
                        }
                    }
                }
            }
            HStack {
                Button("폴더 열기") {
                    NSWorkspace.shared.open(SkillsStore.skillsDir())
                }
                Button("폴더 추가") { pickSkillRoot() }
                Button("가져오기") {
                    skillCandidates = SkillsStore.importCandidates()
                    showSkillsImport = true
                }
                Button("새로고침") { reloadSkills() }
                Spacer()
            }
            Text("켜진 스킬 본문이 시스템 프롬프트 앞에 들어갑니다 (합계 8KB cap). 다음 전송부터 적용.")
                .font(.caption).foregroundStyle(.secondary)
        }.dsSettingsForm()
            .tabItem { Label("스킬", systemImage: "sparkles") }
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
        panel.prompt = "추가"
        panel.message = "스킬(SKILL.md) 폴더를 선택하세요."
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
        mcpTestResult[srv.id] = "확인 중…"
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
                Text(exaApiKey.isEmpty ? "Exa API 키 없음" : "Exa API 키 설정됨")
                    .font(.system(size: 12))
                Spacer()
                Link("키 발급", destination: URL(string: "https://dashboard.exa.ai")!)
                    .font(.system(size: 12))
                Button("테스트") { testExa() }
                    .controlSize(.small)
                    .disabled(exaApiKey.isEmpty)
            }
            SecureField("Exa API 키 (x-api-key)", text: $exaApiKey)
                .textFieldStyle(.roundedBorder)
            if let result = exaTestResult {
                Text(result).font(.caption)
                    .foregroundStyle(result.hasPrefix("성공") ? Color.secondary : Color.red)
            }
            Text("키는 이 Mac에만 저장됩니다. 웹 도구는 키가 있을 때만 모델에게 전달됩니다. "
                + "발급: https://dashboard.exa.ai")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Exa 키 실검색 테스트 (T-352): 1건 조회, 결과 요약 표시.
    private func testExa() {
        exaTestResult = "확인 중…"
        DebugLogger.shared.info(feature: "웹검색", "Exa 키 테스트 시작")
        Task {
            do {
                let hits = try await WebSearch.search(query: "Swift programming", maxResults: 1)
                exaTestResult = hits.isEmpty ? "응답은 왔으나 결과가 비었습니다."
                    : "성공 · \(hits[0].title) — \(hits[0].url)"
            } catch {
                exaTestResult = "실패 · \(error.localizedDescription)"
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
            Text("MCP 서버 추가").font(.system(size: 13, weight: .semibold))
            TextField("이름 (예: exa)", text: $draft.name)
                .textFieldStyle(.roundedBorder)
            Picker("전송", selection: $draft.transport) {
                Text("stdio (로컬 명령)").tag(MCPServerConfig.Transport.stdio)
                Text("SSE (원격 URL)").tag(MCPServerConfig.Transport.sse)
            }.pickerStyle(.segmented)
            if draft.transport == .stdio {
                TextField("명령 (예: npx)", text: $draft.command)
                    .textFieldStyle(.roundedBorder)
                TextField("인자 (공백 구분, 예: -y exa)", text: $argsText)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("URL (http(s)만, 예: http://127.0.0.1:3333/mcp)", text: $draft.url)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("취소", action: onCancel)
                Button("저장") {
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
