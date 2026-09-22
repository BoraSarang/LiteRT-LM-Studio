import AppKit
import Combine
import SwiftUI

extension ContentView {
    /// 인스펙터 탭 (T-324): 사이드바 채팅|모델 패턴 이식.
    enum InspectorTab: String, CaseIterable {
        case backend
        case generate

        var title: String {
            switch self {
            case .backend: return InspectorTitle.backend
            case .generate: return InspectorTitle.generate
            }
        }
    }

    // MARK: - 인스펙터 (T-325 세그먼트 탭+Sticky 적용바)
    var inspector: some View {
        VStack(spacing: 0) {
            if showSystem {
                VStack(alignment: .leading, spacing: 4) {
                    InspectorSectionHeader(
                        title: InspectorTitle.system,
                        summary: InspectorDefaults.systemSummary(live: monitor.live),
                        onHide: { showSystem = false })
                    SystemMetersView(monitor: monitor)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contextMenu {
                    Button(L(L10n.Inspector.hideSection)) { showSystem = false }
                }
            }
            DSSegmented(L(L10n.Inspector.settings), selection: Binding(
                get: { inspectorTab },
                set: {
                    inspectorTabRaw = $0.rawValue
                    DebugLogger.shared.info(feature: "인스펙터", "탭 전환: \($0.title)")
                }
            )) {
                Label(InspectorTitle.backend, systemImage: "cpu").tag(InspectorTab.backend)
                Label(InspectorTitle.generate, systemImage: "slider.horizontal.3").tag(InspectorTab.generate)
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
            List {
                if inspectorTab == .backend {
                    Section {
                        BackendSectionView(config: config, model: selectedModel)
                    } header: {
                        InspectorSectionHeader(
                            title: InspectorTitle.backend,
                            summary: InspectorDefaults.backendSummary(hasChanges: config.hasChanges),
                            onReset: resetBackend)
                    }
                    .contextMenu {
                        Button(L(L10n.Inspector.resetDefaults)) { resetBackend() }
                    }
                } else {
                    Section {
                        generateSectionBody
                    } header: {
                        InspectorSectionHeader(
                            title: InspectorTitle.generate,
                            summary: InspectorDefaults.generateSummary(
                                temperature: chat.temperature, topK: chat.topK),
                            onReset: resetGenerate)
                    }
                    .contextMenu {
                        Button(L(L10n.Inspector.resetDefaults)) { resetGenerate() }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            if inspectorTab == .backend, config.hasChanges {
                Divider()
                HStack(spacing: 8) {
                    Text(L(L10n.Inspector.hasChanges))
                        .font(DS.captionFont).foregroundStyle(.orange)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer()
                    Button(L(L10n.Inspector.cancel)) { config.revert() }
                    Button(L(chat.route == .native ? L10n.Inspector.apply : L10n.Inspector.applyRestart)) {
                        applyBackend()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DSColor.primary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .help(config.diffSummary)
            }
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 320, max: 320) // T-072 사이드바 접힘 영향 차단
        .background(Color(nsColor: .controlBackgroundColor)) // T-333 사이드바 동일 배경
    }

    /// 현재 탭 (원시값 불일치 시 실행 설정 기본).
    var inspectorTab: InspectorTab { InspectorTab(rawValue: inspectorTabRaw) ?? .backend }

    /// 실행 설정 되돌리기 (T-323): 초안 파기, 변경 없으면 모델 기준 재로드.
    private func resetBackend() {
        if config.hasChanges {
            config.revert()
        } else {
            config.load(modelID: chat.model)
        }
        DebugLogger.shared.info(feature: "실행설정", "기본값으로 되돌리기")
    }

    /// 생성 설정 되돌리기 (T-323): T-176 기본값 복원.
    private func resetGenerate() {
        chat.temperature = InspectorDefaults.temperature
        chat.topK = InspectorDefaults.topK
        chat.topP = InspectorDefaults.topP
        chat.maxTokens = nil
        chat.seed = nil
        chat.systemPrompt = ""
        chat.thinkingEnabled = false
        chat.thinkingBudget = -1
        DebugLogger.shared.info(feature: "생성설정", "기본값으로 되돌리기")
    }

    /// 생성 설정 본체 (T-323 분리: inspector 길이 분산).
    private var generateSectionBody: some View {
        Group {
                    HStack {
                        Text(L(L10n.Inspector.temperature)); Slider(value: $chat.temperature, in: 0...1.5, step: 0.05)
                        Text(String(format: "%.2f", chat.temperature)).monospacedDigit()
                    }
                    HStack {
                        Text(L(L10n.Inspector.topK))
                        Spacer()
                        Text("\(chat.topK)").monospacedDigit()
                        Stepper("", value: $chat.topK, in: 1...256).labelsHidden()
                    }
                    HStack {
                        Text(L(L10n.Inspector.topP)); Slider(value: $chat.topP, in: 0...1, step: 0.05)
                        Text(String(format: "%.2f", chat.topP)).monospacedDigit()
                    }
                    HStack {
                        Text(L(L10n.Inspector.maxTokens))
                        Spacer()
                        TextField(L(L10n.Inspector.maxTokensPlaceholder), text: Binding(
                            get: { chat.maxTokens.map(String.init) ?? "" },
                            set: { chat.maxTokens = ConfigStore.intOrNil($0, min: 1) }
                        )).multilineTextAlignment(.trailing).frame(minWidth: 100, idealWidth: 140, maxWidth: 180)
                    }
                    .help(L(L10n.Inspector.maxTokensHelp))
                    HStack {
                        Text(L(L10n.Inspector.seed))
                        Spacer()
                        TextField(L(L10n.Inspector.seedPlaceholder), text: Binding(
                            get: { chat.seed.map(String.init) ?? "" },
                            set: { chat.seed = Int($0.trimmingCharacters(in: .whitespaces)) }
                        )).multilineTextAlignment(.trailing).frame(minWidth: 100, idealWidth: 140, maxWidth: 180)
                    }
                    .help(L(L10n.Inspector.seedHelp))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(L10n.Inspector.systemPrompt))
                        TextField(L(L10n.Inspector.systemPromptPlaceholder), text: $chat.systemPrompt)
                    }
                    .help(L(L10n.Inspector.systemPromptHelp))
                    if selectedModel?.thinking == true {
                        Toggle(L(L10n.Inspector.thinking), isOn: $chat.thinkingEnabled)
                        HStack {
                            Text(L(L10n.Inspector.thinkingBudget))
                            Spacer()
                            TextField(L(L10n.Inspector.unlimitedPlaceholder), text: Binding(
                                get: { chat.thinkingBudget == -1 ? "" : "\(chat.thinkingBudget)" },
                                set: { chat.thinkingBudget = ConfigStore.budgetOrUnlimited($0) }
                            )).multilineTextAlignment(.trailing).frame(minWidth: 80, idealWidth: 100, maxWidth: 140)
                        }
                    } else {
                        // 미지원 → 비활성화 + 사유 캡션 (describe 실측 반영)
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(L(L10n.Inspector.thinking), isOn: .constant(false)).disabled(true)
                                .help(L(L10n.Inspector.thinkingUnsupportedHelp))
                            Text(L(L10n.Inspector.thinkingUnsupported))
                                .font(DS.captionFont).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(L(L10n.Inspector.functionCall), isOn: .constant(false)).disabled(true)
                            .help(functionCallHelp(selectedModel?.functionCall == true))
                        if selectedModel?.functionCall != true {
                            Text(L(L10n.Inspector.functionCallUnsupported))
                                .font(DS.captionFont).foregroundStyle(.secondary)
                        }
                    }
                    Text(L(L10n.Inspector.functionCallEnableHint))
                        .font(DS.captionFont).foregroundStyle(.secondary)
        }
    }
}

/// 미지원 툴팁 문구 (T-122 줄길이 정리용 순수 헬퍼).
nonisolated func functionCallHelp(_ supported: Bool) -> String {
    supported ? "" : L(L10n.Inspector.functionCallUnsupportedHelp)
}

/// 인스펙터 3섹션 on/off 분할 컨트롤 (툴바 상시 표시).
/// 인스펙터 섹션 타이틀 (T-072): 테스트 잠금용 상수.
enum InspectorTitle {
    static var system: String { L(L10n.Inspector.system) }
    static var backend: String { L(L10n.Inspector.backend) }
    static var generate: String { L(L10n.Inspector.generate) }
    static var all: [String] { [system, backend, generate] }
}

/// 인스펙터 기본값·요약 (T-323, 순수, 테스트 가능, T-176 기준).
enum InspectorDefaults {
    static let temperature = 1.0
    static let topK = 64
    static let topP = 0.95

    nonisolated static func systemSummary(live: Bool) -> String {
        L(live ? L10n.Inspector.summaryLive : L10n.Inspector.summaryStopped)
    }

    nonisolated static func backendSummary(hasChanges: Bool) -> String {
        L(hasChanges ? L10n.Inspector.summaryChanged : L10n.Inspector.summaryApplied)
    }

    nonisolated static func generateSummary(temperature: Double, topK: Int) -> String {
        L(L10n.Inspector.summaryGenerate, temperature, topK)
    }
}

/// 인스펙터 섹션 헤더 (T-323 사이드바식, T-324 숨기기 선택화): 제목+요약+호버 ⋯ 메뉴.
struct InspectorSectionHeader: View {
    let title: String
    let summary: String
    var onReset: (() -> Void)?
    var onHide: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(summary).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
            if hovering, onReset != nil || onHide != nil {
                Menu {
                    if let reset = onReset {
                        Button(L(L10n.Inspector.resetDefaults), action: reset)
                    }
                    if let hide = onHide {
                        Button(L(L10n.Inspector.hideSection), action: hide)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                        .accessibilityLabel(L(L10n.Inspector.menu, title))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help(L(L10n.Inspector.menu, title))
            }
        }
        .padding(.trailing, 8) // T-324 행 우측 여백과 맞춤 (요약 돌출 방지)
        .onHover { hovering = $0 }
    }
}

/// 툴바 시스템 토글 1칸 (T-324 탭식: 실행/생성은 탭 전환, 시스템만 on/off).
struct SectionSegments: View {
    @Binding var system: Bool

    var body: some View {
        HStack(spacing: 3) {
            seg(icon: "gauge", on: $system, help: L(L10n.Inspector.systemToggleHelp))
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlColor)))
    }

    private func seg(icon: String, on: Binding<Bool>, help: String) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on.wrappedValue ? .white : .secondary)
                .frame(width: 32, height: 24)
                .background {
                    if on.wrappedValue {
                        RoundedRectangle(cornerRadius: 6).fill(DSColor.primary)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help + " " + L(on.wrappedValue ? L10n.Inspector.onSuffix : L10n.Inspector.offSuffix))
    }
}

/// 채팅 메시지 버블 1개.
/// 백엔드(데몬 설정) 섹션 본체: 초안 편집 + 적용/취소.
struct BackendSectionView: View {
    @ObservedObject var config: ConfigStore
    let model: ModelStore.Model?
    @AppStorage("metalResidency") private var residency = true // T-177 기본 켬
    @AppStorage("visualTokenBudget") private var visualBudget = 1120 // T-177 describe 상한

    var body: some View {
        DSSegmented(L(L10n.Inspector.llmBackend), selection: $config.draftBackend) {
            Text("GPU (Metal)").tag("gpu"); Text("CPU").tag("cpu")
        }
        DSSegmented(L(L10n.Inspector.visionBackend), selection: $config.draftVision) {
            Text("GPU").tag("gpu"); Text("CPU").tag("cpu")
        }
        if model?.modalities.contains("Audio") == true {
            DSSegmented(L(L10n.Inspector.audioBackend), selection: $config.draftAudio) {
                Text("CPU").tag("cpu"); Text("GPU").tag("gpu")
            }
        }
        if config.draftBackend == "cpu" {
            HStack {
                Text(L(L10n.Inspector.cpuThreads))
                Spacer()
                TextField(L(L10n.Inspector.autoPlaceholder), text: $config.draftThreads)
                    .multilineTextAlignment(.trailing).frame(width: 80)
                    .help(L(L10n.Inspector.threadsHelp))
            }
        }
        DSSegmented(L(L10n.Inspector.cache), selection: $config.draftCache) {
            Text(L(L10n.Inspector.cacheDisk)).tag("disk")
            Text(L(L10n.Inspector.cacheMemory)).tag("memory")
            Text(L(L10n.Inspector.cacheNone)).tag("no")
        }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(L(L10n.Inspector.kvTokens))
                Spacer()
                TextField(L(L10n.Inspector.kvPlaceholder), text: $config.draftKV)
                    .multilineTextAlignment(.trailing).frame(minWidth: 100, idealWidth: 140, maxWidth: 180)
                    .help(L(L10n.Inspector.kvHelp))
            }
            Text(L(L10n.Inspector.kvCaption))
                .font(DS.captionFont).foregroundStyle(.secondary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
        if model?.thinking == true {
            Toggle(L(L10n.Inspector.thinkingDefault), isOn: $config.draftThinking)
            HStack {
                Text(L(L10n.Inspector.thinkingBudget))
                Spacer()
                TextField(L(L10n.Inspector.unlimitedPlaceholder), text: $config.draftBudget)
                    .multilineTextAlignment(.trailing).frame(minWidth: 80, idealWidth: 100, maxWidth: 140)
                    .help(L(L10n.Inspector.budgetHelp))
            }
        }
        HStack(spacing: 4) {
            Toggle(L(L10n.Inspector.mtpEnable), isOn: $config.draftMTP)
                .toggleStyle(.switch)
                .help(L(L10n.Inspector.mtpHelp))
                .disabled(model?.speculative == false)
            Image(systemName: "info.circle")
                .font(DS.captionFont).foregroundStyle(.tertiary)
                .help(L(L10n.Inspector.mtpInfoHelp))
        }
        if let mdl = model {
            LabeledContent(
                L(L10n.Inspector.speculativeDecoding),
                value: L(mdl.speculative ? L10n.Inspector.supported : L10n.Inspector.notIncluded))
            LabeledContent(L(L10n.Inspector.supportedInputs), value: ModelAlias.modalities(mdl.modalities))
        }
        DisclosureGroup(L(L10n.Inspector.advanced)) {
            Toggle(L(L10n.Inspector.metalResidency), isOn: $residency)
                .toggleStyle(.switch)
                .help(L(L10n.Inspector.metalResidencyHelp))
            VStack(alignment: .leading, spacing: 4) {
                Text(L(L10n.Inspector.visualBudget))
                Picker(L(L10n.Inspector.visualBudget), selection: $visualBudget) {
                    Text("70").tag(70); Text("140").tag(140); Text("280").tag(280)
                    Text("560").tag(560); Text("1120").tag(1120)
                }.pickerStyle(.segmented)
                .labelsHidden()
                .help(L(L10n.Inspector.visualBudgetHelp))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L(L10n.Inspector.precision))
                Picker(L(L10n.Inspector.precision), selection: $config.draftPrecision) {
                    Text(L(L10n.Inspector.precisionBuiltin)).tag(""); Text("fp16").tag("fp16"); Text("fp32").tag("fp32")
                    Text("int8").tag("int8"); Text("int16").tag("int16")
                }.pickerStyle(.segmented)
                .labelsHidden()
                .help(L(L10n.Inspector.precisionHelp))
            }
        }
    }
}
