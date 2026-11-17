import Foundation

public enum MoneyFormatter {
    public static func formatYuan(cents: Int64, includeSymbol: Bool = true, showFractionIfWhole: Bool = true) -> String {
        let negative = cents < 0
        let absCents = abs(cents)
        let whole = absCents / 100
        let frac = absCents % 100
        let prefix = (negative ? "-" : "") + (includeSymbol ? "¥" : "")

        let wholeStr: String
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.locale = Locale(identifier: "en_US")
        wholeStr = formatter.string(from: NSNumber(value: whole)) ?? "\(whole)"

        if frac == 0 && !showFractionIfWhole {
            return "\(prefix)\(wholeStr)"
        }
        return String(format: "%@%@.%02lld", prefix, wholeStr, frac)
    }

    public static func formatPlainDecimal(cents: Int64) -> String {
        let sign = cents < 0 ? "-" : ""
        let absCents = abs(cents)
        return String(format: "%@%lld.%02lld", sign, absCents / 100, absCents % 100)
    }

    public static func parseToCents(_ raw: String) -> Int64? {
        let trimmed = raw
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let evaluated = evaluateArithmetic(trimmed) {
            guard evaluated.isFinite, abs(evaluated) < 9_000_000_000_000 else { return nil }
            return Int64((evaluated * 100.0).rounded())
        }
        return nil
    }

    /// Evaluates simple inline keypad arithmetic such as "35 + 12.5 * 2" safely.
    public static func evaluateArithmetic(_ expression: String) -> Double? {
        let cleaned = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }

        var index = cleaned.startIndex
        func peek() -> Character? {
            index < cleaned.endIndex ? cleaned[index] : nil
        }
        func advance() {
            if index < cleaned.endIndex {
                index = cleaned.index(after: index)
            }
        }
        func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while let ch = peek(), ch == "+" || ch == "-" {
                advance()
                guard let rhs = parseTerm() else { return nil }
                lhs = ch == "+" ? (lhs + rhs) : (lhs - rhs)
            }
            return lhs
        }
        func parseTerm() -> Double? {
            guard var lhs = parseFactor() else { return nil }
            while let ch = peek(), ch == "*" || ch == "/" {
                advance()
                guard let rhs = parseFactor() else { return nil }
                if ch == "/" {
                    if abs(rhs) < 1e-12 { return nil }
                    lhs /= rhs
                } else {
                    lhs *= rhs
                }
            }
            return lhs
        }
        func parseFactor() -> Double? {
            if peek() == "+" {
                advance()
                return parseFactor()
            }
            if peek() == "-" {
                advance()
                guard let val = parseFactor() else { return nil }
                return -val
            }
            if peek() == "(" {
                advance()
                guard let inner = parseExpression(), peek() == ")" else { return nil }
                advance()
                return inner
            }
            let start = index
            var sawDot = false
            while let ch = peek(), ch.isNumber || (ch == "." && !sawDot) {
                if ch == "." { sawDot = true }
                advance()
            }
            guard start < index else { return nil }
            return Double(cleaned[start..<index])
        }

        guard let value = parseExpression(), index == cleaned.endIndex, value.isFinite else {
            return nil
        }
        return value
    }
}
