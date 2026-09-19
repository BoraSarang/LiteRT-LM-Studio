import AppKit
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

/// 설정 창 공용 폼 스타일 (T-358): 설정 창을 내용 폭(600)에 맞춰 고정한 뒤, 그룹 폼의
/// 네이티브 인셋 위에 사방 같은 값(DSSpace.l)을 더해 좌우·상하 여백을 균일하게 맞춘다.
/// (T-357은 세로만 줬으나, 창 폭 고정 후 그 방식은 상하가 더 커 보였다.)
/// `Settings` 씬의 창 제목은 선택된 탭 이름으로 덮이므로(SwiftUI 동작) 탭이 뜰 때마다 "LiteRT-LM Studio 설정"으로 재설정한다.
extension View {
    func dsSettingsForm() -> some View {
        formStyle(.grouped)
            .padding(DSSpace.l)
            .background(SettingsWindowTitleSetter(title: "LiteRT-LM Studio 설정").frame(width: 0, height: 0))
    }
}

/// T-358: `Settings` 씬 창 제목은 선택된 탭 이름(일반/채팅/…)으로 덮인다(SwiftUI 동작).
/// 한 번 세팅하는 것만으로는 SwiftUI가 다시 덮어써 경합하므로, 창을 찾아 제목을 고정하고
/// `title` 변경을 KVO로 감시해 원하는 값으로 되돌린다.
struct SettingsWindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            context.coordinator.pin(window, title: title)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            context.coordinator.pin(window, title: title)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private weak var window: NSWindow?
        private var observation: NSKeyValueObservation?

        func pin(_ window: NSWindow, title: String) {
            if window.title != title { window.title = title }
            guard observation == nil || self.window !== window else { return }
            self.window = window
            observation?.invalidate()
            observation = window.observe(\.title, options: [.new]) { [weak window] _, _ in
                guard let window, window.title != title else { return }
                DispatchQueue.main.async { window.title = title }
            }
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
