import AppKit
import SwiftUI

/// 다운로드 진행행 (T-248 Web Island식 + T-245/T-246 버튼).
/// 1줄 파일명+% · 2줄 메타 통합 · 행 바닥 2pt 바. 상태별 버튼.
struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    @ObservedObject var center: DownloadCenter
    @ObservedObject var models: ModelStore
    @ObservedObject private var downloader: ModelDownloader

    init(item: DownloadItem, center: DownloadCenter, models: ModelStore) {
        self.item = item
        self.center = center
        self.models = models
        downloader = item.downloader
    }

    private var fraction: Double {
        ModelDownload.clamp01(ModelDownload.progress(received: downloader.received,
                                                     total: downloader.total) ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.fileName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(percentText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(metaText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(metaColor)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                buttons
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 6)
            if downloader.isDownloading {
                GeometryReader { geo in
                    Rectangle().fill(Color.accentColor.opacity(0.2))
                    Rectangle().fill(Color.accentColor)
                        .frame(width: geo.size.width * fraction)
                }
                .frame(height: 2)
            }
        }
        .padding(.vertical, 2)
    }

    private var percentText: String {
        if downloader.finished { return "100%" }
        guard let p = ModelDownload.progress(received: downloader.received,
                                             total: downloader.total) else { return "—" }
        return "\(Int(p * 100))%"
    }

    private var metaText: String {
        if downloader.finished { return "다운로드 완료·미설치" }
        if let err = downloader.errorMessage { return err }
        if downloader.cancelled { return "취소됨" }
        if downloader.paused {
            return "일시정지됨 · \(ModelDownload.formatBytes(downloader.received))"
        }
        return ModelDownload.statusLine(received: downloader.received,
                                        total: downloader.total,
                                        elapsed: Date().timeIntervalSince(downloader.startedAt))
    }

    private var metaColor: Color {
        if downloader.errorMessage != nil { return .red }
        if downloader.finished { return .orange }
        return .secondary
    }

    private var statusIcon: some View {
        Group {
            if downloader.finished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if downloader.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else if downloader.cancelled {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            } else if downloader.paused {
                Image(systemName: "pause.circle.fill").foregroundStyle(.secondary)
            } else {
                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
    }

    @ViewBuilder
    private var buttons: some View {
        if downloader.finished {
            Button("삭제") { confirmDelete() }
                .controlSize(.small)
        } else if downloader.errorMessage != nil || downloader.cancelled {
            Button("다시 받기") { downloader.restart() }
                .controlSize(.small)
                .help("처음부터 다시 받기")
            Button("삭제") { confirmDelete() }
                .controlSize(.small)
        } else if downloader.paused {
            Button("이어받기") { downloader.resume() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            Button("취소") { downloader.cancel(silent: true) }
                .controlSize(.small)
            Button("삭제") { confirmDelete() }
                .controlSize(.small)
        } else {
            Button("일시정지") { downloader.pause() }
                .controlSize(.small)
            Button("취소") { downloader.cancel(silent: true) }
                .controlSize(.small)
                .help("완전 취소 (.part 삭제)")
            Button("삭제") { confirmDelete() }
                .controlSize(.small)
        }
    }

    /// 삭제 컨펌 (T-245): 진행·일시정지 중이면 취소+`.part` 정리 후 제거.
    private func confirmDelete() {
        let active = downloader.isDownloading || downloader.paused
        let alert = NSAlert()
        alert.messageText = active ? "다운로드를 취소하고 목록에서 지울까요?"
            : "목록에서 지울까요?"
        alert.informativeText = item.fileName + (active ? "\n미완성 파일도 함께 삭제됩니다." : "")
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if active { downloader.cancel(silent: true) }
        downloader.discardPartFile()
        if downloader.finished { models.scanStaging() }
        center.remove(id: item.id)
        DebugLogger.shared.info(feature: "모델가져오기", "다운로드 항목 삭제: \(item.fileName)")
    }
}
