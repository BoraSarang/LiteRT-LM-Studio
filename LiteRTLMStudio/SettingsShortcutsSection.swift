import SwiftUI

/// 단축어 허용 목록 섹션 (T-270): run_shortcut 도구가 실행할 이름만 등록.
/// SettingsView 본문 길이를 늘리지 않도록 별도 뷰로 분리.
struct ShortcutsAllowlistSection: View {
    @State private var names: [String] = []
    @State private var draft = ""

    var body: some View {
        Section("단축어 허용 목록") {
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
                    .help("허용 목록에서 제거")
                }
            }
            HStack(spacing: 8) {
                TextField("단축어 이름", text: $draft)
                Button("추가") { add() }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("여기 등록한 이름의 단축어만 모델이 run_shortcut 도구로 실행할 수 있습니다.")
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
