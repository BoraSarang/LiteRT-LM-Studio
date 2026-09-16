import AppKit
import SwiftUI

// MARK: - 모델 관리 창 섹션 (T-232 분리: 파일 길이 분산)

extension ModelManagerView {
    /// 관리 창 탭 (T-240): 사이드바식 전폭 버튼 (segmented 고정폭 금지).
    var managerTabs: some View {
        HStack(spacing: 0) {
            managerTab(title: "찾아보기", selected: browseSelected) { browseSelected = true }
            managerTab(title: "내 모델", selected: !browseSelected) { browseSelected = false }
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
                        RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func installDialog(entry: StagedEntry) {
        let perm = GlobalPermission.current()
        guard perm != .off else {
            notice = "권한이 꺼져 있어 설치할 수 없습니다. 설정에서 권한을 바꿔 주세요."
            DebugLogger.shared.error(code: "E-MAC-PERM-0011", feature: "권한", "설치 차단 (권한 꺼짐)")
            return
        }
        let alert = NSAlert()
        alert.messageText = "이 파일을 설치할까요?"
        alert.informativeText = "\(entry.fileName) (\(ModelDownload.formatBytes(entry.sizeBytes)))"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = mapping[entry.fileName]?.localID
            ?? (entry.fileName as NSString).deletingPathExtension
        field.placeholderString = "로컬 모델 ID (예: gemma4-e2b)"
        alert.accessoryView = field
        alert.addButton(withTitle: "설치")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard confirmIfAsk(title: "설치 확인", message: "\(entry.fileName) → \(field.stringValue)") else { return }
        Task {
            let ok = await models.importFile(fileName: entry.fileName, as: field.stringValue,
                                             repo: mapping[entry.fileName]?.repo)
            if !ok { notice = "설치가 실패했습니다. 로그를 확인해 주세요." }
        }
    }

    func renameDialog(id: String) {
        let alert = NSAlert()
        alert.messageText = "실제 ID 변경"
        alert.informativeText = "표시 이름이 아니라 레지스트리 ID가 바뀝니다. (별칭은 그대로)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = id
        alert.accessoryView = field
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            let ok = await models.renameModel(old: id, new: field.stringValue)
            if !ok { notice = "이름 변경이 실패했습니다. (중복 ID 가능)" }
        }
    }

    func deleteInstalled(id: String) async {
        let perm = GlobalPermission.current()
        guard perm != .off else {
            notice = "권한이 꺼져 있어 삭제할 수 없습니다. 설정에서 권한을 바꿔 주세요."
            DebugLogger.shared.error(code: "E-MAC-PERM-0011", feature: "권한", "삭제 차단 (권한 꺼짐)")
            return
        }
        let stagedFile = ModelStore.stagedFileForModel(id: id, mapping: models.loadMapping(),
                                                       staged: models.staged)
        let alert = NSAlert()
        alert.messageText = "모델 삭제"
        alert.informativeText = "\(id)\n레지스트리에서 제거합니다."
            + (stagedFile == nil ? "" : "\n받은 파일은 유지되어 다시 설치할 수 있습니다.")
        let check = NSButton(checkboxWithTitle: "받은 파일도 함께 삭제", target: nil, action: nil)
        check.state = .off
        check.isEnabled = stagedFile != nil
        alert.accessoryView = check
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
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
        alert.messageText = "파일 삭제"
        alert.informativeText = entry.fileName
            + (installedID == nil ? "\n되돌릴 수 없습니다."
                : "\n설치된 모델(\(installedID!))은 유지됩니다.")
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !models.deleteStaged(fileName: entry.fileName) {
            notice = "파일 삭제가 실패했습니다."
        }
    }
}

/// 미완성 1행 (T-249/T-251/T-252): repo 알면 이어받기, 모르면 다시 받기+삭제.
extension ModelManagerView {
    func orphanRow(_ part: OrphanPart) -> some View {
        let entry = models.loadMapping()[part.fileName]
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(part.fileName).font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Text("미완성 · \(ModelDownload.formatBytes(part.sizeBytes))")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            orphanActions(part, entry: entry)
            Button("삭제") {
                let alert = NSAlert()
                alert.messageText = "미완성 파일을 지울까요?"
                alert.informativeText = part.fileName
                alert.addButton(withTitle: "삭제")
                alert.addButton(withTitle: "취소")
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
            Button("이어받기") {
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
            .help("미완성 파일을 이어서 받기")
        } else {
            Button("다시 받기") {
                catalog.query = ModelCatalog.searchStem(fileName: part.fileName)
                browseSelected = true
                notice = "같은 파일을 새로 받으면 기존 미완성이 덮어씌워집니다."
                Task { await catalog.search() }
            }
            .controlSize(.small)
            .help("찾아보기에서 다시 찾기")
        }
    }
}
