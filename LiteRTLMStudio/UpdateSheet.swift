import AppKit
import SwiftUI

/// 앱 업데이트 시트 (체인지로그 + 수동 설치 안내 + 릴리스 페이지 이동).
/// 설정 `.sheet`와 메뉴바 별도 윈도우에서 공용: `onClose`가 nil이면
/// `dismiss()`(시트 경로), 있으면 직접 닫기(윈도우 경로).
struct UpdateAvailableSheet: View {
    let release: AppRelease
    let currentVersion: String
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                Text(L(L10n.Update.sheetTitle))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(currentVersion) → \(ReleaseNotesParser.displayVersion(release.tag))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            Divider()
            ScrollView {
                MarkdownView(text: release.body.isEmpty ? release.name : release.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 320)
            Text(L(L10n.Update.sheetHowto))
                .font(DS.captionFont).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L(L10n.Update.sheetClose)) { close() }
                Button(L(L10n.Update.sheetDownload)) { openReleasePage() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    /// 에셋 직접 링크가 아니라 릴리스 페이지로 보낸다 (공증 없음 안내 노출 목적).
    /// 브라우저를 열고 안내 창은 닫는다.
    private func openReleasePage() {
        if let url = URL(string: release.url) {
            NSWorkspace.shared.open(url)
            DebugLogger.shared.info(feature: "업데이트", "릴리스 페이지 열기: \(release.tag)")
        }
        close()
    }
}
