import AppKit
import SwiftUI

/// 사이드바 채팅 목록: Claude식 새 채팅 + 전체 선택행 + 정렬 + 핀/이름변경/삭제 (T-058).
struct SessionListView: View {
    @ObservedObject var chat: ChatStore
    @AppStorage("sessionSort") private var sortRaw = ChatStore.SessionSort.recent.rawValue
    @State private var hoverID: UUID?
    @State private var lastDeletedID: UUID? // T-113 삭제 액션 중복 발사 가드
    @State private var lastDeletedAt = Date.distantPast
    @State private var lastRenameID: UUID? // T-139 이름 변경 액션 중복 발사 가드
    @State private var lastRenameAt = Date.distantPast

    /// 삭제 액션 중복 발사 가드 (순수, 테스트 가능, T-113): 동일 ID 1초 내 재호출 무시.
    nonisolated static func allowDelete(id: UUID, lastID: UUID?, lastAt: Date, now: Date,
                                        window: TimeInterval = 1.0) -> Bool {
        id != lastID || now.timeIntervalSince(lastAt) >= window
    }

    /// 이름 변경 액션 중복 발사 가드 (순수, 테스트 가능, T-139): allowDelete와 동일 규칙.
    nonisolated static func allowRename(id: UUID, lastID: UUID?, lastAt: Date, now: Date,
                                        window: TimeInterval = 1.0) -> Bool {
        id != lastID || now.timeIntervalSince(lastAt) >= window
    }

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
    }

    /// 새 채팅 버튼 (T-137): 방을 만들지 않고 드래프트로. 드래프트 활성 시 행 틴트.
    private var newChatButton: some View {
        let draft = chat.currentSessionID == nil
        return Button {
            chat.startDraft()
            NotificationCenter.default.post(name: .focusChatInput, object: nil)
        } label: {
            HStack {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                Text("새 채팅").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background {
                if draft {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
                }
            }
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

    /// 채팅 메뉴 본체 (⋯ 버튼·우클릭 공용, T-058).
    @ViewBuilder
    private func sessionMenu(_ s: ChatStore.Session) -> some View {
        Button(s.pinned ? "고정 해제" : "고정",
               systemImage: s.pinned ? "pin.slash" : "pin") { chat.togglePin(s.id) }
            .disabled(chat.streaming)
        Button("이름 변경", systemImage: "pencil") { promptRename(s) }
            .disabled(chat.streaming)
        Divider()
        Button("삭제", systemImage: "trash", role: .destructive) { confirmDelete(s) }
            .disabled(chat.streaming)
    }

    /// 삭제 컨펌 (T-113): SwiftUI confirmationDialog 이중 표시 회귀 차단용 AppKit 단발 모달.
    private func confirmDelete(_ s: ChatStore.Session) {
        let now = Date()
        guard Self.allowDelete(id: s.id, lastID: lastDeletedID, lastAt: lastDeletedAt,
                               now: now) else { return }
        lastDeletedID = s.id
        lastDeletedAt = now
        let alert = NSAlert()
        alert.messageText = "채팅 삭제"
        alert.informativeText = "이 채팅의 기록이 모두 지워집니다."
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            chat.deleteSession(s.id)
        }
    }

    /// 이름 변경 입력 (T-139): SwiftUI 시트 반복 표시 회귀로 AppKit 단발 모달 사용 (T-113 선례).
    /// Enter=저장, ESC=취소. 동일 ID 1초 내 재호출 무시.
    private func promptRename(_ s: ChatStore.Session) {
        let now = Date()
        guard Self.allowRename(id: s.id, lastID: lastRenameID, lastAt: lastRenameAt,
                               now: now) else { return }
        lastRenameID = s.id
        lastRenameAt = now
        let field = NSTextField(string: s.displayTitle)
        field.placeholderString = "채팅 이름"
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let alert = NSAlert()
        alert.messageText = "이름 변경"
        alert.informativeText = "비우면 자동 제목으로 돌아갑니다."
        alert.accessoryView = field
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            chat.renameSession(s.id, title: field.stringValue)
        }
    }
}
