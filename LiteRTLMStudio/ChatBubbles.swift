import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// 상대 시간 (순수, 테스트 가능, T-077): 방금 전·N초/분/시간 전·어제·N일 전·M월 d일.
nonisolated func chatRelativeTime(from date: Date, now: Date = Date()) -> String {
    let s = max(0, Int(now.timeIntervalSince(date)))
    switch s {
    case 0 ..< 10: return "방금 전"
    case 0 ..< 60: return "\(s)초 전"
    case 0 ..< 3600: return "\(s / 60)분 전"
    case 0 ..< 86400: return "\(s / 3600)시간 전"
    default: break
    }
    let cal = Calendar.current
    if cal.isDateInYesterday(date) { return "어제" }
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: now)).day ?? 0
    if days < 7 { return "\(days)일 전" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "M월 d일"
    return f.string(from: date)
}

/// 완료 상대 시간 라벨 (T-077): 10초 주기 갱신, 라벨만 다시 그림.
struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 10)) { ctx in
            Text(chatRelativeTime(from: date, now: ctx.date))
        }
    }
}

/// 입력창 실측용 너비/높이 키 (T-034).
private struct InputWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct InputHeightKey: PreferenceKey {
    static var defaultValue: CGFloat?
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// 사이드바 채팅 목록: Claude식 새 채팅 + 전체 선택행 + 정렬 + 핀/이름변경/삭제 (T-058).
struct SessionListView: View {
    @ObservedObject var chat: ChatStore
    @AppStorage("sessionSort") private var sortRaw = ChatStore.SessionSort.recent.rawValue
    @State private var hoverID: UUID?
    @State private var renameTarget: UUID?
    @State private var renameText = ""
    @State private var deleteTarget: UUID?

    var order: ChatStore.SessionSort { ChatStore.SessionSort(rawValue: sortRaw) ?? .recent }
    var listed: [ChatStore.Session] { ChatStore.sortedSessions(chat.sessions, by: order) }

    var body: some View {
        Section {
            newChatButton
            ForEach(listed) { s in
                sessionRow(s)
            }
        } header: {
            listHeader
        }
        .confirmationDialog("채팅 삭제", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                guard let id = deleteTarget else { return }
                deleteTarget = nil
                chat.deleteSession(id)
            }
            Button("취소", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("이 채팅의 기록이 모두 지워집니다.")
        }
        .sheet(isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            renameSheet
        }
    }

    /// 상단 새 대화 강조 버튼 (T-058).
    private var newChatButton: some View {
        Button { chat.newSession() } label: {
            HStack {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                Text("새 채팅").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlColor)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(chat.streaming)
        .help("새 채팅 (⌘N)")
    }

    /// 섹션 헤더: 제목+정렬 메뉴 (T-058).
    private var listHeader: some View {
        HStack {
                Text("채팅").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(ChatStore.SessionSort.allCases, id: \.self) { o in
                    Toggle(o.title, isOn: Binding(
                        get: { o == order },
                        set: { _ in sortRaw = o.rawValue }
                    ))
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("정렬: \(order.title)")
        }
    }

    /// 채팅 1행: 동그라미+전체 틴트+호버 메뉴 (T-058).
    private func sessionRow(_ s: ChatStore.Session) -> some View {
        let selected = s.id == chat.currentSessionID
        return HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            if s.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(s.displayTitle).lineLimit(1).truncationMode(.tail)
                .font(.system(size: 13))
            Spacer(minLength: 4)
            if hoverID == s.id || selected {
                Menu {
                    sessionMenu(s)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                        .help("채팅 메뉴")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { chat.selectSession(s.id) }
        .onHover { hoverID = $0 ? s.id : nil }
        .contextMenu { sessionMenu(s) }
        .opacity(chat.streaming && s.id != chat.currentSessionID ? 0.5 : 1)
    }

    /// 이름 변경 시트 본체 (T-058).
    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이름 변경").font(.system(size: 13, weight: .semibold))
            Text("비우면 자동 제목으로 돌아갑니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("채팅 이름", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitRename() }
            HStack {
                Spacer()
                Button("취소") { renameTarget = nil }
                Button("저장") { commitRename() }.buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(width: 320)
    }

    /// 채팅 메뉴 본체 (⋯ 버튼·우클릭 공용, T-058).
    @ViewBuilder
    private func sessionMenu(_ s: ChatStore.Session) -> some View {
        Button(s.pinned ? "고정 해제" : "고정",
               systemImage: s.pinned ? "pin.slash" : "pin") { chat.togglePin(s.id) }
            .disabled(chat.streaming)
        Button("이름 변경", systemImage: "pencil") {
            renameTarget = s.id
            renameText = s.displayTitle
        }.disabled(chat.streaming)
        Divider()
        Button("삭제", systemImage: "trash", role: .destructive) { deleteTarget = s.id }
            .disabled(chat.streaming)
    }

    private func commitRename() {
        if let id = renameTarget { chat.renameSession(id, title: renameText) }
        renameTarget = nil
    }
}

/// 말풍선 디스패처: 역할별 좌우 분리 (PLAN_v3 T-028).
struct MessageBubbleView: View {
    let message: ChatStore.Message
    let showCursor: Bool
    let preparing: Bool
    var scheme: MarkdownScheme = .auto
    var isStreaming: Bool = false
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌
    let onRetry: () -> Void

    var body: some View {
        if message.role == "user" {
            UserBubbleView(message: message, fontScale: fontScale)
        } else {
            AssistantBubbleView(message: message, showCursor: showCursor,
                                preparing: preparing, scheme: scheme,
                                isStreaming: isStreaming, fontScale: fontScale, onRetry: onRetry)
        }
    }
}

/// 유저 버블: 우측 정렬 + 엑센트 틴트 + 복사.
struct UserBubbleView: View {
    let message: ChatStore.Message
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌
    @State private var copied = false

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 14 * fontScale)).textSelection(.enabled)
                    .padding(.vertical, 12) // T-096 좌우 여백 제거 (푸터와 좌단 일치)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 10))
                HStack(spacing: 8) {
                    Button(copied ? "복사됨" : "복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                        copied = true
                    }.buttonStyle(.plain)
                }
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// 어시스턴트 버블: 좌측 정렬 + 복사·재시도 + PERF 뱃지 + 에러 테두리.
struct AssistantBubbleView: View {
    let message: ChatStore.Message
    let showCursor: Bool
    let preparing: Bool
    var scheme: MarkdownScheme = .auto
    var isStreaming: Bool = false
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌
    let onRetry: () -> Void
    @State private var copied = false

    var body: some View {
        // T-065: 어시스턴트는 기본 좌우 여백 없이 전폭. T-096 좌우 패딩 제거로 푸터와 좌단 일치.
        VStack(alignment: .leading, spacing: 4) {
                if message.text.isEmpty {
                    Text(showCursor ? "▍" : "")
                        .font(.system(size: 14 * fontScale))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12) // T-096 좌우 여백 제거
                        .background(Color(.textBackgroundColor).opacity(0.5))
                        .clipShape(.rect(cornerRadius: 10))
                } else {
                    MarkdownView(text: message.text, scheme: scheme, isStreaming: isStreaming,
                                   fontScale: fontScale)
                        .equatable() // T-045: 스트리밍 중 구버블 갱신 차단
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12) // T-096 좌우 여백 제거 (푸터와 좌단 일치)
                        .background(Color(.textBackgroundColor).opacity(0.5))
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay {
                            if message.isError {
                                RoundedRectangle(cornerRadius: 10).stroke(.red.opacity(0.6))
                            }
                        }
                }
                if preparing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("엔진 준비 중… 첫 요청은 수 분 걸릴 수 있어요")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                // 푸터는 응답 완료 후에만 (T-077): 스트리밍 중 복사·재시도 숨김.
                if !isStreaming {
                    HStack(spacing: 8) {
                        if let perf = message.perf {
                            Text(perf).font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        if let finished = message.finishedAt {
                            RelativeTimeText(date: finished)
                                .font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                        Button(copied ? "복사됨" : "복사") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                            copied = true
                        }.buttonStyle(.plain)
                        Button("재시도") { onRetry() }.buttonStyle(.plain)
                            .help("마지막 요청 다시 보내기")
                    }
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
        }
    }
}

/// 입력바: 첨부 행 + 멀티라인 TextEditor + 전송/중단 (PLAN_v3 T-030).
struct ChatInputBar: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var daemon: DaemonManager
    @Binding var input: String
    @Binding var attachedImage: (data: Data, mime: String)?
    @Binding var attachedName: String?
    @State private var containerWidth: CGFloat = 400
    @State private var mirrorHeight: CGFloat = Self.lineHeight
    private let logger = DebugLogger.shared

    /// 14pt 한 줄 높이 (실측 기준, NSFont에서 계산).
    static var lineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: 14)
        return font.ascender - font.descender + font.leading
    }

    /// 실측 높이 → 줄수 2~8 클램프 (순수, 테스트 가능).
    static func rowsFor(mirrorHeight: CGFloat, lineHeight: CGFloat) -> Int {
        min(8, max(2, Int((mirrorHeight / lineHeight).rounded(.up))))
    }

    /// 줄수 → 편집기 명시 높이 (내부 여백 상수 포함).
    static func editorHeight(rows: Int, lineHeight: CGFloat) -> CGFloat {
        CGFloat(rows) * lineHeight + 24
    }

    var body: some View {
        VStack(spacing: 0) {
            if let name = attachedName {
                HStack {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                    Text(name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Button { attachedImage = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("첨부 제거")
                    Spacer()
                }.padding(.horizontal, 12).padding(.top, 8)
            }
            VStack(spacing: 8) {
                TextEditor(text: $input)
                    .font(.system(size: 14))
                    // 실측식 높이: 숨은 Text가 잰 줄수로 명시 지정 (T-034)
                    .frame(height: Self.editorHeight(
                        rows: Self.rowsFor(mirrorHeight: mirrorHeight, lineHeight: Self.lineHeight),
                        lineHeight: Self.lineHeight))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(.textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
                    .overlay(alignment: .topLeading) {
                        if input.isEmpty {
                            Text("메시지 입력… (Return 전송·Shift 줄바꿈)")
                                .font(.system(size: 14)).foregroundStyle(.secondary) // T-071 진하게
                                .padding(.top, 14).padding(.leading, 12)
                                .allowsHitTesting(false)
                        }
                    }
                    .onKeyPress(.return) {
                        // Shift+Return=줄바꿈, Return=전송
                        if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                        submit()
                        return .handled
                    }
                    .disabled(chat.streaming || daemon.status != .running)
                HStack(spacing: 8) {
                    Button { pickImage() } label: {
                        Image(systemName: "paperclip").font(.system(size: 15, weight: .semibold))
                    }.buttonStyle(.plain).help("이미지 첨부 (Vision 지원 모델)")
                        .disabled(chat.streaming || daemon.status != .running)
                    Spacer()
                    if chat.streaming {
                        Button("중지") { chat.stop() }.keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button("전송") { submit() }.keyboardShortcut(.return, modifiers: .command)
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || daemon.status != .running)
                    }
                }
            }.padding(12)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: InputWidthKey.self, value: geo.size.width)
                    }
                }
                .background {
                    // 숨은 실측용: 같은 글자·같은 너비로 실제 줄 높이 측정
                    Text(input.isEmpty ? " " : input)
                        .font(.system(size: 14))
                        .frame(width: max(50, containerWidth - 46), alignment: .leading)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(key: InputHeightKey.self, value: geo.size.height)
                            }
                        }
                        .hidden()
                }
                .onPreferenceChange(InputWidthKey.self) { containerWidth = $0 }
                .onPreferenceChange(InputHeightKey.self) { if let h = $0 { mirrorHeight = h } }
        }
    }

    private func submit() {
        let txt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txt.isEmpty else { return }
        input = ""
        let image = attachedImage
        attachedImage = nil
        attachedName = nil
        chat.send(txt, image: image)
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        // 큰 스크린샷은 Vision 토큰·시간 폭증 → 최대 768px JPEG으로 축소 (속도 최적화)
        let (outData, mime, note): (Data, String, String) = downscaled(data) ?? (data, "image/jpeg", "원본")
        attachedImage = (outData, mime)
        attachedName = "\(url.lastPathComponent) (\(note))"
        logger.info(feature: "첨부선택", "\(url.lastPathComponent) \(data.count)->\(outData.count) bytes \(note)")
    }

    private func downscaled(_ data: Data) -> (Data, String, String)? {
        guard let img = NSImage(data: data) else { return nil }
        let size = img.size
        let maxSide: CGFloat = 768
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: target))
        thumb.unlockFocus()
        guard let tiff = thumb.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }
        return (jpeg, "image/jpeg", "\(Int(target.width))x\(Int(target.height))")
    }
}

/// 하단 패널 본체: chatPane 하단·입력바 위 (T-039, 사이드바 제외).
/// T-094 터미널 개편: 입력창 동일 박스+서버 로그 전용 행+시스템 가로 3칸+자동스크롤+복사/지우기+시각.
struct BottomPanelView: View {
    @ObservedObject var daemon: DaemonManager
    @ObservedObject var monitor: SystemMonitor
    @Binding var logTab: Int
    var onClose: () -> Void
    var onTakeover: () -> Void
    @State private var selection = Set<Int>()
    @State private var copied = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $logTab) {
                    Text("서버 로그").tag(0)
                    Text("시스템").tag(1)
                }.pickerStyle(.segmented).frame(width: 160)
                Text(daemon.external ? "외부 데몬" : "앱 데몬")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                if logTab == 0, !daemon.external, !daemon.logLines.isEmpty {
                    Button(copied ? "복사됨" : "선택 복사") { copyTargets(selectionOrAll) }
                        .help("선택 행 복사 (선택 없으면 전체)")
                    Button("전체 복사") { copyTargets(daemon.logLines) }
                        .help("로그 전체 복사")
                    Button("지우기") { daemon.clearLog(); selection.removeAll() }
                        .help("로그 비우기")
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }.buttonStyle(.plain).help("패널 닫기 (⌘J)")
            }
            if logTab == 0 {
                if daemon.external {
                    // 외부 데몬 로그는 수집 불가 → 안내 + 인수.
                    VStack(spacing: 8) {
                        ContentUnavailableView(
                            "외부 데몬의 로그는 여기서 볼 수 없어요",
                            systemImage: "terminal",
                            description: Text("터미널에서 직접 띄운 데몬이라 앱에 로그 파이프가 없습니다.")
                        )
                        Button("인수해서 재시작 (로그 보기)") { onTakeover() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if daemon.logLines.isEmpty {
                    ContentUnavailableView(
                        "아직 로그가 없어요",
                        systemImage: "terminal",
                        description: Text("서버 시작 후 출력이 여기에 쌓입니다.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        List(selection: $selection) {
                            ForEach(Array(daemon.logLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .onAppear {
                            guard !daemon.logLines.isEmpty else { return }
                            proxy.scrollTo(daemon.logLines.count - 1, anchor: .bottom)
                        }
                        .onChange(of: daemon.logLines.count) { old, n in
                            if n < old {
                                selection.removeAll() // 상한 trim 시 오프셋 어긋남 방지
                            } else if n > 0 {
                                proxy.scrollTo(n - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    SystemCellView(title: "CPU",
                                   value: String(format: "%.0f%%", monitor.cpu),
                                   history: monitor.cpuHistory, color: .blue,
                                   popoverRows: SystemMetersView.cpuPopoverRows(
                                       sys: monitor.cpuSystem, user: monitor.cpuUser)
                                       .enumerated().map { i, r in
                                           ([.red, .blue, .primary][i], r.label, r.value)
                                       })
                    SystemCellView(title: "RAM",
                                   value: String(format: "%.0f%%", SystemMetersView.ramUsedPct(
                                       usedGB: monitor.ramUsedGB, totalGB: monitor.ramTotalGB)),
                                   history: monitor.ramHistory, color: .yellow,
                                   popoverRows: SystemMetersView.ramPopoverRows(
                                       app: monitor.ramAppGB, wired: monitor.ramWiredGB,
                                       comp: monitor.ramCompGB, cache: monitor.ramInactiveGB)
                                       .enumerated().map { i, r in
                                           ([.yellow, .red, .blue, .secondary][i], r.label, r.value)
                                       })
                    SystemCellView(title: "GPU",
                                   value: monitor.gpu.map { String(format: "%.0f%%", $0) } ?? "–",
                                   history: monitor.gpuHistory, color: .purple,
                                   popoverRows: [])
                }
            }
        }
        .padding(12)
        .background(Color(.textBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
        .frame(height: DS.bottomBoxHeight) // T-095 입력창 접힘 높이와 동일
    }

    private var selectionOrAll: [String] {
        selection.isEmpty ? daemon.logLines : selection.sorted().compactMap {
            $0 < daemon.logLines.count ? daemon.logLines[$0] : nil
        }
    }

    private func copyTargets(_ lines: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

/// 시스템 미니 셀 (T-094 가로 3칸, T-096 호버 팝오버): 제목+값+미니 차트.
struct SystemCellView: View {
    let title: String
    let value: String
    let history: [Double]
    let color: Color
    let popoverRows: [(color: Color, label: String, value: String)]
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                Text(value).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { idx, val in
                    LineMark(x: .value("t", idx), y: .value("v", val))
                        .foregroundStyle(color.opacity(0.9))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0 ... 100)
            .frame(height: 44)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(.rect(cornerRadius: 8))
        .frame(maxWidth: .infinity)
        .onHover { hovering = $0 }
        .popover(isPresented: Binding(
            get: { hovering && !popoverRows.isEmpty },
            set: { hovering = $0 }
        ), arrowEdge: .top) {
            MeterPopover(rows: popoverRows)
        }
    }
}
