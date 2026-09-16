import AppKit
import Foundation

/// 스테이징된 다운로드 파일 1건 (T-232): 완료 후에도 `~/Documents/.LiteRT-LM`에 유지.
struct StagedEntry: Identifiable, Hashable, Sendable {
    var id: String { fileName }
    let fileName: String
    var sizeBytes: Int64 = 0
}

/// 파일 매핑 1건 (T-252): 로컬ID + 출처 repo. 구 형식(문자열)도 읽힘.
struct FileMapping: Codable, Sendable, Equatable, Hashable {
    var localID: String
    var repo: String?

    init(localID: String, repo: String? = nil) {
        self.localID = localID
        self.repo = repo
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if let id = try? box.decode(String.self) {
            self.localID = id
            self.repo = nil
        } else {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            self.localID = try keyed.decode(String.self, forKey: .localID)
            self.repo = try keyed.decodeIfPresent(String.self, forKey: .repo)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case localID
        case repo
    }
}

/// 관리 창 행 상태 (T-232): 설치됨 / 다운로드 완료·미설치.
enum StageState: Equatable, Sendable {
    case installed(localID: String)
    case downloadedUninstalled

    var title: String {
        switch self {
        case .installed: return "설치됨"
        case .downloadedUninstalled: return "다운로드 완료·미설치"
        }
    }
}

/// 로컬 모델 레지스트리 (~/.litert-lm/models). list 표기 용량 + du 실제 점유 병기.
@MainActor
final class ModelStore: ObservableObject {
    struct Model: Identifiable, Hashable, Sendable {
        let id: String
        let listedSize: String
        let modified: String
        var realSize: String = "-"
        var functionCall = false
        var thinking = false
        var speculative = false
        var modalities: String = "-"
    }

    @Published var models: [Model] = []
    @Published var lastError: String?

    /// 목록 캐시 (T-232): `list` 서브프로세스 호출 감소. 강제 새로고침·변경 시 무효화.
    @Published var staged: [StagedEntry] = []
    private var listCachedAt: Date?
    static let listCacheTTL: TimeInterval = 60

    let logger = DebugLogger.shared // Staging 확장에서 사용하므로 internal.
    private let uv = UvManager()

    var registryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".litert-lm/models")
    }

    func refresh() async {
        await refresh(force: true)
    }

    /// 강제 새로고침. 성공 시 캐시 시각 갱신 + `[CACHE]` 적중 로그는 `refreshCached` 담당.
    func refresh(force: Bool) async {
        if !force, Self.isCacheValid(since: listCachedAt) {
            logger.info(feature: "모델목록", "[CACHE] 목록 캐시 적중 (\(models.count)개)")
            return
        }
        await refreshList()
    }

    /// 캐시 우선 새로고침 (관리 창 열기용).
    func refreshCached() async {
        await refresh(force: false)
    }

    /// 캐시 무효화 (가져오기·설치·삭제·이름변경 완료 시).
    func invalidateListCache() {
        listCachedAt = nil
    }

    /// 캐시 유효 판정 (순수, 테스트 가능).
    nonisolated static func isCacheValid(since cachedAt: Date?, now: Date = Date()) -> Bool {
        guard let cachedAt else { return false }
        return now.timeIntervalSince(cachedAt) < listCacheTTL
    }

    private func refreshList() async {
        logger.info(feature: "모델목록", "litert-lm list 조회 시작")
        let (out, code) = await uv.run(UvManager.litertBin, args: ["list"])
        guard code == 0 else {
            lastError = "E-MAC-STOR-0003"
            logger.error(code: "E-MAC-STOR-0003", feature: "모델목록", "list 실패")
            return
        }
        var parsed = Self.parseList(out)
        // du 실제 용량 + describe capability 병렬 병합 (T-127): 순서 보존.
        let registryPath = registryURL.path
        parsed = await withTaskGroup(of: (Int, Model).self, returning: [Model].self) { group in
            for (idx, item) in parsed.enumerated() {
                group.addTask {
                    var m = item
                    m.realSize = await Self.realSize(of: m.id, registryPath: registryPath)
                    await Self.fillCapabilities(&m)
                    return (idx, m)
                }
            }
            var out = parsed
            for await (idx, m) in group { out[idx] = m }
            return out
        }
        models = parsed
        listCachedAt = Date()
        scanStaging()
        logger.info(feature: "모델목록", "\(parsed.count)개 모델 확인")
    }

    /// `litert-lm list` 출력 파싱. 안내 줄·헤더 행·빈 줄은 모델이 아니다.
    nonisolated static func parseList(_ out: String) -> [Model] {
        var parsed: [Model] = []
        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("Listing models in:"),
                  trimmed != "ID              SIZE            MODIFIED",
                  !trimmed.hasPrefix("ID ")
            else { continue }
            let cols = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 2, cols[0] != "ID" else { continue }
            // ID는 첫 컬럼, SIZE는 숫자+단위 2컬럼일 수 있어 뒤에서부터 처리
            let id = cols[0]
            let modified = cols.suffix(2).joined(separator: " ")
            let size = cols.dropFirst().dropLast(2).joined(separator: " ")
            parsed.append(Model(id: id, listedSize: size, modified: modified))
        }
        return parsed
    }

    private nonisolated static func realSize(of id: String, registryPath: String) async -> String {
        let target = (registryPath as NSString).appendingPathComponent(id)
        let (out, code) = await UvManager.runProcess("/usr/bin/du", args: ["-sh", target])
        guard code == 0 else { return "-" }
        return out.split(separator: "\t").first.map(String.init) ?? "-"
    }

    private nonisolated static func fillCapabilities(_ model: inout Model) async {
        let (out, code) = await UvManager.runProcess(UvManager.litertBin, args: ["describe", model.id])
        guard code == 0 else { return }
        for line in out.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Supports Function Call:") { model.functionCall = t.hasSuffix("YES") }
            if t.hasPrefix("Supports Thinking:") { model.thinking = t.hasSuffix("YES") }
            if t.hasPrefix("Speculative Decoding:") { model.speculative = t.hasSuffix("YES") }
            if t.hasPrefix("Input Modalities:") {
                let mods = t.replacingOccurrences(of: "Input Modalities:", with: "")
                model.modalities = mods.trimmingCharacters(in: .whitespaces)
            }
        }
    }

    func delete(id: String) async -> Bool {
        logger.info(feature: "모델삭제", "\(id) 삭제 시작")
        let (out, code) = await uv.run(UvManager.litertBin, args: ["delete", id])
        logger.info(feature: "모델삭제", out.prefix(300).description)
        if code == 0 {
            var map = loadMapping()
            map = Self.purgeMapping(map, installedIDs: Set(models.map(\.id)).subtracting([id]))
            saveMapping(map)
        }
        await refresh()
        return code == 0
    }

    /// 모델의 스테이징 파일 찾기 (순수, T-250): 매핑 우선, 파일 stem 폴백.
    nonisolated static func stagedFileForModel(id: String, mapping: [String: FileMapping],
                                               staged: [StagedEntry]) -> String? {
        if let file = mapping.first(where: { $0.value.localID == id })?.key,
           staged.contains(where: { $0.fileName == file }) { return file }
        return staged.first {
            ($0.fileName as NSString).deletingPathExtension == id
        }?.fileName
    }

    /// T-229 입력창 피커 정렬 (순수): Gemma → Qwen → 나머지(가나다). 설치 목록은 그대로.
    nonisolated static func preferredOrder(_ models: [Model]) -> [Model] {
        models.sorted { a, b in
            let ra = Self.familyRank(a.id)
            let rb = Self.familyRank(b.id)
            if ra != rb { return ra < rb }
            return a.id.localizedCompare(b.id) == .orderedAscending
        }
    }

    nonisolated private static func familyRank(_ id: String) -> Int {
        let lower = id.lowercased()
        if lower.contains("gemma") { return 0 }
        if lower.contains("qwen") { return 1 }
        return 2
    }

    /// T-216: 이미 있으면 네트워크 조회 생략 (벤치마크 창 진입용).
    func refreshIfEmpty() async {
        if models.isEmpty { await refresh() }
    }

    /// 로컬 파일 설치 (T-254): 스테이징에 복사 후 미설치로 표시. 원본 유지.
    func importLocalFile(sourceURL: URL) async -> Bool {
        guard Self.isInstallableFile(name: sourceURL.lastPathComponent) else {
            lastError = "E-MAC-STOR-0006"
            logger.error(code: "E-MAC-STOR-0006", feature: "모델가져오기",
                         "지원하지 않는 파일: \(sourceURL.lastPathComponent)")
            return false
        }
        guard ensureStaging() else { return false }
        let dest = stagingURL.appendingPathComponent(sourceURL.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            lastError = "E-MAC-STOR-0006"
            logger.error(code: "E-MAC-STOR-0006", feature: "모델가져오기",
                         "같은 이름 있음: \(dest.lastPathComponent)")
            return false
        }
        logger.info(feature: "모델가져오기", "파일 복사 시작: \(sourceURL.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            lastError = "E-MAC-STOR-0006"
            logger.error(code: "E-MAC-STOR-0006", feature: "모델가져오기",
                         "복사 실패: \(error.localizedDescription)")
            return false
        }
        scanStaging()
        invalidateListCache()
        logger.info(feature: "모델가져오기", "파일 복사 완료: \(dest.lastPathComponent)")
        return true
    }

    /// 설치 가능 판정 (순수, T-254).
    nonisolated static func isInstallableFile(name: String) -> Bool {
        name.hasSuffix(".litertlm") && !name.hasSuffix(".part") && !name.isEmpty
    }

    func importFile(fileName: String, as modelID: String, repo: String? = nil) async -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            lastError = "E-MAC-STOR-0006"
            return false
        }
        logger.info(feature: "모델가져오기", "\(fileName) 설치 시작 (ID: \(trimmed))")
        let path = stagingURL.appendingPathComponent(fileName).path
        let (out, code) = await uv.run(UvManager.litertBin, args: ["import", path, trimmed],
                                       timeout: 600)
        logger.info(feature: "모델가져오기", out.prefix(300).description)
        guard code == 0 else {
            lastError = "E-MAC-STOR-0006"
            logger.error(code: "E-MAC-STOR-0006", feature: "모델가져오기", "\(fileName) 설치 실패")
            return false
        }
        var map = loadMapping()
        map[fileName] = FileMapping(localID: trimmed, repo: repo ?? map[fileName]?.repo)
        saveMapping(map)
        invalidateListCache()
        await refresh()
        logger.info(feature: "모델가져오기", "\(trimmed) 설치됨")
        return true
    }

    /// 실제 ID 변경 (`litert-lm rename OLD NEW`, 별칭과 별개).
    func renameModel(old: String, new: String) async -> Bool {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != old else { return false }
        logger.info(feature: "모델관리", "이름 변경: \(old) → \(trimmed)")
        let (out, code) = await uv.run(UvManager.litertBin, args: ["rename", old, trimmed])
        logger.info(feature: "모델관리", out.prefix(300).description)
        guard code == 0 else {
            lastError = "E-MAC-STOR-0012"
            logger.error(code: "E-MAC-STOR-0012", feature: "모델관리", "이름 변경 실패: \(old)")
            return false
        }
        var map = loadMapping()
        for (file, entry) in map where entry.localID == old {
            map[file] = FileMapping(localID: trimmed, repo: entry.repo)
        }
        saveMapping(map)
        invalidateListCache()
        await refresh()
        return true
    }

    /// 스테이징 파일 삭제 (되돌릴 수 없어 호출 측 확인 필수).
    func deleteStaged(fileName: String) -> Bool {
        let url = stagingURL.appendingPathComponent(fileName)
        do {
            try FileManager.default.removeItem(at: url)
            var map = loadMapping()
            map.removeValue(forKey: fileName)
            saveMapping(map)
            scanStaging()
            logger.info(feature: "모델관리", "스테이징 삭제: \(fileName)")
            return true
        } catch {
            logger.error(code: "E-MAC-STOR-0009", feature: "모델관리",
                         "스테이징 삭제 실패: \(error.localizedDescription)")
            return false
        }
    }

    /// 폴더 열기 (숨김 폴더라 Finder 직접 이동).
    func revealStaging() {
        _ = ensureStaging()
        NSWorkspace.shared.open(stagingURL)
    }
}
