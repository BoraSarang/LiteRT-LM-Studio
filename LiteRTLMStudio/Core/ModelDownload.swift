import Foundation

/// 모델 직접 다운로드 헬퍼+실행기 (T-232, PLAN_v47).
/// 흐름: HF `resolve` URL → 스테이징 `*.part` → 완료 시 `*.litertlm` 개명 (유지).
/// 최종 설치는 `ModelStore.importFile` (`litert-lm import <스테이징> [ID]`)이 담당.
/// 대표 프리셋 1건 (컬렉션 실측 저장소 ID, 파일명은 API 조회로 확정).
struct ModelPreset: Sendable, Hashable {
    let repo: String
    let label: String
    let suggestedID: String
}

enum ModelDownload {
    /// `repo` + `file` → 직접 다운로드 URL.
    nonisolated static func fileURL(repo: String, file: String) -> URL? {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")
    }

    /// 저장소 페이지 URL (파일명 확인용 외부 링크).
    nonisolated static func repoPageURL(repo: String) -> URL? {
        URL(string: "https://huggingface.co/\(repo)")
    }

    /// 저장소 파일 목록 URL (수동 다운로드용 외부 링크, T-243).
    nonisolated static func repoTreeURL(repo: String) -> URL? {
        URL(string: "https://huggingface.co/\(repo)/tree/main")
    }

    /// HF API 파일 목록 URL (파일명 선택용).
    nonisolated static func siblingsURL(repo: String) -> URL? {
        URL(string: "https://huggingface.co/api/models/\(repo)")
    }

    /// 최종 파일명 → 진행 중 임시명.
    nonisolated static func partName(for fileName: String) -> String { fileName + ".part" }

    /// 파일 stem (순수, T-253): 확장자 제외 실제 파일명.
    nonisolated static func fileStem(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// 임시명 → 최종명 (`.part` 접미사만 제거, 없으면 그대로).
    nonisolated static func finalName(part: String) -> String {
        part.hasSuffix(".part") ? String(part.dropLast(5)) : part
    }

    /// 0~1 진행률 (전체 미상 시 nil).
    nonisolated static func progress(received: Int64, total: Int64?) -> Double? {
        guard let total, total > 0, received >= 0 else { return nil }
        return min(1, Double(received) / Double(total))
    }

    /// 남은 시간(초) 추정. 진행률 0 이하면 nil.
    nonisolated static func etaSeconds(elapsed: TimeInterval, progress: Double?) -> TimeInterval? {
        guard let progress, progress > 0.001, elapsed > 0 else { return nil }
        return elapsed * (1 - progress) / progress
    }

    /// 바이트 표기 (B/KB/MB/GB).
    nonisolated static func formatBytes(_ bytes: Int64) -> String {
        let v = Double(max(0, bytes))
        switch v {
        case 0 ..< 1024: return "\(Int(v)) B"
        case 1024 ..< 1024 * 1024: return String(format: "%.0f KB", v / 1024)
        default:
            let mb = v / 1024 / 1024
            return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
        }
    }

    /// 초 → `mm:ss` 또는 `h:mm:ss`.
    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// 진행 행 1줄: `n% · 받은량/전체량 · 속도 · 경과 mm:ss · 남은 mm:ss` (T-244 속도).
    nonisolated static func statusLine(received: Int64, total: Int64?,
                                       elapsed: TimeInterval) -> String {
        let pct = progress(received: received, total: total).map { "\(Int($0 * 100))%" } ?? "진행 중"
        let size: String
        if let total { size = "\(formatBytes(received))/\(formatBytes(total))" } else {
            size = formatBytes(received)
        }
        var parts = [pct, size]
        if let speed = averageSpeed(received: received, elapsed: elapsed) {
            parts.append("\(formatBytes(speed))/s")
        }
        parts.append("경과 \(formatDuration(elapsed))")
        if let eta = etaSeconds(elapsed: elapsed, progress: progress(received: received, total: total)) {
            parts.append("남은 \(formatDuration(eta))")
        }
        return parts.joined(separator: " · ")
    }

    /// 평균 속도 (B/s, 순수, T-244): 1초 미만이면 nil.
    nonisolated static func averageSpeed(received: Int64, elapsed: TimeInterval) -> Int64? {
        guard elapsed >= 1, received > 0 else { return nil }
        return Int64(Double(received) / elapsed)
    }

    /// HF API 응답에서 `.litertlm` 형제 파일명만 추출 (파일 선택용).
    nonisolated static func litertlmSiblings(from apiJSON: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: apiJSON) as? [String: Any],
              let siblings = json["siblings"] as? [[String: Any]] else { return [] }
        return siblings.compactMap { $0["rfilename"] as? String }
            .filter { $0.hasSuffix(".litertlm") }
            .sorted()
    }

    /// 목록이 있으면 선택값, 비었으면 직접입력 (순수, T-233 파일 폴백).
    nonisolated static func resolveFile(siblings: [String], fileIndex: Int,
                                        customFile: String) -> String {
        if !siblings.isEmpty, siblings.indices.contains(fileIndex) { return siblings[fileIndex] }
        return customFile.trimmingCharacters(in: .whitespaces)
    }

    /// 토큰 Authorization 헤더값 (없으면 nil, T-233).
    nonisolated static func authHeader(token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : "Bearer \(trimmed)"
    }

    /// 동일 파일 진행 중 여부 (순수, T-233 중복 시작 가드).
    nonisolated static func hasActiveDownload(_ items: [(fileName: String, active: Bool)],
                                              fileName: String) -> Bool {
        items.contains { $0.fileName == fileName && $0.active }
    }

    /// HEAD 응답에서 크기 확정 (순수, T-239).
    /// 3xx 본문 길이(리다이렉트 페이지, 140B 오인 사례)를 크기로 쓰지 않는다.
    nonisolated static func sizeFromHead(status: Int, linked: Int64?,
                                         contentLength: Int64) -> Int64? {
        if let linked { return linked }
        guard (200 ... 299).contains(status), contentLength > 0 else { return nil }
        return contentLength
    }
    /// HTTP 상태 → 사용자 문구 (순수, T-242): 401/403은 게이트 안내.
    nonisolated static func httpErrorMessage(status: Int) -> String {
        switch status {
        case 401, 403:
            return "승인 필요 (HTTP \(status)): HF에서 저장소 접근 승인 후 토큰 입력"
        case 404:
            return "파일 없음 (HTTP 404): 저장소·파일명을 확인해 주세요"
        default:
            return "HTTP \(status)"
        }
    }
    /// 302 헤더에서 x-linked-size 추출 (순수, T-239).
    nonisolated static func linkedSize(headers: [AnyHashable: Any]) -> Int64? {
        for (key, value) in headers {
            guard (key as? String)?.lowercased() == "x-linked-size" else { continue }
            if let str = value as? String,
               let num = Int64(str.trimmingCharacters(in: .whitespaces)) { return num }
            if let num = value as? Int { return Int64(num) }
        }
        return nil
    }

    /// Content-Range 전체값 추출 (순수, T-239. `bytes 0-0/12345` → 12345).
    nonisolated static func rangeTotal(contentRange: String?) -> Int64? {
        guard let range = contentRange, let slash = range.lastIndex(of: "/") else { return nil }
        return Int64(range[range.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }

    /// 원격 파일 크기 (T-239): x-linked-size → content-length → Range 폴백.
    /// HF resolve는 302+Xet 구조라 리다이렉트 추종 HEAD로는 크기가 안 나옴.
    nonisolated static func remoteFileSize(url: URL, token: String?) async -> Int64? {
        let auth = authHeader(token: token ?? "")
        let blocker = NoRedirectDelegate()
        let session = URLSession(configuration: .default, delegate: blocker, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        if let auth { head.setValue(auth, forHTTPHeaderField: "Authorization") }
        if let (_, resp) = try? await session.data(for: head),
           let http = resp as? HTTPURLResponse,
           let size = sizeFromHead(status: http.statusCode,
                                   linked: linkedSize(headers: http.allHeaderFields),
                                   contentLength: http.expectedContentLength) {
            return size
        }
        var ranged = URLRequest(url: url)
        ranged.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        if let auth { ranged.setValue(auth, forHTTPHeaderField: "Authorization") }
        if let (_, resp) = try? await URLSession.shared.data(for: ranged),
           let http = resp as? HTTPURLResponse {
            return rangeTotal(contentRange: http.value(forHTTPHeaderField: "Content-Range"))
        }
        return nil
    }

    /// 대표 프리셋 (컬렉션 실측 저장소 ID, 파일명은 API 조회로 확정).
    nonisolated static func presets() -> [ModelPreset] {
        [
            ModelPreset(repo: "litert-community/gemma-4-E2B-it-litert-lm",
                        label: "Gemma 4 E2B", suggestedID: "gemma4-e2b"),
            ModelPreset(repo: "litert-community/gemma-4-12B-it-litert-lm",
                        label: "Gemma 4 12B", suggestedID: "gemma4-12b"),
            ModelPreset(repo: "google/gemma-3n-E2B-it-litert-lm",
                        label: "Gemma 3n E2B", suggestedID: "gemma3n-e2b"),
            ModelPreset(repo: "litert-community/Qwen3-4B",
                        label: "Qwen3 4B", suggestedID: "qwen3-4b"),
            ModelPreset(repo: "litert-community/Qwen2.5-1.5B-Instruct",
                        label: "Qwen2.5 1.5B", suggestedID: "qwen2.5-1.5b")
        ]
    }
}
