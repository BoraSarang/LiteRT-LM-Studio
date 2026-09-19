import SwiftUI

/// 대화 목차 1행 (T-258): 사용자 질문 첫 줄 미리보기.
struct ChatOutlineEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let preview: String
}

/// 대화 목차 추출 (T-258, AI Model Talk 질문 목차와 동일 규칙).
enum ChatOutline {
    /// 사용자 메시지 첫 줄 40자. 빈 본문은 이미지 첨부 표기.
    nonisolated static func entries(from messages: [ChatStore.Message]) -> [ChatOutlineEntry] {
        messages.filter { $0.role == "user" }.map { msg in
            let first = msg.text.components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let preview = first.isEmpty ? "(이미지 첨부)" : String(first.prefix(40))
            return ChatOutlineEntry(id: msg.id, preview: preview)
        }
    }
}

/// 우측 중앙 플로팅 목차 (T-258/T-259): 평상시 바 3개, 호버 시 확장.
/// 컨테이너 호버+0.3초 지연 접힘으로 클릭 가능. 패널 50% 투명.
struct ChatOutlineView: View {
    let entries: [ChatOutlineEntry]
    var onJump: (UUID) -> Void = { _ in }
    @State private var expanded = false
    @State private var hideWork: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 0) {
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            Button {
                                onJump(entry.id)
                            } label: {
                                Text(entry.preview)
                                    .font(.system(size: 12))
                                    .lineLimit(1).truncationMode(.tail)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(DSColor.primary.opacity(0.12))
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .help(entry.preview)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: 220, maxHeight: 400)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            // 축소 바 3개 (히트 영역).
            VStack(spacing: 5) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.secondary)
                        .frame(width: expanded ? 24 : 16, height: 3)
                }
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hideWork?.cancel()
                expanded = true
            } else {
                let work = DispatchWorkItem { expanded = false }
                hideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }
}
