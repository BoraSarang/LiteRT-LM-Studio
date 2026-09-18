import AppKit
import SwiftUI

/// 설정 MCP·스킬·wigolo 탭 분리 (T-285, T-288 본문 길이 관리).
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
        }.formStyle(.grouped).padding()
            .tabItem { Label("MCP", systemImage: "server.rack") }
    }

    /// 스킬 탭.
    var skillsTab: some View {
        Form {
            if skills.isEmpty {
                Text("SKILL.md 없음. 폴더 열기로 Skills 폴더에 <이름>/SKILL.md를 넣으세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(skills) { skill in
                Toggle(skill.name, isOn: skillBinding(for: skill.name))
                    .help(skill.blurb)
            }
            HStack {
                Button("폴더 열기") {
                    NSWorkspace.shared.open(SkillsStore.skillsDir())
                }
                Button("새로고침") { reloadSkills() }
                Spacer()
            }
            Text("켜진 스킬 본문이 시스템 프롬프트 앞에 들어갑니다 (합계 8KB cap). 다음 전송부터 적용.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).padding()
            .tabItem { Label("스킬", systemImage: "sparkles") }
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

    /// 스킬 목록 새로고침 (T-285).
    func reloadSkills() {
        skills = SkillsStore.list()
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

    /// wigolo 상태·설치 행 (T-287, T-288 내장 검색 4칸+단계+로그 복사).
    var wigoloRows: some View {
        Group {
            HStack(spacing: 8) {
                Circle().fill(wigoloDot).frame(width: 8, height: 8)
                Text("내장 검색 \(wigolo.status.rawValue)\(wigoloVersionSuffix)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if wigolo.status == .missing {
                    Button("설치") { showInstallConfirm = true }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                } else if wigolo.status == .installing {
                    Button("취소") { wigolo.cancelInstall() }.controlSize(.small)
                } else if wigolo.status == .running {
                    Button("중지") { wigolo.stop() }.controlSize(.small)
                } else {
                    Button("시작") { wigolo.start() }.controlSize(.small)
                }
                Button("다시 확인") { Task { await wigolo.doctor() } }
                    .controlSize(.small)
                ServeLogButton(wigolo: wigolo)
            }
            .help("내장 검색 엔진 (wigolo 로컬 데몬, 127.0.0.1:3333). 앱 시작 시 자동 실행.")
            HStack(spacing: 12) {
                healthLane(title: "CLI", ok: wigolo.health.cli)
                healthLane(title: "데몬", ok: wigolo.health.daemon)
                healthLane(title: "브라우저", ok: wigolo.health.browser)
                healthLane(title: "모델", ok: wigolo.health.models)
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
            if let stage = wigolo.installStage {
                Text(stage).font(.caption).foregroundStyle(.orange)
            }
            if wigolo.status == .installing || !wigolo.installLog.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(wigolo.installLog.indices, id: \.self) { i in
                            Text(wigolo.installLog[i])
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(height: 120)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
                HStack {
                    Spacer()
                    Button("로그 복사") {
                        PasteboardUtil.copy(wigolo.installLog.joined(separator: "\n"))
                    }.controlSize(.small)
                }
            }
        }
    }

    /// 상태 1칸 (T-288).
    func healthLane(title: String, ok: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(ok ? Color.green : Color.gray).frame(width: 6, height: 6)
            Text(title)
        }
    }

    /// wigolo 상태점 (T-284).
    var wigoloDot: Color {
        switch wigolo.status {
        case .running: .green
        case .starting, .installing: .orange
        case .failed, .missing: .red
        case .stopped: .gray
        }
    }

    /// wigolo 버전 접미 (T-284).
    var wigoloVersionSuffix: String {
        wigolo.version.map { " · \($0)" } ?? ""
    }
}

/// 검색 데몬 실행 로그 버튼+팝오버 (T-308): `시작` 출력 확인용.
struct ServeLogButton: View {
    @ObservedObject var wigolo: WigoloManager
    @State private var show = false

    var body: some View {
        Button("로그 보기") {
            show = true
            DebugLogger.shared.info(feature: "웹검색", "실행 로그 보기 열기")
        }
        .controlSize(.small)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("검색 데몬 실행 로그")
                    .font(.system(size: 13, weight: .semibold))
                if wigolo.serveLog.isEmpty {
                    Text("아직 실행 로그가 없어요. 시작을 누르면 여기에 표시됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(wigolo.serveLog.indices, id: \.self) { i in
                                Text(wigolo.serveLog[i])
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(height: 200)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
                }
                HStack {
                    Spacer()
                    if !wigolo.serveLog.isEmpty {
                        Button("복사") {
                            PasteboardUtil.copy(wigolo.serveLog.joined(separator: "\n"))
                        }.controlSize(.small)
                    }
                    Button("닫기") { show = false }.controlSize(.small)
                }
            }
            .padding(12)
            .frame(width: 440)
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
            TextField("이름 (예: wigolo)", text: $draft.name)
                .textFieldStyle(.roundedBorder)
            Picker("전송", selection: $draft.transport) {
                Text("stdio (로컬 명령)").tag(MCPServerConfig.Transport.stdio)
                Text("SSE (원격 URL)").tag(MCPServerConfig.Transport.sse)
            }.pickerStyle(.segmented)
            if draft.transport == .stdio {
                TextField("명령 (예: npx)", text: $draft.command)
                    .textFieldStyle(.roundedBorder)
                TextField("인자 (공백 구분, 예: -y wigolo)", text: $argsText)
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
