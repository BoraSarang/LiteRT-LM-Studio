import SwiftUI

/// 후속질문 칩 행 (T-261): 어시스턴트 버블 직하·우측 정렬, 클릭 즉시 전송.
/// T-360: 파일 길이 관리를 위해 `FollowUpSuggest.swift`에서 분리.
struct FollowUpChipsView: View {
    let chips: [String]
    var disabled = false
    var onTap: (String) -> Void = { _ in }

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button { onTap(chip) } label: {
                        Text(chip)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(DSColor.primary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(L(L10n.FollowUp.sendHelp))
                    .disabled(disabled)
                }
            }
        }
        .transition(.opacity) // T-313: 스켈레톤→칩 크로스페이드
    }
}

/// 후속질문 로딩 자리 (T-291/T-313): 칩과 동일 배치(Capsule·높이 28)의 스켈레톤 3개.
/// 심머가 좌→우로 흐르고, 완료 시 칩으로 크로스페이드된다. 동작 줄이기 시 정적.
struct FollowUpSkeletonView: View {
    /// 칩 폭과 비슷한 길이 변주 (단조로움 완화).
    private static let barWidths: [CGFloat] = [148, 120, 164]

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(Array(Self.barWidths.enumerated()), id: \.offset) { item in
                    SkeletonBar(width: item.element)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L(L10n.FollowUp.generating))
        .transition(.opacity) // T-313: 스켈레톤→칩 크로스페이드
    }
}

/// 심머 스켈레톤 바 (T-313): 밝은 그라데이션이 좌→우로 지나간다.
private struct SkeletonBar: View {
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.secondary.opacity(0.18))
            .frame(width: width, height: 28)
            .overlay {
                if !reduceMotion {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [.clear, Color.primary.opacity(0.14), .clear],
                            startPoint: .leading, endPoint: .trailing))
                        .offset(x: (phase * 2 - 1) * width)
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false),
                                   value: phase)
                }
            }
            .clipShape(Capsule(style: .continuous))
            .onAppear { phase = 1 }
    }
}
