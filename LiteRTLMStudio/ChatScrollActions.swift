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
        followGate.entryEpoch += 1 // T-202 낡은 폴링 세대 폐기
        followGate.entrySince = Date()
        followGate.lastDocHeights = []
        followGate.kickDone = false
        // T-084 진입 진단 (시작 1줄). T-200 finder 부착 여부 추가 (재부착 레이스 계측).
        let docH0 = chatScrollView?.documentView?.bounds.height ?? -1
        let off0 = chatScrollView.map { Int($0.contentView.bounds.origin.y) } ?? -1
        let finder = chatScrollView == nil ? "없음" : "있음"
        logger.info(feature: "진입", "시작 메시지=\(chat.messages.count) 문서=\(Int(docH0)) 오프셋=\(off0) finder=\(finder)")
        entryPoll(session: session, attempt: 0, epoch: followGate.entryEpoch)
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
        // T-198 지연 보정: 진입 체인 중단·상한 종료 후에도 문서 밖 오프셋이면 수렴.
        // 정상 위치는 clampToDocument가 건드리지 않음.
        // T-199: 느린 첫 페인트(표 많은 방) 대비 5초까지 연장.
        // T-202: clampWorks 분리 — finish가 폴링만 취소해도 보정은 살아남음. 다음 전환 시 취소.
        followGate.clampWorks.forEach { $0.cancel() }
        followGate.clampWorks.removeAll()
        for delay in [1.5, 3.0, 5.0] {
            let sessionID = session ?? chat.currentSessionID
            let work = DispatchWorkItem { [weak followGate] in
                guard followGate != nil,
                      sessionID == nil || sessionID == self.chat.currentSessionID else { return }
                self.clampToDocument()
                self.clampTopStuck() // T-202 위 고착 보정 (휠 없으면만)
            }
            followGate.clampWorks.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// 진입 폴링 1회 (T-080, T-081, T-083, T-104 관측 후 점프): 킥은 레이아웃 증거 후 1회,
    /// 정착 전에는 점프 없이 높이만 관측 (매회 절대점프가 전환 출렁의 원인).
    /// 정착 확인 후 확정 점프 1회+검증 1회로 종료. 상한까지 미정착이면 최선 점프 1회.
    func entryPoll(session: UUID?, attempt: Int, epoch: Int) {
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
            guard let gate = followGate, gate.entryEpoch == epoch else { return } // T-202 낡은 세대 폐기
            // 세션 교체·진입 후 휠이면 중단 (낡은 예약·읽기 우선). 핀은 실측으로 정정.
            guard session == nil || session == self.chat.currentSessionID,
                  gate.lastWheel < gate.entrySince else {
                self.reconcilePin()
                self.clampToDocument() // T-198: 중단 시에도 빈 영역이면 수렴.
                self.logger.info(feature: "진입", "중단: 세션교체·휠")
                return
            }
            if self.applyEntryStep(gate: gate, attempt: attempt, minAttempts: minAttempts) {
                self.entryPoll(session: session, attempt: attempt + 1, epoch: epoch)
            }
        }
        followGate.entryWorks.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.0 : 0.15), execute: work)
    }

    /// 진입 1회 적용 (T-126 분리, T-167 절대점프 일원화): 관측+판정+효과 수행.
    /// 프록시 scrollTo는 추정 레이아웃에 오버슛(빈 화면)하므로 사용 금지.
    /// jumpToBottom은 클램프+4pt 데드밴드라 수렴 시 무동작 — 출렁 없음.
    func applyEntryStep(gate: FollowGate, attempt: Int, minAttempts: Int) -> Bool {
        let docH = self.chatScrollView?.documentView?.bounds.height ?? 0
        // T-167 진입 킥도 절대 점프 (프록시 오버슛 제거). 미착지는 데드밴드로 무시.
        if !gate.kickDone, !self.chat.messages.isEmpty,
           docH >= CGFloat(self.chat.messages.count) * 36.0 + 32.0 {
            gate.kickDone = true
            self.jumpToBottom()
        }
        // T-104 정착 전 점프 없음: 높이만 관측 (출렁 원인 제거).
        gate.lastDocHeights.append(docH)
        if gate.lastDocHeights.count > 3 { gate.lastDocHeights.removeFirst() }
        // T-199 폴링 중 상시 보정: 문서 밖 오프셋이면 즉시 수렴 (읽는 중 위치 불변).
        self.clampToDocument()
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
            // T-167 종료 시 클램프 점프 확정 (데드밴드로 수렴 시 무동작, 미수렴만 교정).
            self.jumpToBottom()
            self.pendingSessionJump = false
            gate.entryWorks.forEach { $0.cancel() }
            gate.entryWorks.removeAll()
            // T-200 종료 맥락 추가 (회차·문서·위치, 무거운 방 미수렴 분석용).
            self.logger.info(feature: "진입", "종료: \(reason) 회차=\(attempt) 문서=\(Int(docH)) 오프셋=\(Int(snap.offsetY))")
            return false
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

    /// 빈 영역 판정 (순수, 테스트 가능, T-198): 문서 끝 초과면 보정 대상.
    /// 방 전환 잔재 등 오프셋이 문서 밖에 있으면 타임라인이 휑하게 보임.
    nonisolated static func blankOffset(cur: CGFloat, docHeight: CGFloat, clipHeight: CGFloat,
                                        threshold: CGFloat = 8) -> Bool {
        cur > max(0, docHeight - clipHeight) + threshold
    }

    /// 빈 영역 보정 (T-198): 문서 밖 오프셋만 하단으로 수렴.
    /// 정상 위치(읽는 중 포함)는 절대 건드리지 않음.
    func clampToDocument() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        guard Self.blankOffset(cur: sv.contentView.bounds.origin.y,
                               docHeight: doc.bounds.height,
                               clipHeight: sv.contentView.bounds.height) else { return }
        let maxY = max(0, doc.bounds.height - sv.contentView.bounds.height)
        sv.contentView.setBoundsOrigin(NSPoint(x: 0, y: maxY))
        sv.reflectScrolledClipView(sv.contentView)
        reconcilePin()
        logger.info(feature: "스크롤", "빈 영역 보정 → 하단")
    }

    /// 위 고착 보정 (T-202): 진입 후 휠 입력 없이 상단에 머물면 하단으로.
    /// 문서 밖 오버슛과 달리 문서 안이라 휠 가드 필수 (읽는 중 위치 불변).
    func clampTopStuck() {
        guard let sv = chatScrollView, let doc = sv.documentView else { return }
        guard followGate.lastWheel < followGate.entrySince else { return }
        guard Self.topStuck(offset: sv.contentView.bounds.origin.y,
                            docHeight: doc.bounds.height,
                            clipHeight: sv.contentView.bounds.height) else { return }
        jumpToBottom()
        logger.info(feature: "스크롤", "위 고착 보정 → 하단")
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
        .hoverTip("최신 메시지로 이동")
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
        bench.route = chat.route
        bench.run(modelID: id)
    }
}
