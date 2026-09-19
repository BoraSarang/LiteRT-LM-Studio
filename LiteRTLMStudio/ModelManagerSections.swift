import AppKit
import SwiftUI

// MARK: - 모델 관리 창 섹션 (T-232 분리: 파일 길이 분산)

extension ModelManagerView {
    /// 관리 창 탭 (T-240): 사이드바식 전폭 버튼 (segmented 고정폭 금지).
    var managerTabs: some View {
        HStack(spacing: 0) {
            managerTab(title: L(L10n.ModelManager.browseTab), selected: browseSelected) { browseSelected = true }
            managerTab(title: L(L10n.ModelManager.myModelsTab), selected: !browseSelected) { browseSelected = false }
        }
    }

    func managerTab(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8).fill(DSColor.primary.opacity(0.15))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func installDialog(entry: StagedEntry) {
        let perm = GlobalPermission.current()
        guard perm != .off else {
            notice = L(L10n.ModelManager.permissionInstallOff)
            DebugLogger.shared.error(code: "E-MAC-PERM-0011", feature: "권한", "설치 차단 (권한 꺼짐)")
            return
        }
        let alert = NSAlert()
        alert.messageText = L(L10n.ModelManager.installTitle)
        alert.informativeText = "\(entry.fileName) (\(ModelDownload.formatBytes(entry.sizeBytes)))"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = mapping[entry.fileName]?.localID
            ?? (entry.fileName as NSString).deletingPathExtension
        field.placeholderString = L(L10n.ModelManager.installIDPlaceholder)
        alert.accessoryView = field
        alert.addButton(withTitle: L(L10n.ModelManager.installButton))
        alert.addButton(withTitle: L(L10n.ModelManager.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard confirmIfAsk(title: L(L10n.ModelManager.installConfirmTitle),
                           message: "\(entry.fileName) → \(field.stringValue)") else { return }
        Task {
            let ok = await models.importFile(fileName: entry.fileName, as: field.stringValue,
                                             repo: mapping[entry.fileName]?.repo)
            if !ok { notice = L(L10n.ModelManager.installFailed) }
        }
    }

    func renameDialog(id: String) {
        let alert = NSAlert()
        alert.messageText = L(L10n.ModelManager.renameTitle)
        alert.informativeText = L(L10n.ModelManager.renameInfo)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = id
        alert.accessoryView = field
        alert.addButton(withTitle: L(L10n.ModelManager.renameButton))
        alert.addButton(withTitle: L(L10n.ModelManager.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            let ok = await models.renameModel(old: id, new: field.stringValue)
            if !ok { notice = L(L10n.ModelManager.renameFailed) }
        }
    }

    func deleteInstalled(id: String) async {
        let perm = GlobalPermission.current()
        guard perm != .off else {
            notice = L(L10n.ModelManager.permissionDeleteOff)
            DebugLogger.shared.error(code: "E-MAC-PERM-0011", feature: "권한", "삭제 차단 (권한 꺼짐)")
            return
        }
        let stagedFile = ModelStore.stagedFileForModel(id: id, mapping: models.loadMapping(),
                                                       staged: models.staged)
        let alert = NSAlert()
        alert.messageText = L(L10n.ModelManager.deleteModelTitle)
        alert.informativeText = L(L10n.ModelManager.deleteModelInfo, id)
            + (stagedFile == nil ? "" : L(L10n.ModelManager.deleteModelKeepFile))
        let check = NSButton(checkboxWithTitle: L(L10n.ModelManager.deleteReceivedToo), target: nil, action: nil)
        check.state = .off
        check.isEnabled = stagedFile != nil
        alert.accessoryView = check
        alert.addButton(withTitle: L(L10n.ModelManager.deleteButton))
        alert.addButton(withTitle: L(L10n.ModelManager.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // ask면 위 단발 확인이 확인을 겸한다.
        DebugLogger.shared.info(feature: "권한", "삭제 확인됨: \(id)")
        _ = await models.delete(id: id)
        if check.state == .on, let file = stagedFile {
            _ = models.deleteStaged(fileName: file)
        }
        models.invalidateListCache()
    }

    func deleteStagedDialog(entry: StagedEntry) {
        let map = models.loadMapping()
        let installedID = map[entry.fileName]?.localID
            ?? (models.models.map(\.id).contains((entry.fileName as NSString).deletingPathExtension)
                ? (entry.fileName as NSString).deletingPathExtension : nil)
        let alert = NSAlert()
        alert.messageText = L(L10n.ModelManager.deleteFileTitle)
        alert.informativeText = entry.fileName
            + (installedID == nil ? L(L10n.ModelManager.deleteFileIrreversible)
                : L(L10n.ModelManager.deleteFileKeepsInstalled, installedID!))
        alert.addButton(withTitle: L(L10n.ModelManager.deleteButton))
        alert.addButton(withTitle: L(L10n.ModelManager.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !models.deleteStaged(fileName: entry.fileName) {
            notice = L(L10n.ModelManager.deleteFileFailed)
        }
    }
}

// MARK: - 내 모델 행 (T-321: 파일 길이 분산, ModelManagerView 경량화)

extension ModelManagerView {
    func installedRow(_ m: ModelStore.Model) -> some View {
        HStack(spacing: 8) {
            DSBadge(text: L(L10n.ModelManager.badgeInstalled), kind: .success)
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelAlias.display(id: m.id)).font(.system(size: 13, weight: .medium))
                Text(L(L10n.ModelManager.rowSummary, m.id, m.listedSize, m.realSize))
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Menu {
                Button(L(L10n.ModelManager.selectForChat)) {
                    NotificationCenter.default.post(name: .selectChatModel, object: m.id)
                }
                Button(L(L10n.ModelManager.renameDisplayName)) {
                    NotificationCenter.default.post(name: .requestAlias, object: m.id)
                }
                Button(L(L10n.ModelManager.renameRealID)) { renameDialog(id: m.id) }
                Button(L(L10n.ModelManager.runBenchmark)) {
                    NotificationCenter.default.post(name: .runBenchmarkModel, object: m.id)
                }
                Divider()
                Button(L(L10n.ModelManager.deleteModelMenu), role: .destructive) {
                    Task { await deleteInstalled(id: m.id) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 20).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(L(L10n.ModelManager.modelMenu))
        }
        .padding(.vertical, 2)
        .background {
            if highlightModelID == m.id {
                RoundedRectangle(cornerRadius: 8).fill(DSColor.primary.opacity(0.15))
            }
        }
    }

    func stagedRow(_ s: StagedEntry) -> some View {
        let state = ModelStore.stageState(fileName: s.fileName,
                                          installedIDs: installedIDs, mapping: mapping)
        return HStack(spacing: 8) {
            DSBadge(text: state == .downloadedUninstalled
                    ? L(L10n.ModelManager.badgeNotInstalled) : L(L10n.ModelManager.badgeInstalled),
                    kind: state == .downloadedUninstalled ? .warning : .success)
            VStack(alignment: .leading, spacing: 2) {
                Text(friendlyFileName(s.fileName)).font(.system(size: 13, weight: .medium))
                Text("\(ModelDownload.formatBytes(s.sizeBytes)) · \(state.title)")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.tail)
            .help(s.fileName)
            Spacer(minLength: 4)
            if state == .downloadedUninstalled {
                Button(L(L10n.ModelManager.installButton)) { installDialog(entry: s) }
                    .buttonStyle(.borderedProminent)
                    .tint(DSColor.primary)
                    .controlSize(.small)
                    .help(L(L10n.ModelManager.installRegistryHelp))
            }
            Menu {
                if state == .downloadedUninstalled {
                    Button(L(L10n.ModelManager.installButton)) { installDialog(entry: s) }
                }
                Button(L(L10n.ModelManager.deleteFileAction), role: .destructive) { deleteStagedDialog(entry: s) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 20).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(L(L10n.ModelManager.stagedMenu))
        }
        .padding(.vertical, 2)
    }
}

/// 미완성 1행 (T-249/T-251/T-252): repo 알면 이어받기, 모르면 다시 받기+삭제.
extension ModelManagerView {
    func orphanRow(_ part: OrphanPart) -> some View {
        let entry = models.loadMapping()[part.fileName]
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(DSColor.warning)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelDownload.fileStem(part.fileName)).font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                    .help(part.fileName)
                Text(L(L10n.ModelManager.incomplete, ModelDownload.formatBytes(part.sizeBytes)))
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            orphanActions(part, entry: entry)
            Button(L(L10n.ModelManager.deleteButton)) {
                let alert = NSAlert()
                alert.messageText = L(L10n.ModelManager.incompleteDeleteTitle)
                alert.informativeText = part.fileName
                alert.addButton(withTitle: L(L10n.ModelManager.deleteButton))
                alert.addButton(withTitle: L(L10n.ModelManager.cancel))
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                center.deleteOrphan(part.fileName)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    /// 고아 액션 분기 (T-252 분리: 함수 길이 분산).
    @ViewBuilder
    func orphanActions(_ part: OrphanPart, entry: FileMapping?) -> some View {
        if let repo = entry?.repo,
           let url = ModelDownload.fileURL(repo: repo, file: part.fileName) {
            Button(L(L10n.ModelManager.resume)) {
                let localID = entry?.localID
                    ?? (part.fileName as NSString).deletingPathExtension
                let downloader = ModelDownloader()
                downloader.stageForResume(
                    url: url,
                    partURL: models.stagingURL.appendingPathComponent(
                        ModelDownload.partName(for: part.fileName)),
                    finalURL: models.stagingURL.appendingPathComponent(part.fileName),
                    received: part.sizeBytes)
                center.add(DownloadItem(repo: repo, fileName: part.fileName,
                                        localID: localID, downloader: downloader))
                center.orphans.removeAll { $0.fileName == part.fileName }
                DebugLogger.shared.info(feature: "모델가져오기",
                                        "고아 이어받기: \(part.fileName)")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(DSColor.primary)
            .help(L(L10n.ModelManager.resumeHelp))
        } else {
            Button(L(L10n.ModelManager.redownload)) {
                catalog.query = ModelCatalog.searchStem(fileName: part.fileName)
                browseSelected = true
                notice = L(L10n.ModelManager.redownloadNotice)
                Task { await catalog.search() }
            }
            .controlSize(.small)
            .help(L(L10n.ModelManager.redownloadHelp))
        }
    }
}
