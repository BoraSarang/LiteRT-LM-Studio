import Foundation

/// 앱 내 엔진 백엔드 묶음 확장 (T-273 분리: 본문 길이 관리).
extension NativeEngine {
    /// 엔진 백엔드 묶음 (T-177): config.json 추종 결과.
    struct EngineBackends: Equatable {
        var backend: Backend = .gpu
        var vision: Backend? = .cpu()
        var audio: Backend?
    }

    /// config.json 추종 백엔드 (순수, 테스트 가능, T-177): default 섹션 읽기.
    /// 실패·미기재 시 기존 고정값 (.gpu/.cpu()/nil). npu 등 미지원은 gpu로 폴백.
    nonisolated static func resolveBackends(configURL: URL) -> EngineBackends {
        func parsed(_ s: String?, threads: Int?) -> Backend? {
            switch s {
            case "cpu": .cpu(threadCount: threads)
            case "gpu": .gpu
            default: nil
            }
        }
        guard let json = ConfigStore.jsonDict(at: configURL),
              let def = json["default"] as? [String: Any] else {
            return EngineBackends()
        }
        let threads = def["cpu_thread_count"] as? Int
        return EngineBackends(
            backend: parsed(def["backend"] as? String, threads: threads) ?? .gpu,
            vision: parsed(def["vision_backend"] as? String, threads: nil),
            audio: parsed(def["audio_backend"] as? String, threads: nil))
    }

    /// Metal residency (T-177): 미설정 시 켬 (Gallery 동일).
    nonisolated static func residencyEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "metalResidency") as? Bool ?? true
    }

    /// Visual 예산 (T-177): 미설정 시 1120 (describe 상한, Gemma4 5단 중 최대).
    nonisolated static func visualBudget(_ defaults: UserDefaults = .standard) -> Int32 {
        Int32(defaults.object(forKey: "visualTokenBudget") as? Int ?? 1120)
    }

    /// 모달 제외 폴백 (순수, 테스트 가능, T-273): vision·audio 있으면 뺀 값, 없으면 nil.
    nonisolated static func modalFallback(_ backends: EngineBackends) -> EngineBackends? {
        guard backends.vision != nil || backends.audio != nil else { return nil }
        return EngineBackends(backend: backends.backend, vision: nil, audio: nil)
    }
}
