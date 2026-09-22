import Foundation

// MARK: - 다운로더 본체 (T-246 분리: 파일 길이 분산)

/// 리다이렉트 추종 차단 (T-239): 302 응답 헤더(x-linked-size) 직접 읽기용.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// 단일 다운로드 진행 스냅샷 (뷰 표시용).
struct DownloadSnapshot: Sendable {
    var received: Int64 = 0
    var total: Int64? // expectedContentLength 미상(-1)이면 nil
    var startedAt = Date()
    var finished = false
    var error: String?
}

/// 이어받기 판정 (T-246): 206 append · 200 restart · 그 외 fail.
enum ResumeAction: Sendable, Equatable {
    case append
    case restart
    case fail
}

/// 재개·재시작 요청 묶음 (T-246, 대형 튜플 회피).
struct DownloadRequest: Sendable {
    let url: URL
    let token: String?
    let part: URL
    let final: URL?
}

extension ModelDownload {
    /// Range 재개 헤더값 (순수, T-246).
    nonisolated static func resumeRangeHeader(existing: Int64) -> String {
        "bytes=\(max(0, existing))-"
    }

    /// 디스크 파일 크기 (T-371): NSNumber에서 int64Value로 직접 읽어
    /// 수 GB `.part`의 32bit 잘림을 방지. 없으면 0.
    nonisolated static func fileSizeBytes(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let num = attrs[.size] as? NSNumber else { return 0 }
        return num.int64Value
    }

    /// 재개 응답 판정 (순수, T-246).
    nonisolated static func resumeAction(status: Int) -> ResumeAction {
        switch status {
        case 206: return .append
        case 200: return .restart
        default: return .fail
        }
    }

    /// 바 분율 클램프 (순수, T-248).
    nonisolated static func clamp01(_ v: Double) -> Double {
        min(1, max(0, v))
    }
}

/// URLSession 직접 다운로드 → 스테이징 `.part` → 완료 시 개명 (T-232).
/// 일시정지/이어받기 (T-246) + 완전 취소 (`.part` 삭제) 지원.
final class ModelDownloader: NSObject, ObservableObject, URLSessionDataDelegate, @unchecked Sendable {
    @Published var received: Int64 = 0
    @Published var total: Int64?
    @Published var finished = false
    @Published var errorMessage: String?
    @Published var paused = false
    @Published var cancelled = false
    var startedAt = Date()

    private let lock = NSLock()
    private var handle: FileHandle?
    private var partURL: URL?
    private var finalURL: URL?
    private var lastURL: URL?
    private var lastToken: String?
    private var resuming = false
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var completion: ((Bool) -> Void)?

    /// 받는 중 판정 (T-246, 중복 가드용): 일시정지·취소·완료·실패는 제외.
    var isDownloading: Bool {
        !finished && errorMessage == nil && !paused && !cancelled
    }

    /// 재실행 복원용 staged 상태 주입 (T-249): 항상 일시정지, 이어받기로 재개.
    func stageForResume(url: URL?, partURL: URL, finalURL: URL, received: Int64) {
        lock.withLock {
            self.lastURL = url
            self.lastToken = nil
            self.partURL = partURL
            self.finalURL = finalURL
            self.resuming = false
        }
        startedAt = Date()
        self.received = received
        paused = true
    }

    /// 다운로드 시작. 토큰은 비공개 저장소용 (없으면 nil).
    func start(url: URL, token: String?, partURL: URL, finalURL: URL,
               completion: ((Bool) -> Void)? = nil) {
        lock.withLock {
            self.partURL = partURL
            self.finalURL = finalURL
            self.lastURL = url
            self.lastToken = token
            self.resuming = false
            self.completion = completion
        }
        // 기존 `.part` 모호성 제거 (T-246): 시작은 항상 처음부터.
        try? FileManager.default.removeItem(at: partURL)
        FileManager.default.createFile(atPath: partURL.path, contents: nil)
        do {
            handle = try FileHandle(forWritingTo: partURL)
        } catch {
            fail(L(L10n.Downloader.writeFailed, error.localizedDescription))
            return
        }
        var req = URLRequest(url: url)
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        startedAt = Date()
        DebugLogger.shared.info(feature: "모델가져오기", "다운로드 시작: \(url.lastPathComponent)")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: req)
        self.task = task
        task.resume()
    }

    /// 완전 취소 (T-246): 중단 + `.part` 삭제 + 취소 상태.
    /// silent면 완료 콜백 생략 (사용자 직접 취소·삭제 시 실패 문구 방지).
    func cancel(silent: Bool = false) {
        task?.cancel()
        session?.invalidateAndCancel()
        lock.withLock { handle = nil }
        discardPartFile()
        DebugLogger.shared.info(feature: "모델가져오기", "다운로드 취소 (.part 삭제)")
        DispatchQueue.main.async { [weak self] in
            self?.cancelled = true
            if !silent {
                self?.completion?(false)
                self?.completion = nil
            }
        }
    }

    /// 일시정지 (T-246): 중단 + `.part`·수신량 유지, 이어받기 가능.
    func pause() {
        task?.cancel()
        session?.invalidateAndCancel()
        lock.withLock { handle = nil }
        DebugLogger.shared.info(feature: "모델가져오기", "다운로드 일시정지 (.part 유지)")
        DispatchQueue.main.async { [weak self] in
            self?.paused = true
        }
    }

    /// 이어받기 (T-246): Range 재개, 200이면 처음부터.
    func resume() {
        let req: DownloadRequest? = lock.withLock {
            guard let url = lastURL, let part = partURL else { return nil }
            return DownloadRequest(url: url, token: lastToken, part: part, final: nil)
        }
        guard let req else { return }
        let (url, token, part) = (req.url, req.token, req.part)
        let existing = ModelDownload.fileSizeBytes(at: part)
        do {
            let handle: FileHandle
            if FileManager.default.fileExists(atPath: part.path) {
                handle = try FileHandle(forWritingTo: part)
                try handle.seekToEnd()
            } else {
                FileManager.default.createFile(atPath: part.path, contents: nil)
                handle = try FileHandle(forWritingTo: part)
            }
            lock.withLock {
                self.handle = handle
                self.resuming = true
            }
        } catch {
            fail(L(L10n.Downloader.openFailed, error.localizedDescription))
            return
        }
        var request = URLRequest(url: url)
        request.setValue(ModelDownload.resumeRangeHeader(existing: existing),
                         forHTTPHeaderField: "Range")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        DebugLogger.shared.info(feature: "모델가져오기",
                                "다운로드 이어받기: \(url.lastPathComponent) (+\(existing)B)")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        DispatchQueue.main.async { [weak self] in self?.paused = false }
        task.resume()
    }

    /// 처음부터 다시 받기 (T-246): 상태 초기화 후 시작.
    func restart() {
        let req: DownloadRequest? = lock.withLock {
            guard let url = lastURL, let part = partURL, let final = finalURL else { return nil }
            return DownloadRequest(url: url, token: lastToken, part: part, final: final)
        }
        guard let req, let final = req.final else { return }
        let (url, token, part) = (req.url, req.token, req.part)
        let completion = lock.withLock { self.completion }
        DispatchQueue.main.async { [weak self] in
            self?.received = 0
            self?.total = nil
            self?.errorMessage = nil
            self?.paused = false
            self?.cancelled = false
            self?.startedAt = Date()
        }
        start(url: url, token: token, partURL: part, finalURL: final, completion: completion)
    }

    /// `.part` 파일 삭제 (T-245/T-246).
    func discardPartFile() {
        if let part = lock.withLock({ partURL }),
           FileManager.default.fileExists(atPath: part.path) {
            try? FileManager.default.removeItem(at: part)
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            fail(L(L10n.Downloader.responseError))
            completionHandler(.cancel)
            return
        }
        let isResume = lock.withLock { resuming }
        if isResume {
            switch ModelDownload.resumeAction(status: http.statusCode) {
            case .append:
                if let total = ModelDownload.rangeTotal(
                    contentRange: http.value(forHTTPHeaderField: "Content-Range")) {
                    DispatchQueue.main.async { [weak self] in self?.total = total }
                }
            case .restart:
                lock.withLock {
                    if let part = partURL {
                        try? FileManager.default.removeItem(at: part)
                        FileManager.default.createFile(atPath: part.path, contents: nil)
                        handle = try? FileHandle(forWritingTo: part)
                    }
                    resuming = false
                }
                DispatchQueue.main.async { [weak self] in
                    self?.received = 0
                    let len = http.expectedContentLength
                    self?.total = len > 0 ? len : nil
                }
            case .fail:
                fail(ModelDownload.httpErrorMessage(status: http.statusCode))
                completionHandler(.cancel)
                return
            }
            lock.withLock { resuming = false }
            completionHandler(.allow)
            return
        }
        if !(200 ... 299).contains(http.statusCode) {
            fail(ModelDownload.httpErrorMessage(status: http.statusCode))
            completionHandler(.cancel)
            return
        }
        let expected = response.expectedContentLength
        DispatchQueue.main.async { [weak self] in
            self?.total = expected > 0 ? expected : nil
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock { try? handle?.write(contentsOf: data) }
        DispatchQueue.main.async { [weak self] in
            self?.received += Int64(data.count)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.withLock { handle = nil }
        session.invalidateAndCancel()
        if let error {
            if (error as NSError).code == NSURLErrorCancelled { return } // cancel()에서 처리
            fail(error.localizedDescription)
            return
        }
        guard let partURL, let finalURL else {
            fail(L(L10n.Downloader.internalPathError))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: partURL, to: finalURL)
            DebugLogger.shared.info(feature: "모델가져오기", "다운로드 완료→개명: \(finalURL.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.finished = true
                self?.completion?(true)
                self?.completion = nil
            }
        } catch {
            fail(L(L10n.Downloader.renameFailed, error.localizedDescription))
        }
    }

    private func fail(_ message: String) {
        DebugLogger.shared.error(code: "E-MAC-STOR-0006", feature: "모델가져오기", "다운로드 실패: \(message)")
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = message
            self?.completion?(false)
            self?.completion = nil
        }
    }
}
