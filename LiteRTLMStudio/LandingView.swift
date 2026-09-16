import SwiftUI

/// 첫 실행 랜딩 (T-257, PLAN_v53): uv·litert-lm 설치 확인 후 시작.
/// 자동 설치는 후속, 수동 안내+복사+재확인만 제공.
struct LandingView: View {
    @Binding var done: Bool
    @StateObject private var uv = UvManager()

    private var uvOK: Bool { uv.uvAvailable }
    private var litertOK: Bool { uv.litertVersion != "없음" && uv.litertVersion != "확인 중…" }
    private var canStart: Bool { uvOK && litertOK }
    private var versionLow: Bool {
        litertOK && !OnboardingGate.meetsMinimum(uv.litertVersion)
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("LiteRT-LM Studio")
                .font(.system(size: 24, weight: .bold))
            Text("시작 전에 실행 환경을 확인합니다.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                checkRow(title: "uv", detail: uv.uvVersion, ok: uvOK)
                checkRow(title: "litert-lm", detail: uv.litertVersion, ok: litertOK)
            }
            .frame(width: 420)
            if !litertOK, uvOK {
                installGuide
                    .frame(width: 420)
            }
            if !uvOK {
                Text("uv가 없습니다. https://docs.astral.sh/uv/ 에서 설치 후 재확인해 주세요.")
                    .font(DS.captionFont).foregroundStyle(.secondary)
                    .frame(width: 420)
            }
            if versionLow {
                Text("litert-lm 버전이 낮습니다. `uv tool upgrade litert-lm` 권장 (시작은 가능).")
                    .font(DS.captionFont).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button("재확인") { Task { await uv.refresh() } }
                Button("시작하기") {
                    done = true
                    DebugLogger.shared.info(feature: "온보딩", "게이트 통과, 메인 진입")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
            Spacer()
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            await uv.refresh()
        }
    }

    private func checkRow(title: String, detail: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(detail).font(DS.captionFont).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10).fill(Color(.textBackgroundColor).opacity(0.5))
        }
    }

    private var installGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("litert-lm 설치가 필요합니다.")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Text("uv tool install litert-lm")
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 8).fill(Color(.textBackgroundColor))
                    }
                Button("복사") {
                    PasteboardUtil.copy("uv tool install litert-lm")
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10).fill(Color(.textBackgroundColor).opacity(0.5))
        }
    }
}
