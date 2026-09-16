import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    /// 사이드바 탭 (T-230): 채팅 무한 증식과 무관하게 모델·벤치마크 접근 보장.
    enum SidebarTab: String, CaseIterable {
        case chat
        case models

        var title: String {
            switch self {
            case .chat: return "채팅"
            case .models: return "모델"
            }
        }
    }

    // MARK: - 사이드바 (T-231: 환경+탭 상단 고정, 목록만 스크롤)
    var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedModelID) {
                Section("환경") {
                    LabeledRow(icon: "shippingbox", title: "uv", value: uv.uvVersion)
                    LabeledRow(icon: "brain", title: "litert-lm", value: uv.litertVersion)
                    LabeledRow(icon: "info.circle", title: "버전", value: AboutView.appVersion)
                    LabeledRow(icon: "bolt.fill", title: "가속",
                               value: config.configExists ? config.summary : "미설정(CPU 기본값)")
                    LabeledRow(icon: "cpu", title: "엔진", value: engineModeValue)
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
                    engineLifecycleRow
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
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .frame(height: envFixedHeight)
            HStack(spacing: 0) {
                ForEach(SidebarTab.allCases, id: \.rawValue) { t in
                    Button {
                        sidebarTabRaw = t.rawValue
                        DebugLogger.shared.info(feature: "사이드바", "탭 전환: \(t.title)")
                    } label: {
                        Text(t.title)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background {
                                if sidebarTab == t {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
            List(selection: $selectedModelID) {
                if sidebarTab == .chat {
                    SessionListView(chat: chat)
                } else {
                    modelSection
                    BenchmarkListView(history: benchHistory, bench: bench, chat: chat)
                }
            }
            .listStyle(.sidebar)
            .padding(.top, 6)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await models.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("모델 목록 새로고침 (⌘R은 서버 시작)")
            }
        }
    }

    /// 고정 환경 List 높이 (상태별 행 수 추종, 잘림·빈틈 방지).
    var envFixedHeight: CGFloat {
        var rows = 7 // uv·litert-lm·버전·가속·엔진·수명주기1·상태
        if chat.route == .native {
            switch nativeEngine.state {
            case .ready, .failed: rows += 1 // 버튼 2행
            case .idle, .preparing: break
            }
        }
        if config.externalRestartPending { rows += 1 }
        return 24 + CGFloat(rows) * 31 + 10
    }

    /// 현재 탭 (원시값 불일치 시 채팅 기본).
    var sidebarTab: SidebarTab { SidebarTab(rawValue: sidebarTabRaw) ?? .chat }

    /// 모델 섹션 본체 (채팅식: 관리 버튼+선택행+호버 메뉴).
    var modelSection: some View {
        Section {
            manageButton
            ForEach(models.models) { m in
                modelRow(m)
            }
        } header: {
            HStack {
                Text("모델").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(models.models.count)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.trailing, 16)
        }
    }

    /// 모델 관리 버튼: 별도 창 열기 (T-232).
    private var manageButton: some View {
        Button {
            DebugLogger.shared.info(feature: "모델관리", "관리 창 열기")
            openWindow(id: "modelManager")
        } label: {
            HStack {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                Text("모델 관리").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("모델 관리 창 열기")
    }

    /// 모델 1행: 탭=선택+호버 메뉴 (채팅식).
    private func modelRow(_ m: ModelStore.Model) -> some View {
        let selected = m.id == selectedModelID
        return HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelAlias.display(id: m.id)).font(.system(size: 13, weight: .medium))
                Text("\(m.id) · \(m.listedSize) · 실점유 \(m.realSize)")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if selected {
                Menu {
                    modelMenu(m)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("모델 메뉴")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedModelID = m.id }
        .contextMenu { modelMenu(m) }
    }

    /// 모델 메뉴 본체 (⋯ 버튼·우클릭 공용).
    @ViewBuilder
    private func modelMenu(_ m: ModelStore.Model) -> some View {
        Button("채팅 모델로 선택") { selectedModelID = m.id }
        Button("표시 이름 바꾸기") {
            aliasTarget = m.id
            aliasText = ModelAlias.display(id: m.id)
        }
        Button("벤치마크 실행") { runBenchmark(id: m.id) }
            .disabled(bench.running)
        Divider()
        Button("모델 관리에서 삭제") {
            DebugLogger.shared.info(feature: "모델관리", "사이드바에서 관리 창으로 이동: \(m.id)")
            NotificationCenter.default.post(name: .openModelManagerMyModels, object: m.id)
        }
    }

    /// 엔진 표시값 (T-130/T-186): 입력창 route 기준. 서버 / 앱 내 엔진+준비 상태.
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

    /// 엔진 수명주기 행: 입력창 route를 따른다 (규칙 1). 채팅식 전폭 행.
    @ViewBuilder
    var engineLifecycleRow: some View {
        if Self.showsNativeLifecycle(route: chat.route) {
            switch nativeEngine.state {
            case .idle:
                lifecycleActionRow(icon: "play.fill", title: "앱 내 엔진 초기화",
                                   help: "앱 내 엔진 초기화 (\(ModelAlias.display(id: chat.model)), 처음 1회 약 10초 이상)") {
                    Task { try? await nativeEngine.prepare(modelID: chat.model) }
                }
            case .preparing:
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    Text("준비 중…").font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 7)
            case .ready:
                lifecycleActionRow(icon: "stop.fill", title: "앱 내 엔진 중지",
                                   help: "앱 내 엔진 메모리 반납") {
                    nativeEngine.release()
                    DebugLogger.shared.info(feature: "네이티브엔진", "사용자 중지 (메모리 반납)")
                }
                lifecycleActionRow(icon: "arrow.clockwise", title: "다시 실행",
                                   help: "반납 후 처음부터 다시 준비") {
                    Task { try? await nativeEngine.restart(modelID: chat.model) }
                }
            case .failed:
                Text(nativeEngine.lastError ?? "")
                    .font(DS.captionFont).foregroundStyle(.red)
                    .help("앱 내 엔진 초기화 실패 코드")
                lifecycleActionRow(icon: "arrow.clockwise", title: "다시 실행",
                                   help: "반납 후 처음부터 다시 준비") {
                    Task { try? await nativeEngine.restart(modelID: chat.model) }
                }
            }
        } else {
            if daemon.status == .running {
                lifecycleActionRow(icon: "stop.fill", title: "데몬 중지",
                                   help: "서버 데몬 중지 (⌘.)") {
                    daemon.stop()
                }
            } else {
                lifecycleActionRow(icon: "play.fill", title: "데몬 시작",
                                   help: "서버 데몬 시작 (⌘R)") {
                    Task { await daemon.start() }
                }
            }
        }
    }

    /// 전폭 액션 1행 (중앙 정렬, 꺾임 없음).
    private func lifecycleActionRow(icon: String, title: String, help: String,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// route 분기 판정 (순수, 테스트 가능): 네이티브일 때만 네이티브 버튼.
    nonisolated static func showsNativeLifecycle(route: EngineMode) -> Bool {
        route == .native
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

    /// 모델 삭제는 모델 관리 창·내 모델 탭으로 일원화 (T-247).
    /// 권한 게이트+확인은 관리 창의 삭제 대화상자가 담당한다.

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
