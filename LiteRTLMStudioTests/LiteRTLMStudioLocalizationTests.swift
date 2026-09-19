import XCTest
@testable import LiteRTLMStudio

/// 테스트는 시스템 언어와 무관하게 결정적이어야 하므로 한국어를 기본으로 고정한다.
/// 영어 문구는 각 테스트에서 `setAppLanguageForTesting(.en)`으로 명시 전환한다.
class LiteRTLMStudioTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        setAppLanguageForTesting(.ko)
    }
}

/// 다국어 커버리지 (T-361·T-362): 카탈로그 키가 ko·en 양쪽에 모두 있는지 검증.
/// `L()`은 키가 없으면 키 원문을 그대로 노출하므로, 이 테스트가 누락 안전망이다.
final class LiteRTLMStudioLocalizationTests: LiteRTLMStudioTestCase {

    /// 앱 번들의 `.lproj/Localizable.strings` 로드 (테스트는 앱을 호스트로 실행).
    private func strings(for language: String) -> [String: String]? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path),
              let url = bundle.url(forResource: "Localizable", withExtension: "strings"),
              let table = NSDictionary(contentsOf: url) as? [String: String]
        else { return nil }
        return table
    }

    func testCatalogCoversKoreanAndEnglish() throws {
        let ko = try XCTUnwrap(strings(for: "ko"), "ko.lproj/Localizable.strings 없음")
        let en = try XCTUnwrap(strings(for: "en"), "en.lproj/Localizable.strings 없음")
        XCTAssertFalse(ko.isEmpty, "카탈로그가 비어 있음")
        XCTAssertTrue(Set(ko.keys).subtracting(en.keys).isEmpty,
                      "영어 누락: \(Set(ko.keys).subtracting(en.keys).sorted())")
        XCTAssertTrue(Set(en.keys).subtracting(ko.keys).isEmpty,
                      "한국어 누락: \(Set(en.keys).subtracting(ko.keys).sorted())")
    }

    func testEnglishValuesAreTranslated() throws {
        let en = try XCTUnwrap(strings(for: "en"))
        let untranslated = en.filter { $0.value.isEmpty || $0.value == $0.key }
        XCTAssertTrue(untranslated.isEmpty, "미번역: \(untranslated.keys.sorted())")
    }

    func testLanguageSelectionParsing() {
        XCTAssertEqual(AppLanguage(rawValue: "system"), .system)
        XCTAssertEqual(AppLanguage(rawValue: "ko"), .ko)
        XCTAssertEqual(AppLanguage(rawValue: "en"), .en)
        XCTAssertNil(AppLanguage(rawValue: "zz"))
    }

    /// 시스템 표면(권한 설명)은 `InfoPlist.xcstrings`가 담당한다 (T-366).
    /// Info.plist가 값이 아니라 키로 조회되므로 ko·en 양쪽 존재를 고정한다.
    func testInfoPlistPermissionStringsAreLocalized() throws {
        let keys = ["NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription",
                    "NSRemindersUsageDescription", "NSRemindersFullAccessUsageDescription"]
        for language in ["ko", "en"] {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path),
                  let url = bundle.url(forResource: "InfoPlist", withExtension: "strings"),
                  let table = NSDictionary(contentsOf: url) as? [String: String]
            else { return XCTFail("\(language).lproj/InfoPlist.strings 없음") }
            for key in keys {
                XCTAssertFalse(table[key]?.isEmpty ?? true, "\(language) 누락: \(key)")
            }
        }
    }

    /// 선택 언어에 맞는 번들이 잡히는지 (키 원문이 아니라 번역문이 나와야 한다).
    func testLookupResolvesSelectedLanguage() {
        setAppLanguageForTesting(.ko)
        XCTAssertEqual(L(L10n.Settings.generalTab), "일반")
        XCTAssertEqual(L(L10n.Tools.categoryWeb), "웹")
        setAppLanguageForTesting(.en)
        XCTAssertEqual(L(L10n.Settings.generalTab), "General")
        XCTAssertEqual(L(L10n.Tools.categoryWeb), "Web")
    }

    /// 등록된 키 전수: 두 언어 모두 값이 있고 키 원문이 노출되지 않는다.
    func testRegisteredKeysAreResolvable() {
        let keys = L10n.allKeys
        XCTAssertGreaterThan(keys.count, 100)
        for language in [AppLanguage.ko, .en] {
            setAppLanguageForTesting(language)
            for key in keys {
                XCTAssertNotEqual(L(key), key.raw, "\(language.rawValue) 미해석: \(key.raw)")
            }
        }
    }

    /// 인자 있는 포맷 키가 언어별로 올바르게 치환되는지.
    func testFormattedKeys() {
        setAppLanguageForTesting(.ko)
        XCTAssertEqual(L(L10n.Time.minutesAgo, 3), "3분 전")
        XCTAssertEqual(L(L10n.Benchmark.elapsedMinutes, 1, 30), "1분 30초")
        XCTAssertEqual(L(L10n.MenuBar.uptimeSeconds, 45), "가동 45초")
        setAppLanguageForTesting(.en)
        XCTAssertEqual(L(L10n.Time.minutesAgo, 3), "3 min ago")
        XCTAssertEqual(L(L10n.Benchmark.elapsedMinutes, 1, 30), "1m 30s")
        XCTAssertEqual(L(L10n.MenuBar.uptimeSeconds, 45), "Up 45s")
    }

    /// 영어 전환 시 순수 헬퍼도 함께 바뀌는지 (T-362).
    func testPureHelpersFollowLanguage() {
        setAppLanguageForTesting(.en)
        XCTAssertEqual(ToolCatalog.title(for: "get_system_info"), "System info")
        XCTAssertEqual(InspectorDefaults.systemSummary(live: false), "Stopped")
        XCTAssertEqual(ModelAlias.modalities("Text Vision"), "Text·Image")
        XCTAssertEqual(chatRelativeTime(from: Date(), now: Date()), "Just now")
    }
}
