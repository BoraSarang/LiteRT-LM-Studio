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
        static let save = L10nKey("common.save")
        static let delete = L10nKey("common.delete")
    }

    // MARK: 환경·랜딩

    enum Env {
        static let checking = L10nKey("env.checking")
        static let missing = L10nKey("env.missing")
    }

    enum Landing {
        static let checking = L10nKey("landing.checking")
        static let uvMissing = L10nKey("landing.uvMissing")
        static let litertOld = L10nKey("landing.litertOld")
        static let litertMissing = L10nKey("landing.litertMissing")
        static let recheck = L10nKey("landing.recheck")
        static let start = L10nKey("landing.start")
        static let copy = L10nKey("landing.copy")
    }

    // MARK: 메인·채팅

    enum Chat {
        static let newChat = L10nKey("chat.newChat")
        static let selectModel = L10nKey("chat.selectModel")
        static let pickModel = L10nKey("chat.pickModel")
        static let emptyNativeTitle = L10nKey("chat.empty.native.title")
        static let emptyNativeMessage = L10nKey("chat.empty.native.message")
        static let emptyServerTitle = L10nKey("chat.empty.server.title")
        static let emptyServerMessage = L10nKey("chat.empty.server.message")
        static let copyQuestion = L10nKey("chat.copy.question")
        static let editResend = L10nKey("chat.edit.resend")
        static let waitingFirstTokenSeconds = L10nKey("chat.waitingFirstToken.seconds")
        static let waitingFirstToken = L10nKey("chat.waitingFirstToken")
        static let responding = L10nKey("chat.responding")
        static let copyAnswer = L10nKey("chat.copy.answer")
        static let retry = L10nKey("chat.retry")
        static let reasoningActive = L10nKey("chat.reasoning.active")
        static let reasoningTitle = L10nKey("chat.reasoning.title")
        static let reasoningExpand = L10nKey("chat.reasoning.expand")
        static let reasoningGenerating = L10nKey("chat.reasoning.generating")
        static let imageAttachment = L10nKey("chat.imageAttachment")
        static let scrollToLatest = L10nKey("chat.scrollToLatest")
    }

    enum ToolCall {
        static let help = L10nKey("toolCall.help")
        static let showFormatted = L10nKey("toolCall.showFormatted")
        static let showRaw = L10nKey("toolCall.showRaw")
        static let openInBrowser = L10nKey("toolCall.openInBrowser")
    }

    enum Input {
        static let removeAttachment = L10nKey("input.removeAttachment")
        static let placeholder = L10nKey("input.placeholder")
        static let attachImage = L10nKey("input.attachImage")
        static let noModel = L10nKey("input.noModel")
        static let noModelHelp = L10nKey("input.noModelHelp")
        static let modelPicker = L10nKey("input.modelPicker")
        static let modelPickerHelp = L10nKey("input.modelPickerHelp")
        static let routePicker = L10nKey("input.routePicker")
        static let routePickerHelp = L10nKey("input.routePickerHelp")
        static let stop = L10nKey("input.stop")
        static let send = L10nKey("input.send")
        static let sendHelp = L10nKey("input.sendHelp")
        static let sendHelpNative = L10nKey("input.sendHelp.native")
        static let sendHelpServer = L10nKey("input.sendHelp.server")
        static let attachedOriginal = L10nKey("input.attachedOriginal")
    }
}
