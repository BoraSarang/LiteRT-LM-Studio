import AppKit
import Combine
import SwiftUI

extension ContentView {
    // MARK: - 인스펙터 (3섹션 on/off, 토글은 툴바 섹션 토글)
    var inspector: some View {
        Form {
            if showSystem {
                Section(InspectorTitle.system) {
                    SystemMetersView(monitor: monitor)
                }
            }
            if showBackend {
                Section(InspectorTitle.backend) {
                    BackendSectionView(config: config, model: selectedModel,
                                           isNativeRoute: chat.route == .native) {
                        applyBackend()
                    }
                }
            }
            if showGenerate {
                Section(InspectorTitle.generate) {
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
        .formStyle(.grouped).padding(8)
        .navigationSplitViewColumnWidth(min: 320, ideal: 320, max: 320) // T-072 사이드바 접힘 영향 차단
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

/// 툴바 섹션 토글 3칸 (T-016 보기 옵션): 눌러서 켜고 끄는 버튼, 인디게이터 아님.
struct SectionSegments: View {
    @Binding var system: Bool
    @Binding var backend: Bool
    @Binding var generate: Bool

    var body: some View {
        HStack(spacing: 3) {
            seg(icon: "gauge", on: $system, help: "시스템 현황 보기/숨기기")
            seg(icon: "server.rack", on: $backend, help: "실행 설정 보기/숨기기")
            seg(icon: "wand.and.stars", on: $generate, help: "생성 설정 보기/숨기기")
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
