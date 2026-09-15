import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// 명령 팔레트 시트 본체.
struct PaletteView: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var daemon: DaemonManager
    @ObservedObject var models: ModelStore
    @Binding var showPalette: Bool
    var onToggleLog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("명령 팔레트").font(.system(size: 13, weight: .semibold)).padding(12)
            Divider()
            List {
                Button("새 채팅 (⌘N)") {
                    chat.clear()
                    showPalette = false
                    NotificationCenter.default.post(name: .focusChatInput, object: nil)
                }
                Button(daemon.status == .running
                       ? (daemon.external ? "외부 연결 끊기 (⌘.)" : "서버 중지 (⌘.)")
                       : "서버 시작 (⌘R)") {
                    showPalette = false
                    Task { daemon.status == .running ? daemon.stop() : await daemon.start() }
                }
                Button("모델 새로고침") { showPalette = false; Task { await models.refresh() } }
                Button("하단 패널 토글 (⌘J)") { showPalette = false; onToggleLog() }
                Button("디버그 패널 (⇧⌘D)") {
                    showPalette = false
                    NotificationCenter.default.post(name: .toggleDebug, object: nil)
                }
            }.listStyle(.plain)
        }.frame(width: 480, height: 320)
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
