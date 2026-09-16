import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// 명령 1건 (T-263): 고정 6종, id 기준 실행.
struct PaletteCommand: Identifiable, Hashable {
    let id: String
    let title: String
    let hint: String
}

/// 팔레트 행 (T-263): 명령+채팅 단일 선택 공간.
enum PaletteRow: Identifiable, Hashable {
    case command(PaletteCommand)
    case hit(ChatSearchHit)

    var id: String {
        switch self {
        case .command(let cmd): return "cmd-\(cmd.id)"
        case .hit(let hit): return "hit-\(hit.id)"
        }
    }
}

/// Spotlight식 커맨드 팔레트 (T-263): 검색창+명령 필터+전체 채팅 검색.
/// ↑↓ 이동·Enter 실행·Esc 닫기. 채팅 결과 Enter는 방 전환+스크롤+플래시.
struct PaletteView: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var daemon: DaemonManager
    @ObservedObject var models: ModelStore
    @Binding var showPalette: Bool
    var onToggleLog: () -> Void
    var onJumpMessage: (UUID, UUID) -> Void = { _, _ in }

    @State private var query = ""
    @State private var selection = 0
    @State private var hits: [ChatSearchHit] = []
    @FocusState private var searchFocused: Bool
    private let logger = DebugLogger.shared

    /// 고정 명령 6종 (서버 행은 상태 추종).
    var commands: [PaletteCommand] {
        let running = daemon.status == .running
        return [
            PaletteCommand(id: "newChat", title: "새 채팅", hint: "⌘N"),
            PaletteCommand(
                id: "server",
                title: running ? (daemon.external ? "외부 연결 끊기" : "서버 중지") : "서버 시작",
                hint: running ? "⌘." : "⌘R"),
            PaletteCommand(id: "refreshModels", title: "모델 새로고침", hint: ""),
            PaletteCommand(id: "modelManager", title: "모델 관리 열기", hint: ""),
            PaletteCommand(id: "logPanel", title: "하단 패널 토글", hint: "⌘J"),
            PaletteCommand(id: "debug", title: "디버그 패널", hint: "⇧⌘D")
        ]
    }

    /// 필터된 명령 (빈 질의면 전체).
    var filteredCommands: [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return commands }
        return commands.filter { $0.title.lowercased().contains(q) }
    }

    /// 단일 선택 공간 (명령+채팅).
    var rows: [PaletteRow] {
        filteredCommands.map(PaletteRow.command) + hits.map(PaletteRow.hit)
    }

    /// 현재 선택 행 id (범위 밖이면 nil).
    var selectedID: String? {
        rows.indices.contains(selection) ? rows[selection].id : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("명령·채팅 검색 (초성 가능)…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onSubmit { runSelected() }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("지우기")
                }
                Text("esc").font(DS.captionFont).foregroundStyle(.tertiary)
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !filteredCommands.isEmpty {
                        sectionLabel("명령")
                        ForEach(filteredCommands) { cmd in
                            commandRow(cmd)
                        }
                    }
                    if !hits.isEmpty {
                        sectionLabel("채팅")
                        ForEach(hits) { hit in
                            hitRow(hit)
                        }
                    }
                    if rows.isEmpty {
                        Text("일치하는 명령·대화가 없어요")
                            .font(DS.captionFont).foregroundStyle(.secondary)
                            .padding(16)
                    }
                    if chat.streaming, !hits.isEmpty {
                        Text("전송 중에는 대화 이동을 할 수 없어요")
                            .font(DS.captionFont).foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 320)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(.rect(cornerRadius: 12))
        .shadow(radius: 12)
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator) }
        .onAppear {
            searchFocused = true
            refreshHits()
        }
        .onChange(of: query) { _, _ in
            selection = 0
            refreshHits()
        }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.escape) {
            showPalette = false
            return .handled
        }
    }

    /// 섹션 라벨.
    func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 4)
    }

    /// 명령 1행.
    func commandRow(_ cmd: PaletteCommand) -> some View {
        Button { runCommand(cmd.id) } label: {
            HStack {
                Text(cmd.title).font(.system(size: 13))
                Spacer()
                if !cmd.hint.isEmpty {
                    Text(cmd.hint).font(DS.captionFont).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background {
                if selectedID == "cmd-\(cmd.id)" {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    /// 채팅 결과 1행 (방 이름+미리보기+시각).
    func hitRow(_ hit: ChatSearchHit) -> some View {
        Button { runHit(hit) } label: {
            HStack(spacing: 8) {
                Image(systemName: hit.role == "user" ? "person" : "bubble.left")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.sessionTitle)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(hit.preview)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                RelativeTimeText(date: hit.matchedAt)
                    .font(DS.captionFont).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background {
                if selectedID == "hit-\(hit.id)" {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .disabled(chat.streaming)
    }

    /// 선택 이동 (순환, 범위 밖이면 0).
    func moveSelection(by delta: Int) -> KeyPress.Result {
        guard !rows.isEmpty else { return .handled }
        selection = (selection + delta + rows.count) % rows.count
        return .handled
    }

    /// Enter: 현재 선택 실행.
    func runSelected() {
        guard rows.indices.contains(selection) else { return }
        run(rows[selection])
    }

    /// 행 실행 분기.
    func run(_ row: PaletteRow) {
        switch row {
        case .command(let cmd): runCommand(cmd.id)
        case .hit(let hit): runHit(hit)
        }
    }

    /// 명령 실행 (기존 6종 그대로).
    func runCommand(_ id: String) {
        showPalette = false
        logger.info(feature: "팔레트", "명령: \(id)")
        switch id {
        case "newChat":
            chat.clear()
            NotificationCenter.default.post(name: .focusChatInput, object: nil)
        case "server":
            Task { daemon.status == .running ? daemon.stop() : await daemon.start() }
        case "refreshModels":
            Task { await models.refresh() }
        case "modelManager":
            NotificationCenter.default.post(name: .openModelManager, object: nil)
        case "logPanel":
            onToggleLog()
        case "debug":
            NotificationCenter.default.post(name: .toggleDebug, object: nil)
        default: break
        }
    }

    /// 채팅 결과 실행 (전송 중 제외).
    func runHit(_ hit: ChatSearchHit) {
        guard !chat.streaming else { return }
        showPalette = false
        logger.info(feature: "팔레트", "검색 이동: \(hit.sessionTitle) \(hit.preview.prefix(20))")
        onJumpMessage(hit.sessionID, hit.messageID)
    }

    /// 채팅 검색 갱신 (2자 미만이면 비움).
    func refreshHits() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= ChatSearch.minLength else {
            hits = []
            return
        }
        hits = ChatSearch.search(query: q, sessions: chat.sessions,
                                 transcripts: chat.transcripts())
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
                .font(DS.captionFont).foregroundStyle(.secondary)
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
