import Foundation

/// 번역 키 모음 (T-361). 영역별 네임스페이스 + `static let` — 없는 키는 컴파일 에러.
/// 키 문자열은 `영역.하위.이름` 점 표기를 쓰고 값은 `Localizable.xcstrings`에 둔다.
/// (swiftlint `nesting` 때문에 타입은 1단계까지만 중첩한다.)
enum L10n {

    // MARK: 공통

    enum Common {
        static let cancel = L10nKey("common.cancel")
        static let close = L10nKey("common.close")
        static let reset = L10nKey("common.reset")
        static let select = L10nKey("common.select")
    }

    // MARK: 설정

    enum Settings {
        static let generalTab = L10nKey("settings.general.tab")
        static let generalAppearance = L10nKey("settings.general.appearance")
        static let generalLanguage = L10nKey("settings.general.language")
        static let generalLanguageHelp = L10nKey("settings.general.language.help")
    }

    // MARK: 언어 (AppLanguage.label)

    static let languageSystem = L10nKey("language.system")

    // MARK: 도구 (ToolCatalog)

    enum Tools {
        static let categoryBasic = L10nKey("tools.category.basic")
        static let categoryWeb = L10nKey("tools.category.web")
        static let categorySystem = L10nKey("tools.category.system")
        static let categoryMcp = L10nKey("tools.category.mcp")
        // 도구별 `tools.<name>.title` / `tools.<name>.detail`은 `ToolInfo`가 이름에서 만든다.
    }

    // MARK: 모델 (ModelAlias)

    enum Model {
        static let modalityText = L10nKey("model.modality.text")
        static let modalityVision = L10nKey("model.modality.vision")
        static let modalityAudio = L10nKey("model.modality.audio")
        static let stageInstalled = L10nKey("model.stage.installed")
        static let stageDownloadedUninstalled = L10nKey("model.stage.downloadedUninstalled")
    }

    // MARK: 외관·권한·엔진

    enum Appearance {
        static let system = L10nKey("appearance.system")
        static let light = L10nKey("appearance.light")
        static let dark = L10nKey("appearance.dark")
    }

    enum Permission {
        static let off = L10nKey("permission.off")
        static let ask = L10nKey("permission.ask")
        static let allowAll = L10nKey("permission.allowAll")
    }

    enum Engine {
        static let modeServer = L10nKey("engine.mode.server")
        static let modeNative = L10nKey("engine.mode.native")
    }

    enum History {
        static let unlimited = L10nKey("history.unlimited")
        static let turns = L10nKey("history.turns")
    }

    /// 통합 상태 한 줄 (UnifiedStatus).
    enum Status {
        static let externalTitle = L10nKey("status.external.title")
        static let externalDetail = L10nKey("status.external.detail")
        static let readyTitle = L10nKey("status.ready.title")
        static let readyDaemon = L10nKey("status.ready.daemon")
        static let readyBothEngines = L10nKey("status.ready.bothEngines")
        static let readyNativeEngine = L10nKey("status.ready.nativeEngine")
        static let stoppedTitle = L10nKey("status.stopped.title")
        static let stoppedNative = L10nKey("status.stopped.native")
        static let stoppedCli = L10nKey("status.stopped.cli")
    }

    // MARK: 세션·사이드바·인스펙터

    enum Session {
        static let sortRecent = L10nKey("session.sort.recent")
        static let sortName = L10nKey("session.sort.name")
        static let sortCreated = L10nKey("session.sort.created")
    }

    enum Sidebar {
        static let chat = L10nKey("sidebar.chat")
        static let models = L10nKey("sidebar.models")
    }

    enum Inspector {
        static let system = L10nKey("inspector.system")
        static let backend = L10nKey("inspector.backend")
        static let generate = L10nKey("inspector.generate")
        static let summaryLive = L10nKey("inspector.summary.live")
        static let summaryStopped = L10nKey("inspector.summary.stopped")
        static let summaryChanged = L10nKey("inspector.summary.changed")
        static let summaryApplied = L10nKey("inspector.summary.applied")
        static let summaryGenerate = L10nKey("inspector.summary.generate")
    }

    enum Skill {
        static let sourceOther = L10nKey("skill.source.other")
    }

    // MARK: 벤치마크

    enum Benchmark {
        static let stageInit = L10nKey("benchmark.stage.init")
        static let stageMeasure = L10nKey("benchmark.stage.measure")
        static let stageSummarize = L10nKey("benchmark.stage.summarize")
        static let stageDone = L10nKey("benchmark.stage.done")
        static let estimateAverage = L10nKey("benchmark.estimate.average")
        static let estimateNative = L10nKey("benchmark.estimate.native")
        static let estimateCli = L10nKey("benchmark.estimate.cli")
        static let elapsedSeconds = L10nKey("benchmark.elapsed.seconds")
        static let elapsedMinutes = L10nKey("benchmark.elapsed.minutes")
        static let statusDone = L10nKey("benchmark.status.done")
        static let statusCancelled = L10nKey("benchmark.status.cancelled")
        static let statusFailed = L10nKey("benchmark.status.failed")
        static let tokensPerSecond = L10nKey("benchmark.tokensPerSecond")
        static let retentionTen = L10nKey("benchmark.retention.ten")
        static let retentionFifty = L10nKey("benchmark.retention.fifty")
        static let retentionHundred = L10nKey("benchmark.retention.hundred")
        static let retentionUnlimited = L10nKey("benchmark.retention.unlimited")
        static let allRecords = L10nKey("benchmark.allRecords")
        static let analysisNotPrepared = L10nKey("benchmark.analysis.notPrepared")
        static let analysisCancelled = L10nKey("benchmark.analysis.cancelled")
        static let analysisFailed = L10nKey("benchmark.analysis.failed")
    }

    // MARK: 모델 카탈로그

    enum ModelCatalog {
        static let familyAll = L10nKey("modelCatalog.family.all")
        static let familyOther = L10nKey("modelCatalog.family.other")
        static let sortDownloads = L10nKey("modelCatalog.sort.downloads")
        static let sortLikes = L10nKey("modelCatalog.sort.likes")
        static let sortUpdated = L10nKey("modelCatalog.sort.updated")
    }

    // MARK: 시간·도구 상태

    enum Time {
        static let justNow = L10nKey("time.justNow")
        static let secondsAgo = L10nKey("time.secondsAgo")
        static let minutesAgo = L10nKey("time.minutesAgo")
        static let hoursAgo = L10nKey("time.hoursAgo")
        static let yesterday = L10nKey("time.yesterday")
        static let daysAgo = L10nKey("time.daysAgo")
    }

    enum ToolStatus {
        static let streaming = L10nKey("toolStatus.streaming")
        static let received = L10nKey("toolStatus.received")
        static let done = L10nKey("toolStatus.done")
        static let failed = L10nKey("toolStatus.failed")
        static let denied = L10nKey("toolStatus.denied")
    }

    // MARK: 메뉴바

    enum MenuBar {
        static let running = L10nKey("menuBar.running")
        static let runningExternal = L10nKey("menuBar.running.external")
        static let starting = L10nKey("menuBar.starting")
        static let failed = L10nKey("menuBar.failed")
        static let unlinked = L10nKey("menuBar.unlinked")
        static let stopped = L10nKey("menuBar.stopped")
        static let tooltip = L10nKey("menuBar.tooltip")
        static let uptimeHours = L10nKey("menuBar.uptime.hours")
        static let uptimeMinutes = L10nKey("menuBar.uptime.minutes")
        static let uptimeSeconds = L10nKey("menuBar.uptime.seconds")
        static let routeNativeReady = L10nKey("menuBar.route.native.ready")
        static let routeNativePreparing = L10nKey("menuBar.route.native.preparing")
        static let routeNativeFailed = L10nKey("menuBar.route.native.failed")
        static let routeNativeIdle = L10nKey("menuBar.route.native.idle")
        static let actionStopNative = L10nKey("menuBar.action.stopNative")
        static let actionStartNative = L10nKey("menuBar.action.startNative")
        static let actionDisconnectExternal = L10nKey("menuBar.action.disconnectExternal")
        static let actionStopServer = L10nKey("menuBar.action.stopServer")
        static let actionStartServer = L10nKey("menuBar.action.startServer")
    }
}
