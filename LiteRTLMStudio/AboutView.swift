import AppKit
import SwiftUI

/// 정보 창 본체 (T-068, TubeKeep AboutView 구조): 아이콘+버전+제작자+라이브러리+copyright. 문의 이메일 없음.
struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("LiteRT-LM Studio")
                        .font(.title.weight(.semibold))

                    Text("버전 \(Self.appVersion) (build \(Self.buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("제작자: BoRaSaRang")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("macOS 전용 온디바이스 LLM 채팅 매니저")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .padding(.vertical, 4)

            Text("사용한 라이브러리")
                .font(.caption.weight(.semibold))

            ForEach(AboutLibraries.all, id: \.name) { lib in
                AboutLibraryRow(library: lib)
            }

            Divider()
                .padding(.vertical, 4)

            Text("© 2026 BoRaSaRang. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(24)
        .frame(width: 520)
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

/// 정보 창 라이브러리 데이터 (T-068): 번들 JS 벤더 2종, 버전 핀.
struct AboutLibrary {
    let name: String
    let version: String
    let url: String
}

enum AboutLibraries {
    nonisolated static let all = [
        AboutLibrary(name: "marked", version: "v18.0.13",
                     url: "https://github.com/markedjs/marked"),
        AboutLibrary(name: "highlight.js", version: "v11.12.0",
                     url: "https://github.com/highlightjs/highlight.js"),
    ]
}
