import Foundation

/// 화면 문구 키 (T-363) — 대화·패널·설정·도구·모델.
extension L10n {
    enum Panel {
        static let serverLog = L10nKey("panel.serverLog")
        static let system = L10nKey("panel.system")
        static let externalDaemon = L10nKey("panel.externalDaemon")
        static let appDaemon = L10nKey("panel.appDaemon")
        static let copied = L10nKey("panel.copied")
        static let copySelection = L10nKey("panel.copySelection")
        static let copySelectionHelp = L10nKey("panel.copySelectionHelp")
        static let copyAll = L10nKey("panel.copyAll")
        static let copyAllHelp = L10nKey("panel.copyAllHelp")
        static let clear = L10nKey("panel.clear")
        static let clearHelp = L10nKey("panel.clearHelp")
        static let closeHelp = L10nKey("panel.closeHelp")
        static let externalLogTitle = L10nKey("panel.externalLog.title")
        static let externalLogDetail = L10nKey("panel.externalLog.detail")
        static let takeover = L10nKey("panel.takeover")
        static let noLogTitle = L10nKey("panel.noLog.title")
        static let noLogDetail = L10nKey("panel.noLog.detail")
    }

    enum Dialog {
        static let takeoverTitle = L10nKey("dialog.takeover.title")
        static let takeoverRestart = L10nKey("dialog.takeover.restart")
        static let takeoverSaveOnly = L10nKey("dialog.takeover.saveOnly")
        static let takeoverMessage = L10nKey("dialog.takeover.message")
        static let toolTitle = L10nKey("dialog.tool.title")
        static let allow = L10nKey("dialog.allow")
        static let deny = L10nKey("dialog.deny")
        static let toolMessage = L10nKey("dialog.tool.message")
    }

    enum Help {
        static let commandPalette = L10nKey("help.commandPalette")
        static let bottomPanelOn = L10nKey("help.bottomPanel.on")
        static let bottomPanelOff = L10nKey("help.bottomPanel.off")
        static let inspectorToggle = L10nKey("help.inspector.toggle")
        static let inspectorShow = L10nKey("help.inspector.show")
    }

    enum Server {
        static let nativePreparing = L10nKey("server.native.preparing")
        static let nativeStop = L10nKey("server.native.stop")
        static let nativeRestart = L10nKey("server.native.restart")
        static let nativeInit = L10nKey("server.native.init")
        static let externalDisconnect = L10nKey("server.external.disconnect")
        static let stop = L10nKey("server.stop")
        static let startReadyNative = L10nKey("server.start.readyNative")
        static let start = L10nKey("server.start")
    }

    enum FollowUp {
        static let more = L10nKey("followUp.more")
        static let example = L10nKey("followUp.example")
        static let exampleGeneric = L10nKey("followUp.exampleGeneric")
        static let summarize = L10nKey("followUp.summarize")
        static let next = L10nKey("followUp.next")
        static let fallbackDetail = L10nKey("followUp.fallback.detail")
        static let fallbackExample = L10nKey("followUp.fallback.example")
        static let fallbackSummary = L10nKey("followUp.fallback.summary")
        static let fallbackRelated = L10nKey("followUp.fallback.related")
    }

    // MARK: 설정

    enum Settings {
        static let generalTab = L10nKey("settings.general.tab")
        static let generalAppearance = L10nKey("settings.general.appearance")
        static let generalLanguage = L10nKey("settings.general.language")
        static let generalLanguageHelp = L10nKey("settings.general.language.help")
        static let themeMode = L10nKey("settings.themeMode")
        static let themeModeHelp = L10nKey("settings.themeMode.help")
        static let showInDock = L10nKey("settings.showInDock")
        static let launchAtLogin = L10nKey("settings.launchAtLogin")
        static let loginItemError = L10nKey("settings.launchAtLogin.error")
        static let systemSection = L10nKey("settings.system")
        static let quitStopsDaemon = L10nKey("settings.quitStopsDaemon")
        static let quitStopsDaemonHelp = L10nKey("settings.quitStopsDaemon.help")
        static let prefillWarmup = L10nKey("settings.prefillWarmup")
        static let prefillWarmupHelp = L10nKey("settings.prefillWarmup.help")
        static let routeNote = L10nKey("settings.route.note")
        static let routeNoteHelp = L10nKey("settings.route.note.help")
        static let serverNote = L10nKey("settings.server.note")
        static let advancedSection = L10nKey("settings.advanced")
        static let benchmarkRetention = L10nKey("settings.benchmarkRetention")
        static let benchmarkRetentionHelp = L10nKey("settings.benchmarkRetention.help")
        static let permissionSection = L10nKey("settings.permission.section")
        static let permission = L10nKey("settings.permission")
        static let permissionHelp = L10nKey("settings.permission.help")
        static let displaySection = L10nKey("settings.display")
        static let outlineEnabled = L10nKey("settings.outlineEnabled")
        static let outlineEnabledHelp = L10nKey("settings.outlineEnabled.help")
        static let followUpEnabled = L10nKey("settings.followUpEnabled")
        static let followUpEnabledHelp = L10nKey("settings.followUpEnabled.help")
        static let chatFontSize = L10nKey("settings.chatFontSize")
        static let defaultButton = L10nKey("settings.defaultButton")
        static let chatFontSizeHelp = L10nKey("settings.chatFontSize.help")
        static let sessionSort = L10nKey("settings.sessionSort")
        static let sessionSortHelp = L10nKey("settings.sessionSort.help")
        static let behaviorSection = L10nKey("settings.behavior")
        static let historyTurns = L10nKey("settings.historyTurns")
        static let historyTurnsHelp = L10nKey("settings.historyTurns.help")
        static let chatTab = L10nKey("settings.chat.tab")
        static let webTools = L10nKey("settings.webTools")
        static let webToolsHelp = L10nKey("settings.webTools.help")
        static let toolsDisabledNote = L10nKey("settings.tools.disabledNote")
        static let fileShell = L10nKey("settings.fileShell")
        static let workspace = L10nKey("settings.workspace")
        static let workspaceDefault = L10nKey("settings.workspace.default")
        static let selectButton = L10nKey("settings.select")
        static let workspaceHelp = L10nKey("settings.workspace.help")
        static let toolsTab = L10nKey("settings.tools.tab")
    }

    // MARK: 언어 (AppLanguage.label)

    static let languageSystem = L10nKey("language.system")

    // MARK: 도구 (ToolCatalog)

    enum SkillImport {
        static let title = L10nKey("skillImport.title")
        static let searchPlaceholder = L10nKey("skillImport.search.placeholder")
        static let emptyAll = L10nKey("skillImport.empty.all")
        static let emptyQuery = L10nKey("skillImport.empty.query")
        static let counts = L10nKey("skillImport.counts")
        static let selectAll = L10nKey("skillImport.selectAll")
        static let deselectAll = L10nKey("skillImport.deselectAll")
        static let refresh = L10nKey("skillImport.refresh")
        static let installed = L10nKey("skillImport.installed")
        static let close = L10nKey("skillImport.close")
        static let importButton = L10nKey("skillImport.import")
    }

    enum ModelManager {
        static let browseTab = L10nKey("modelManager.browse.tab")
        static let myModelsTab = L10nKey("modelManager.myModels.tab")
        static let cancel = L10nKey("modelManager.cancel")
        static let deleteButton = L10nKey("modelManager.delete")
        static let installButton = L10nKey("modelManager.install")
        static let permissionInstallOff = L10nKey("modelManager.permission.installOff")
        static let permissionDeleteOff = L10nKey("modelManager.permission.deleteOff")
        static let permissionImportOff = L10nKey("modelManager.permission.importOff")
        static let installTitle = L10nKey("modelManager.install.title")
        static let installIDPlaceholder = L10nKey("modelManager.install.idPlaceholder")
        static let installConfirmTitle = L10nKey("modelManager.install.confirmTitle")
        static let installFailed = L10nKey("modelManager.install.failed")
        static let renameTitle = L10nKey("modelManager.rename.title")
        static let renameInfo = L10nKey("modelManager.rename.info")
        static let renameButton = L10nKey("modelManager.rename.button")
        static let renameFailed = L10nKey("modelManager.rename.failed")
        static let deleteModelTitle = L10nKey("modelManager.deleteModel.title")
        static let deleteModelInfo = L10nKey("modelManager.deleteModel.info")
        static let deleteModelKeepFile = L10nKey("modelManager.deleteModel.keepFile")
        static let deleteReceivedToo = L10nKey("modelManager.deleteModel.receivedToo")
        static let deleteFileTitle = L10nKey("modelManager.deleteFile.title")
        static let deleteFileIrreversible = L10nKey("modelManager.deleteFile.irreversible")
        static let deleteFileKeepsInstalled = L10nKey("modelManager.deleteFile.keepsInstalled")
        static let deleteFileFailed = L10nKey("modelManager.deleteFile.failed")
        static let badgeInstalled = L10nKey("modelManager.badge.installed")
        static let badgeNotInstalled = L10nKey("modelManager.badge.notInstalled")
        static let rowSummary = L10nKey("modelManager.row.summary")
        static let selectForChat = L10nKey("modelManager.action.selectForChat")
        static let renameDisplayName = L10nKey("modelManager.action.renameDisplayName")
        static let renameRealID = L10nKey("modelManager.action.renameRealID")
        static let runBenchmark = L10nKey("modelManager.action.runBenchmark")
        static let deleteModelMenu = L10nKey("modelManager.action.deleteModel")
        static let modelMenu = L10nKey("modelManager.menu.model")
        static let stagedMenu = L10nKey("modelManager.menu.staged")
        static let installRegistryHelp = L10nKey("modelManager.install.registryHelp")
        static let deleteFileAction = L10nKey("modelManager.action.deleteFile")
        static let incomplete = L10nKey("modelManager.incomplete")
        static let incompleteDeleteTitle = L10nKey("modelManager.incomplete.deleteTitle")
        static let resume = L10nKey("modelManager.resume")
        static let resumeHelp = L10nKey("modelManager.resume.help")
        static let redownload = L10nKey("modelManager.redownload")
        static let redownloadNotice = L10nKey("modelManager.redownload.notice")
        static let redownloadHelp = L10nKey("modelManager.redownload.help")
        static let emptyTitle = L10nKey("modelManager.empty.title")
        static let emptyDescription = L10nKey("modelManager.empty.description")
        static let sectionDownloading = L10nKey("modelManager.section.downloading")
        static let sectionIncomplete = L10nKey("modelManager.section.incomplete")
        static let sectionInstalled = L10nKey("modelManager.section.installed")
        static let sectionStaging = L10nKey("modelManager.section.staging")
        static let purgeNotice = L10nKey("modelManager.purge.notice")
        static let purgeAction = L10nKey("modelManager.purge.action")
        static let purgeConfirm = L10nKey("modelManager.purge.confirm")
        static let purgeConfirmNote = L10nKey("modelManager.purge.confirmNote")
        static let purgeFailed = L10nKey("modelManager.purge.failed")
        static let importPanelMessage = L10nKey("modelManager.import.panelMessage")
        static let importFailed = L10nKey("modelManager.import.failed")
        static let importNew = L10nKey("modelManager.import.new")
        static let importNewHelp = L10nKey("modelManager.import.newHelp")
        static let installFromFile = L10nKey("modelManager.import.fromFile")
        static let installFromFileHelp = L10nKey("modelManager.import.fromFileHelp")
        static let openFolder = L10nKey("modelManager.openFolder")
        static let openFolderHelp = L10nKey("modelManager.openFolder.help")
        static let refresh = L10nKey("modelManager.refresh")
        static let refreshHelp = L10nKey("modelManager.refresh.help")
        static let stagingNote = L10nKey("modelManager.staging.note")
        static let continueButton = L10nKey("modelManager.continue")
    }

    enum Download {
        static let inProgress = L10nKey("download.inProgress")
        static let elapsed = L10nKey("download.elapsed")
        static let remaining = L10nKey("download.remaining")
        static let finished = L10nKey("download.finished")
        static let cancelled = L10nKey("download.cancelled")
        static let paused = L10nKey("download.paused")
        static let delete = L10nKey("download.delete")
        static let restart = L10nKey("download.restart")
        static let restartHelp = L10nKey("download.restart.help")
        static let resume = L10nKey("download.resume")
        static let cancel = L10nKey("download.cancel")
        static let pause = L10nKey("download.pause")
        static let cancelHelp = L10nKey("download.cancel.help")
        static let deleteActiveConfirm = L10nKey("download.delete.activeConfirm")
        static let deleteIdleConfirm = L10nKey("download.delete.idleConfirm")
        static let deleteActiveNote = L10nKey("download.delete.activeNote")
        static let authRequired = L10nKey("download.error.authRequired")
        static let notFound = L10nKey("download.error.notFound")
        static let httpStatus = L10nKey("download.error.httpStatus")
    }

    enum MCP {
        static let emptyServers = L10nKey("mcp.empty")
        static let test = L10nKey("mcp.test")
        static let delete = L10nKey("mcp.delete")
        static let addServer = L10nKey("mcp.add")
        static let addNote = L10nKey("mcp.add.note")
        static let noSkillMD = L10nKey("skill.noSkillMD")
        static let externalRoots = L10nKey("skill.externalRoots")
        static let remove = L10nKey("skill.remove")
        static let openFolder = L10nKey("skill.openFolder")
        static let addFolder = L10nKey("skill.addFolder")
        static let importButton = L10nKey("skill.import")
        static let refresh = L10nKey("skill.refresh")
        static let prefixNote = L10nKey("skill.prefixNote")
        static let tab = L10nKey("skill.tab")
        static let addButton = L10nKey("skillRoots.add")
        static let pickFolderMessage = L10nKey("skillRoots.pickMessage")
        static let checking = L10nKey("exa.checking")
        static let keyMissing = L10nKey("exa.key.missing")
        static let keySet = L10nKey("exa.key.set")
        static let getKey = L10nKey("exa.key.get")
        static let keyPlaceholder = L10nKey("exa.key.placeholder")
        static let keyFooter = L10nKey("exa.key.footer")
        static let emptyResult = L10nKey("exa.test.empty")
        static let success = L10nKey("exa.test.success")
        static let failure = L10nKey("exa.test.failure")
        static let successPrefix = L10nKey("exa.test.successPrefix")
        static let addTitle = L10nKey("mcpAdd.title")
        static let namePlaceholder = L10nKey("mcpAdd.name")
        static let transport = L10nKey("mcpAdd.transport")
        static let stdio = L10nKey("mcpAdd.stdio")
        static let sse = L10nKey("mcpAdd.sse")
        static let commandPlaceholder = L10nKey("mcpAdd.command")
        static let argsPlaceholder = L10nKey("mcpAdd.args")
        static let urlPlaceholder = L10nKey("mcpAdd.url")
        static let cancel = L10nKey("mcpAdd.cancel")
        static let save = L10nKey("mcpAdd.save")
        static let connected = L10nKey("mcp.connected")
        static let failed = L10nKey("mcp.failed")
    }

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
}
