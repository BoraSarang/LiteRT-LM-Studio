import AppKit
import Combine
import SwiftUI

extension ContentView {
    // MARK: - 채팅
    /// 빈 화면 문구 (순수, 테스트 가능, T-143): 서버 실행 중이면 환영형, 아니면 시작 안내.
    nonisolated static func emptyStateCopy(isRunning: Bool) -> (title: String, message: String) {
        if isRunning {
            return (L(L10n.Chat.emptyNativeTitle), L(L10n.Chat.emptyNativeMessage))
        }
        return (L(L10n.Chat.emptyServerTitle), L(L10n.Chat.emptyServerMessage))
    }

    var chatPane: some View {
        VStack(spacing: 0) {
            if chat.messages.isEmpty {
                // T-262: 빈 화면은 웰컴 (새소식+업데이트+추천 링크, 가로·세로 중앙).
                WelcomeView(notes: releases, uv: uv,
                            daemonRunning: daemon.status == .running)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageListView
            }
            bottomSection
        }
        .padding(12) // T-095 바깥 카드 안쪽 여백 (T-098 유지)
        .background(Color(nsColor: .controlBackgroundColor)) // T-095 카드 배경
        .clipShape(.rect(cornerRadius: 12)) // T-095 모서리 클립
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator) } // T-095 외곽선
        .padding(8) // T-098 바깥 여백 8 (플로팅 카드, 인스펙터 톤 통일)
        .onChange(of: chat.currentSessionID) { _, id in
            // 드래프트 진입(nil)은 점프 스킵 (T-137): 빈 뷰 5초 공회전 방지.
            guard id != nil else { return }
            // T-265: 팔레트 검색 이동은 진입 체인 스킵 (1회 소비, 폴링 자살 방지).
            if Self.shouldSkipSessionJump(suppressNextSessionJump) {
                suppressNextSessionJump = false
                logger.info(feature: "팔레트", "전환 진입 체인 억제 (검색 이동)")
                return
            }
            sessionJump(to: id)
        }
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
                    bench: bench, history: benchHistory,
                    showPalette: $showPalette) {
            toggleLogPanel()
        } onJumpMessage: { sessionID, messageID in
            jumpToMessage(sessionID: sessionID, messageID: messageID)
        }
    }

    /// 팔레트 오버레이 (T-263): Spotlight식 중앙 상단 플로팅, 바깥 클릭 닫기.
    @ViewBuilder
    var paletteOverlay: some View {
        if showPalette {
            ZStack {
                Color.primary.opacity(0.12)
                    .onTapGesture { showPalette = false }
                VStack {
                    palette
                        .frame(width: 560)
                        .padding(.top, 48)
                    Spacer()
                }
            }
        }
    }

    /// 검색 이동 (T-263/T-265): 방 전환 후 해당 대화로 스크롤+플래시.
    /// 진입 체인 억제+무스탬프 코어로 폴링 자살 방지.
    func jumpToMessage(sessionID: UUID, messageID: UUID) {
        guard !chat.streaming else { return }
        if sessionID != chat.currentSessionID {
            suppressNextSessionJump = true
            chat.selectSession(sessionID)
        }
        // 세션 전환 레이아웃 대기 후 코어 점프 (핀 해제+스크롤+플래시).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.jumpToOutlineCore(id: messageID)
        }
        DebugLogger.shared.info(feature: "팔레트", "검색 이동 점프: \(messageID)")
    }

    /// 하단 섹션 (T-137): chatPane 본문 타입체크 분할용 (터미널+입력).
    var bottomSection: some View {
        VStack(spacing: 0) {
            if logPanelVisible, daemon.status == .running {
                bottomPanel
                    .frame(maxWidth: DS.chatMaxWidth) // T-093 터미널 로그 열폭 통일
                    .padding(.top, 8) // T-094 구분선 제거 대체 간격
            }
            ChatInputBar(chat: chat, daemon: daemon, models: models, selectedModelID: $selectedModelID,
                         input: $input, focusNonce: focusNonce,
                         attachedImage: $attachedImage, attachedName: $attachedName)
                .frame(maxWidth: DS.chatMaxWidth) // T-093 입력창 열폭 통일
                .padding(.top, 8) // T-094 구분선 제거 대체 간격
        }
    }

    /// 메시지 리스트 (T-137): chatPane 본문 타입체크 분할용.
    var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chat.messages) { m in
                        messageRow(m).id(m.id)
                    }
                    // 하단 앵커: 스택 안에서 측정해야 위치 정확 (T-036)
                    Color.clear.frame(height: 1)
                        .id("chatBottom") // T-081 프록시 강제 생성용
                        .background {
                            GeometryReader { geo in
                                // T-213 initial:true — 최초 레이아웃 즉시 보고 (미발화면 영원히 0).
                                Color.clear.onChange(of: geo.frame(in: .named("chatScroll")).maxY,
                                                     initial: true) { _, maxY in
                                    followGate.anchorMaxY = maxY // T-206 앵커 실측 저장 (재렌더 없음)
                                    pinnedToBottom = Self.isPinnedToBottom(
                                        bottomMaxY: maxY, viewportHeight: viewportHeight)
                                }
                            }
                        }
                }.padding(.vertical, 16) // T-096 가로 여백 통일 (열 cap과 일치)
                .padding(.horizontal, 12) // T-172 대화 열 inset (입력창과 구분)
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
            .onChange(of: chat.messages.last?.text) { _, _ in followStreamedText() }
            .onChange(of: chat.messages.last?.thinking) { _, _ in followStreamedText() }
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
            .onReceive(NotificationCenter.default.publisher(for: .requestPinCheck)) { _ in
                // T-260: 휠 스탬프 시 실측 정정 (수동 상승→버튼 보장).
                let wasPinned = pinnedToBottom
                reconcilePin()
                if wasPinned, !pinnedToBottom {
                    logger.info(feature: "스크롤", "휠 — 핀 해제")
                }
            }
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
            .overlay(alignment: .trailing) {
                // T-258 대화 목차 플로팅 (우측 중앙).
                if outlineEnabled {
                    let entries = ChatOutline.entries(from: chat.messages)
                    if !entries.isEmpty {
                        ChatOutlineView(entries: entries) { id in jumpToOutline(id: id) }
                            .padding(.trailing, 8)
                    }
                }
            }
        }
    }

    /// 세션 점프 억제 판정 (순수, 테스트 가능, T-265): 팔레트 전환 1회만 스킵.
    nonisolated static func shouldSkipSessionJump(_ suppress: Bool) -> Bool {
        suppress
    }

    /// 목차 점프 (T-258): 수동 클릭용 — 추종 차단 스탬프 후 코어로 이동.
    func jumpToOutline(id: UUID) {
        followGate.lastWheel = Date()
        jumpToOutlineCore(id: id)
        DebugLogger.shared.info(feature: "대화목차", "점프: \(id)")
    }

    /// 점프 코어 (T-265): 플래시+스크롤+핀 해제, 휠 스탬프 없음 (진입 체인 오인 방지).
    func jumpToOutlineCore(id: UUID) {
        pinnedToBottom = false
        outlineFlashWork?.cancel()
        outlineFlashID = id
        let work = DispatchWorkItem { outlineFlashID = nil }
        outlineFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        withAnimation { scrollProxy?.scrollTo(id, anchor: .top) }
    }

    /// 스트리밍 추종 (T-048/T-106): 문서가 늘었을 때만 따라감.
    func followStreamedText() {
        // 하단 스킵은 정적 콘텐츠에만 유효해서 증가 판정으로 교체.
        let now = Date()
        let wheeling = now.timeIntervalSince(followGate.lastWheel) < 0.8
        if wheeling, !pauseNotified {
            pauseNotified = true
            logger.info(feature: "스크롤", "읽는 중 — 자동 추종 일시정지")
        }
        let contentH = chatScrollView?.documentView?.bounds.height ?? 0
        // T-106수정: 텍스트 길이 추종 (동기 상태라 stale 높이 레이스 무관, 주 경로).
        // T-276: 추론만 늘 때도 추종 (합산 길이).
        let textLen = Self.streamedLength(text: chat.messages.last?.text,
                                          thinking: chat.messages.last?.thinking)
        let textGrew = textLen > followGate.maxTextLen
        followGate.maxTextLen = max(followGate.maxTextLen, textLen)
        // T-106 재시도 삭제 등 문서 축소 시 높이 기준 리셋 (점프 없이 계속).
        if Self.contentShrank(current: contentH, last: followGate.lastContent) {
            followGate.lastContent = contentH
        } else {
            followGate.lastContent = max(followGate.lastContent, contentH)
        }
        let grew = textGrew || Self.contentGrew(current: contentH,
                                                last: followGate.lastContent)
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

    /// 메시지 행 빌더 (T-137): ForEach 본문 타입체크 분할용.
    /// T-261: 마지막 어시스턴트 응답 아래에 후속질문 칩 (우측 정렬·즉시 전송).
    func messageRow(_ m: ChatStore.Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MessageBubbleView(
                message: m,
                showCursor: chat.streaming && m.id == chat.messages.last?.id,
                preparing: chat.preparing && m.id == chat.messages.last?.id,
                scheme: AppearanceMode.effectiveScheme(
                    mode: appearanceMode, systemDark: colorScheme == .dark),
                isStreaming: chat.streaming && m.id == chat.messages.last?.id,
                fontScale: chatFontScale,
                onRetry: { chat.retry() },
                controlsDisabled: chat.streaming,
                onEdit: { msg in
                    // T-165 다시 요청: 질문을 입력창에 채우고 이후 내역 제거.
                    guard let text = chat.editMessage(msg.id) else { return }
                    input = text
                    focusChatInput()
                }
            )
            .background {
                // T-258 점프 플래시 (행 배경 강조 1.5초).
                if outlineFlashID == m.id {
                    RoundedRectangle(cornerRadius: 10).fill(DSColor.warning.opacity(0.25))
                }
            }
            if shouldShowFollowUp(m) {
                followUpArea(m)
            }
        }
    }

    /// T-291 후속질문 영역: LLM 로딩=스켈레톤, 완료=LLM 칩, 실패=휴리스틱 폴백.
    /// T-313: 스켈레톤↔칩 크로스페이드 (뚝 바뀌지 않게).
    func followUpArea(_ m: ChatStore.Message) -> some View {
        Group {
            if followUps.messageID == m.id && followUps.loading {
                FollowUpSkeletonView()
            } else if followUps.messageID == m.id && !followUps.chips.isEmpty {
                FollowUpChipsView(chips: followUps.chips, disabled: chat.streaming) { chip in
                    logger.info(feature: "후속질문", "전송: \(chip.prefix(20))")
                    chat.send(chip)
                }
            } else {
                FollowUpChipsView(
                    chips: FollowUpSuggest.suggestFollowUps(for: m.text),
                    disabled: chat.streaming
                ) { chip in
                    logger.info(feature: "후속질문", "전송: \(chip.prefix(20))")
                    chat.send(chip)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: followUps.loading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: followUps.chips)
        .onAppear {
            followUps.finalize(messageID: m.id,
                               question: FollowUpSuggest.questionBefore(messages: chat.messages,
                                                                        id: m.id),
                               answer: m.text, chat: chat)
        }
    }

    /// 후속질문 표시 판정 (순수 조건 묶음, T-261): 마지막 완료 응답에만.
    func shouldShowFollowUp(_ m: ChatStore.Message) -> Bool {
        followUpEnabled
            && m.role == "assistant"
            && m.id == chat.messages.last?.id
            && !chat.streaming && !chat.preparing
            && !m.text.isEmpty && !m.isError
    }
}
