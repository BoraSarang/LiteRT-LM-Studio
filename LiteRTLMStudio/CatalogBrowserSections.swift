import AppKit
import SwiftUI

// MARK: - 카탈로그 상세 (T-234 분리: 파일 길이 분산)

extension CatalogBrowserView {
    // MARK: - 우 상세

    var detailPane: some View {
        Group {
            if let repo = catalog.selectedRepo {
                detailBody(repo: repo)
            } else {
                ContentUnavailableView("모델을 고르세요", systemImage: "square.grid.2x2",
                                       description: Text("왼쪽 목록에서 고르면 상세·다운로드 옵션이 나옵니다."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detailBody(repo: String) -> some View {
        Group {
            if let detail = catalog.detail, detail.repo == repo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        detailHeader(detail)
                        downloadOptions(detail)
                        capabilitiesNote(detail)
                        readmeSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(repo).font(DS.captionFont).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detailHeader(_ detail: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CatalogAvatar(repo: detail.repo).frame(width: 32, height: 32)
                Text(detail.repo).font(.system(size: 15, weight: .semibold))
                    .textSelection(.enabled)
                Button {
                    PasteboardUtil.copy(detail.repo)
                } label: {
                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("저장소 ID 복사")
            }
            HStack(spacing: 10) {
                Label("↓\(ModelCatalog.prettyCount(detail.downloads))", systemImage: "arrow.down.circle")
                Label("\(detail.likes)", systemImage: "star")
                if let days = ModelCatalog.daysAgo(iso: detail.lastModified ?? detail.createdAt) {
                    Text(days == 0 ? "오늘 업데이트" : "\(days)일 전 업데이트")
                }
            }
            .font(DS.captionFont).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let params = ModelCatalog.paramsHint(repo: detail.repo) {
                    DetailChip(text: "매개변수 \(params)")
                }
                ForEach(ModelCatalog.badges(pipelineTag: detail.pipelineTag), id: \.rawValue) { badge in
                    DetailChip(text: badge.title)
                }
                Text("수치는 참고용").font(DS.captionFont).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 다운로드 옵션

    private func downloadOptions(_ detail: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("다운로드 옵션").font(.system(size: 13, weight: .semibold))
            if detail.siblings.isEmpty {
                Text("`.litertlm` 파일을 찾지 못했습니다.")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            } else {
                Picker("", selection: $detailFileIndex) {
                    ForEach(detail.siblings.indices, id: \.self) { i in
                        Text(ModelDownload.fileStem(detail.siblings[i])).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .help(detail.siblings.indices.contains(detailFileIndex)
                    ? detail.siblings[detailFileIndex] : "파일 선택")
                .onChange(of: detailFileIndex) { _, _ in refreshDetailSize(detail) }
                HStack(spacing: 8) {
                    TextField("로컬 모델 ID", text: $detailLocalID)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                    downloadActionTrailing(detail)
                    Button("다운로드") { startDetailDownload(detail) }
                        .buttonStyle(.borderedProminent)
                        .tint(DSColor.primary)
                        .disabled(detailFile(detail).isEmpty
                            || detailLocalID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                SecureField("Hugging Face 토큰 (게이트 저장소만)", text: $catalog.token)
                    .textFieldStyle(.roundedBorder)
                    .help("google 계열 등 승인 필요 저장소는 HF에서 접근 승인 후 토큰 입력 (세션만 유지)")
                if let notice = downloadNotice {
                    Text(notice).font(DS.captionFont).foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10).fill(Color(.textBackgroundColor).opacity(0.5))
        }
        .task(id: "\(detail.repo)#\(detailFileIndex)") {
            refreshDetailSize(detail)
        }
    }

    private func detailFile(_ detail: CatalogEntry) -> String {
        guard detail.siblings.indices.contains(detailFileIndex) else { return "" }
        return detail.siblings[detailFileIndex]
    }

    /// 용량+수동 다운로드 링크 행 (T-243 분리: 함수 길이 분산).
    @ViewBuilder
    private func downloadActionTrailing(_ detail: CatalogEntry) -> some View {
        if let size = catalog.fileSizes["\(detail.repo)/\(detailFile(detail))"] {
            Text(ModelDownload.formatBytes(size))
                .font(DS.captionFont).foregroundStyle(.secondary)
        }
        if let treeURL = ModelDownload.repoTreeURL(repo: detail.repo) {
            Link("수동 다운로드", destination: treeURL)
                .font(.system(size: 13))
                .help("브라우저에서 파일 목록을 열어 직접 받기")
        }
    }

    private func refreshDetailSize(_ detail: CatalogEntry) {
        let file = detailFile(detail)
        guard !file.isEmpty else { return }
        // T-253: 실제 파일명으로 ID 항상 동기화.
        detailLocalID = ModelDownload.fileStem(file)
        Task { await catalog.loadSize(repo: detail.repo, file: file) }
    }

    private func startDetailDownload(_ detail: CatalogEntry) {
        let file = detailFile(detail)
        let trimmedID = detailLocalID.trimmingCharacters(in: .whitespaces)
        guard GlobalPermission.current() != .off else {
            downloadNotice = "권한이 꺼져 있습니다. 설정에서 바꿔 주세요."
            return
        }
        let states = center.items.map { (fileName: $0.fileName, active: $0.downloader.isDownloading) }
        guard !ModelDownload.hasActiveDownload(states, fileName: file) else {
            downloadNotice = "같은 파일을 이미 받는 중입니다."
            return
        }
        guard models.ensureStaging(),
              let url = ModelDownload.fileURL(repo: detail.repo, file: file) else { return }
        let downloader = ModelDownloader()
        let item = DownloadItem(repo: detail.repo, fileName: file,
                                  localID: trimmedID, downloader: downloader)
        center.add(item)
        downloadNotice = "다운로드를 요청했습니다. 내 모델 탭 다운로드 중에서 확인하세요."
        DebugLogger.shared.info(feature: "모델가져오기", "카탈로그 다운로드: \(file) → \(trimmedID)")
        downloader.start(url: url, token: catalog.token.isEmpty ? nil : catalog.token,
                         partURL: models.stagingURL.appendingPathComponent(ModelDownload.partName(for: file)),
                         finalURL: models.stagingURL.appendingPathComponent(file)) { ok in
            if ok {
                var map = models.loadMapping()
                map[file] = FileMapping(localID: trimmedID, repo: detail.repo)
                models.saveMapping(map)
                models.scanStaging()
                models.invalidateListCache()
                center.saveQueue()
            } else {
                downloadNotice = "다운로드 실패: \(item.downloader.errorMessage ?? "원인 불명")"
            }
        }
    }

    private func capabilitiesNote(_ detail: CatalogEntry) -> some View {
        Text("추론·함수 호출 지원은 설치 후 실측으로 확정됩니다 (실행 설정 표시).")
            .font(DS.captionFont).foregroundStyle(.secondary)
    }

    // MARK: - 모델 설명

    private var readmeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("모델 설명").font(.system(size: 13, weight: .semibold))
            if let readme = catalog.readme, !readme.isEmpty {
                MarkdownView(text: String(readme.prefix(60_000)))
            } else {
                Text("모델 설명이 없습니다.").font(DS.captionFont).foregroundStyle(.secondary)
            }
        }
    }
}

/// 저장소 뱃지 (T-241): HF 아바타 주소가 무효(401)라 로컬 이니셜로 대체.
/// 오프라인에서도 깨지지 않음.
struct CatalogAvatar: View {
    let repo: String

    private var family: CatalogFamily { ModelCatalog.family(of: repo) }

    private var initial: String {
        repo.split(separator: "/").last?.first.map { String($0).uppercased() } ?? "?"
    }

    private var tint: Color {
        switch family {
        case .gemma: return .blue
        case .qwen: return .purple
        case .all, .other: return .gray
        }
    }

    var body: some View {
        Text(initial)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 7).fill(tint)
            }
    }
}

/// 상세 정보 칩 (T-234).
struct DetailChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.captionFont).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6).fill(Color(.textBackgroundColor))
            }
    }
}
