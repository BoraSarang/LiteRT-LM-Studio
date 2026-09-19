import SwiftUI

/// 단축어 허용 목록 섹션 (T-270): run_shortcut 도구가 실행할 이름만 등록.
/// SettingsView 본문 길이를 늘리지 않도록 별도 뷰로 분리.
struct ShortcutsAllowlistSection: View {
    @State private var names: [String] = []
    @State private var draft = ""

    var body: some View {
        Section(L(L10n.Shortcuts.section)) {
            ForEach(names, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Button {
                        remove(name)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(L(L10n.Shortcuts.remove))
                }
            }
            HStack(spacing: 8) {
                TextField(L(L10n.Shortcuts.namePlaceholder), text: $draft)
                Button(L(L10n.Shortcuts.add)) { add() }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(L(L10n.Shortcuts.note))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { names = ShortcutsAllowlist.names() }
    }

    private func add() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        ShortcutsAllowlist.add(name)
        names = ShortcutsAllowlist.names()
        draft = ""
        DebugLogger.shared.info(feature: "도구설정", "단축어 허용: \(name)")
    }

    private func remove(_ name: String) {
        ShortcutsAllowlist.remove(name)
        names = ShortcutsAllowlist.names()
        DebugLogger.shared.info(feature: "도구설정", "단축어 제거: \(name)")
    }
}
