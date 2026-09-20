import AppKit
import SwiftUI

/// 정보 창 본체 (T-068, TubeKeep AboutView 구조): 아이콘+버전+제작자+라이브러리+copyright. 문의 이메일 없음.
struct AboutView: View {
    @ObservedObject var releases: ReleaseNotes
    @State private var checking = false
    @State private var checkMessage: String?
    @State private var showUpdateSheet = false

    /// 설치된 앱 버전보다 새 앱 정식 릴리즈 (없으면 nil=최신).
    var appUpdate: AppRelease? { releases.appUpdate(installed: Self.appVersion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("LiteRT-LM Studio")
                        .font(.title.weight(.semibold))

                    Text(L(L10n.About.version, Self.appVersion, Self.buildNumber))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(L(L10n.About.author))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(L(L10n.About.tagline))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    updateRow
                }
            }

            Divider()
                .padding(.vertical, 4)

            if !AboutLibraries.all.isEmpty {
                Text(L(L10n.About.libraries))
                    .font(.caption.weight(.semibold))

                ForEach(AboutLibraries.all, id: \.name) { lib in
                    AboutLibraryRow(library: lib)
                }

                Divider()
                    .padding(.vertical, 4)
            }

            Text("© 2026 BoRaSaRang. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(24)
        .frame(width: 520)
        .sheet(isPresented: $showUpdateSheet) {
            if let update = appUpdate {
                UpdateAvailableSheet(release: update, currentVersion: Self.appVersion)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkAppUpdate)) { _ in
            Task { await checkUpdate() }
        }
    }

    /// 업데이트 확인 행: 확인 버튼 + 상태, 신버전 있으면 주황 표시+시트.
    var updateRow: some View {
        HStack(spacing: 6) {
            if checking {
                ProgressView().scaleEffect(0.7)
                Text(L(L10n.Update.checking))
                    .font(.caption).foregroundStyle(.secondary)
            } else if let update = appUpdate {
                Button {
                    showUpdateSheet = true
                } label: {
                    Text(L(L10n.Update.available,
                            ReleaseNotesParser.displayVersion(update.tag)))
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            } else {
                Button(L(L10n.Update.check)) { Task { await checkUpdate() } }
                    .controlSize(.small)
                if let message = checkMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 수동 확인: 조회 후 시각 기록, 신버전이면 시트 자동 팝업.
    func checkUpdate() async {
        guard !checking else { return }
        checking = true
        checkMessage = nil
        defer { checking = false }
        await releases.refresh()
        UserDefaults.standard.set(Date().timeIntervalSince1970,
                                  forKey: ReleaseNotes.appUpdateCheckedAtKey)
        if appUpdate != nil {
            showUpdateSheet = true
        } else if releases.lastError != nil {
            checkMessage = L(L10n.Update.failed)
        } else if releases.releases.first(where: { $0.source == .app }) == nil {
            checkMessage = L(L10n.Update.noRelease)
        } else {
            checkMessage = L(L10n.Update.latest)
        }
    }

    private var icon: NSImage {
        NSApp.applicationIconImage
            ?? NSImage(systemSymbolName: "brain", accessibilityDescription: nil) ?? NSImage()
    }

    nonisolated static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    nonisolated static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

/// 정보 창 라이브러리 1행: 이름·버전 좌, 링크 우 (TubeKeep LibraryRow + 클릭 가능).
struct AboutLibraryRow: View {
    let library: AboutLibrary

    var body: some View {
        HStack(spacing: 4) {
            Text(library.name)
                .foregroundStyle(.primary)
            Text(library.version)
                .foregroundStyle(.secondary)
                .font(.caption2)
            Spacer()
            if let url = URL(string: library.url) {
                Link(library.url, destination: url)
                    .foregroundStyle(.tertiary)
                    .truncationMode(.middle)
                    .lineLimit(1)
            }
        }
    }
}

/// 정보 창 라이브러리 데이터 (T-150): JS 벤더 제거로 빈 목록 유지.
struct AboutLibrary {
    let name: String
    let version: String
    let url: String
}

enum AboutLibraries {
    nonisolated static let all: [AboutLibrary] = []
}
