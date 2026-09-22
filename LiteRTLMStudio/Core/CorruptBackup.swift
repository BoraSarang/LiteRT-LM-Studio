import Foundation

/// 손상 JSON 격리 (T-372): 디코드 실패 시 원본을 `.corrupt-시각`으로 옮겨
/// 다음 save()가 덮어쓰기 전에 복구 가능성을 남긴다. 파일 없으면 no-op.
enum CorruptBackup {
    /// 디코드 조회: 성공 시 값, 파일 없음·손상 시 nil (손상분은 격리).
    nonisolated static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            quarantine(url)
            return nil
        }
        return value
    }

    /// 격리 실행 (순수 이동, 테스트 가능): 성공 시 격리 경로 반환.
    @discardableResult
    nonisolated static func quarantine(_ url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dst = url.appendingPathExtension("corrupt-\(stamp)")
        guard (try? FileManager.default.moveItem(at: url, to: dst)) != nil else { return nil }
        return dst
    }
}
