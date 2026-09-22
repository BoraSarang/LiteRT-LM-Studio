import AppKit
import SwiftUI

/// 진행 중 다운로드 1건 (행 표시용 래퍼).
final class DownloadItem: ObservableObject, Identifiable {
    let id = UUID()
    let repo: String
    let fileName: String
    let localID: String
    let downloader: ModelDownloader

    init(repo: String, fileName: String, localID: String, downloader: ModelDownloader) {
        self.repo = repo
        self.fileName = fileName
        self.localID = localID
        self.downloader = downloader
    }
}

/// 진행 중 다운로드 보관 (창 닫아도 ModelStore와 별개로 유지).
final class DownloadCenter: ObservableObject {
    @Published var items: [DownloadItem] = []
    @Published var orphans: [OrphanPart] = []

    func add(_ item: DownloadItem) {
        items.append(item)
        saveQueue()
    }

    func remove(id: DownloadItem.ID) {
        items.removeAll { $0.id == id }
        saveQueue()
    }

    // MARK: - 큐 영속 (T-249)

    var stagingDir: URL?

    private var queueURL: URL? { stagingDir?.appendingPathComponent(".queue.json") }

    /// 미완료 항목만 저장 (원자 쓰기, 크래시 내성). 토큰은 저장 안 함.
    func saveQueue() {
        guard let url = queueURL else { return }
        let records = items.filter { !$0.downloader.finished }.map {
            QueuedDownload(repo: $0.repo, file: $0.fileName, localID: $0.localID)
        }
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: url, options: .atomic)
            DebugLogger.shared.info(feature: "모델관리", "[CACHE] 큐 저장 \(records.count)건")
        }
    }

    /// 복원 (T-249): final 있으면 완료로 제외, 나머지는 일시정지.
    func restore(staging: URL) {
        stagingDir = staging
        guard let url = queueURL,
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([QueuedDownload].self, from: data) else {
            scanOrphans(staging: staging)
            return
        }
        let finals = Set((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? [])
        var restored: [DownloadItem] = []
        for rec in Self.pendingRecords(records, existingFinals: finals) {
            let part = staging.appendingPathComponent(ModelDownload.partName(for: rec.file))
            let size = ModelDownload.fileSizeBytes(at: part)
            let downloader = ModelDownloader()
            downloader.stageForResume(
                url: ModelDownload.fileURL(repo: rec.repo, file: rec.file),
                partURL: part,
                finalURL: staging.appendingPathComponent(rec.file),
                received: size)
            restored.append(DownloadItem(repo: rec.repo, fileName: rec.file,
                                         localID: rec.localID, downloader: downloader))
        }
        items = restored
        if !restored.isEmpty {
            DebugLogger.shared.info(feature: "모델관리", "큐 복원 \(restored.count)건 (일시정지)")
        }
        scanOrphans(staging: staging)
        saveQueue()
    }

    /// 복원 대상 선별 (순수, T-249): final 존재분 제외.
    nonisolated static func pendingRecords(_ records: [QueuedDownload],
                                           existingFinals: Set<String>) -> [QueuedDownload] {
        records.filter { !existingFinals.contains($0.file) }
    }

    /// 고아 스캔 (T-249): `.part` 중 큐·진행행에 없는 것.
    func scanOrphans(staging: URL) {
        let known = Set(items.map(\.fileName))
        orphans = Self.orphanFinals(partFiles: Self.partFiles(at: staging), queuedFiles: known)
            .map { name in
                let part = staging.appendingPathComponent(ModelDownload.partName(for: name))
                let size = ModelDownload.fileSizeBytes(at: part)
                return OrphanPart(fileName: name, sizeBytes: size)
            }
            .sorted { $0.fileName.localizedCompare($1.fileName) == .orderedAscending }
    }

    /// 스테이징 `.part`의 최종 파일명 목록.
    nonisolated static func partFiles(at dir: URL) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        return names.filter { $0.hasSuffix(".part") }.map { ModelDownload.finalName(part: $0) }
    }

    /// 고아 판정 (순수, T-249).
    nonisolated static func orphanFinals(partFiles: [String], queuedFiles: Set<String>) -> [String] {
        partFiles.filter { !queuedFiles.contains($0) }
    }

    /// 고아 `.part` 삭제.
    func deleteOrphan(_ fileName: String) {
        guard let dir = stagingDir else { return }
        let part = dir.appendingPathComponent(ModelDownload.partName(for: fileName))
        try? FileManager.default.removeItem(at: part)
        orphans.removeAll { $0.fileName == fileName }
        DebugLogger.shared.info(feature: "모델관리", "고아 삭제: \(fileName).part")
    }
}

/// 큐 영속 레코드 (T-249): 토큰 제외.
struct QueuedDownload: Codable, Sendable, Equatable {
    let repo: String
    let file: String
    let localID: String
}

/// 미완성 고아 1건 (T-249): 큐 기록 없는 `.part`.
struct OrphanPart: Identifiable, Hashable, Sendable {
    var id: String { fileName }
    let fileName: String
    var sizeBytes: Int64 = 0
}

/// 모델 관리 별도창 (T-232, PLAN_v47; T-233 상주 center 주입).
/// 정렬 규칙: 데이터 있음 좌측·상단, 빈 목록은 중앙 문구.
struct ModelManagerView: View {
    @ObservedObject var models: ModelStore
    @ObservedObject var center: DownloadCenter
    // Sections 확장에서 접근하므로 internal (T-251).
    @StateObject var catalog = CatalogStore()
    @State private var showImport = false
    // Sections 확장에서 접근하므로 internal (T-240/T-247).
    @State var notice: String?
    // Sections 확장에서 접근하므로 internal (T-240).
    @State var browseSelected = true
    // Sections 확장에서 접근하므로 internal (T-321 행 분리).
    @State var highlightModelID: String?
    @State private var highlightTask: Task<Void, Never>?
    @State private var showPurgeConfirm = false

    /// 하이라이트 만료 판정 (순수, T-247).
    nonisolated static func shouldClearHighlight(setAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(setAt) >= 3
    }

    // Sections 확장에서 접근하므로 internal (T-321 행 분리).
    var installedIDs: Set<String> { Set(models.models.map(\.id)) }
    // Sections 확장에서 접근하므로 internal (T-247).
    var mapping: [String: FileMapping] { models.loadMapping() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            managerTabs
            if browseSelected {
                CatalogBrowserView(catalog: catalog, models: models, center: center)
            } else {
                myModelsBody
            }
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 600)
        .task {
            models.ensureStaging()
            await models.refreshCached()
            models.scanStaging()
            center.restore(staging: models.stagingURL)
            DebugLogger.shared.info(feature: "모델관리", "관리 창 열림")
        }
        .sheet(isPresented: $showImport) {
            ImportSheet(models: models, center: center)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openModelManagerMyModels)) { n in
            browseSelected = false
            highlightModelID = n.object as? String
            highlightTask?.cancel()
            highlightTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                highlightModelID = nil
            }
        }
    }

    /// 내 모델 탭 본체 (T-232/T-233 유지).
    private var myModelsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // T-321: 디스크 2배 사용 경고 배너 (설치됨+스테이징 중복분 정리 액션).
            if !purgeableStaged.isEmpty {
                DSWarningBanner(
                    text: L(L10n.ModelManager.purgeNotice, purgeableStaged.count),
                    actionTitle: L(L10n.ModelManager.purgeAction)) {
                    guard checkPermission() else { return }
                    showPurgeConfirm = true
                }
            }
            if models.models.isEmpty, models.staged.isEmpty,
               center.items.isEmpty, center.orphans.isEmpty {
                ContentUnavailableView(L(L10n.ModelManager.emptyTitle), systemImage: "archivebox",
                                       description: Text(L(L10n.ModelManager.emptyDescription)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !center.items.isEmpty {
                        Section(L(L10n.ModelManager.sectionDownloading)) {
                            ForEach(center.items) { item in
                                DSCardRow {
                                    DownloadRow(item: item, center: center, models: models)
                                }
                            }
                        }
                    }
                    if !center.orphans.isEmpty {
                        Section(L(L10n.ModelManager.sectionIncomplete)) {
                            ForEach(center.orphans) { part in
                                DSCardRow {
                                    orphanRow(part)
                                }
                            }
                        }
                    }
                    Section(L(L10n.ModelManager.sectionInstalled, models.models.count)) {
                        ForEach(models.models) { m in
                            DSCardRow {
                                installedRow(m)
                            }
                        }
                    }
                    Section(L(L10n.ModelManager.sectionStaging, models.staged.count)) {
                        ForEach(models.staged) { s in
                            DSCardRow {
                                stagedRow(s)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            footer
        }
        .confirmationDialog(L(L10n.ModelManager.purgeConfirm, purgeableStaged.count),
                            isPresented: $showPurgeConfirm, titleVisibility: .visible) {
            Button(L(L10n.ModelManager.purgeAction), role: .destructive) { purgeStagedOriginals() }
            Button(L(L10n.ModelManager.cancel), role: .cancel) {}
        } message: {
            Text(L(L10n.ModelManager.purgeConfirmNote))
        }
    }

    /// 설치된 모델의 스테이징 원본 목록 (T-321): 2배 디스크 정리 대상.
    private var purgeableStaged: [StagedEntry] {
        let map = models.loadMapping()
        return models.staged.filter { entry in
            let localID = map[entry.fileName]?.localID
                ?? (entry.fileName as NSString).deletingPathExtension
            return installedIDs.contains(localID)
        }
    }

    /// 스테이징 원본 일괄 삭제 (T-321): 설치 모델은 유지.
    private func purgeStagedOriginals() {
        var failed = 0
        for entry in purgeableStaged where !models.deleteStaged(fileName: entry.fileName) {
            failed += 1
        }
        models.scanStaging()
        models.invalidateListCache()
        if failed > 0 {
            notice = L(L10n.ModelManager.purgeFailed, failed)
        } else {
            notice = nil
        }
        DebugLogger.shared.info(feature: "모델관리", "원본 삭제 \(purgeableStaged.count)건 (실패 \(failed)건)")
    }

    /// 친화적 표시명 (T-321): `.litertlm` 숨김 + 별칭 우선.
    /// Sections 확장에서 접근하므로 internal.
    func friendlyFileName(_ fileName: String) -> String {
        let stem = ModelDownload.fileStem(fileName)
        if let localID = mapping[fileName]?.localID, !localID.isEmpty {
            return ModelAlias.display(id: localID)
        }
        let pretty = ModelAlias.pretty(id: stem)
        return pretty == stem ? stem : pretty
    }

    // MARK: - 상·하단

    /// 로컬 파일 선택 (T-254): NSOpenPanel → 스테이징 복사.
    private func pickLocalFile() {
        let panel = NSOpenPanel()
        panel.message = L(L10n.ModelManager.importPanelMessage)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let ok = await models.importLocalFile(sourceURL: url)
            if !ok { notice = L(L10n.ModelManager.importFailed) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                guard checkPermission() else { return }
                showImport = true
            } label: {
                Label(L(L10n.ModelManager.importNew), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(DSColor.primary)
            .help(L(L10n.ModelManager.importNewHelp))
            Button {
                guard checkPermission() else { return }
                pickLocalFile()
            } label: {
                Label(L(L10n.ModelManager.installFromFile), systemImage: "folder")
            }
            .help(L(L10n.ModelManager.installFromFileHelp))
            Spacer()
            Button(L(L10n.ModelManager.openFolder)) { models.revealStaging() }
                .help(L(L10n.ModelManager.openFolderHelp))
            Button(L(L10n.ModelManager.refresh)) { Task { await models.refresh() } }
                .help(L(L10n.ModelManager.refreshHelp))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let notice {
                Text(notice).font(DS.captionFont).foregroundStyle(.red)
            }
            Text(L(L10n.ModelManager.stagingNote))
                .font(DS.captionFont).foregroundStyle(.secondary)
        }
    }

    // MARK: - 행 (본체는 ModelManagerSections.swift)

    // MARK: - 액션

    /// 가져오기·설치 공통 권한 게이트 (T-228 확장): off 차단, ask는 호출 측 확인.
    private func checkPermission() -> Bool {
        let perm = GlobalPermission.current()
        guard perm != .off else {
            notice = L(L10n.ModelManager.permissionImportOff)
            DebugLogger.shared.error(code: "E-MAC-PERM-0011", feature: "권한", "가져오기 차단 (권한 꺼짐)")
            return false
        }
        return true
    }

    // Sections 확장에서 접근하므로 internal (T-247).
    func confirmIfAsk(title: String, message: String) -> Bool {
        guard GlobalPermission.needsConfirm(GlobalPermission.current()) else { return true }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L(L10n.ModelManager.continueButton))
        alert.addButton(withTitle: L(L10n.ModelManager.cancel))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
