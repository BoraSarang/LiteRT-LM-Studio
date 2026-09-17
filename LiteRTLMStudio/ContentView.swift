import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// 3분할 매니저형: 사이드바(환경·모델·서버) / 중앙(채팅) / 인스펙터(생성 파라미터).
struct ContentView: View {
    @StateObject var uv = UvManager()
    @ObservedObject var models: ModelStore
    @ObservedObject var daemon: DaemonManager
    // 모니터는 직접 관찰하지 않음 (T-045): 1Hz 틱이 채팅 전체를 다시 그리며 CPU 100%를 냄.
    // 관찰은 SystemMetersView·BottomPanelView가 각자 담당 (해당 서브트리만 갱신).
    let monitor: SystemMonitor
    // 앱 내 엔진 엔진은 준비·해제 때만 퍼블리시라 직접 관찰 (사이드바 상태 표시용).
    @ObservedObject var nativeEngine: NativeEngine
    // T-216: 채팅·벤치마크는 AppServices 단일 인스턴스 공유 (별도창·사이드바).
    @ObservedObject var chat: ChatStore
    @ObservedObject var bench: BenchmarkStore
    @ObservedObject var benchHistory: BenchmarkHistoryStore
    /// T-262: 웰컴 새소식 공유 (AppServices 단일 인스턴스).
    @ObservedObject var releases: ReleaseNotes
    /// T-284: wigolo 공유 (자동 시작용).
    @ObservedObject var wigolo: WigoloManager
    /// T-266 S-2: 도구 승인 요청 공유 (싱글톤 관찰).
    @ObservedObject var toolApproval = ToolApproval.shared
    @StateObject var config = ConfigStore()
    @StateObject var logger = DebugLogger.shared

    // T-279: 모델 선택도 AppStorage (SceneStorage는 메뉴바 상주에서 복원 불안정).
    // 구 SceneStorage 값은 첫 복원 시 1회 승계.
    @AppStorage("selectedModelID") var selectedModelID: String?
    @SceneStorage("selectedModelID") var legacySelectedModelID: String?
    @SceneStorage("logPanelVisible")  var logPanelVisible = false
    // 표시 상태 4종은 재실행 유지가 필요해서 AppStorage (SceneStorage는 메뉴바 상주 생명주기에서 복원 불안정).
    @AppStorage("showSystem")  var showSystem = true
    @AppStorage("showBackend")  var showBackend = true
    @AppStorage("showGenerate")  var showGenerate = true
    @AppStorage("inspectorVisible")  var inspectorVisible = true
    @AppStorage("chatFontScale")  var chatFontScale = 1.0 // T-070 채팅 폰트 줌
    @AppStorage("sidebarTab")  var sidebarTabRaw = SidebarTab.chat.rawValue // T-230 탭 영속
    @AppStorage("appearance")  var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("onboardingDone") var onboardingDone = true // T-257 게이트 복귀용
    @Environment(\.colorScheme)  var colorScheme
    @Environment(\.openWindow)  var openWindow // T-053 디버그 윈도우
    @State var logTab = 0
    @State var aliasTarget: String?
    @State var aliasText = ""
    @State var showTakeoverConfirm = false
    @State var input = ""
    @State var showPalette = false
    @State var showWigoloBanner = false // T-286 설치 제안 배너
    @State var wigoloBannerShown = false // T-286 세션 1회 제한
    @State var attachedImage: ChatStore.ChatImage?
    @State var attachedName: String?
    @State var pinnedToBottom = false // Sticky-Pin: 하단 고정 시만 추종 (T-212 모름=false, 첫 보고에 정정)
    @State var viewportHeight: CGFloat = 600
    @StateObject var followGate = FollowGate() // T-044 휠 일시정지
    @StateObject var followUps = FollowUpStore() // T-291 후속질문 LLM
    @State var wheelMonitor: Any?
    @State var lastFollow = Date.distantPast
    @State var pauseNotified = false
    @State var chatScrollView: NSScrollView? // T-047 절대좌표 점프용
    @State var pendingScrollWorks: [DispatchWorkItem] = [] // T-047 수렴 예약
    @State var pendingSessionJump = true // T-046 첫 표시 점프 (복원 기록 포함)
    @State var scrollProxy: ScrollViewProxy? // T-081 Lazy 강제 생성용 프록시 보관
    @State var focusNonce = 0 // T-137 드래프트 시작 시 입력 포커스 신호
    @AppStorage("chatOutlineEnabled") var outlineEnabled = true // T-258 대화 목차 사용
    @AppStorage("followUpEnabled") var followUpEnabled = true // T-261 후속질문 칩
    @State var outlineFlashID: UUID? // T-258 점프 대상 플래시
    @State var outlineFlashWork: DispatchWorkItem? // T-258 플래시 해제 예약
    @State var suppressNextSessionJump = false // T-265 팔레트 전환 진입 체인 1회 억제

    var selectedModel: ModelStore.Model? {
        models.models.first(where: { $0.id == selectedModelID }) ?? models.models.first
    }

    /// 현재 외관 (T-041, 재실행 유지).
    var appearanceMode: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    /// 사이드바 타이틀 = 현재 채팅방 이름 (T-141). 드래프트는 "새 채팅".
    var roomTitle: String {
        guard let id = chat.currentSessionID,
              let s = chat.sessions.first(where: { $0.id == id }) else { return "새 채팅" }
        return s.displayTitle
    }

    /// 헤더 1줄째: 모델 표시명 (별칭 > 자동 예쁘게 > 원 ID).
    var headerTitle: String {
        guard let id = selectedModelID ?? models.models.first?.id else { return "모델 선택" }
        return ModelAlias.display(id: id)
    }

    /// 헤더 2줄째: 용량·모달리티·가속 요약 (여유 있게).
    var headerSubtitle: String {
        guard let mdl = selectedModel else { return "사이드바에서 모델을 고르세요" }
        var parts = [mdl.listedSize, mdl.modalities]
        if mdl.speculative { parts.append("MTP") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        // 하단 로그는 chatPane 하단 (사이드바 제외, T-039).
        // 팔레트는 Spotlight식 오버레이 (T-263, 시트 교체).
        rootEvents(rootDialogs(
            mainSplit
                .background { WindowTitleSync(title: roomTitle) }
                .toolbar { mainToolbar }
                .overlay { paletteOverlay }
        ))
    }

    /// 시트·다이얼로그·task·선택 동기 체인 (T-232: body 타입 추론 부하 분산용 분리).
    private func rootDialogs<T: View>(_ view: T) -> some View {
        view
            .sheet(isPresented: aliasBinding) {
                AliasSheetView(targetID: aliasTarget ?? "", text: $aliasText) {
                    if let id = aliasTarget { ModelAlias.setAlias(id: id, name: aliasText) }
                    logger.info(feature: "별칭", "\(aliasTarget ?? "") 표시 이름 저장")
                    aliasTarget = nil
                } onCancel: {
                    aliasTarget = nil
                }
            }
            .confirmationDialog("외부 데몬 인수", isPresented: $showTakeoverConfirm,
                                 titleVisibility: .visible) {
                Button("종료 후 앱 데몬으로 재시작", role: .destructive) {
                    Task { await daemon.takeOverAndRestart() }
                }
                Button("설정만 저장 (직접 재시작)") {
                    config.externalRestartPending = true
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("터미널에서 실행 중인 데몬을 종료하고 앱이 직접 띄운 데몬으로 바꿉니다. 터미널 쪽 연결은 끊어집니다.")
            }
            .confirmationDialog("도구 실행 허용", isPresented: toolApprovalBinding,
                                titleVisibility: .visible) {
                Button("허용") { toolApproval.resolve(true) }
                Button("거부", role: .cancel) { toolApproval.resolve(false) }
            } message: {
                Text(toolApproval.pending.map { "\($0.toolName) \($0.detail)" }
                    ?? "도구 실행을 허용할까요? (120초 무응답 시 거부)")
            }
            .task {
                await restoreState()
            }
            .onChange(of: selectedModelID) { _, v in
                if let v {
                    chat.model = v
                    config.load(modelID: v)
                }
                autoPrepareNativeIfNeeded()
            }
            .onChange(of: chat.route) { _, _ in
                autoPrepareNativeIfNeeded()
            }
            .onChange(of: daemon.status) { _, _ in
                monitor.invalidateDaemonCache()
                monitor.daemonRunning = daemon.status == .running
            }
            .onChange(of: appearanceRaw) { _, _ in
                AppearanceMode.apply(appearanceMode)
            }
    }

    /// 알림 체인 (T-232: body 타입 추론 부하 분산용 분리).
    private func rootEvents<T: View>(_ view: T) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
                chat.clear()
                wigoloBannerShown = false
                showWigoloBanner = false
                focusChatInput()
            }
            .onReceive(NotificationCenter.default.publisher(for: .serverStart)) { _ in
                Task { await daemon.start() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .serverStop)) { _ in daemon.stop() }
            .onReceive(NotificationCenter.default.publisher(for: .toggleDebug)) { _ in openWindow(id: "debug") }
            .onReceive(NotificationCenter.default.publisher(for: .openAbout)) { _ in openWindow(id: "about") }
            .onReceive(NotificationCenter.default.publisher(for: .openBenchmark)) { _ in openWindow(id: "benchmark") }
            .onReceive(NotificationCenter.default.publisher(for: .openModelManager)) { _ in
                openWindow(id: "modelManager")
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestAlias)) { n in
                if let id = n.object as? String {
                    aliasTarget = id
                    aliasText = ModelAlias.display(id: id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectChatModel)) { n in
                if let id = n.object as? String {
                    selectedModelID = id
                    DebugLogger.shared.info(feature: "모델관리", "채팅 모델 선택: \(id)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .runBenchmarkModel)) { n in
                guard let id = n.object as? String else { return }
                guard !bench.running else {
                    DebugLogger.shared.info(feature: "벤치마크", "측정 중이라 예약 무시: \(id)")
                    return
                }
                runBenchmark(id: id)
            }
            .onReceive(zoomNotes) { n in applyZoomNote(n) }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in toggleInspectorColumn() }
            .onReceive(NotificationCenter.default.publisher(for: .toggleLogPanel)) { _ in toggleLogPanel() }
            .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { _ in focusChatInput() }
    }

    /// 별칭 시트 바인딩 (T-232 분리).
    private var aliasBinding: Binding<Bool> {
        Binding(get: { aliasTarget != nil }, set: { if !$0 { aliasTarget = nil } })
    }

    /// 도구 승인 바인딩 (T-266 S-2): 닫힘=거부.
    private var toolApprovalBinding: Binding<Bool> {
        Binding(get: { toolApproval.pending != nil },
                set: { if !$0 { toolApproval.resolve(false) } })
    }
    /// 3분할 본체 (T-232: body 타입 추론 부하 분산용 분리).
    /// 3번째 칸 숨김은 visibility가 아니라 레이아웃 분기로 (.doubleColumn은 사이드바를 숨기므로 사용 금지).
    private var mainSplit: some View {
        Group {
            if inspectorColumnShown {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 320)
                } content: {
                    chatPane
                } detail: {
                    inspector
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 320)
                } detail: {
                    chatPane
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
    }

    /// 툴바 본체 (T-232: body 타입 추론 부하 분산용 분리).
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { showPalette = true } label: {
                Image(systemName: "command").font(.system(size: 16, weight: .semibold))
            }.help("명령 팔레트 (⌘K)").keyboardShortcut("k", modifiers: .command)
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(headerSubtitle)
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        ToolbarItem(placement: .primaryAction) {
            // 독립 캡슐: 그룹 캡슐 재계산 시 정지 버튼 이탈 방지. 고정폭으로 글리프 너비차 흡수.
            Button { toggleServer() } label: {
                Image(systemName: serverIcon).font(.system(size: 16, weight: .semibold))
                    .frame(width: 28)
            }
            .help(serverHelp)
            .disabled(serverDisabled)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { toggleLogPanel() } label: {
                Image(systemName: "terminal").font(.system(size: 16, weight: .semibold))
            }
            .help(daemon.status == .running ? "하단 패널 토글 (⌘J)" : "서버 실행 중에만 볼 수 있어요 (⌘J)")
            .disabled(daemon.status != .running)
        }
        ToolbarItem(placement: .primaryAction) {
            // 인스펙터 3섹션 on/off 분할 컨트롤 (진실원천).
            SectionSegments(system: $showSystem, backend: $showBackend,
                            generate: $showGenerate)
        }
        ToolbarItem(placement: .primaryAction) {
            // 인스펙터 전체 보이기/숨기기 (맨 오른쪽 끝).
            Button { toggleInspectorColumn() } label: {
                Image(systemName: "sidebar.right").font(.system(size: 16, weight: .semibold))
            }.help(anySectionVisible ? "인스펙터 토글 (⌥⌘I)" : "인스펙터 보이기 (⌥⌘I)")
        }
    }

    /// 입력 포커스 (T-137): 다음 런루프에 신호 증가 (ChatInputBar가 감지해 포커스).
    func focusChatInput() {
        DispatchQueue.main.async { focusNonce += 1 }
    }
}
