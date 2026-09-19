import AppKit
import SwiftUI

/// 카탈로그 둘러보기 탭 본체 (T-234, PLAN_v49).
/// 기본 추천 모델 + `[전체 모델 보기]` 확장. 상세는 Sections 확장.
struct CatalogBrowserView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var models: ModelStore
    @ObservedObject var center: DownloadCenter

    @State private var searchTask: Task<Void, Never>?
    // Sections 확장에서 접근하므로 internal (T-234).
    @State var detailFileIndex = 0
    @State var detailLocalID = ""
    @State var downloadNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchBar
            if catalog.mode == .recommended {
                // T-319: 추천은 상단 가로 카드로만 표시, 좌 리스트 중복 제거.
                recommendedPane
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                filterBar
                HSplitView {
                    listPane
                        .frame(width: 264)
                    detailPane
                        .frame(maxWidth: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                }
            }
            footerBar
        }
    }

    // MARK: - 검색

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("모델 검색 (입력하면 전체에서 검색)", text: $catalog.query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: catalog.query) { _, _ in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        guard !Task.isCancelled else { return }
                        await catalog.search()
                    }
                }
            if catalog.mode == .all {
                Button("추천 모델로") { catalog.mode = .recommended }
                    .buttonStyle(.link).font(DS.captionFont)
            }
        }
    }

    // MARK: - 추천 모델

    private var recommendedPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("추천 모델").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("전체 모델 보기") { Task { await catalog.search() } }
                    .buttonStyle(.link).font(DS.captionFont)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(catalog.recommended, id: \.repo) { pick in
                        pickCard(pick)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func pickCard(_ pick: RecommendedModel) -> some View {
        let selected = catalog.selectedRepo == pick.repo
        let installed = models.models.contains(where: { $0.id == pick.suggestedID })
        return Button {
            detailLocalID = pick.suggestedID
            detailFileIndex = 0
            Task { await catalog.select(repo: pick.repo) }
        } label: {
            HStack(spacing: 8) {
                CatalogAvatar(repo: pick.repo)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pick.label).font(.system(size: 13, weight: .semibold))
                        DSBadge(text: installed ? "설치됨" : "미설치",
                                kind: installed ? .success : .neutral)
                    }
                    Text(pick.blurb).font(DS.captionFont).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(10)
            .frame(width: 240, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? DSColor.primary.opacity(0.15) : Color(.textBackgroundColor))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("\(pick.label) — \(pick.blurb)")
    }

    // MARK: - 전체 모드 필터

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(CatalogFamily.allCases, id: \.rawValue) { f in
                    Button {
                        catalog.family = f
                    } label: {
                        Text(f.title)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background {
                                if catalog.family == f {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(DSColor.primary.opacity(0.15))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("", selection: $catalog.sort) {
                ForEach(CatalogSort.allCases, id: \.rawValue) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: catalog.sort) { _, _ in Task { await catalog.search() } }
            Spacer()
            if catalog.isLoading {
                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
            }
            Text("\(catalog.filtered.count)건").font(DS.captionFont).foregroundStyle(.secondary)
        }
    }

    // MARK: - 좌 목록

    private var listPane: some View {
        Group {
            if catalog.filtered.isEmpty, !catalog.isLoading {
                ContentUnavailableView("검색 결과 없음", systemImage: "magnifyingglass",
                                       description: Text("검색어·필터를 바꿔 보세요."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { catalog.selectedRepo },
                                        set: { v in
                                            if let v {
                                                detailFileIndex = 0
                                                detailLocalID = ModelCatalog.paramsHint(repo: v).map {
                                                    "\(v.split(separator: "/").last.map(String.init) ?? v)-\($0)"
                                                        .lowercased()
                                                } ?? ""
                                                Task { await catalog.select(repo: v) }
                                            }
                                        })) {
                    ForEach(catalog.filtered) { entry in
                        entryRow(repo: entry.repo, title: entry.shortName,
                                 subtitle: entry.pipelineTag ?? entry.org,
                                 stat: Self.statLine(entry: entry))
                            .tag(entry.repo)
                    }
                    if catalog.hasMore {
                        Button(catalog.isLoading ? "불러오는 중…" : "더 보기") {
                            Task { await catalog.loadMore() }
                        }
                        .buttonStyle(.link).font(DS.captionFont)
                        .disabled(catalog.isLoading)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// 목록행 통계 1줄 (순수 조합).
    nonisolated static func statLine(entry: CatalogEntry) -> String {
        var parts = ["↓\(ModelCatalog.prettyCount(entry.downloads))"]
        if entry.likes > 0 { parts.append("☆\(entry.likes)") }
        if let age = ModelCatalog.daysAgo(iso: entry.lastModified ?? entry.createdAt) {
            parts.append(age == 0 ? "오늘" : "\(age)일 전")
        }
        return parts.joined(separator: " · ")
    }

    private func entryRow(repo: String, title: String, subtitle: String, stat: String) -> some View {
        HStack(spacing: 8) {
            CatalogAvatar(repo: repo)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(subtitle).font(DS.captionFont).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                    if !stat.isEmpty {
                        Text(stat).font(DS.captionFont).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 하단 푸터

    private var footerBar: some View {
        HStack(spacing: 8) {
            Text("로컬 설치 \(models.models.count)개 · 스테이징 \(models.staged.count)개"
                + " (\(ModelDownload.formatBytes(ModelStore.totalBytes(models.staged))))")
                .font(DS.captionFont).foregroundStyle(.secondary)
            Spacer()
            Text(models.stagingURL.path).font(DS.captionFont).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Button("열기") { models.revealStaging() }
                .buttonStyle(.link).font(DS.captionFont)
        }
    }
}
