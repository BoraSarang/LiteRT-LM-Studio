import Foundation

/// 도구 실행 결정 (T-266 S-2): 진행·거부(사유 포함).
enum ToolDecision: Sendable, Equatable {
    case proceed
    case denied(String)
}

/// 로컬 안전 도구 묶음 (T-266 S-2): 현재시각·사칙계산. 부작용 없음.
/// T-269: 웹 검색·가져오기 추가 (토글 꺼지면 제외).
enum LocalTools {
    /// 권한별 등록 목록 (순수, 테스트 가능): Off면 빈 배열 (모델이 호출 불가).
    nonisolated static func registered(
        permission: GlobalPermission = GlobalPermission.current()
    ) -> [any Tool] {
        guard permission != .off else { return [] }
        var tools: [any Tool] = [GetTimeTool(), CalculatorTool()]
        if WebSearch.enabled() {
            tools += [WebSearchTool(), WebFetchTool()]
        }
        return tools
    }

    /// 실행 결정 (T-266 S-2): Off·거부·타임아웃은 거부, Allow는 진행, Ask는 승인 대기.
    static func decide(toolName: String, detail: String,
                       permission: GlobalPermission = GlobalPermission.current()) async -> ToolDecision {
        switch permission {
        case .off:
            return .denied("도구 사용이 꺼져 있습니다. 설정에서 권한을 바꿔 주세요.")
        case .allowAll:
            return .proceed
        case .ask:
            let allow = await ToolApproval.shared.request(toolName: toolName, detail: detail)
            return allow ? .proceed : .denied("사용자가 도구 실행을 거부했습니다.")
        }
    }

    /// 승인 후 실행 래퍼 (T-266 S-2): 거부·실패는 모델 전달 문자열로 (스트림 유지).
    static func runTolled(
        toolName: String,
        detail: String,
        permission: GlobalPermission = GlobalPermission.current(),
        execute: () async throws -> Any
    ) async -> Any {
        switch await decide(toolName: toolName, detail: detail, permission: permission) {
        case .proceed:
            do {
                let result = try await execute()
                let summary = summarize(result)
                await ToolLedger.shared.record(toolName: toolName, detail: detail,
                                               result: summary, denied: false)
                return result
            } catch {
                let message = "도구 실행 실패: \(error.localizedDescription)"
                await ToolLedger.shared.record(toolName: toolName, detail: detail,
                                               result: message, denied: false, failed: true)
                DebugLogger.shared.error(code: "E-MAC-ENG-0004", feature: "도구",
                                         "\(toolName) 실패: \(error)")
                return message
            }
        case .denied(let reason):
            await ToolLedger.shared.record(toolName: toolName, detail: detail,
                                           result: reason, denied: true)
            DebugLogger.shared.info(feature: "도구", "\(toolName) 거부됨")
            return reason
        }
    }

    /// 결과 요약 (순수): 100자 절단.
    nonisolated static func summarize(_ result: Any) -> String {
        String(describing: result).prefix(100).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 현재시각 도구 (T-266 S-2): 파라미터 없음.
struct GetTimeTool: Tool {
    static let name = "get_time"
    static let description = "현재 날짜와 시각을 알려줍니다. 시간 질문에 사용하세요."

    func run() async throws -> Any {
        await LocalTools.runTolled(toolName: Self.name, detail: "현재시각 조회") {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ko_KR")
            f.dateFormat = "yyyy년 M월 d일 EEEE HH시 mm분"
            return f.string(from: Date())
        }
    }
}

/// 사칙계산 도구 (T-266 S-2): 단일 수식 문자열.
struct CalculatorTool: Tool {
    static let name = "calculate"
    static let description = "사칙연산 수식을 계산합니다. 숫자와 + - * / ( ) 만 사용하세요."

    @ToolParam(description: "계산할 수식 (예: (1+2)*3)")
    var expression = ""

    func run() async throws -> Any {
        let expr = expression
        return await LocalTools.runTolled(toolName: Self.name, detail: expr) {
            let value = try CalcParser.evaluate(expr)
            if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
                return String(Int(value))
            }
            return String(value)
        }
    }
}

/// 계산 오류 (T-266 S-2).
enum CalcError: Error, Equatable {
    case emptyExpression
    case invalidCharacter(Character)
    case unexpectedEnd
    case divideByZero
    case trailingGarbage(String)
}

/// 사칙연산 파서 (T-266 S-2, 순수·테스트 가능): 재귀 하강, + - * / ( ) 소수·단항 마이너스.
enum CalcParser {
    nonisolated static func evaluate(_ source: String) throws -> Double {
        var parser = Parser(tokens: Array(source.filter { !$0.isWhitespace }))
        guard !parser.tokens.isEmpty else { throw CalcError.emptyExpression }
        let value = try parser.expr()
        guard parser.pos == parser.tokens.count else {
            throw CalcError.trailingGarbage(String(parser.tokens[parser.pos...]))
        }
        return value
    }

    private struct Parser {
        let tokens: [Character]
        var pos = 0

        mutating func expr() throws -> Double {
            var value = try term()
            while let op = peek(), op == "+" || op == "-" {
                pos += 1
                let rhs = try term()
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() throws -> Double {
            var value = try factor()
            while let op = peek(), op == "*" || op == "/" {
                pos += 1
                let rhs = try factor()
                if op == "/" {
                    guard rhs != 0 else { throw CalcError.divideByZero }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        mutating func factor() throws -> Double {
            guard let ch = peek() else { throw CalcError.unexpectedEnd }
            if ch == "-" {
                pos += 1
                return -(try factor())
            }
            if ch == "(" {
                pos += 1
                let value = try expr()
                guard peek() == ")" else { throw CalcError.unexpectedEnd }
                pos += 1
                return value
            }
            return try number()
        }

        mutating func number() throws -> Double {
            var text = ""
            var dots = 0
            while let ch = peek(), ch.isNumber || ch == "." {
                if ch == "." {
                    dots += 1
                    guard dots <= 1 else { break }
                }
                text.append(ch)
                pos += 1
            }
            guard let value = Double(text) else {
                if let ch = peek() { throw CalcError.invalidCharacter(ch) }
                throw CalcError.unexpectedEnd
            }
            return value
        }

        func peek() -> Character? {
            pos < tokens.count ? tokens[pos] : nil
        }
    }
}
