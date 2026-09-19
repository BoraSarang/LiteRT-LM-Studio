import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var wigolo: WigoloManager
    @ObservedObject var config: ConfigStore
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("quitStopsDaemon") private var quitStopsDaemon = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("historyTurns") private var historyTurns = HistoryWindow.turns10.rawValue
    @AppStorage("benchmarkRetention") private var benchmarkRetention = BenchmarkRetention.ten.rawValue
    @AppStorage("globalPermission") private var permissionRaw = GlobalPermission.ask.rawValue
    @AppStorage("chatOutlineEnabled") private var outlineEnabled = true // T-258 대화 목차
    @AppStorage("followUpEnabled") private var followUpEnabled = true // T-261 후속질문 칩
    @AppStorage("webSearchEnabled") private var webSearchEnabled = true // T-269 웹 검색 도구
    @AppStorage("prefillWarmup") private var prefillWarmup = false // T-302 첫터치 프리필
    @AppStorage("workspaceRoot") private var workspaceRoot = "" // T-272 작업폴더 (빈값=기본값)
    @AppStorage("selectedModelID") private var selectedModelID: String? // 모델 ID 저장
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
    @State var showInstallConfirm = false // T-284 wigolo 설치 확인 (확장 접근용)

    var body: some View {
        TabView {
            ScrollView {
            Form {
                DSSection("외관") {
                DSSegmented("외관", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
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
                }
                DSSection("시스템") {
                Toggle("앱 종료 시 데몬도 함께 종료", isOn: $quitStopsDaemon)
                    .help("끄면 앱을 닫아도 데몬이 남아 다음 실행 때 바로 씁니다. 터미널 데몬은 항상 유지됩니다.")
                Text("전송 경로(서버·앱 내 엔진)는 채팅 입력창의 피커에서 매번 선택합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("MTP(추측적 디코딩) 활성화", isOn: Binding(
                        get: { config.draftMTP },
                        set: { config.draftMTP = $0 }
                    ))
                    .help("Gemma 4 등 지원 모델에서 디코드 속도 2-3배 향상. 모델 재시작 필요.")
                    .onChange(of: config.draftMTP) { _, on in
                        DebugLogger.shared.info(feature: "MTP", on ? "활성화" : "비활성화")
                    }
                }
                DSSection("대화") {
                DSSegmented("대화 기록 전송", selection: $historyTurns) {
                    ForEach(HistoryWindow.allCases, id: \.rawValue) { w in
                        Text(w.title).tag(w.rawValue)
                    }
                }
                    .help("매 전송에 포함할 과거 대화 범위. 짧을수록 빠르지만 앞부분 맥락이 잘립니다. 제한 없음은 기존 그대로 전부 전송합니다.")
                    .onChange(of: historyTurns) { _, raw in
                        DebugLogger.shared.info(
                            feature: "히스토리범위",
                            "전환: \((HistoryWindow(rawValue: raw) ?? .unlimited).title)")
                    }
                DSSegmented("벤치마크 기록 보관", selection: $benchmarkRetention) {
                    ForEach(BenchmarkRetention.allCases, id: \.rawValue) { r in
                        Text(r.title).tag(r.rawValue)
                    }
                }
                    .help("벤치마크 히스토리 최대 보관 수. 초과분은 오래된 것부터 삭제됩니다.")
                    .onChange(of: benchmarkRetention) { _, raw in
                        DebugLogger.shared.info(
                            feature: "벤치마크",
                            "보관 전환: \((BenchmarkRetention(rawValue: raw) ?? .ten).title)")
                    }
                }
                DSSection("권한") {
                DSSegmented("권한", selection: $permissionRaw) {
                    ForEach(GlobalPermission.allCases, id: \.rawValue) { p in
                        Text(p.title).tag(p.rawValue)
                    }
                }
                    .help("모델 삭제·가져오기·설치에 적용되는 전역 권한. 사용 안 함=차단, 매번 묻기=확인 후 실행, 모두 허용=바로 실행. 채팅 전송은 항상 허용.")
                    .onChange(of: permissionRaw) { _, raw in
                        DebugLogger.shared.info(
                            feature: "권한",
                            "전환: \((GlobalPermission(rawValue: raw) ?? .ask).title)")
                    }
                }
if let err = loginError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Text("포트는 127.0.0.1:9379 고정, 모델은 ~/.litert-lm/models 참조.")
                .font(.caption).foregroundStyle(.secondary)
            // 적용 버튼 (변경사항 저장)
            Section {
                HStack {
                    Spacer()
                    Button("적용") {
                        let modelID = selectedModelID
                            ?? UserDefaults.standard.string(forKey: "selectedModelID")
                            ?? ""
                        guard !modelID.isEmpty else {
                            DebugLogger.shared.info(feature: "설정", "적용 실패: 모델 미선택")
                            return
                        }
                        config.apply(modelID: modelID)
                        DebugLogger.shared.info(feature: "설정", "적용 완료: \(modelID)")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(DSColor.primary)
                    .disabled(!config.hasChanges)
                }
            }
        }.formStyle(.grouped).padding()
            }
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
                Toggle("첫터치 프리필", isOn: $prefillWarmup)
                    .help("방을 열람하면 기반 모델을 미리 준비해 첫 응답의 준비 구간을 줄입니다. 켜두면 발열·배터리를 조금 더 사용합니다.")
                    .onChange(of: prefillWarmup) { _, on in
                        DebugLogger.shared.info(feature: "프리필", on ? "켜짐" : "꺼짐")
                    }
                Toggle("웹 도구 사용", isOn: $webSearchEnabled)
                    .help("모델이 web_search·web_fetch 도구를 쓸 수 있게 합니다. wigolo 설치 필요.")
                    .onChange(of: webSearchEnabled) { _, on in
                        DebugLogger.shared.info(feature: "웹검색", on ? "켜짐" : "꺼짐")
                        if on {
                            if WigoloManager.resolveBinary() == nil {
                                showInstallConfirm = true
                            } else {
                                Task { await wigolo.ensureRunning() }
                            }
                        }
                    }
            }.formStyle(.grouped).padding()
                .tabItem { Label("채팅", systemImage: "bubble.left.and.bubble.right") }
            Form {
                ForEach(ToolInfo.Category.allCases, id: \.rawValue) { category in
                    Section(category.rawValue) {
                        ForEach(ToolCatalog.all.filter { $0.category == category }) { info in
                            Toggle(info.title, isOn: toolBinding(for: info.name))
                                .help(info.detail)
                        }
                        if category == .web {
                            wigoloRows
                        }
                    }
                }
                Text("꺼진 도구는 모델에게 전달되지 않습니다. 실행 여부는 일반 탭의 권한(사용 안 함·매번 묻기·모두 허용)이 정합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("작업폴더: \(workspaceRoot.isEmpty ? "기본값" : workspaceRoot)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("선택") { pickWorkspace() }
                    if !workspaceRoot.isEmpty {
                        Button("기본값") { workspaceRoot = "" }
                    }
                }.help("셸·파일 도구가 접근할 수 있는 폴더. 밖은 차단됩니다.")
            }.formStyle(.grouped).padding()
                .tabItem { Label("도구", systemImage: "wrench") }
            mcpTab
            skillsTab
        }.frame(minWidth: 580, minHeight: 420)
            .onAppear {
                let mid = selectedModelID
                    ?? UserDefaults.standard.string(forKey: "selectedModelID")
                if let mid, !mid.isEmpty { config.load(modelID: mid) }
                reloadToolFlags(); reloadSkills()
            }
            .onChange(of: selectedModelID) { _, v in
                let mid = v ?? UserDefaults.standard.string(forKey: "selectedModelID")
                if let mid, !mid.isEmpty { config.load(modelID: mid) }
            }
            .confirmationDialog("wigolo 설치", isPresented: $showInstallConfirm,
                                titleVisibility: .visible) {
                Button("설치 (패키지+초기화, 약 1.5GB 내려받음)") { wigolo.install() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("`npm i -g wigolo` 후 `wigolo init`을 실행합니다. 수 분 걸릴 수 있어요.")
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
            loginError = "로그인 항목 변경 실패: \(error.localizedDescription)"
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
            Text("스킬 가져오기").font(.system(size: 13, weight: .semibold))

            // 검색 필드
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("스킬 이름 또는 설명 검색", text: $searchText)
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
                     ? "가져올 외부 스킬을 찾지 못했어요. (opencode·claude·agents 스킬 폴더 확인)"
                     : "'\(searchText)'에 일치하는 스킬이 없습니다")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                // 헤더: 카운트 + 액션
                let installedCount = candidates.filter { $0.installed }.count
                HStack {
                    Text("총 \(candidates.count)개 · 검색 \(filteredCandidates.count)개 · 설치됨 \(installedCount)개")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("모두 선택") {
                        selected = Set(filteredCandidates.filter { !$0.installed }.map { $0.id })
                    }.controlSize(.small)
                    Button("모두 해제") { selected.removeAll() }.controlSize(.small)
                    Button(action: onRefresh) {
                        Label("새로고침", systemImage: "arrow.clockwise")
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
                                            Text("설치됨").font(DS.captionFont)
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
                Button("닫기", action: onClose)
                Button("가져오기") {
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
