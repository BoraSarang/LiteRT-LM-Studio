import AppKit
import SwiftUI

/// 새 모델 가져오기 시트 (T-233, 4섹션): 1 모델 → 2 파일 → 3 저장 → 4 진행.
/// 파일 목록은 저장소·토큰 변경 시 자동 재조회. 시작 후 입력 잠금.
struct ImportSheet: View {
    @ObservedObject var models: ModelStore
    @ObservedObject var center: DownloadCenter
    @Environment(\.dismiss) private var dismiss

    @State private var usePreset = true
    @State private var presetIndex = 0
    @State private var repo = "litert-community/gemma-4-E2B-it-litert-lm"
    @State private var siblings: [String] = []
    @State private var fileIndex = 0
    @State private var customFile = ""
    @State private var localID = "gemma4-e2b"
    @State private var token = ""
    @State private var fetching = false
    @State private var fetchError: String?
    @State private var fetchTask: Task<Void, Never>?
    @State private var activeItem: DownloadItem?
    @State private var locked = false

    private var presets: [ModelPreset] {
        ModelDownload.presets()
    }

    private var effectiveRepo: String {
        usePreset ? presets[presetIndex].repo : repo.trimmingCharacters(in: .whitespaces)
    }

    private var effectiveFile: String {
        ModelDownload.resolveFile(siblings: siblings, fileIndex: fileIndex, customFile: customFile)
    }

    /// 동일 파일 진행 중 여부 (중복 시작 가드).
    private var duplicateActive: Bool {
        let states = center.items.map { (fileName: $0.fileName, active: $0.downloader.isDownloading) }
        return ModelDownload.hasActiveDownload(states, fileName: effectiveFile)
    }

    private var canStart: Bool {
        !locked && !duplicateActive && !effectiveFile.isEmpty
            && !localID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L(L10n.Import.title)).font(.system(size: 13, weight: .semibold))
            modelSection
            fileSection
            storeSection
            progressSection
            HStack {
                Spacer()
                if locked {
                    Button(L(L10n.Import.fetchNew)) {
                        activeItem = nil
                        locked = false
                    }
                    .disabled(activeItem?.downloader.isDownloading == true)
                    Button(L(L10n.Import.close)) { dismiss() }
                } else {
                    Button(L(L10n.Import.close)) { dismiss() }
                    Button(L(L10n.Import.startDownload)) { startDownload() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canStart)
                }
            }
        }
        .padding(16)
        .frame(width: 480)
        .task {
            if usePreset { await fetchSiblings() }
        }
        .onChange(of: effectiveRepo) { _, _ in scheduleFetch() }
        .onChange(of: token) { _, _ in scheduleFetch() }
    }

    // MARK: - 1 · 모델

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(L10n.Import.stepModel)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Picker("", selection: $usePreset) {
                Text(L(L10n.Import.recommended)).tag(true)
                Text(L(L10n.Import.manualEntry)).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(locked)
            if usePreset {
                Picker("", selection: $presetIndex) {
                    ForEach(presets.indices, id: \.self) { i in
                        Text(presets[i].label).tag(i)
                    }
                }
                .labelsHidden()
                .disabled(locked)
                .onChange(of: presetIndex) { _, v in
                    localID = presets[v].suggestedID
                    scheduleFetch()
                }
            } else {
                TextField(L(L10n.Import.repoPlaceholder), text: $repo)
                    .textFieldStyle(.roundedBorder)
                    .disabled(locked)
            }
        }
    }

    // MARK: - 2 · 파일

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L(L10n.Import.stepFile)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                if fetching {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                }
                Spacer()
                Button(L(L10n.Import.repoPage)) {
                    if let url = ModelDownload.repoPageURL(repo: effectiveRepo) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link).font(DS.captionFont)
                .help(L(L10n.Import.checkFileHelp))
            }
            if !siblings.isEmpty {
                Picker("", selection: $fileIndex) {
                    ForEach(siblings.indices, id: \.self) { i in
                        Text(ModelDownload.fileStem(siblings[i])).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(locked)
                .help(siblings.indices.contains(fileIndex) ? siblings[fileIndex] : L(L10n.Import.pickFile))
            } else {
                TextField(L(L10n.Import.filePlaceholder), text: $customFile)
                    .textFieldStyle(.roundedBorder)
                    .disabled(locked)
            }
            // 에러 고정 슬롯 (줄 점프 방지).
            Text(fetchError ?? " ")
                .font(DS.captionFont).foregroundStyle(DSColor.error)
                .lineLimit(1).truncationMode(.tail)
        }
    }

    // MARK: - 3 · 저장

    private var storeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(L10n.Import.stepSave)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            TextField(L(L10n.Import.localIDPlaceholder), text: $localID)
                .textFieldStyle(.roundedBorder)
                .disabled(locked)
            SecureField(L(L10n.Import.tokenPlaceholder), text: $token)
                .textFieldStyle(.roundedBorder)
                .disabled(locked)
            if duplicateActive {
                Text(L(L10n.Import.duplicate))
                    .font(DS.captionFont).foregroundStyle(DSColor.warning)
            }
        }
    }

    // MARK: - 4 · 진행

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(L10n.Import.stepProgress)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if let item = activeItem {
                DownloadRow(item: item, center: center, models: models)
            } else {
                Text(L(L10n.Import.pending))
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 동작

    /// 0.5초 debounce 자동 재조회 (수동 버튼 없음, T-233).
    private func scheduleFetch() {
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await fetchSiblings()
        }
    }

    private func fetchSiblings() async {
        fetching = true
        fetchError = nil
        defer { fetching = false }
        guard let url = ModelDownload.siblingsURL(repo: effectiveRepo) else {
            fetchError = L(L10n.Import.badRepo)
            return
        }
        var req = URLRequest(url: url)
        if let auth = ModelDownload.authHeader(token: token) {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let files = ModelDownload.litertlmSiblings(from: data)
            siblings = files
            fileIndex = 0
            if files.isEmpty {
                fetchError = L(L10n.Import.noLiteFile)
            }
        } catch {
            fetchError = L(L10n.Import.fetchFailed, error.localizedDescription)
        }
    }

    private func startDownload() {
        guard models.ensureStaging() else { return }
        guard let url = ModelDownload.fileURL(repo: effectiveRepo, file: effectiveFile) else { return }
        let trimmedID = localID.trimmingCharacters(in: .whitespaces)
        let part = models.stagingURL.appendingPathComponent(ModelDownload.partName(for: effectiveFile))
        let final = models.stagingURL.appendingPathComponent(effectiveFile)
        let downloader = ModelDownloader()
        let item = DownloadItem(repo: effectiveRepo, fileName: effectiveFile,
                                  localID: trimmedID, downloader: downloader)
        activeItem = item
        locked = true
        center.add(item)
        DebugLogger.shared.info(feature: "모델가져오기", "가져오기 시작: \(effectiveFile) → \(trimmedID)")
        downloader.start(url: url, token: token.isEmpty ? nil : token,
                         partURL: part, finalURL: final) { ok in
            if ok {
                var map = models.loadMapping()
                map[effectiveFile] = FileMapping(localID: trimmedID, repo: effectiveRepo)
                models.saveMapping(map)
                models.scanStaging()
                models.invalidateListCache()
                center.saveQueue()
            }
        }
    }
}
