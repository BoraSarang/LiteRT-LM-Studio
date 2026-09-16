import Foundation

/// 온보딩 게이트 판정 (T-257, PLAN_v53): 버전 파싱·최소버전 비교.
enum OnboardingGate {
    /// 최소 요구 버전 (import --from-huggingface-repo 지원 전제).
    static let minimumLitertVersion = "0.14.0"

    /// 버전 문자열에서 `x.y.z` 추출 (순수).
    nonisolated static func parseVersion(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\.(\d+)\.(\d+)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 4,
              let range = Range(match.range(at: 0), in: text) else { return nil }
        return String(text[range])
    }

    /// 최소버전 충족 판정 (순수, 숫자 구간 비교).
    nonisolated static func meetsMinimum(_ version: String?, minimum: String = minimumLitertVersion) -> Bool {
        guard let version, let lhs = parseVersion(version), let rhs = parseVersion(minimum) else {
            return false
        }
        let lparts = lhs.split(separator: ".").compactMap { Int($0) }
        let rparts = rhs.split(separator: ".").compactMap { Int($0) }
        guard lparts.count == 3, rparts.count == 3 else { return false }
        for (left, right) in zip(lparts, rparts) where left != right {
            return left > right
        }
        return true
    }
}
