import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

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
                    BackendSectionView(config: config, model: selectedModel) {
                        applyBackend()
                    }
                }
            }
            if showGenerate {
                Section(InspectorTitle.generate) {
                    HStack {
                        Text("Temperature"); Slider(value: $chat.temperature, in: 0...1.5, step: 0.05)
                        Text(String(format: "%.2f", chat.temperature)).monospacedDigit()
                    }
                    // 현 gemma4-12b 미지원 → 비활성화 + 툴팁 (describe 실측 반영)
                    Toggle("Thinking", isOn: .constant(false)).disabled(true)
                        .help(selectedModel?.thinking == true ? "" : "이 모델은 Thinking 미지원 (E-MAC-VALID-0007)")
                    Toggle("Function Calling", isOn: .constant(false)).disabled(true)
                        .help(functionCallHelp(selectedModel?.functionCall == true))
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
    supported ? "" : "이 모델은 Function Calling 미지원 (E-MAC-VALID-0008)"
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
                        RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
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
    var onApply: () -> Void

    var body: some View {
        Picker("LLM 실행", selection: $config.draftBackend) {
            Text("GPU (Metal)").tag("gpu"); Text("CPU").tag("cpu")
        }.pickerStyle(.segmented)
        Picker("Vision 실행", selection: $config.draftVision) {
            Text("GPU").tag("gpu"); Text("CPU").tag("cpu")
        }.pickerStyle(.segmented)
        Toggle("MTP (Speculative Decoding)", isOn: $config.draftMTP)
            .help("GPU 백엔드 권장. 모델이 drafter 포함 시 가속.")
            .disabled(model?.speculative == false)
        if let mdl = model {
            LabeledContent("모델 Speculative", value: mdl.speculative ? "지원" : "미포함")
            LabeledContent("모달리티", value: mdl.modalities)
        }
        if config.hasChanges {
            Text(config.diffSummary).font(DS.captionFont).foregroundStyle(.orange)
            HStack {
                Button("취소") { config.revert() }
                Spacer()
                Button("적용 후 재시작", action: onApply)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Text("바꾸면 여기에 적용·취소가 나와요. 적용은 서버 재시작을 동반합니다.")
                .font(DS.captionFont).foregroundStyle(.secondary)
        }
    }
}
