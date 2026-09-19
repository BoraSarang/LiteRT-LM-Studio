import Foundation

/// 화면 문구 키 (T-362·T-363) — 세션·사이드바·인스펙터·벤치마크·모델 카탈로그·메뉴바.
extension L10n {
    enum Session {
        static let sortRecent = L10nKey("session.sort.recent")
        static let sortName = L10nKey("session.sort.name")
        static let sortCreated = L10nKey("session.sort.created")
        static let new = L10nKey("session.new")
        static let newHelp = L10nKey("session.newHelp")
        static let sortHelp = L10nKey("session.sortHelp")
        static let menu = L10nKey("session.menu")
        static let unpin = L10nKey("session.unpin")
        static let pin = L10nKey("session.pin")
        static let rename = L10nKey("session.rename")
        static let deleteTitle = L10nKey("session.delete.title")
        static let deleteMessage = L10nKey("session.delete.message")
        static let renameTitle = L10nKey("session.rename.title")
        static let renameMessage = L10nKey("session.rename.message")
        static let namePlaceholder = L10nKey("session.namePlaceholder")
    }

    enum Sidebar {
        static let chat = L10nKey("sidebar.chat")
        static let models = L10nKey("sidebar.models")
        static let sectionEnvironment = L10nKey("sidebar.section.environment")
        static let labelVersion = L10nKey("sidebar.label.version")
        static let labelAcceleration = L10nKey("sidebar.label.acceleration")
        static let labelEngine = L10nKey("sidebar.label.engine")
        static let labelStatus = L10nKey("sidebar.label.status")
        static let statusHelp = L10nKey("sidebar.status.help")
        static let accelUnset = L10nKey("sidebar.accel.unset")
        static let externalRestart = L10nKey("sidebar.externalRestart")
        static let copyRestartCommand = L10nKey("sidebar.copyRestartCommand")
        static let refreshHelp = L10nKey("sidebar.refreshHelp")
        static let manage = L10nKey("sidebar.manage")
        static let manageHelp = L10nKey("sidebar.manageHelp")
        static let rowDetail = L10nKey("sidebar.row.detail")
        static let menu = L10nKey("sidebar.menu")
        static let menuSelectForChat = L10nKey("sidebar.menu.selectForChat")
        static let menuRename = L10nKey("sidebar.menu.rename")
        static let menuRunBenchmark = L10nKey("sidebar.menu.runBenchmark")
        static let menuRemove = L10nKey("sidebar.menu.remove")
        static let enginePreparing = L10nKey("sidebar.engine.preparing")
        static let engineFailed = L10nKey("sidebar.engine.failed")
        static let engineIdle = L10nKey("sidebar.engine.idle")
        static let actionInitNative = L10nKey("sidebar.action.initNative")
        static let actionInitNativeHelp = L10nKey("sidebar.action.initNativeHelp")
        static let preparing = L10nKey("sidebar.preparing")
        static let actionStopNative = L10nKey("sidebar.action.stopNative")
        static let actionStopNativeHelp = L10nKey("sidebar.action.stopNativeHelp")
        static let actionRestart = L10nKey("sidebar.action.restart")
        static let actionRestartHelp = L10nKey("sidebar.action.restartHelp")
        static let actionStopDaemon = L10nKey("sidebar.action.stopDaemon")
        static let actionStopDaemonHelp = L10nKey("sidebar.action.stopDaemonHelp")
        static let actionStartDaemon = L10nKey("sidebar.action.startDaemon")
        static let actionStartDaemonHelp = L10nKey("sidebar.action.startDaemonHelp")
        static let externalSuffix = L10nKey("sidebar.externalSuffix")
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
