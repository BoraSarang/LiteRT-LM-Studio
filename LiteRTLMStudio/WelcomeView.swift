import AppKit
import SwiftUI

/// 추천 링크 1행 (T-262): 제목·설명·URL 고정.
struct WelcomeLink: Hashable {
    let title: String
    let detail: String
    let url: String
    let icon: String

    nonisolated static var all: [WelcomeLink] {
        [
            WelcomeLink(title: L(L10n.Welcome.docLink), detail: L(L10n.Welcome.docLinkDetail),
                        url: "https://ai.google.dev/edge/litert-lm", icon: "book"),
            WelcomeLink(title: L(L10n.Welcome.github), detail: L(L10n.Welcome.githubDetail),
                        url: "https://github.com/google-ai-edge/LiteRT-LM",
                        icon: "chevron.left.forwardslash.chevron.right"),
            WelcomeLink(title: L(L10n.Welcome.appRepo), detail: L(L10n.Welcome.appRepoDetail),
                        url: "https://github.com/BoraSarang/LiteRT-LM-Studio",
                        icon: "macwindow"),
            WelcomeLink(title: L(L10n.Welcome.huggingFace), detail: L(L10n.Welcome.huggingFaceDetail),
                        url: "https://huggingface.co/litert-community", icon: "face.smiling"),
            WelcomeLink(title: L(L10n.Welcome.gallery), detail: L(L10n.Welcome.galleryDetail),
                        url: "https://github.com/google-ai-edge/gallery", icon: "square.grid.2x2")
        ]
    }
}

/// 메인 웰컴 (T-262): 빈 채팅 화면 교체. 환영+새소식+업데이트+추천 링크.
struct WelcomeView: View {
    @ObservedObject var notes: ReleaseNotes
    @ObservedObject var uv: UvManager
    var daemonRunning: Bool

    @State private var showUpgradeConfirm = false
    @State private var upgrading = false
    @State private var upgradeNote: String?

    /// 설치된 litert-lm 버전 (`x.y.z` 추출, 없으면 nil).
    var installed: String? { OnboardingGate.parseVersion(uv.litertVersion) }

    /// 설치 버전보다 새 정식 릴리즈 (없으면 nil=최신).
    var update: AppRelease? { ReleaseNotesParser.newerStable(notes.releases, installed: installed) }

    /// 설치된 Studio 버전보다 새 앱 정식 릴리즈 (없으면 nil=최신).
    var appUpdate: AppRelease? { notes.appUpdate(installed: AboutView.appVersion) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                envLine
                newsCard
                if update != nil { updateRow }
                linksCard
                serverHint
            }
            .frame(maxWidth: DS.chatMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.bottom, 24) // T-325 하단 잘림 방지 (bottom inset 보강)
        }
        .task { await notes.refreshIfNeeded() }
        .confirmationDialog(L(L10n.Welcome.upgradeTitle), isPresented: $showUpgradeConfirm,
                            titleVisibility: .visible) {
            Button(L(L10n.Welcome.runUpgrade)) { Task { await runUpgrade() } }
            Button(L(L10n.Welcome.cancel), role: .cancel) {}
        } message: {
            Text(L(L10n.Welcome.upgradeNote))
        }
    }

    /// 환영 헤더 (앱 아이콘+이름, AboutView와 동일 소스).
    var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 14))
            Text("LiteRT-LM Studio")
                .font(.system(size: 22, weight: .bold))
            Text(L(L10n.Welcome.tagline))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    /// 환경 1줄: 설치 버전+최신 버전+상태 점.
    var envLine: some View {
        HStack(spacing: 6) {
            Circle().fill(daemonRunning ? .green : .gray)
                .frame(width: 8, height: 8)
            Text("litert-lm \(installed ?? L(L10n.Welcome.checking))")
                .font(DS.captionFont).foregroundStyle(.secondary)
            if let tag = notes.latestStable?.tag {
                Text(L(L10n.Welcome.latest, ReleaseNotesParser.displayVersion(tag)))
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            if update != nil {
                Text(L(L10n.Welcome.updateAvailable))
                    .font(DS.captionFont.weight(.semibold)).foregroundStyle(.orange)
            }
            Text("· Studio \(AboutView.appVersion)")
                .font(DS.captionFont).foregroundStyle(.secondary)
            if let appTag = appUpdate?.tag {
                Button {
                    NotificationCenter.default.post(name: .openAbout, object: nil)
                } label: {
                    Text(L(L10n.Update.available,
                            ReleaseNotesParser.displayVersion(appTag)))
                        .font(DS.captionFont.weight(.semibold)).foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 새소식 카드 (최대 3건, What's New 요약).
    var newsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L(L10n.Welcome.releaseNotes))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if notes.showingCache {
                    Text(L(L10n.Welcome.offlineSaved))
                        .font(DS.captionFont).foregroundStyle(.secondary)
                }
                if notes.isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { Task { await notes.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(L(L10n.Welcome.refreshNotes))
                }
            }
            if notes.featured.isEmpty, !notes.isLoading {
                Text(L(L10n.Welcome.notesFailed))
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            ForEach(notes.featured) { rel in
                newsRow(rel)
                if rel.id != notes.featured.last?.id { Divider() }
            }
        }.cardBox()
    }

    /// 새소식 1행: 출처 뱃지+버전+날짜+요약 3줄+자세히 링크.
    func newsRow(_ rel: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(rel.source == .app ? "Studio" : "litert-lm")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Text(ReleaseNotesParser.displayVersion(rel.tag))
                    .font(.system(size: 13, weight: .semibold))
                if rel.prerelease {
                    Text(L(L10n.Welcome.prerelease)).font(DS.captionFont).foregroundStyle(.secondary)
                }
                Spacer()
                if let date = rel.publishedAt {
                    RelativeTimeText(date: date)
                        .font(DS.captionFont).foregroundStyle(.tertiary)
                }
            }
            ForEach(ReleaseNotesParser.summaryLines(rel.body), id: \.self) { line in
                Text(line).font(DS.captionFont).foregroundStyle(.secondary).lineLimit(2)
            }
            if let url = URL(string: rel.url), !rel.url.isEmpty {
                Link(L(L10n.Welcome.readMore), destination: url)
                    .font(DS.captionFont)
            }
        }
    }

    /// 업데이트 행 (신버전 있을 때만).
    var updateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                if let tag = update?.tag {
                    Text(L(L10n.Welcome.available, ReleaseNotesParser.displayVersion(tag)))
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                if upgrading {
                    ProgressView().scaleEffect(0.7)
                    Text(L(L10n.Welcome.updating)).font(DS.captionFont).foregroundStyle(.secondary)
                } else {
                    Button(L(L10n.Welcome.update)) { showUpgradeConfirm = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            if let note = upgradeNote {
                Text(note).font(DS.captionFont).foregroundStyle(.secondary)
            }
        }.cardBox()
    }

    /// 추천 링크 카드 4행.
    var linksCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(L10n.Welcome.recommendedLinks))
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 4)
            ForEach(WelcomeLink.all, id: \.url) { link in
                Button { openLink(link.url) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: link.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.title).font(.system(size: 13, weight: .medium))
                            Text(link.detail).font(DS.captionFont).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L(L10n.Welcome.openLink, link.title))
            }
            Text(L(L10n.Welcome.source))
                .font(DS.captionFont).foregroundStyle(.tertiary)
                .padding(.top, 4)
        }.cardBox()
    }

    /// 서버 미실행 시 축소 안내.
    var serverHint: some View {
        Group {
            if !daemonRunning {
                Text(L(L10n.Welcome.startHint))
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
        }
    }

    /// 앱 아이콘 (AboutView와 동일 소스, 없으면 brain 폴백).
    var appIcon: NSImage {
        NSApp.applicationIconImage
            ?? NSImage(systemSymbolName: "brain", accessibilityDescription: nil) ?? NSImage()
    }

    /// 외부 링크 열기 (기본 브라우저).
    func openLink(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
        DebugLogger.shared.info(feature: "웰컴", "링크 열기: \(raw)")
    }

    /// litert-lm 업데이트 실행 (확인 팝업 이후 호출).
    func runUpgrade() async {
        upgrading = true
        upgradeNote = nil
        defer { upgrading = false }
        DebugLogger.shared.info(feature: "업데이트", "uv tool upgrade litert-lm 시작")
        let (out, code) = await UvManager.runProcess(
            UvManager.uvPath, args: ["tool", "upgrade", "litert-lm"], timeout: 120)
        if code == 0 {
            await uv.refresh()
            await notes.refresh()
            upgradeNote = L(L10n.Welcome.upgradeDone, installed ?? "")
            DebugLogger.shared.info(feature: "업데이트", "완료: \(out.prefix(120))")
        } else {
            upgradeNote = L(L10n.Welcome.upgradeFailed)
            DebugLogger.shared.error(code: "E-MAC-ENG-0003", feature: "업데이트", out)
        }
    }
}
