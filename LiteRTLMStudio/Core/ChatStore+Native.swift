import Foundation

/// 네이티브 전송 확장 (T-130): 분기·토큰·실패 매핑.
extension ChatStore {
    /// 네이티브 분기 판정 (T-130, 테스트 가능): 모드+주입 모두 필요.
    func usesNative() -> Bool {
        EngineMode.current() == .native && inferenceEngine != nil
    }

    /// 전송 가능 판정 (순수, 테스트 가능, T-146): 스트리밍 중 제외,
    /// 데몬 실행 중 또는 네이티브 준비. CLI 모드(nativeReady=false)는 기존 조건과 동일.
    nonisolated static func sendAllowed(streaming: Bool, daemonRunning: Bool, nativeReady: Bool) -> Bool {
        !streaming && (daemonRunning || nativeReady)
    }

    /// 첫 토큰 기록 (T-130, CLI·네이티브 공용): preparing 해제+TTFT 로그.
    func noteFirstToken(started: Date) {
        preparing = false
        let ttft = Date().timeIntervalSince(started)
        logger.perf(feature: "채팅전송", "첫 토큰 TTFT=\(String(format: "%.1f", ttft))s")
    }

    /// 네이티브 전송 (T-130): prepare → 스트림 소비. 완료·PERF·중단 골격은 CLI와 동일.
    func runNative(engine: any InferenceEngine, prompt: String,
                   image: ChatImage?, idx: Int, started: Date) async {
        do {
            try await engine.prepare(modelID: model)
            // T-149: 전송 범위 설정 적용 (제한 없음이면 전량, 기존 동작).
            let windowed = Self.windowedHistory(Array(messages.dropLast(2)),
                                                turns: HistoryWindow.currentTurns())
            let past = windowed.map { (role: $0.role, text: $0.text) }
            let stream = engine.stream(prompt: prompt, image: image,
                                       history: Array(past), temperature: temperature)
            var acc = ""
            var firstTokenAt: Date?
            var lastFlush = started
            for try await chunk in stream {
                if Task.isCancelled { break }
                if firstTokenAt == nil {
                    firstTokenAt = Date()
                    self.noteFirstToken(started: started)
                }
                acc += chunk
                // T-148: 0.1초 묶음 갱신 (토큰당 전체 리렌더 방지). 종료 후 최종 반영.
                if Self.shouldFlushText(now: Date(), lastFlush: lastFlush) {
                    messages[idx].text = acc
                    lastFlush = Date()
                }
            }
            messages[idx].text = acc
            let elapsed = Date().timeIntervalSince(started)
            messages[idx].perf = Self.perfLine(chars: acc.count, elapsed: elapsed)
            messages[idx].finishedAt = Date() // T-077 완료 시각 기록
            logger.perf(feature: "채팅전송", "완료 elapsed=\(String(format: "%.1f", elapsed))s chars=\(acc.count)")
        } catch is CancellationError {
            logger.info(feature: "채팅중단", "사용자 중단")
        } catch {
            if Task.isCancelled {
                logger.info(feature: "채팅중단", "사용자 중단")
            } else {
                self.nativeFailed(at: idx, error: error)
            }
        }
        preparing = false
        streaming = false
        save()
    }

    /// 네이티브 실패 반영 (T-130): EngineError 코드 매핑.
    func nativeFailed(at idx: Int, error: Error) {
        let code = (error as? EngineError)?.code ?? EngineError.inferenceFailed("").code
        lastError = code
        messages[idx].text = code == EngineError.initFailed("").code
            ? "엔진 초기화에 실패했습니다. 모델 파일과 메모리를 확인해 주세요. (E-MAC-ENG-0001)"
            : "네이티브 추론에 실패했습니다. 다른 엔진 모드로 바꿔 다시 시도해 주세요. (E-MAC-ENG-0002)"
        messages[idx].isError = true
        messages[idx].finishedAt = Date()
        logger.error(code: code, feature: "채팅전송", "\(error)")
    }

}
