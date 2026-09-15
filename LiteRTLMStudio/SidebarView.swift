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
                LabeledRow(icon: "info.circle", title: "버전", value: AboutView.appVersion)
                LabeledRow(icon: "bolt.fill", title: "가속",
                           value: config.configExists ? config.summary : "미설정(CPU 기본값)")
                LabeledRow(icon: "cpu", title: "엔진", value: engineModeValue)
                nativeLifecycleRow
                HStack {
                    Label("상태", systemImage: "server.rack")
                        .symbolRenderingMode(.hierarchical).font(.system(size: 13))
                    Spacer()
                    Circle().fill(unifiedDot)
                        .frame(width: 8, height: 8)
                    Text(unifiedStatus.title)
                        .font(DS.captionFont).foregroundStyle(.secondary)
                }
                .help("Ollama식 통합 상태 — \(unifiedDetail)")
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
                }.help("모델 목록 새로고침 (⌘R은 서버 시작)")
            }
        }
    }

    /// 엔진 표시값 (T-130/T-186): 입력창 route 기준. CLI 데몬 / 네이티브+준비 상태.
    var engineModeValue: String {
        guard chat.route == .native else { return EngineMode.cli.title }
        if let id = nativeEngine.preparedModelID {
            return "\(EngineMode.native.title) · \(ModelAlias.display(id: id))"
        }
        switch nativeEngine.state {
        case .preparing: return "\(EngineMode.native.title) · 준비 중…"
        case .failed: return "\(EngineMode.native.title) · 실패"
        case .idle, .ready: return "\(EngineMode.native.title) · 미초기화"
        }
    }

    /// 네이티브 수명주기 버튼 (T-185): 실행/중지/다시 실행. 준비 중 스피너, 실패 코드 표시.
    @ViewBuilder
    var nativeLifecycleRow: some View {
        HStack(spacing: 8) {
            Spacer()
            switch nativeEngine.state {
            case .idle:
                Button("실행") {
                    Task { try? await nativeEngine.prepare(modelID: chat.model) }
                }.buttonStyle(.link)
                    .help("네이티브 엔진 초기화 (처음 1회 약 10초 이상)")
            case .preparing:
                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                Text("준비 중…").font(DS.captionFont).foregroundStyle(.secondary)
            case .ready:
                Button("중지") {
                    nativeEngine.release()
                    DebugLogger.shared.info(feature: "네이티브엔진", "사용자 중지 (메모리 반납)")
                }.buttonStyle(.link).help("네이티브 엔진 메모리 반납")
                Button("다시 실행") {
                    Task { try? await nativeEngine.restart(modelID: chat.model) }
                }.buttonStyle(.link).help("반납 후 처음부터 다시 준비")
            case .failed:
                Text(nativeEngine.lastError ?? "")
                    .font(DS.captionFont).foregroundStyle(.red)
                    .help("네이티브 초기화 실패 코드")
                Button("다시 실행") {
                    Task { try? await nativeEngine.restart(modelID: chat.model) }
                }.buttonStyle(.link).help("반납 후 처음부터 다시 준비")
            }
        }
    }

    /// Ollama식 통합 상태 (T-183/T-186): 대화 가능 = 데몬 실행 중 OR 네이티브 준비됨.
    /// 엔진 경로는 입력창 route를 본다.
    var unifiedStatus: UnifiedStatus {
        let label = nativeEngine.preparedModelID.map { ModelAlias.display(id: $0) }
        return UnifiedStatus.resolve(daemonRunning: daemon.status == .running,
                                     unlinkedRunning: daemon.unlinkedRunning,
                                     engineMode: chat.route,
                                     preparedLabel: label)
    }

    /// 통합 상태 상세 (외부 데몬 표기 포함).
    var unifiedDetail: String {
        var detail = unifiedStatus.detail
        if daemon.status == .running, daemon.external, !detail.contains("외부") {
            detail += " (외부)"
        }
        return detail
    }

    /// 통합 상태 점 색 (초록=대화 가능, 주황=미연결, 회색=중지).
    var unifiedDot: Color {
        if unifiedStatus.unlinked { return .orange }
        return unifiedStatus.live ? .green : .gray
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
