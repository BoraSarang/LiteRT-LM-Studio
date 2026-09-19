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
}
