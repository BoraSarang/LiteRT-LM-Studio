import Foundation

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

    private let logger = DebugLogger.shared
    private let uv = UvManager()

    var registryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".litert-lm/models")
    }

    func refresh() async {
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
        await refresh()
        return code == 0
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
}
