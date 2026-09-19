import Foundation

/// 오류 코드 → 표시 문구 대조표 (T-366).
///
/// T-002의 `error_message_ko.json`을 카탈로그로 이관했다. 키는 `error.<코드>`이고
/// 문구는 `L()`이 선택 언어로 해석한다. 화면에 나가는 맥락별 오류 문구(`chatError.*` 등)는
/// 코드를 덧붙여 따로 관리하지만, 코드만 알 때의 ko/en 대조는 이 표 하나로 유지한다.
enum ErrorCatalog {
    /// 코드 오름차순 전체 목록.
    static let codes: [String] = [
        "E-MAC-ENG-0001", "E-MAC-ENG-0002", "E-MAC-ENG-0003", "E-MAC-ENG-0004",
        "E-MAC-ENG-0005", "E-MAC-ENG-0006",
        "E-MAC-EXEC-0001", "E-MAC-EXEC-0002",
        "E-MAC-NET-0002", "E-MAC-NET-0004", "E-MAC-NET-0005", "E-MAC-NET-0006",
        "E-MAC-NET-0010", "E-MAC-NET-0013", "E-MAC-NET-0014", "E-MAC-NET-0015",
        "E-MAC-NET-0016",
        "E-MAC-PERM-0011", "E-MAC-PERM-0016",
        "E-MAC-STOR-0003", "E-MAC-STOR-0006", "E-MAC-STOR-0009", "E-MAC-STOR-0012",
        "E-MAC-STOR-0013", "E-MAC-STOR-0014",
        "E-MAC-VALID-0001", "E-MAC-VALID-0007", "E-MAC-VALID-0008", "E-MAC-VALID-0017"
    ]

    static func key(_ code: String) -> L10nKey { L10nKey("error.\(code)") }

    /// 선택 언어의 문구 (미등록 키면 키 원문이 나온다).
    static func message(_ code: String) -> String { L(key(code)) }
}
