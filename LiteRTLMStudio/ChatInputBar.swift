import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

/// 입력바: 첨부 행 + 멀티라인 TextEditor + 전송/중단 (PLAN_v3 T-030).
struct ChatInputBar: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var daemon: DaemonManager
    @ObservedObject var models: ModelStore
    @Binding var selectedModelID: String?
    @AppStorage("globalPermission") private var permissionRaw = GlobalPermission.ask.rawValue
    @Binding var input: String
    var focusNonce: Int = 0 // T-137 드래프트 시작 신호 (선언 순서=호출 순서)
    @FocusState private var editorFocused: Bool
    @Binding var attachedImage: ChatStore.ChatImage?
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

    /// 전송 가능 (T-146/T-186): 스트리밍 중 제외, 선택 경로별 준비 필요.
    /// 데몬=실행 중, 네이티브=엔진 준비됨. 입력 자체는 막지 않고 전송만 차단.
    var canSend: Bool {
        switch chat.route {
        case .cli:
            return ChatStore.sendAllowed(streaming: chat.streaming,
                                         daemonRunning: daemon.status == .running,
                                         nativeReady: false)
        case .native:
            return ChatStore.sendAllowed(streaming: chat.streaming,
                                         daemonRunning: false,
                                         nativeReady: chat.nativePrepared)
        }
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
                    .focused($editorFocused)
                    .onChange(of: focusNonce) { _, _ in editorFocused = true }
                    // 실측식 높이: 숨은 Text가 잰 줄수로 명시 지정 (T-034)
                    .frame(height: Self.editorHeight(
                        rows: Self.rowsFor(mirrorHeight: mirrorHeight, lineHeight: Self.lineHeight),
                        lineHeight: Self.lineHeight))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.clear) // T-097 테두리는 바깥 박스로 이동 (터미널과 동일 뼈대)
                    .overlay(alignment: .topLeading) {
                        if input.isEmpty {
                            Text("메시지 입력… (Return 전송·Shift 줄바꿈)")
                                .font(.system(size: 14)).foregroundStyle(.secondary) // T-071 진하게
                                // T-144: TextEditor 내부 여백과 동일값으로 입력 시작점 일치
                                // T-145: 가로 10 (세로 8 유지, 최종)
                                .padding(.top, 8).padding(.leading, 10)
                                .allowsHitTesting(false)
                        }
                    }
                    .onKeyPress(.return) {
                        // Shift+Return=줄바꿈, Return=전송
                        if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                        submit()
                        return .handled
                    }
                    .disabled(chat.streaming)
                HStack(spacing: 8) {
                    Button { pickImage() } label: {
                        Image(systemName: "paperclip").font(.system(size: 15, weight: .semibold))
                    }.buttonStyle(.plain).help("이미지 첨부 (Vision 지원 모델)")
                        .disabled(chat.streaming)
                    if models.models.isEmpty {
                        Text("모델 없음").font(.system(size: 12)).foregroundStyle(.secondary)
                            .help("사이드바 새로고침 후 모델을 가져오세요")
                    } else {
                        Picker("채팅 모델", selection: Binding(
                            get: { selectedModelID ?? models.models.first?.id ?? "" },
                            set: { selectedModelID = $0 }
                        )) {
                            ForEach(ModelStore.preferredOrder(models.models)) { m in
                                Text(ModelAlias.display(id: m.id)).tag(m.id)
                            }
                        }.pickerStyle(.menu)
                            .help("이번 채팅에 쓸 모델. 설치된 모델만 표시 (Gemma·Qwen 우선).")
                            .disabled(chat.streaming)
                    }
                    Picker("전송 경로", selection: $chat.route) {
                        ForEach(EngineMode.allCases, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }.pickerStyle(.menu)
                        .help("이번 전송에 쓸 경로. 데몬=서버 경유, 네이티브=프로세스 내 직접 추론.")
                        .disabled(chat.streaming)
                    Spacer()
                    if chat.streaming {
                        Button("중지") { chat.stop() }.keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button("전송") { submit() }.keyboardShortcut(.return, modifiers: .command)
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || !canSend)
                            .help(canSend ? "전송 (⌘Return)"
                                : chat.route == .native && !chat.nativePrepared
                                ? "앱 내 엔진 초기화 후 전송 가능"
                                : "서버 시작 후 전송 가능")
                    }
                }
            }.cardBox() // T-097 터미널과 동일 뼈대 (바깥 박스)
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
        let perm = GlobalPermission(rawValue: permissionRaw) ?? .ask
        guard GlobalPermission.allows(perm, confirmed: true) else {
            logger.error(code: "E-MAC-PERM-0011", feature: "권한", "전송 차단 (권한 꺼짐)")
            return
        }
        if GlobalPermission.needsConfirm(perm) {
            logger.info(feature: "권한", "전송 확인 요청")
            guard confirmSend() else { return }
        }
        let txt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txt.isEmpty else { return }
        input = ""
        let image = attachedImage
        attachedImage = nil
        attachedName = nil
        chat.send(txt, image: image)
    }

    /// 매번 묻기 확인 (T-113/T-139 선례: AppKit 단발 모달).
    private func confirmSend() -> Bool {
        let alert = NSAlert()
        alert.messageText = "이 모델로 전송할까요?"
        alert.informativeText = ModelAlias.display(id: selectedModelID ?? "")
        alert.addButton(withTitle: "전송")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        // 큰 스크린샷은 Vision 토큰·시간 폭증 → 최대 768px JPEG으로 축소 (속도 최적화)
        if let small = ImageUtil.downscaledJPEG(data) {
            attachedImage = ChatStore.ChatImage(data: small.data, mime: small.mime)
            attachedName = "\(url.lastPathComponent) (\(small.note))"
            let sizes = "\(data.count)->\(small.data.count) bytes \(small.note)"
            logger.info(feature: "첨부선택", "\(url.lastPathComponent) \(sizes)")
        } else {
            attachedImage = ChatStore.ChatImage(data: data, mime: "image/jpeg")
            attachedName = "\(url.lastPathComponent) (원본)"
            logger.info(feature: "첨부선택", "\(url.lastPathComponent) \(data.count) bytes 원본")
        }
    }
}
