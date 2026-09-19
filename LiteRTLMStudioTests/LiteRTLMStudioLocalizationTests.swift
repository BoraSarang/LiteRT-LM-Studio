import XCTest
@testable import LiteRTLMStudio

/// 다국어 커버리지 (T-361): 카탈로그 키가 ko·en 양쪽에 모두 있는지 검증.
/// `L()`은 키가 없으면 키 원문을 그대로 노출하므로, 이 테스트가 누락 안전망이다.
final class LiteRTLMStudioLocalizationTests: XCTestCase {

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

    /// 선택 언어에 맞는 번들이 잡히는지 (키 원문이 아니라 번역문이 나와야 한다).
    func testLookupResolvesSelectedLanguage() throws {
        let ko = try XCTUnwrap(strings(for: "ko")?["settings.general.tab"])
        let en = try XCTUnwrap(strings(for: "en")?["settings.general.tab"])
        XCTAssertEqual(ko, "일반")
        XCTAssertEqual(en, "General")
    }
}
