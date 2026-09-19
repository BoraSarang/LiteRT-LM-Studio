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
            Text("새 모델 가져오기").font(.system(size: 13, weight: .semibold))
            modelSection
            fileSection
            storeSection
            progressSection
            HStack {
                Spacer()
                if locked {
                    Button("새로 받기") {
                        activeItem = nil
                        locked = false
                    }
                    .disabled(activeItem?.downloader.isDownloading == true)
                    Button("닫기") { dismiss() }
                } else {
                    Button("닫기") { dismiss() }
                    Button("다운로드 시작") { startDownload() }
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
            Text("1 · 모델").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Picker("", selection: $usePreset) {
                Text("추천 목록").tag(true)
                Text("직접 입력").tag(false)
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
                TextField("저장소 (org/repo)", text: $repo)
                    .textFieldStyle(.roundedBorder)
                    .disabled(locked)
            }
        }
    }

    // MARK: - 2 · 파일

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("2 · 파일").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                if fetching {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                }
                Spacer()
                Button("저장소 페이지") {
                    if let url = ModelDownload.repoPageURL(repo: effectiveRepo) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link).font(DS.captionFont)
                .help("파일명을 Files 탭에서 확인")
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
                .help(siblings.indices.contains(fileIndex) ? siblings[fileIndex] : "파일 선택")
            } else {
                TextField("파일명 (예: gemma-4-E2B-it.litertlm)", text: $customFile)
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
            Text("3 · 저장").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            TextField("로컬 모델 ID (예: gemma4-e2b)", text: $localID)
                .textFieldStyle(.roundedBorder)
                .disabled(locked)
            SecureField("Hugging Face 토큰 (비공개 저장소만)", text: $token)
                .textFieldStyle(.roundedBorder)
                .disabled(locked)
            if duplicateActive {
                Text("같은 파일을 이미 받는 중입니다.")
                    .font(DS.captionFont).foregroundStyle(DSColor.warning)
            }
        }
    }

    // MARK: - 4 · 진행

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("4 · 진행").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if let item = activeItem {
                DownloadRow(item: item, center: center, models: models)
            } else {
                Text("대기 중 — 다운로드 시작을 누르면 여기에 표시됩니다.")
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
            fetchError = "저장소 주소가 올바르지 않습니다."
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
                fetchError = "`.litertlm` 없음 — 저장소·토큰 확인 또는 파일명 직접 입력."
            }
        } catch {
            fetchError = "목록 조회 실패: \(error.localizedDescription)"
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
