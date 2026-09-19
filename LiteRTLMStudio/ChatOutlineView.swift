import SwiftUI

/// 대화 목차 1행 (T-258): 사용자 질문 첫 줄 미리보기.
struct ChatOutlineEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let preview: String
}

/// 대화 목차 추출 (T-258, AI Model Talk 질문 목차와 동일 규칙).
enum ChatOutline {
    /// 목록 최대 높이 (T-258 후속): 넘으면 스크롤.
    nonisolated static let maxListHeight: CGFloat = 400

    /// 사용자 메시지 첫 줄 40자. 빈 본문은 이미지 첨부 표기.
    nonisolated static func entries(from messages: [ChatStore.Message]) -> [ChatOutlineEntry] {
        messages.filter { $0.role == "user" }.map { msg in
            let first = msg.text.components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let preview = first.isEmpty ? "(이미지 첨부)" : String(first.prefix(40))
            return ChatOutlineEntry(id: msg.id, preview: preview)
        }
    }

    /// 내용 높이 → 목록 높이 (순수, 테스트 가능, T-258 후속): 최대 400 클램프.
    nonisolated static func cappedHeight(_ content: CGFloat,
                                         maxHeight: CGFloat = maxListHeight) -> CGFloat {
        max(0, min(content, maxHeight))
    }
}

/// 목록 실측 높이 키 (T-258 후속).
private struct OutlineHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 우측 하단 플로팅 목차 (T-258/T-259/T-332): 평상시 바 3개, 호버 시 확장.
/// 반투명 머티리얼 캡슐(입력창과 구분), 펼치면 최근 질문이 보이게 하단 스크롤.
struct ChatOutlineView: View {
    let entries: [ChatOutlineEntry]
    var onJump: (UUID) -> Void = { _ in }
    @State private var expanded = false
    @State private var hideWork: DispatchWorkItem?
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .trailing, spacing: 3) {
                            ForEach(entries) { entry in
                                Button {
                                    onJump(entry.id)
                                } label: {
                                    Text(entry.preview)
                                        .font(.system(size: 12))
                                        .lineLimit(1).truncationMode(.tail)
                                        .padding(.horizontal, 12).padding(.vertical, 5)
                                        .background(.thinMaterial, in: Capsule())
                                        .overlay(Capsule().stroke(.separator))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                                .help(entry.preview)
                                .id(entry.id)
                            }
                        }
                        .padding(.vertical, 2)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(key: OutlineHeightKey.self,
                                                       value: geo.size.height)
                            }
                        }
                    }
                    .frame(maxWidth: 220)
                    .frame(height: max(contentHeight, 1))
                    .onPreferenceChange(OutlineHeightKey.self) { contentHeight = $0 }
                    .onAppear { scrollToBottom(proxy: proxy) }
                    .onChange(of: expanded) { _, open in
                        if open { scrollToBottom(proxy: proxy) }
                    }
                    .onChange(of: entries.count) { _, _ in
                        if expanded { scrollToBottom(proxy: proxy) }
                    }
                }
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

    /// 맨 아래로 (T-332): 최근 질문이 보이게 펼침·추가 시 하단 스크롤.
    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = entries.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }
}
