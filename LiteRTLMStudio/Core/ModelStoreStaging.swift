import AppKit
import Foundation

// MARK: - 스테이징·매핑 (T-232 분리: 파일 길이 분산)

extension ModelStore {
    /// stale 매핑 제거 (순수, T-250): 설치되지 않은 ID를 가리키는 항목 제거.
    nonisolated static func purgeMapping(_ map: [String: FileMapping],
                                         installedIDs: Set<String>) -> [String: FileMapping] {
        map.filter { installedIDs.contains($0.value.localID) }
    }

    // MARK: - 스테이징 (T-232, PLAN_v47)

    /// 스테이징 폴더: 숨김·유지 (`~/.litert-lm-studio/staging`, T-314). 완료 후에도 삭제 안 함.
    var stagingURL: URL { StudioPaths.stagingURL }

    var mappingURL: URL { stagingURL.appendingPathComponent(".mapping.json") }

    /// 스테이징 폴더 생성 (다운로드·스캔 전). 실패해도 목록은 동작.
    @discardableResult
    func ensureStaging() -> Bool {
        do {
            try FileManager.default.createDirectory(at: stagingURL,
                                                    withIntermediateDirectories: true)
            logger.info(feature: "모델관리", "스테이징 폴더 준비: \(stagingURL.path)")
            return true
        } catch {
            logger.error(code: "E-MAC-STOR-0009", feature: "모델관리",
                         "스테이징 폴더 생성 실패: \(error.localizedDescription)")
            return false
        }
    }

    /// 스테이징 스캔 → `staged` 갱신 (`.part` 제외, 최종 파일만).
    func scanStaging() {
        staged = Self.scanStaging(at: stagingURL)
    }

    /// 스테이징 용량 합 (순수, T-234 푸터용).
    nonisolated static func totalBytes(_ staged: [StagedEntry]) -> Int64 {
        staged.reduce(0) { $0 + $1.sizeBytes }
    }

    /// 스테이징 스캔 (순수 입력, 테스트 가능).
    nonisolated static func scanStaging(at dir: URL) -> [StagedEntry] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return [] }
        return items
            .filter { $0.pathExtension == "litertlm" }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return StagedEntry(fileName: url.lastPathComponent, sizeBytes: Int64(size))
            }
            .sorted { $0.fileName.localizedCompare($1.fileName) == .orderedAscending }
    }

    /// 파일명 → 매핑 읽기/쓰기 (설치·이름변경 추적용, T-252 repo 포함).
    /// 구 형식(문자열=로컬ID)도 읽힘.
    func loadMapping() -> [String: FileMapping] {
        guard let data = try? Data(contentsOf: mappingURL),
              let map = try? JSONDecoder().decode([String: FileMapping].self, from: data) else {
            return [:]
        }
        return map
    }

    func saveMapping(_ map: [String: FileMapping]) {
        guard ensureStaging() else { return }
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: mappingURL, options: .atomic)
        }
    }

    /// 행 상태 판정 (순수, 테스트 가능).
    /// installed > downloadedUninstalled 순. `.part`는 스캔에서 제외라 미완성은 별도 표시.
    nonisolated static func stageState(fileName: String, installedIDs: Set<String>,
                                       mapping: [String: FileMapping]) -> StageState {
        if let localID = mapping[fileName]?.localID, installedIDs.contains(localID) {
            return .installed(localID: localID)
        }
        // 매핑이 없어도 파일명 stem이 설치 ID와 같으면 설치됨으로 본다.
        let stem = (fileName as NSString).deletingPathExtension
        if installedIDs.contains(stem) { return .installed(localID: stem) }
        return .downloadedUninstalled
    }

    /// 스테이징 파일을 레지스트리에 설치 (`litert-lm import <파일> [ID]`).
}
