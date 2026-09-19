import Foundation
import SwiftUI

// MARK: - 지원 언어 (T-361)

/// 지원 언어. 기본은 시스템 언어 추종.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case ko
    case en

    var id: String { rawValue }

    /// 시스템 선호 언어 해석 (지원 2종 고정: 한국어만 ko, 그 외 en).
    static var systemResolved: AppLanguage {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ko") ? .ko : .en
    }

    /// 선택지 표기. 한국어·영어는 자기 언어로 적고, 시스템만 번역한다.
    var label: String {
        switch self {
        case .system: return L(L10n.languageSystem)
        case .ko: return "한국어"
        case .en: return "English"
        }
    }
}

// MARK: - 키

/// 시맨틱 키 값. 오타는 컴파일러가 아니라 커버리지 테스트가 잡는다.
struct L10nKey: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let raw: String

    init(_ raw: String) { self.raw = raw }
    init(stringLiteral value: String) { self.raw = value }

    var description: String { raw }
}

// MARK: - 조회 (nonisolated)

/// 언어 상태 저장소. SwiftUI 밖(순수 헬퍼·AppKit·테스트)에서도 읽히므로 잠금으로 보호한다.
private final class LanguageStore: @unchecked Sendable {
    static let shared = LanguageStore()

    private let lock = NSLock()
    private var language: AppLanguage = AppLanguage.systemResolved

    var current: AppLanguage {
        lock.lock(); defer { lock.unlock() }
        return language
    }

    func set(_ language: AppLanguage) {
        lock.lock(); defer { lock.unlock() }
        self.language = language
    }

    /// 선택 언어 리소스 번들 (`ko.lproj`/`en.lproj`). 없으면 메인.
    var bundle: Bundle {
        let code = current.rawValue
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    var locale: Locale { Locale(identifier: current.rawValue) }

    func string(_ key: String, _ args: [CVarArg]) -> String {
        // 키가 없으면 키 원문이 노출된다 — 커버리지 테스트가 누락을 잡는다.
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: args)
    }
}

/// 현재 언어로 문자열 조회. SwiftUI 밖(순수 헬퍼·AppKit)에서도 사용한다.
func L(_ key: L10nKey, _ args: CVarArg...) -> String {
    LanguageStore.shared.string(key.raw, args)
}

/// 현재 선택 언어의 로케일 (순수 헬퍼의 `DateFormatter` 등).
nonisolated var appLocale: Locale { LanguageStore.shared.locale }

/// 테스트 전용: 언어를 고정한다. `UserDefaults`·`AppleLanguages`는 건드리지 않는다.
func setAppLanguageForTesting(_ language: AppLanguage) {
    LanguageStore.shared.set(language)
}

/// SwiftUI 본문용.
func T(_ key: L10nKey, _ args: CVarArg...) -> Text {
    Text(LanguageStore.shared.string(key.raw, args))
}

/// `LocalizedStringKey`가 필요한 자리(scene·command 제목)에서 사용.
/// 이미 번역된 값을 키로 삼아 조회하므로 미스 시에도 번역문이 그대로 나온다.
func LK(_ key: L10nKey) -> LocalizedStringKey {
    LocalizedStringKey(LanguageStore.shared.string(key.raw, []))
}

// MARK: - 전환 (MainActor)

/// 언어 설정 보관·적용. 변경하면 루트가 리빌드되어 즉시 반영된다.
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    /// 즉시 반영이 어려운 AppKit 표면(창 제목·상태 아이템) 재적용용.
    static let didChange = Notification.Name("com.borasarang.litert-lm-studio.languageDidChange")

    private static let selectionKey = "appLanguage"

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            apply()
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.selectionKey) ?? ""
        selection = AppLanguage(rawValue: raw) ?? .system
        LanguageStore.shared.set(resolved)
    }

    /// 실제 적용 언어 (system이면 시스템 선호에서 해석).
    var resolved: AppLanguage {
        selection == .system ? AppLanguage.systemResolved : selection
    }

    var locale: Locale { LanguageStore.shared.locale }

    private func apply() {
        UserDefaults.standard.set(selection.rawValue, forKey: Self.selectionKey)
        LanguageStore.shared.set(resolved)
        // 권한 대화상자 등 OS 소유 문구는 다음 실행 때 맞춰진다.
        if selection == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([resolved.rawValue], forKey: "AppleLanguages")
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

extension View {
    /// T-361: 언어 설정을 뷰 트리에 주입. 바뀌면 `.id`로 트리를 다시 만들어 즉시 반영한다.
    @MainActor func languageAware(_ manager: LanguageManager) -> some View {
        environment(\.locale, manager.locale)
            .id(manager.resolved)
    }
}
