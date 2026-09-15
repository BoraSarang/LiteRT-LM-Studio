import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 액션 (타입 본문 길이 관리용 분리)
extension ContentView {
    /// 폰트 줌 적용 (T-070): 리셋 또는 ±스텝, 재실행 유지(AppStorage).
     func applyZoom(step: Double = 0, reset: Bool = false) {
        chatFontScale = reset ? 1.0 : Self.steppedZoom(chatFontScale, step: step)
        logger.info(feature: "폰트", "채팅 크기 \(Int(chatFontScale * 100))%")
    }

    /// 줌 알림 병합 (T-070): onReceive 체인 1개로 묶어 타입체크 부하 방지.
     var zoomNotes: AnyPublisher<Notification, Never> {
        let c = NotificationCenter.default
        return Publishers.MergeMany([
            c.publisher(for: .chatZoomIn),
            c.publisher(for: .chatZoomOut),
            c.publisher(for: .chatZoomReset)
        ]).eraseToAnyPublisher()
    }

    /// 줌 알림 분기 (T-070).
     func applyZoomNote(_ n: Notification) {
        switch n.name {
        case .chatZoomIn: applyZoom(step: 0.1)
        case .chatZoomOut: applyZoom(step: -0.1)
        default: applyZoom(reset: true)
        }
    }

    /// 진입 점프 수렴 (T-078, T-080 수렴 기반): 문서 높이 안정까지 연장(상한 5초),
    /// 스트리밍 탭과 독립 예약. 성공 확인 후 남은 예약 취소+플래그 해제.
     func scheduleEntryJump(session: UUID?) {
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
     func sessionJump(to session: UUID?) {
        // T-112 이중 발사 제거: 동일 세션 1초 내 재호출 스킵 (전환 로그 3ms 중복 확인).
        // 동일 세션 재탭은 selectSession 가드가 막으니 정상 전환은 항상 통과.
        if session == followGate.lastJumpSession,
           Date().timeIntervalSince(followGate.lastJumpAt) < 1.0 { return }
        followGate.lastJumpSession = session
        followGate.lastJumpAt = Date()
        pinnedToBottom = true
        lastFollow = .distantPast
        followGate.lastWheel = .distantPast
        followGate.wheelAccum = 0
        followGate.lastContent = 0 // T-048 이전 세션 문서 높이 잔재 제거
        followGate.maxTextLen = chat.messages.last?.text.count ?? 0 // T-106 텍스트 기준 초기화
        pauseNotified = false
        logger.info(feature: "스크롤", "채팅 전환 — 하단 이동")
        // T-153 진입 즉시 점프: 폴링(min 1.2초) 전 빈 화면·상단 노출 방지. finder 부착 전이면 no-op.
        DispatchQueue.main.async { self.jumpToBottom() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.jumpToBottom() }
        scheduleEntryJump(session: session ?? chat.currentSessionID)
    }

    /// 진입 폴링 1회 (T-080, T-081, T-083, T-104 관측 후 점프): 킥은 레이아웃 증거 후 1회,
    /// 정착 전에는 점프 없이 높이만 관측 (매회 절대점프가 전환 출렁의 원인).
    /// 정착 확인 후 확정 점프 1회+검증 1회로 종료. 상한까지 미정착이면 최선 점프 1회.
    func entryPoll(session: UUID?, attempt: Int) {
        let maxAttempts = 32 // 0.15초 간격 ≈ 5초 상한
        let minAttempts = 8 // T-081 버스트 전 고원(≈1.2초) 회피
        guard attempt < maxAttempts else {
            pendingSessionJump = false
            self.jumpToBottom() // T-104 미정착 종료 시 최선 1회
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
            if self.applyEntryStep(gate: gate, attempt: attempt, minAttempts: minAttempts) {
                self.entryPoll(session: session, attempt: attempt + 1)
            }
        }
        followGate.entryWorks.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.0 : 0.15), execute: work)
    }

    /// 진입 1회 적용 (T-126 분리): 관측+판정+효과 수행. 계속 폴링이면 true.
    func applyEntryStep(gate: FollowGate, attempt: Int, minAttempts: Int) -> Bool {
        // T-083 Lazy 강제 생성 1회: 플레이스홀더 합산 이상 자랐을 때만 (앵커 존재 증거).
        // 프록시 킥이라 AppKit 뷰 발견 전에도 수행. 0회차 허공 킥·매회 이중 구동이 떨림·폭풍의 원인이었음.
        let docH = self.chatScrollView?.documentView?.bounds.height ?? 0
        let kickSnap = ContentView.EntrySnapshot(
            attempt: attempt,
            kickDone: gate.kickDone,
            emptyMessages: self.chat.messages.isEmpty,
            docH0: docH,
            expectMin: CGFloat(self.chat.messages.count) * 36.0 + 32.0
        )
        if Self.decideEntry(kickSnap, minAttempts: minAttempts).kick {
            gate.kickDone = true
            self.scrollProxy?.scrollTo("chatBottom", anchor: .bottom)
        }
        // T-104 정착 전 점프 없음: 높이만 관측 (출렁 원인 제거).
        gate.lastDocHeights.append(docH)
        if gate.lastDocHeights.count > 3 { gate.lastDocHeights.removeFirst() }
        guard let sv = self.chatScrollView, let doc = sv.documentView else { return true }
        let clipH = sv.contentView.bounds.height
        // T-150 네이티브 동기 렌더: 페인트 대기 불필요, 항상 참.
        let painted = true
        let snap = ContentView.EntrySnapshot(
            attempt: attempt,
            kickDone: gate.kickDone,
            emptyMessages: self.chat.messages.isEmpty,
            docH0: docH,
            expectMin: CGFloat(self.chat.messages.count) * 36.0 + 32.0,
            maxY: max(0, doc.bounds.height - clipH),
            offsetY: sv.contentView.bounds.origin.y,
            docH: doc.bounds.height,
            clipH: clipH,
            stable: Self.docStable(gate.lastDocHeights),
            painted: painted
        )
        switch Self.decideEntry(snap, minAttempts: minAttempts).verdict {
        case .observe:
            break
        case .confirmJump:
            // T-104 정착됐는데 하단이 아니면 확정 점프 1회 (수렴 확인은 다음 회차).
            self.jumpToBottom()
        case .finish(let reason):
            self.jumpToBottom() // T-104 정착 후 확정 점프 1회
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
                return false
            }
        }
        return true
    }

    /// 핀 실측 정정 (T-081): 체인 종료·중단 시 실제 좌표로 버튼 노출 여부 복원.
     func reconcilePin() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        pinnedToBottom = Self.isAtBottomOffset(offset: sv.contentView.bounds.origin.y,
                                               content: doc.bounds.height,
                                               container: sv.contentView.bounds.height)
    }

    /// 하단 중앙 점프 버튼 (T-064): 텍스트 대신 아래 화살표 원형.
     var scrollBottomButton: some View {
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
     func toggleInspectorColumn() {
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

     func toggleServer() {
        if daemon.status == .running {
            daemon.stop()
        } else {
            Task { await daemon.start() }
        }
    }

     func toggleLogPanel() {
        if daemon.status != .running {
            logger.info(feature: "하단패널", "서버 중지 상태 — 패널 열기 불가")
            return
        }
        logPanelVisible.toggle()
    }

    /// 채팅 스크롤 휠 감시 설치 (T-044, T-080 누적 임계): 호버 중에만 제스처 시각 기록,
    /// 8pt 미만 미세 접촉은 무시. 이벤트는 그대로 통과.
     func installWheelMonitor() {
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

     func removeWheelMonitor() {
        if let token = wheelMonitor {
            NSEvent.removeMonitor(token)
            wheelMonitor = nil
        }
    }

    /// 전송 시작 이동 (T-076, T-109 질문행 앵커): 명시 의사라 T-044 게이트 우회.
    /// 절대좌표 5연타 대신 새 질문행 앵커 2회 (행 기준이라 stale 높이 오버슛·빈화면 차단).
    /// 이후 토큰 추종은 follower가 담당 (T-106 텍스트 기준).
     func sendJump() {
        pinnedToBottom = true
        lastFollow = .distantPast
        followGate.lastWheel = .distantPast
        followGate.wheelAccum = 0
        followGate.lastContent = 0 // 다음 토큰 증가 감지 보장
        followGate.maxTextLen = chat.messages.last?.text.count ?? 0 // T-106 텍스트 기준 초기화
        pauseNotified = false
        guard let promptID = chat.messages.dropLast().last(where: { $0.role == "user" })?.id else {
            logger.info(feature: "스크롤", "전송 — 질문행 없음, 하단 이동")
            jumpToBottom()
            return
        }
        let session = chat.currentSessionID
        let sendTime = Date()
        logger.info(feature: "스크롤", "전송 — 질문행 이동")
        scrollProxy?.scrollTo(promptID, anchor: .top)
        // 0.5초 보정 (T-135): 준비중이면 하단으로 (준비 표시 노출).
        // 스트리밍 중이면 추종에 맡기고, 그 사이 휠 입력이면 취소.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard session == self.chat.currentSessionID,
                  self.followGate.lastWheel < sendTime else { return }
            switch Self.sendCorrectAction(preparing: self.chat.preparing,
                                          streaming: self.chat.streaming) {
            case .jumpBottom:
                self.jumpToBottom()
            case .reanchor:
                self.scrollProxy?.scrollTo(promptID, anchor: .top)
            case .none:
                break
            }
        }
    }

    /// 절대 하단 점프 (T-047): 문서 끝 오프셋으로 직접 이동. 같은 위치 재적용은 no-op이라 떨림 없음.
    /// 오버슛 방지 (T-054): 미확정 문서는 건너뛰고, 초과분은 클램프+지연 재확인으로 치유.
     func jumpToBottom() {
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
        // T-104 진입 체인 활성 중에는 스킵 (다음 점프와 겹친 역보정이 출렁의 일부).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard self.followGate.entryWorks.isEmpty else { return }
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
     func scrollToFitBottom(cancelOnWheelSince since: Date? = nil) {
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
     func applyBackend() {
        guard config.apply(modelID: chat.model) else { return }
        if daemon.external {
            showTakeoverConfirm = true
            return
        }
        config.externalRestartPending = false
        daemon.stop()
        Task { await daemon.start() }
    }

     func runBenchmark(id: String) {
        showBench = true
        bench.run(modelID: id)
    }
}
