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
            let size = (try? FileManager.default.attributesOfItem(atPath: part.path)[.size]
                as? Int) ?? 0
            let downloader = ModelDownloader()
            downloader.stageForResume(
                url: ModelDownload.fileURL(repo: rec.repo, file: rec.file),
                partURL: part,
                finalURL: staging.appendingPathComponent(rec.file),
                received: Int64(size))
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
                let size = (try? FileManager.default.attributesOfItem(atPath: part.path)[.size]
                    as? Int) ?? 0
                return OrphanPart(fileName: name, sizeBytes: Int64(size))
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
    @State private var highlightModelID: String?
    @State private var highlightTask: Task<Void, Never>?

    /// 하이라이트 만료 판정 (순수, T-247).
    nonisolated static func shouldClearHighlight(setAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(setAt) >= 3
    }

    private var installedIDs: Set<String> { Set(models.models.map(\.id)) }
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
            if models.models.isEmpty, models.staged.isEmpty,
               center.items.isEmpty, center.orphans.isEmpty {
                ContentUnavailableView("모델이 없어요", systemImage: "archivebox",
                                       description: Text("새 모델 가져오기로 Hugging Face에서 받으세요."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !center.items.isEmpty {
                        Section("다운로드 중") {
                            ForEach(center.items) { item in
                                DownloadRow(item: item, center: center, models: models)
                            }
                        }
                    }
                    if !center.orphans.isEmpty {
                        Section("미완성") {
                            ForEach(center.orphans) { part in
                                orphanRow(part)
                            }
                        }
                    }
                    Section("설치됨 (\(models.models.count))") {
                        ForEach(models.models) { m in
                            installedRow(m)
                        }
                    }
                    Section("스테이징 (\(models.staged.count))") {
                        ForEach(models.staged) { s in
                            stagedRow(s)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            footer
        }
    }

    // MARK: - 상·하단

    /// 로컬 파일 선택 (T-254): NSOpenPanel → 스테이징 복사.
    private func pickLocalFile() {
        let panel = NSOpenPanel()
        panel.message = ".litertlm 모델 파일을 고르세요"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let ok = await models.importLocalFile(sourceURL: url)
            if !ok { notice = "파일 가져오기가 실패했습니다. 로그를 확인해 주세요." }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                guard checkPermission() else { return }
                showImport = true
            } label: {
                Label("새 모델 가져오기", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .help("Hugging Face 저장소에서 직접 다운로드")
            Button {
                guard checkPermission() else { return }
                pickLocalFile()
            } label: {
                Label("파일로 설치", systemImage: "folder")
            }
            .help("로컬 .litertlm 파일을 스테이징에 복사 (원본 유지)")
            Spacer()
            Button("폴더 열기") { models.revealStaging() }
                .help("스테이징 폴더 열기 (~/Documents/.LiteRT-LM, 숨김 폴더)")
            Button("새로고침") { Task { await models.refresh() } }
                .help("목록 강제 새로고침 (캐시 무시)")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let notice {
                Text(notice).font(DS.captionFont).foregroundStyle(.red)
            }
            Text("스테이징에 보관된 파일 + 설치된 모델이라 디스크를 2배 씁니다. 완료 후에도 스테이징 파일은 유지됩니다.")
                .font(DS.captionFont).foregroundStyle(.secondary)
        }
    }

    // MARK: - 행

    private func installedRow(_ m: ModelStore.Model) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color.green).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelAlias.display(id: m.id)).font(.system(size: 13, weight: .medium))
                Text("\(m.id) · \(m.listedSize) · 실점유 \(m.realSize)")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(StageState.installed(localID: m.id).title)
                .font(DS.captionFont).foregroundStyle(.secondary)
            Menu {
                Button("채팅 모델로 선택") {
                    NotificationCenter.default.post(name: .selectChatModel, object: m.id)
                }
                Button("표시 이름 바꾸기") {
                    NotificationCenter.default.post(name: .requestAlias, object: m.id)
                }
                Button("실제 ID 변경") { renameDialog(id: m.id) }
                Button("벤치마크 실행") {
                    NotificationCenter.default.post(name: .runBenchmarkModel, object: m.id)
                }
                Divider()
                Button("모델 삭제", role: .destructive) {
                    Task { await deleteInstalled(id: m.id) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 20).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("모델 메뉴")
        }
        .padding(.vertical, 2)
        .background {
            if highlightModelID == m.id {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
            }
        }
    }

    private func stagedRow(_ s: StagedEntry) -> some View {
        let state = ModelStore.stageState(fileName: s.fileName,
                                          installedIDs: installedIDs, mapping: mapping)
        return HStack(spacing: 8) {
            Circle().fill(state == .downloadedUninstalled ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.fileName).font(.system(size: 13, weight: .medium))
                Text("\(ModelDownload.formatBytes(s.sizeBytes)) · \(state.title)")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if state == .downloadedUninstalled {
                Button("설치") { installDialog(entry: s) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("레지스트리에 설치 (litert-lm import)")
            }
            Menu {
                if state == .downloadedUninstalled {
                    Button("설치") { installDialog(entry: s) }
                }
                Button("파일 삭제", role: .destructive) { deleteStagedDialog(entry: s) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 20).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("스테이징 메뉴")
        }
        .padding(.vertical, 2)
    }

    // MARK: - 액션

    /// 가져오기·설치 공통 권한 게이트 (T-228 확장): off 차단, ask는 호출 측 확인.
    private func checkPermission() -> Bool {
        let perm = GlobalPermission.current()
        guard perm != .off else {
            notice = "권한이 꺼져 있어 가져올 수 없습니다. 설정에서 권한을 바꿔 주세요."
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
        alert.addButton(withTitle: "계속")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
