import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// 추종 게이트 상태 박스 (T-044): escaping 휠 모니터가 최신값을 읽기 위한 참조형.
/// `pinnedToBottom`(@State, 오버레이 표시용)과 별도로 제스처 시각만 보관.
final class FollowGate: ObservableObject {
    var hover = false
    var lastWheel = Date.distantPast
    var lastContent: CGFloat = 0 // T-048 마지막 관측 문서 높이 (증가 감지용)
    var entryWorks: [DispatchWorkItem] = [] // T-078 진입 점프 독립 예약
    var entrySince = Date.distantPast // T-078 진입 시작 시각 (휠 존중용)
    var wheelAccum: CGFloat = 0 // T-080 휠 누적 (미세 접촉 무시용)
    var lastDocHeights: [CGFloat] = [] // T-080 진입 수렴 안정 판정용
    var kickDone = false // T-083 프록시 킥 1회 플래그
    var verifyKickDone = false // T-086 수렴 검증 킥 플래그
}

/// 상위 NSScrollView 탐색 (T-047): 절대좌표 점프용 AppKit 진입점. 렌더 없음(AIModelTalk 이식).
/// ScrollViewProxy의 레이아웃 스냅샷 오차 없이 문서 끝으로 이동한다.
struct ScrollViewFinder: NSViewRepresentable {
    let onFound: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        DispatchQueue.main.async { [weak host] in
            guard let host else { return }
            // 계층 부착이 늦는 경우가 있어 재시도 — 발견 시 즉시 중단.
            var attempt = 0
            func walk() {
                var current: NSView? = host
                while let candidate = current {
                    if let scrollView = candidate as? NSScrollView {
                        onFound(scrollView)
                        return
                    }
                    current = candidate.superview
                }
                attempt += 1
                if attempt < 40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: walk)
                }
            }
            walk()
        }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 3분할 매니저형: 사이드바(환경·모델·서버) / 중앙(채팅) / 인스펙터(생성 파라미터).
struct ContentView: View {
    @StateObject private var uv = UvManager()
    @StateObject private var models = ModelStore()
    @ObservedObject var daemon: DaemonManager
    // 모니터는 직접 관찰하지 않음 (T-045): 1Hz 틱이 채팅 전체를 다시 그리며 CPU 100%를 냄.
    // 관찰은 SystemMetersView·BottomPanelView가 각자 담당 (해당 서브트리만 갱신).
    let monitor: SystemMonitor
    @StateObject private var chat = ChatStore()
    @StateObject private var config = ConfigStore()
    @StateObject private var logger = DebugLogger.shared

    @SceneStorage("selectedModelID") private var selectedModelID: String?
    @SceneStorage("logPanelVisible") private var logPanelVisible = false
    // 표시 상태 4종은 재실행 유지가 필요해서 AppStorage (SceneStorage는 메뉴바 상주 생명주기에서 복원 불안정).
    @AppStorage("showSystem") private var showSystem = true
    @AppStorage("showBackend") private var showBackend = true
    @AppStorage("showGenerate") private var showGenerate = true
    @AppStorage("inspectorVisible") private var inspectorVisible = true
    @AppStorage("chatFontScale") private var chatFontScale = 1.0 // T-070 채팅 폰트 줌
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow // T-053 디버그 윈도우
    @State private var logTab = 0
    @State private var aliasTarget: String?
    @State private var aliasText = ""
    @State private var showTakeoverConfirm = false
    @State private var input = ""
    @State private var showPalette = false
    @State private var attachedImage: (data: Data, mime: String)?
    @State private var attachedName: String?
    @State private var pinnedToBottom = true // Sticky-Pin: 하단 고정 시만 추종
    @State private var viewportHeight: CGFloat = 600
    @StateObject private var followGate = FollowGate() // T-044 휠 일시정지
    @State private var wheelMonitor: Any?
    @State private var lastFollow = Date.distantPast
    @State private var pauseNotified = false
    @State private var chatScrollView: NSScrollView? // T-047 절대좌표 점프용
    @State private var pendingScrollWorks: [DispatchWorkItem] = [] // T-047 수렴 예약
    @State private var pendingSessionJump = true // T-046 첫 표시 점프 (복원 기록 포함)
    @State private var scrollProxy: ScrollViewProxy? // T-081 Lazy 강제 생성용 프록시 보관
    @StateObject private var bench = BenchmarkStore()
    @State private var showBench = false

    var selectedModel: ModelStore.Model? {
        models.models.first(where: { $0.id == selectedModelID }) ?? models.models.first
    }

    /// 현재 외관 (T-041, 재실행 유지).
    var appearanceMode: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    /// 헤더 1줄째: 별칭 > 자동 예쁘게 > 원 ID.
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
        Group {
            // 3번째 칸 숨김은 visibility가 아니라 레이아웃 분기로 (.doubleColumn은 사이드바를 숨기므로 사용 금지).
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showPalette = true } label: {
                    Image(systemName: "command").font(.system(size: 16, weight: .semibold))
                }.help("명령 팔레트 (⌘K)")
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(headerTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(headerSubtitle)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
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
                .disabled(daemon.status == .starting)
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
        .sheet(isPresented: $showPalette) { palette }
        .sheet(isPresented: $showBench) { BenchmarkView(store: bench) }
        .sheet(isPresented: Binding(get: { aliasTarget != nil }, set: { if !$0 { aliasTarget = nil } })) {
            AliasSheetView(targetID: aliasTarget ?? "", text: $aliasText) {
                if let id = aliasTarget { ModelAlias.setAlias(id: id, name: aliasText) }
                logger.info(feature: "별칭", "\(aliasTarget ?? "") 표시 이름 저장")
                aliasTarget = nil
            } onCancel: {
                aliasTarget = nil
            }
        }
        .confirmationDialog("외부 데몬 인수", isPresented: $showTakeoverConfirm, titleVisibility: .visible) {
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
        .task {
            await uv.refresh()
            await models.refresh()
            let modelID = selectedModelID ?? models.models.first?.id ?? "gemma4-12b"
            config.load(modelID: modelID)
            if await daemon.isHealthy() {
                daemon.status = .running
                daemon.external = true
            }
            chat.model = selectedModelID ?? chat.model
            monitor.start()
            monitor.daemonRunning = daemon.status == .running
            daemon.beginPolling()
            // Dock 정책·외관은 화면 표시 이후 적용 (App.init 시점 호출 금지).
            NSApp.setActivationPolicy(UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory)
            AppearanceMode.apply(appearanceMode)
            logger.info(feature: "앱시작", "상태 복원 완료")
        }
        .onChange(of: selectedModelID) { _, v in
            if let v {
                chat.model = v
                config.load(modelID: v)
            }
        }
        .onChange(of: daemon.status) { _, _ in
            monitor.invalidateDaemonCache()
            monitor.daemonRunning = daemon.status == .running
        }
        .onChange(of: appearanceRaw) { _, _ in
            AppearanceMode.apply(appearanceMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in chat.clear() }
        .onReceive(NotificationCenter.default.publisher(for: .serverStart)) { _ in
            Task { await daemon.start() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverStop)) { _ in daemon.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleDebug)) { _ in openWindow(id: "debug") }
        .onReceive(NotificationCenter.default.publisher(for: .openAbout)) { _ in openWindow(id: "about") }
        .onReceive(zoomNotes) { n in applyZoomNote(n) }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in toggleInspectorColumn() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLogPanel)) { _ in toggleLogPanel() }
    }

    // MARK: - 채팅
    var chatPane: some View {
        VStack(spacing: 0) {
            if chat.messages.isEmpty {
                // 정렬 규칙: 데이터 없음 → 가로·세로 중앙 정렬
                ContentUnavailableView(
                    "서버를 시작하고 채팅해 보세요",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("사이드바에서 모델을 고르고 ▶ 버튼(⌘R)으로 데몬을 띄우세요. 서버 시작 후 ⌘J로 서버 로그를 볼 수 있어요.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(chat.messages) { m in
                            MessageBubbleView(
                                message: m,
                                showCursor: chat.streaming && m.id == chat.messages.last?.id,
                                preparing: chat.preparing && m.id == chat.messages.last?.id,
                                scheme: AppearanceMode.effectiveScheme(
                                    mode: appearanceMode, systemDark: colorScheme == .dark),
                                isStreaming: chat.streaming && m.id == chat.messages.last?.id,
                                fontScale: chatFontScale,
                                onRetry: { chat.retry() }
                            ).id(m.id)
                        }
                            // 하단 앵커: 스택 안에서 측정해야 위치 정확 (T-036)
                            Color.clear.frame(height: 1)
                                .id("chatBottom") // T-081 프록시 강제 생성용
                                .background {
                                    GeometryReader { geo in
                                        Color.clear.onChange(of: geo.frame(in: .named("chatScroll")).maxY) { _, maxY in
                                            pinnedToBottom = Self.isPinnedToBottom(
                                                bottomMaxY: maxY, viewportHeight: viewportHeight)
                                        }
                                    }
                                }
                    }.padding(.vertical, 16) // T-096 가로 여백 통일 (열 cap과 일치)
                    .frame(maxWidth: DS.chatMaxWidth) // T-091 열 폭 고정
                    .frame(maxWidth: .infinity) // 중앙 정렬
                    .background {
                        ScrollViewFinder { chatScrollView = $0 }
                            .frame(width: 0, height: 0)
                    }
                    .onAppear { scrollProxy = proxy } // T-081 body 평가 중 변경 회피
                    }
                    .coordinateSpace(name: "chatScroll")
                    .background {
                        GeometryReader { geo in
                            Color.clear.onChange(of: geo.size.height, initial: true) { _, h in
                                viewportHeight = h
                            }
                        }
                    }
                    .onChange(of: chat.messages.last?.text) { _, _ in
                        // 추종 (T-048): 문서가 늘었을 때만 따라감. 증가 없으면 스킵(무진동),
                        // 하단 스킵은 정적 콘텐츠에만 유효해서 증가 판정으로 교체.
                        let now = Date()
                        let wheeling = now.timeIntervalSince(followGate.lastWheel) < 0.8
                        if wheeling, !pauseNotified {
                            pauseNotified = true
                            logger.info(feature: "스크롤", "읽는 중 — 자동 추종 일시정지")
                        }
                        let contentH = chatScrollView?.documentView?.bounds.height ?? 0
                        let grew = Self.contentGrew(current: contentH, last: followGate.lastContent)
                        followGate.lastContent = max(followGate.lastContent, contentH)
                        guard grew else { return }
                        guard Self.shouldFollow(pinned: pinnedToBottom, now: now,
                                                lastFollow: lastFollow,
                                                lastWheel: followGate.lastWheel),
                              chat.messages.last?.id != nil else { return }
                        lastFollow = now
                        if pauseNotified {
                            pauseNotified = false
                            logger.info(feature: "스크롤", "하단 복귀 — 자동 추종 재개")
                        }
                        DispatchQueue.main.async {
                            // 발사 후 휠이 들어오면 건너뜀 (사용자 제스처 우선).
                            if self.pinnedToBottom,
                               Date().timeIntervalSince(self.followGate.lastWheel) >= 0.8 {
                                self.jumpToBottom()
                            }
                        }
                    }
                    .onChange(of: chat.streaming) { _, streaming in
                        if streaming {
                            // 전송 시작: 명시 의사라 게이트 우회 즉시 점프 (T-076).
                            sendJump()
                        } else if pinnedToBottom {
                            // 응답 완료: 높이 정착 수렴 (핀 ON일 때만, T-047).
                            scrollToFitBottom(cancelOnWheelSince: Date())
                        }
                    }
                    .onHover { followGate.hover = $0 }
                    .onAppear {
                        installWheelMonitor()
                        // 첫 표시 점프 (T-046): 복원 기록·빈 화면→대화 전환. 1회만 소비.
                        if pendingSessionJump {
                            sessionJump(to: chat.currentSessionID)
                        }
                    }
                    .onDisappear { removeWheelMonitor() }
                    .overlay(alignment: .bottom) {
                        if !pinnedToBottom { scrollBottomButton }
                    }
                }
            }
            if logPanelVisible, daemon.status == .running {
                bottomPanel
                    .frame(maxWidth: DS.chatMaxWidth) // T-093 터미널 로그 열폭 통일
                    .padding(.top, 8) // T-094 구분선 제거 대체 간격
            }
            ChatInputBar(chat: chat, daemon: daemon, input: $input,
                         attachedImage: $attachedImage, attachedName: $attachedName)
                .frame(maxWidth: DS.chatMaxWidth) // T-093 입력창 열폭 통일
                .padding(.top, 8) // T-094 구분선 제거 대체 간격
        }
        .padding(12) // T-095 바깥 카드 여백
        .background(Color(nsColor: .controlBackgroundColor)) // T-095 카드 배경
        .clipShape(.rect(cornerRadius: 12)) // T-095 모서리 클립
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator) } // T-095 외곽선
        .onChange(of: chat.currentSessionID) { _, id in sessionJump(to: id) }
    }

    // MARK: - 인스펙터 (3섹션 on/off, 토글은 툴바 섹션 토글)
    var inspector: some View {
        Form {
            if showSystem {
                Section(InspectorTitle.system) {
                    SystemMetersView(monitor: monitor)
                }
            }
            if showBackend {
                Section(InspectorTitle.backend) {
                    BackendSectionView(config: config, model: selectedModel) {
                        applyBackend()
                    }
                }
            }
            if showGenerate {
                Section(InspectorTitle.generate) {
                    HStack {
                        Text("Temperature"); Slider(value: $chat.temperature, in: 0...1.5, step: 0.05)
                        Text(String(format: "%.2f", chat.temperature)).monospacedDigit()
                    }
                    // 현 gemma4-12b 미지원 → 비활성화 + 툴팁 (describe 실측 반영)
                    Toggle("Thinking", isOn: .constant(false)).disabled(true)
                        .help(selectedModel?.thinking == true ? "" : "이 모델은 Thinking 미지원 (E-MAC-VALID-0007)")
                    Toggle("Function Calling", isOn: .constant(false)).disabled(true)
                        .help(selectedModel?.functionCall == true ? "" : "이 모델은 Function Calling 미지원 (E-MAC-VALID-0008)")
                    Text("지원 모델을 가져오면 활성화됩니다.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped).padding(8)
        .navigationSplitViewColumnWidth(min: 320, ideal: 320, max: 320) // T-072 사이드바 접힘 영향 차단
    }

    // MARK: - 하단 패널 (chatPane 하단·⌘J·실행 중에만, T-039)
    var bottomPanel: some View {
        BottomPanelView(daemon: daemon, monitor: monitor, logTab: $logTab) {
            logPanelVisible = false
        } onTakeover: {
            showTakeoverConfirm = true
        }
    }

    // MARK: - 팔레트
    var palette: some View {
        PaletteView(chat: chat, daemon: daemon, models: models,
                    showPalette: $showPalette) {
            toggleLogPanel()
        }
    }
}

// MARK: - 액션 (타입 본문 길이 관리용 분리)
extension ContentView {
    /// 폰트 줌 적용 (T-070): 리셋 또는 ±스텝, 재실행 유지(AppStorage).
    private func applyZoom(step: Double = 0, reset: Bool = false) {
        chatFontScale = reset ? 1.0 : Self.steppedZoom(chatFontScale, step: step)
        logger.info(feature: "폰트", "채팅 크기 \(Int(chatFontScale * 100))%")
    }

    /// 줌 알림 병합 (T-070): onReceive 체인 1개로 묶어 타입체크 부하 방지.
    private var zoomNotes: AnyPublisher<Notification, Never> {
        let c = NotificationCenter.default
        return Publishers.MergeMany([
            c.publisher(for: .chatZoomIn),
            c.publisher(for: .chatZoomOut),
            c.publisher(for: .chatZoomReset),
        ]).eraseToAnyPublisher()
    }

    /// 줌 알림 분기 (T-070).
    private func applyZoomNote(_ n: Notification) {
        switch n.name {
        case .chatZoomIn: applyZoom(step: 0.1)
        case .chatZoomOut: applyZoom(step: -0.1)
        default: applyZoom(reset: true)
        }
    }

    /// 진입 점프 수렴 (T-078, T-080 수렴 기반): 문서 높이 안정까지 연장(상한 5초),
    /// 스트리밍 탭과 독립 예약. 성공 확인 후 남은 예약 취소+플래그 해제.
    private func scheduleEntryJump(session: UUID?) {
        followGate.entryWorks.forEach { $0.cancel() }
        followGate.entryWorks.removeAll()
        followGate.entrySince = Date()
        followGate.lastDocHeights = []
        followGate.kickDone = false
        followGate.verifyKickDone = false
        // T-084 진입 진단 (시작 1줄).
        let docH0 = chatScrollView?.documentView?.bounds.height ?? -1
        let off0 = chatScrollView.map { Int($0.contentView.bounds.origin.y) } ?? -1
        logger.info(feature: "진입", "시작 메시지=\(chat.messages.count) 문서=\(Int(docH0)) 오프셋=\(off0)")
        entryPoll(session: session, attempt: 0)
    }

    /// 세션 전환·첫 표시 하단 점프 (T-046, T-084 확장 이전): 명시 이동이라 T-044 게이트 우회.
    /// 수렴은 진입 전용 예약으로 분리: 스트리밍 탭과 취소 공유 안 함.
    private func sessionJump(to session: UUID?) {
        pinnedToBottom = true
        lastFollow = .distantPast
        followGate.lastWheel = .distantPast
        followGate.wheelAccum = 0
        followGate.lastContent = 0 // T-048 이전 세션 문서 높이 잔재 제거
        pauseNotified = false
        logger.info(feature: "스크롤", "채팅 전환 — 하단 이동")
        scheduleEntryJump(session: session ?? chat.currentSessionID)
    }

    /// 진입 폴링 1회 (T-080, T-081, T-083): 킥은 레이아웃 증거 후 1회,
    /// 이후 상한까지 절대점프 풀 회전. 조기 종료는 수렴+안정+최소 회차 모두 만족 때만.
    private func entryPoll(session: UUID?, attempt: Int) {
        let maxAttempts = 32 // 0.15초 간격 ≈ 5초 상한
        let minAttempts = 8 // T-081 버스트 전 고원(≈1.2초) 회피
        guard attempt < maxAttempts else {
            pendingSessionJump = false
            reconcilePin()
            logger.info(feature: "진입", "종료: 상한")
            return
        }
        let work = DispatchWorkItem { [weak followGate] in
            guard let gate = followGate else { return }
            // 세션 교체·진입 후 휠이면 중단 (낡은 예약·읽기 우선). 핀은 실측으로 정정.
            guard session == nil || session == self.chat.currentSessionID,
                  gate.lastWheel < gate.entrySince else {
                self.reconcilePin()
                self.logger.info(feature: "진입", "중단: 세션교체·휠")
                return
            }
            // T-083 Lazy 강제 생성 1회: 플레이스홀더 합산 이상 자랐을 때만 (앵커 존재 증거).
            // 0회차 허공 킥·매회 이중 구동이 떨림·폭풍의 원인이었음.
            let expectMin = CGFloat(self.chat.messages.count) * 36.0 + 32.0
            let docH0 = self.chatScrollView?.documentView?.bounds.height ?? 0
            if !gate.kickDone, !self.chat.messages.isEmpty, docH0 >= expectMin {
                gate.kickDone = true
                self.scrollProxy?.scrollTo("chatBottom", anchor: .bottom)
            }
            self.jumpToBottom()
            let docH = self.chatScrollView?.documentView?.bounds.height ?? 0
            gate.lastDocHeights.append(docH)
            if gate.lastDocHeights.count > 3 { gate.lastDocHeights.removeFirst() }
            if let sv = self.chatScrollView, let doc = sv.documentView {
                let clipH = sv.contentView.bounds.height
                let maxY = max(0, doc.bounds.height - clipH)
                var exitReason: String? = nil
                if attempt >= minAttempts, maxY <= 120, Self.docStable(gate.lastDocHeights) {
                    exitReason = "짧음" // T-084 최소 회차 게이트
                } else if attempt >= minAttempts,
                          Self.docStable(gate.lastDocHeights),
                          Self.entryConverged(offsetY: sv.contentView.bounds.origin.y,
                                              docHeight: doc.bounds.height,
                                              clipHeight: clipH) {
                    exitReason = "수렴"
                }
                if let reason = exitReason {
                    // T-086 검증 킥: 거짓 수렴이면 문서가 자라서 다음 회차가 이어받음.
                    if !gate.verifyKickDone {
                        gate.verifyKickDone = true
                        self.scrollProxy?.scrollTo("chatBottom", anchor: .bottom)
                        self.logger.info(feature: "진입", "검증 킥")
                    } else {
                        self.pendingSessionJump = false
                        gate.entryWorks.forEach { $0.cancel() }
                        gate.entryWorks.removeAll()
                        self.logger.info(feature: "진입", "종료: \(reason)")
                        return
                    }
                }
            }
            self.entryPoll(session: session, attempt: attempt + 1)
        }
        followGate.entryWorks.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.0 : 0.15), execute: work)
    }

    /// 핀 실측 정정 (T-081): 체인 종료·중단 시 실제 좌표로 버튼 노출 여부 복원.
    private func reconcilePin() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        pinnedToBottom = Self.isAtBottomOffset(offset: sv.contentView.bounds.origin.y,
                                               content: doc.bounds.height,
                                               container: sv.contentView.bounds.height)
    }

    /// 하단 중앙 점프 버튼 (T-064): 텍스트 대신 아래 화살표 원형.
    private var scrollBottomButton: some View {
            Button {
                pinnedToBottom = true
                followGate.lastWheel = .distantPast
                followGate.wheelAccum = 0
                lastFollow = .distantPast
                logger.info(feature: "스크롤", "수동 하단 이동")
                jumpToBottom()
            } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(.thinMaterial, in: Circle())
                .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
        .help("최신 메시지로 이동")
        .accessibilityLabel("최신 메시지로 이동")
    }
    // MARK: - 사이드바
    var sidebar: some View {
        List(selection: $selectedModelID) {
            Section("환경") {
                LabeledRow(icon: "shippingbox", title: "uv", value: uv.uvVersion)
                LabeledRow(icon: "brain", title: "litert-lm", value: uv.litertVersion)
                LabeledRow(icon: "bolt.fill", title: "가속",
                           value: config.configExists ? config.summary : "미설정(CPU 기본값)")
                HStack {
                    Label("서버", systemImage: "server.rack")
                        .symbolRenderingMode(.hierarchical).font(.system(size: 13))
                    Spacer()
                    Circle().fill(daemon.status == .running ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(daemon.status.rawValue + (daemon.external ? " (외부)" : ""))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if config.externalRestartPending {
                    Label("외부 데몬 재시작 필요 — 터미널에서 재시작하세요", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .contextMenu {
                            Button("재시작 명령 복사") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("litert-lm serve --host 127.0.0.1 --port 9379", forType: .string)
                            }
                        }
                }
            }
            SessionListView(chat: chat)
            Section("모델 (\(models.models.count))") {
                ForEach(models.models) { m in
                    NavigationLink(value: m.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ModelAlias.display(id: m.id)).font(.system(size: 13, weight: .medium))
                            Text("\(m.id) · \(m.listedSize) · 실점유 \(m.realSize)")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("채팅 모델로 선택") { selectedModelID = m.id }
                        Button("표시 이름 바꾸기") {
                            aliasTarget = m.id
                            aliasText = ModelAlias.display(id: m.id)
                        }
                        Button("벤치마크 실행") { runBenchmark(id: m.id) }
                            .disabled(bench.running)
                        Divider()
                        Button("삭제", role: .destructive) {
                            Task { _ = await models.delete(id: m.id) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await models.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("새로고침 (⌘R)")
            }
        }
    }

    /// 켜진 섹션이 하나라도 있는지 (순수, 테스트 가능).
    nonisolated static func anyVisible(_ flags: Bool...) -> Bool {
        flags.contains(true)
    }

    var anySectionVisible: Bool {
        Self.anyVisible(showSystem, showBackend, showGenerate)
    }

    /// 컬럼 표시 여부 (순수, 테스트 가능).
    nonisolated static func columnShown(columnOn: Bool, sections: Bool...) -> Bool {
        columnOn && sections.contains(true)
    }

    var inspectorColumnShown: Bool {
        Self.columnShown(columnOn: inspectorVisible, sections: showSystem, showBackend, showGenerate)
    }

    /// 마스터 토글: 전체 off 상태면 전체 복원(보이기), 아니면 컬럼 토글.
    private func toggleInspectorColumn() {
        if !anySectionVisible {
            showSystem = true
            showBackend = true
            showGenerate = true
            inspectorVisible = true
            logger.info(feature: "인스펙터", "전체 섹션 복원 (보이기)")
        } else {
            inspectorVisible.toggle()
        }
    }

    /// 단일 시작/중지 버튼 상태. 실행 중 아이콘은 기본 도형만 사용
    /// (link.badge.minus는 16pt 툴바에서 링처럼 뭉개져 보임). 외부 구분은 help+사이드바 표기로.
    var serverIcon: String {
        daemon.status == .running ? "stop.fill" : "play.fill"
    }

    var serverHelp: String {
        if daemon.status == .running {
            return daemon.external
                ? "외부 데몬 연결 끊기 (⌘.) — 터미널 데몬은 계속 실행됩니다"
                : "서버 중지 (⌘.)"
        }
        return "서버 시작 (⌘R)"
    }

    private func toggleServer() {
        if daemon.status == .running {
            daemon.stop()
        } else {
            Task { await daemon.start() }
        }
    }

    private func toggleLogPanel() {
        if daemon.status != .running {
            logger.info(feature: "하단패널", "서버 중지 상태 — 패널 열기 불가")
            return
        }
        logPanelVisible.toggle()
    }

    /// 채팅 스크롤 휠 감시 설치 (T-044, T-080 누적 임계): 호버 중에만 제스처 시각 기록,
    /// 8pt 미만 미세 접촉은 무시. 이벤트는 그대로 통과.
    private func installWheelMonitor() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak followGate] event in
            if let gate = followGate, gate.hover {
                let r = ContentView.wheelStamp(accum: gate.wheelAccum, delta: event.deltaY)
                gate.wheelAccum = r.accum
                if r.stamp { gate.lastWheel = Date() }
            }
            return event
        }
    }

    private func removeWheelMonitor() {
        if let token = wheelMonitor {
            NSEvent.removeMonitor(token)
            wheelMonitor = nil
        }
    }

    /// 전송 시작 점프 (T-076): 명시 의사라 T-044 게이트 우회. re-pin+수렴으로
    /// 내 버블·준비중을 즉시 보이고 이후 추종을 재개 (읽는 중 토큰 추종은 그대로 차단).
    private func sendJump() {
        pinnedToBottom = true
        lastFollow = .distantPast
        followGate.lastWheel = .distantPast
        followGate.wheelAccum = 0
        followGate.lastContent = 0 // 다음 토큰 증가 감지 보장
        pauseNotified = false
        logger.info(feature: "스크롤", "전송 — 하단 이동")
        scrollToFitBottom(cancelOnWheelSince: Date())
    }

    /// 절대 하단 점프 (T-047): 문서 끝 오프셋으로 직접 이동. 같은 위치 재적용은 no-op이라 떨림 없음.
    /// 오버슛 방지 (T-054): 미확정 문서는 건너뛰고, 초과분은 클램프+지연 재확인으로 치유.
    private func jumpToBottom() {
        guard let scrollView = chatScrollView, let doc = scrollView.documentView else { return }
        let clip = scrollView.contentView
        if doc.bounds.height <= 0 {
            // T-084 stale 오프셋 제거: 빈 문서는 0으로 (백지 방지).
            clip.setBoundsOrigin(NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(clip)
            return
        }
        let targetY = Self.clampedTargetY(target: Self.bottomTargetY(docHeight: doc.bounds.height,
                                                                      clipHeight: clip.bounds.height),
                                          docHeight: doc.bounds.height,
                                          clipHeight: clip.bounds.height)
        // 데드밴드 (T-087): 4pt 이내는 생략 (미세 출렁 방지).
        guard Self.shouldJump(cur: clip.bounds.origin.y, target: targetY) else { return }
        clip.setBoundsOrigin(NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(clip)
        // 지연 치유 (T-054, T-087 8pt로 둔감화): 의미 있는 오버슛만 교정.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let doc = scrollView.documentView else { return }
            let maxY = Self.bottomTargetY(docHeight: doc.bounds.height,
                                          clipHeight: scrollView.contentView.bounds.height)
            let cur = scrollView.contentView.bounds.origin.y
            if cur > maxY + 8 {
                DebugLogger.shared.info(feature: "스크롤", "점프 보정: \(Int(cur))→\(Int(maxY))")
                scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: maxY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    /// 수렴 스크롤 (T-047, T-087 1.4 추가): 5연타 + 새 요청 시 이전 취소 (웹뷰 비동기 높이 수렴용).
    private func scrollToFitBottom(cancelOnWheelSince since: Date? = nil) {
        pendingScrollWorks.forEach { $0.cancel() }
        pendingScrollWorks.removeAll()
        for delay in [0.0, 0.15, 0.4, 0.9, 1.4] {
            let work = DispatchWorkItem {
                if let since, self.followGate.lastWheel >= since { return }
                self.jumpToBottom()
            }
            pendingScrollWorks.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// 백엔드 적용: 저장 → 데몬 재시작. 외부 데몬은 확인 후 인수.
    private func applyBackend() {
        guard config.apply(modelID: chat.model) else { return }
        if daemon.external {
            showTakeoverConfirm = true
            return
        }
        config.externalRestartPending = false
        daemon.stop()
        Task { await daemon.start() }
    }

    private func runBenchmark(id: String) {
        showBench = true
        bench.run(modelID: id)
    }
}

/// 인스펙터 3섹션 on/off 분할 컨트롤 (툴바 상시 표시).
/// 인스펙터 섹션 타이틀 (T-072): 테스트 잠금용 상수.
enum InspectorTitle {
    static let system = "시스템 현황"
    static let backend = "실행 설정"
    static let generate = "생성 설정"
    static var all: [String] { [system, backend, generate] }
}

/// 툴바 섹션 토글 3칸 (T-016 보기 옵션): 눌러서 켜고 끄는 버튼, 인디게이터 아님.
struct SectionSegments: View {
    @Binding var system: Bool
    @Binding var backend: Bool
    @Binding var generate: Bool

    var body: some View {
        HStack(spacing: 3) {
            seg(icon: "gauge", on: $system, help: "시스템 현황 보기/숨기기")
            seg(icon: "server.rack", on: $backend, help: "실행 설정 보기/숨기기")
            seg(icon: "wand.and.stars", on: $generate, help: "생성 설정 보기/숨기기")
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlColor)))
    }

    private func seg(icon: String, on: Binding<Bool>, help: String) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on.wrappedValue ? .white : .secondary)
                .frame(width: 32, height: 24)
                .background {
                    if on.wrappedValue {
                        RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help + (on.wrappedValue ? " (켜짐)" : " (꺼짐)"))
    }
}

struct LabeledRow: View {
    let icon, title, value: String
    var body: some View {
        HStack {
            Label(title, systemImage: icon).symbolRenderingMode(.hierarchical).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// 명령 팔레트 시트 본체.
struct PaletteView: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var daemon: DaemonManager
    @ObservedObject var models: ModelStore
    @Binding var showPalette: Bool
    var onToggleLog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("명령 팔레트").font(.system(size: 13, weight: .semibold)).padding(12)
            Divider()
            List {
                Button("새 채팅 (⌘N)") { chat.clear(); showPalette = false }
                Button(daemon.status == .running
                       ? (daemon.external ? "외부 연결 끊기 (⌘.)" : "서버 중지 (⌘.)")
                       : "서버 시작 (⌘R)") {
                    showPalette = false
                    Task { daemon.status == .running ? daemon.stop() : await daemon.start() }
                }
                Button("모델 새로고침") { showPalette = false; Task { await models.refresh() } }
                Button("하단 패널 토글 (⌘J)") { showPalette = false; onToggleLog() }
                Button("디버그 패널 (⇧⌘D)") {
                    showPalette = false
                    NotificationCenter.default.post(name: .toggleDebug, object: nil)
                }
            }.listStyle(.plain)
        }.frame(width: 480, height: 320)
    }
}

/// 채팅 메시지 버블 1개.
/// 백엔드(데몬 설정) 섹션 본체: 초안 편집 + 적용/취소.
struct BackendSectionView: View {
    @ObservedObject var config: ConfigStore
    let model: ModelStore.Model?
    var onApply: () -> Void

    var body: some View {
        Picker("LLM 실행", selection: $config.draftBackend) {
            Text("GPU (Metal)").tag("gpu"); Text("CPU").tag("cpu")
        }.pickerStyle(.segmented)
        Picker("Vision 실행", selection: $config.draftVision) {
            Text("GPU").tag("gpu"); Text("CPU").tag("cpu")
        }.pickerStyle(.segmented)
        Toggle("MTP (Speculative Decoding)", isOn: $config.draftMTP)
            .help("GPU 백엔드 권장. 모델이 drafter 포함 시 가속.")
            .disabled(model?.speculative == false)
        if let mdl = model {
            LabeledContent("모델 Speculative", value: mdl.speculative ? "지원" : "미포함")
            LabeledContent("모달리티", value: mdl.modalities)
        }
        if config.hasChanges {
            Text(config.diffSummary).font(.system(size: 11)).foregroundStyle(.orange)
            HStack {
                Button("취소") { config.revert() }
                Spacer()
                Button("적용 후 재시작", action: onApply)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Text("바꾸면 여기에 적용·취소가 나와요. 적용은 서버 재시작을 동반합니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
/// 표시 이름 바꾸기 시트.
struct AliasSheetView: View {
    let targetID: String
    @Binding var text: String
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("표시 이름 바꾸기").font(.system(size: 13, weight: .semibold))
            Text("ID `\(targetID)`는 그대로, 화면 표시만 바뀝니다. 비우면 자동 이름으로 돌아갑니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("예: Gemma 4 12B (집)", text: $text)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("취소", action: onCancel)
                Button("저장", action: onSave).buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(width: 380)
    }
}
