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

    // MARK: - 인스펙터 (T-324 탭식: 시스템 고정+실행/생성 탭, on/off는 툴바 단일 토글)
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
                    Button("이 섹션 숨기기") { showSystem = false }
                }
            }
            HStack(spacing: 0) {
                ForEach(InspectorTab.allCases, id: \.rawValue) { t in
                    Button {
                        inspectorTabRaw = t.rawValue
                        DebugLogger.shared.info(feature: "인스펙터", "탭 전환: \(t.title)")
                    } label: {
                        Text(t.title)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background {
                                if inspectorTab == t {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(DSColor.primary.opacity(0.15))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
            List {
                if inspectorTab == .backend {
                    Section {
                        BackendSectionView(config: config, model: selectedModel,
                                           isNativeRoute: chat.route == .native) {
                            applyBackend()
                        }
                    } header: {
                        InspectorSectionHeader(
                            title: InspectorTitle.backend,
                            summary: InspectorDefaults.backendSummary(hasChanges: config.hasChanges),
                            onReset: resetBackend)
                    }
                    .contextMenu {
                        Button("기본값으로 되돌리기") { resetBackend() }
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
                        Button("기본값으로 되돌리기") { resetGenerate() }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 320, max: 320) // T-072 사이드바 접힘 영향 차단
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
                        Text("온도"); Slider(value: $chat.temperature, in: 0...1.5, step: 0.05)
                        Text(String(format: "%.2f", chat.temperature)).monospacedDigit()
                    }
                    HStack {
                        Text("상위 K")
                        Spacer()
                        Text("\(chat.topK)").monospacedDigit()
                        Stepper("", value: $chat.topK, in: 1...256).labelsHidden()
                    }
                    HStack {
                        Text("상위 P"); Slider(value: $chat.topP, in: 0...1, step: 0.05)
                        Text(String(format: "%.2f", chat.topP)).monospacedDigit()
                    }
                    HStack {
                        Text("Max 토큰")
                        Spacer()
                        TextField("예: 500", text: Binding(
                            get: { chat.maxTokens.map(String.init) ?? "" },
                            set: { chat.maxTokens = ConfigStore.intOrNil($0, min: 1) }
                        )).multilineTextAlignment(.trailing).frame(width: 140)
                    }
                    .help("응답 길이 상한. 빈칸이면 무제한.")
                    HStack {
                        Text("시드")
                        Spacer()
                        TextField("예: 7", text: Binding(
                            get: { chat.seed.map(String.init) ?? "" },
                            set: { chat.seed = Int($0.trimmingCharacters(in: .whitespaces)) }
                        )).multilineTextAlignment(.trailing).frame(width: 140)
                    }
                    .help("빈칸이면 랜덤. 숫자를 고정하면 같은 질문에 같은 답.")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("시스템 프롬프트")
                        TextField("예: 간결하게 답해", text: $chat.systemPrompt)
                    }
                    .help("앱 내 엔진 대화에만 전달됩니다. 서버 경로는 미지원.")
                    if selectedModel?.thinking == true {
                        Toggle("추론", isOn: $chat.thinkingEnabled)
                        HStack {
                            Text("추론 예산")
                            Spacer()
                            TextField("무제한", text: Binding(
                                get: { chat.thinkingBudget == -1 ? "" : "\(chat.thinkingBudget)" },
                                set: { chat.thinkingBudget = ConfigStore.budgetOrUnlimited($0) }
                            )).multilineTextAlignment(.trailing).frame(width: 100)
                        }
                    } else {
                        // 미지원 → 비활성화 + 사유 캡션 (describe 실측 반영)
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("추론", isOn: .constant(false)).disabled(true)
                                .help("이 모델은 추론 미지원 (E-MAC-VALID-0007)")
                            Text("현 모델 미지원 — 추론 지원 모델(E2B/E4B 등)이 필요해요.")
                                .font(DS.captionFont).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("함수 호출", isOn: .constant(false)).disabled(true)
                            .help(functionCallHelp(selectedModel?.functionCall == true))
                        if selectedModel?.functionCall != true {
                            Text("현 모델 미지원 — FunctionGemma 계열이 필요해요.")
                                .font(DS.captionFont).foregroundStyle(.secondary)
                        }
                    }
                    Text("지원 모델을 가져오면 활성화됩니다.")
                        .font(DS.captionFont).foregroundStyle(.secondary)
        }
    }
}

/// 미지원 툴팁 문구 (T-122 줄길이 정리용 순수 헬퍼).
nonisolated func functionCallHelp(_ supported: Bool) -> String {
    supported ? "" : "이 모델은 함수 호출 미지원 (E-MAC-VALID-0008)"
}

/// 인스펙터 3섹션 on/off 분할 컨트롤 (툴바 상시 표시).
/// 인스펙터 섹션 타이틀 (T-072): 테스트 잠금용 상수.
enum InspectorTitle {
    static let system = "시스템 현황"
    static let backend = "실행 설정"
    static let generate = "생성 설정"
    static var all: [String] { [system, backend, generate] }
}

/// 인스펙터 기본값·요약 (T-323, 순수, 테스트 가능, T-176 기준).
enum InspectorDefaults {
    static let temperature = 1.0
    static let topK = 64
    static let topP = 0.95

    nonisolated static func systemSummary(live: Bool) -> String {
        live ? "LIVE" : "중지됨"
    }

    nonisolated static func backendSummary(hasChanges: Bool) -> String {
        hasChanges ? "변경됨" : "적용됨"
    }

    nonisolated static func generateSummary(temperature: Double, topK: Int) -> String {
        String(format: "온도 %.2f · 상위K %d", temperature, topK)
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
                        Button("기본값으로 되돌리기", action: reset)
                    }
                    if let hide = onHide {
                        Button("이 섹션 숨기기", action: hide)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("\(title) 메뉴")
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
            seg(icon: "gauge", on: $system, help: "시스템 현황 보기/숨기기")
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
        .help(help + (on.wrappedValue ? " (켜짐)" : " (꺼짐)"))
    }
}

/// 채팅 메시지 버블 1개.
/// 백엔드(데몬 설정) 섹션 본체: 초안 편집 + 적용/취소.
struct BackendSectionView: View {
    @ObservedObject var config: ConfigStore
    let model: ModelStore.Model?
    let isNativeRoute: Bool
    var onApply: () -> Void
    @AppStorage("metalResidency") private var residency = true // T-177 기본 켬
    @AppStorage("visualTokenBudget") private var visualBudget = 1120 // T-177 describe 상한

    var body: some View {
        DSSegmented("LLM 실행", selection: $config.draftBackend) {
            Text("GPU (Metal)").tag("gpu"); Text("CPU").tag("cpu")
        }
        DSSegmented("Vision 실행", selection: $config.draftVision) {
            Text("GPU").tag("gpu"); Text("CPU").tag("cpu")
        }
        if model?.modalities.contains("Audio") == true {
            DSSegmented("Audio 실행", selection: $config.draftAudio) {
                Text("CPU").tag("cpu"); Text("GPU").tag("gpu")
            }
        }
        if config.draftBackend == "cpu" {
            HStack {
                Text("CPU 스레드")
                Spacer()
                TextField("자동", text: $config.draftThreads)
                    .multilineTextAlignment(.trailing).frame(width: 80)
                    .help("빈칸이면 자동. 1 이상 숫자.")
            }
        }
        DSSegmented("캐시", selection: $config.draftCache) {
            Text("디스크").tag("disk"); Text("메모리").tag("memory"); Text("사용 안 함").tag("no")
        }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("KV 토큰")
                Spacer()
                TextField("예: 10000", text: $config.draftKV)
                    .multilineTextAlignment(.trailing).frame(width: 140)
                    .help("컨텍스트+출력 창. 빈칸이면 모델 기본.")
            }
            Text("빈칸=모델 기본. 크게 잡으면 긴 대화 가능, 메모리 사용 증가.")
                .font(DS.captionFont).foregroundStyle(.secondary)
        }
        if model?.thinking == true {
            Toggle("추론 기본값", isOn: $config.draftThinking)
            HStack {
                Text("추론 예산")
                Spacer()
                TextField("무제한", text: $config.draftBudget)
                    .multilineTextAlignment(.trailing).frame(width: 100)
                    .help("빈칸이면 무제한(-1).")
            }
        }
        Toggle("MTP (추측적 디코딩)", isOn: $config.draftMTP)
            .help("GPU 백엔드 권장. 모델이 drafter 포함 시 가속.")
            .disabled(model?.speculative == false)
        if let mdl = model {
            LabeledContent("모델 Speculative", value: mdl.speculative ? "지원" : "미포함")
            LabeledContent("모달리티", value: mdl.modalities)
        }
        DisclosureGroup("고급") {
            Toggle("Metal residency", isOn: $residency)
                .help("GPU 메모리에 모델을 상주시켜 스와핑 방지. 앱 내 엔진 초기화 때 적용 (모델 전환·재실행 후).")
            Picker("Visual 예산", selection: $visualBudget) {
                Text("70").tag(70); Text("140").tag(140); Text("280").tag(280)
                Text("560").tag(560); Text("1120").tag(1120)
            }.pickerStyle(.segmented)
            .help("이미지당 시각 토큰 상한 (Gemma4 전용). 엔진 초기화 때 적용.")
            Picker("정밀도", selection: $config.draftPrecision) {
                Text("내장").tag(""); Text("fp16").tag("fp16"); Text("fp32").tag("fp32")
                Text("int8").tag("int8"); Text("int16").tag("int16")
            }.pickerStyle(.segmented)
            .help("연산 정밀도 재지정. serve 경로만 유효, 적용 후 재시작.")
        }
        if config.hasChanges {
            Text(config.diffSummary).font(DS.captionFont).foregroundStyle(.orange)
            HStack {
                Button("취소") { config.revert() }
                Spacer()
                Button(isNativeRoute ? "적용 (다음 초기화 때 반영)" : "적용 후 재시작", action: onApply)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Text(isNativeRoute ? "바꾸면 여기에 적용·취소가 나와요. 앱 내 엔진은 다음 초기화 때 반영됩니다."
                 : "바꾸면 여기에 적용·취소가 나와요. 적용은 서버 재시작을 동반합니다.")
                .font(DS.captionFont).foregroundStyle(.secondary)
        }
    }
}
