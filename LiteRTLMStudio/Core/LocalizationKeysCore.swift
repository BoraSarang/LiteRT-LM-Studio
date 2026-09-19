import Foundation

/// Core 표시 문구 키 (T-364) — 실행 설정 요약·채팅 오류·도구 인자 라벨.
extension L10n {
    enum Config {
        static let on = L10nKey("config.on")
        static let off = L10nKey("config.off")
        static let auto = L10nKey("config.auto")
        static let defaultValue = L10nKey("config.default")
        static let unlimited = L10nKey("config.unlimited")
        static let builtin = L10nKey("config.builtin")
        static let mtp = L10nKey("config.mtp")
        static let thinking = L10nKey("config.thinking")
        static let threads = L10nKey("config.threads")
        static let cache = L10nKey("config.cache")
        static let kv = L10nKey("config.kv")
        static let budget = L10nKey("config.budget")
        static let precision = L10nKey("config.precision")
    }

    enum ChatError {
        static let nativeNotReady = L10nKey("chatError.nativeNotReady")
        static let timeout = L10nKey("chatError.timeout")
        static let request = L10nKey("chatError.request")
        static let engineInit = L10nKey("chatError.engineInit")
        static let engineTimeout = L10nKey("chatError.engineTimeout")
        static let engineInference = L10nKey("chatError.engineInference")
    }

    enum Perf {
        static let line = L10nKey("perf.line")
    }

    enum ToolArg {
        static let content = L10nKey("toolArg.content")
        static let code = L10nKey("toolArg.code")
        static let days = L10nKey("toolArg.days")
        static let includeCompleted = L10nKey("toolArg.includeCompleted")
        static let onlyIncomplete = L10nKey("toolArg.onlyIncomplete")
    }

    enum Downloader {
        static let writeFailed = L10nKey("downloader.writeFailed")
        static let openFailed = L10nKey("downloader.openFailed")
        static let responseError = L10nKey("downloader.responseError")
        static let internalPathError = L10nKey("downloader.internalPathError")
        static let renameFailed = L10nKey("downloader.renameFailed")
    }

    enum EngineNotice {
        static let noModel = L10nKey("engineNotice.noModel")
        static let noFile = L10nKey("engineNotice.noFile")
    }

    enum Power {
        static let mtpLimited = L10nKey("power.mtpLimited")
        static let mtpOff = L10nKey("power.mtpOff")
        static let mtpUnset = L10nKey("power.mtpUnset")
        static let battery = L10nKey("power.battery")
        static let discharging = L10nKey("power.discharging")
        static let charging = L10nKey("power.charging")
    }
}
