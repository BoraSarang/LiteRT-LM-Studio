import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    // MARK: - 사이드바
    var sidebar: some View {
        List(selection: $selectedModelID) {
            Section("환경") {
                LabeledRow(icon: "shippingbox", title: "uv", value: uv.uvVersion)
                LabeledRow(icon: "brain", title: "litert-lm", value: uv.litertVersion)
                LabeledRow(icon: "bolt.fill", title: "가속",
                           value: config.configExists ? config.summary : "미설정(CPU 기본값)")
                LabeledRow(icon: "cpu", title: "엔진", value: engineModeValue)
                HStack {
                    Label("서버", systemImage: "server.rack")
                        .symbolRenderingMode(.hierarchical).font(.system(size: 13))
                    Spacer()
                    Circle().fill(daemon.status == .running ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(daemon.status.rawValue + (daemon.external ? " (외부)" : ""))
                        .font(DS.captionFont).foregroundStyle(.secondary)
                }
                if config.externalRestartPending {
                    Label("외부 데몬 재시작 필요 — 터미널에서 재시작하세요", systemImage: "exclamationmark.triangle")
                        .font(DS.captionFont).foregroundStyle(.orange)
                        .contextMenu {
                            Button("재시작 명령 복사") {
                                PasteboardUtil.copy("litert-lm serve --host 127.0.0.1 --port 9379")
                            }
                        }
                }
            }
            SessionListView(chat: chat)
            Section("모델 (\(models.models.count))") {
                ForEach(models.models) { m in
                    NavigationLink(value: m.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ModelAlias.display(id: m.id)).font(.system(size: 13, weight: .medium))
                            Text("\(m.id) · \(m.listedSize) · 실점유 \(m.realSize)")
                                .font(DS.captionFont).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("채팅 모델로 선택") { selectedModelID = m.id }
                        Button("표시 이름 바꾸기") {
                            aliasTarget = m.id
                            aliasText = ModelAlias.display(id: m.id)
                        }
                        Button("벤치마크 실행") { runBenchmark(id: m.id) }
                            .disabled(bench.running)
                        Divider()
                        Button("삭제", role: .destructive) {
                            Task { _ = await models.delete(id: m.id) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await models.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("새로고침 (⌘R)")
            }
        }
    }

    /// 엔진 표시값 (T-130): CLI 데몬 / 네이티브+준비 상태.
    var engineModeValue: String {
        guard EngineMode.current() == .native else { return EngineMode.cli.title }
        if let id = nativeEngine.preparedModelID {
            return "\(EngineMode.native.title) · \(ModelAlias.display(id: id))"
        }
        return "\(EngineMode.native.title) · 미초기화"
    }

}

struct LabeledRow: View {    let icon, title, value: String
    var body: some View {
        HStack {
            Label(title, systemImage: icon).symbolRenderingMode(.hierarchical).font(.system(size: 13))
            Spacer()
            Text(value).font(DS.captionFont).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }
}
