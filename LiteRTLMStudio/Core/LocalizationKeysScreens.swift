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
}
