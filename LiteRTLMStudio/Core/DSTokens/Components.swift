import SwiftUI

/// 공용 컴포넌트 (T-318, PLAN_v96): 전 화면은 이것만 재사용, 커스텀 스타일 금지.
/// 네이티브 segmented 공통화 (사용자 결정, AGENTS.local 전폭 규칙 예외).

struct DSPrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(DSColor.primary)
    }
}

struct DSSecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }
}

struct DSTextLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.link)
    }
}

/// 네이티브 세그먼트 공통 래퍼 (Picker + .segmented).
struct DSSegmented<Value: Hashable, Label: View>: View {
    let title: String
    @Binding var selection: Value
    let content: () -> Label
    init(_ title: String, selection: Binding<Value>, @ViewBuilder content: @escaping () -> Label) {
        self.title = title
        self._selection = selection
        self.content = content
    }
    var body: some View {
        Picker(title, selection: $selection, content: content)
            .pickerStyle(.segmented)
    }
}

struct DSSection<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        Section(title) { content }
    }
}

enum DSBadgeKind {
    case success, warning, error, neutral
    var color: Color {
        switch self {
        case .success: DSColor.success
        case .warning: DSColor.warning
        case .error: DSColor.error
        case .neutral: .secondary
        }
    }
}

/// 상태 뱃지 (아이콘+텍스트): 초록/주황 점 대체.
struct DSBadge: View {
    let text: String
    let kind: DSBadgeKind
    var body: some View {
        Label(text, systemImage: badgeIcon)
            .font(DSType.caption)
            .foregroundStyle(kind.color)
    }
    private var badgeIcon: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .neutral: "circle.fill"
        }
    }
}

/// 경고 배너 (상단 강조 + 액션 1개).
struct DSWarningBanner: View {
    let text: String
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: DSSpace.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DSColor.warning)
            Text(text).font(DSType.callout)
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(DSSpace.s)
        .background(DSColor.warning.opacity(0.12))
        .clipShape(.rect(cornerRadius: DSSpace.radiusS))
    }
}

/// 리스트 카드 행 (T-327): 회색 리스트 위 흰색 카드.
struct DSCardRow<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .padding(DSSpace.m)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(.rect(cornerRadius: DSSpace.radiusL))
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
