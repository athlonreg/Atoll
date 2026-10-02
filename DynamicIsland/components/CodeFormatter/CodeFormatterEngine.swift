/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

// MARK: - Outcomes

/// A formatter failure carrying a message that is safe to surface in the UI.
struct CodeFormatterFailure: Error {
    let message: String
}

struct CodeFormatterResult {
    /// Formatted text on success; the untouched source on failure.
    let output: String
    let isValid: Bool
    let message: String?

    static func success(_ output: String) -> CodeFormatterResult {
        CodeFormatterResult(output: output, isValid: true, message: nil)
    }

    static func failure(_ message: String, fallback: String) -> CodeFormatterResult {
        CodeFormatterResult(output: fallback, isValid: false, message: message)
    }
}

// MARK: - Engine

enum CodeFormatterEngine {
    /// Formats `source` according to `language`, pretty-printing it.
    static func format(
        _ source: String,
        language: CodeFormatterLanguage,
        indentWidth: Int = 2,
        uppercaseSQLKeywords: Bool = true
    ) -> CodeFormatterResult {
        let width = Self.clampedWidth(indentWidth)
        let trimmed = Self.normalizedSource(source)
        guard !trimmed.isEmpty else {
            return .failure(String(localized: "Nothing to format yet."), fallback: "")
        }

        switch language {
        case .json:
            return Self.runJSON(trimmed, width: width, compact: false)
        case .yaml:
            return .success(YAMLReindenter(indentWidth: width).reindent(trimmed))
        case .sql:
            return Self.runSQL(trimmed, width: width, uppercase: uppercaseSQLKeywords)
        case .html:
            return MarkupFormatter.format(trimmed, language: .html, width: width)
        case .xml:
            return MarkupFormatter.format(trimmed, language: .xml, width: width)
        case .css:
            return .success(CSSFormatter.format(trimmed, width: width))
        case .javascript:
            return .success(JSFormatter.format(trimmed, width: width))
        }
    }

    /// Collapses `source` into its most compact legal form for `language`.
    static func minify(_ source: String, language: CodeFormatterLanguage) -> CodeFormatterResult {
        let trimmed = Self.normalizedSource(source)
        guard !trimmed.isEmpty else {
            return .failure(String(localized: "Nothing to minify yet."), fallback: "")
        }

        switch language {
        case .json:
            return Self.runJSON(trimmed, width: 2, compact: true)
        case .yaml:
            // YAML has no safe single-line form: compact means stripping blank lines.
            return .success(YAMLReindenter(indentWidth: 2, dropBlankLines: true).reindent(trimmed))
        case .sql:
            return Self.runSQL(trimmed, width: 2, uppercase: false, compact: true)
        case .html:
            return MarkupFormatter.minify(trimmed, language: .html)
        case .xml:
            return MarkupFormatter.minify(trimmed, language: .xml)
        case .css:
            return .success(CSSFormatter.minify(trimmed))
        case .javascript:
            return .success(JSFormatter.minify(trimmed))
        }
    }

    /// Languages where minifying has a meaningful, well-defined result.
    static var minifiableLanguages: Set<CodeFormatterLanguage> {
        [.json, .sql, .html, .xml, .css, .javascript]
    }

    // MARK: Private plumbing

    private static func clampedWidth(_ value: Int) -> Int {
        min(max(value, 1), 8)
    }

    /// Trims surrounding noise and normalises line endings so downstream
    /// scanners only ever see `\n`.
    private static func normalizedSource(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runJSON(_ source: String, width: Int, compact: Bool) -> CodeFormatterResult {
        do {
            var parser = JSONParser(source)
            let value = try parser.parseDocument()
            return .success(JSONWriter.write(value, indentWidth: width, compact: compact))
        } catch let failure as CodeFormatterFailure {
            return .failure(failure.message, fallback: source)
        } catch {
            return .failure(error.localizedDescription, fallback: source)
        }
    }

    private static func runSQL(
        _ source: String,
        width: Int,
        uppercase: Bool,
        compact: Bool = false
    ) -> CodeFormatterResult {
        let tokens = SQLTokenizer(source).tokenize()
        guard !tokens.isEmpty else {
            return .failure(String(localized: "Nothing to format yet."), fallback: source)
        }
        let output = SQLRenderer(indentWidth: width, uppercaseKeywords: uppercase, compact: compact)
            .render(tokens)
        return .success(output)
    }
}

/// Indentation helper shared by every formatter.
private func indentString(_ levels: Int, width: Int) -> String {
    guard levels > 0 else { return "" }
    return String(repeating: " ", count: levels * width)
}

// MARK: - JSON

private enum JSONValue {
    case null
    case boolean(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])
}

private struct JSONParser {
    private let chars: [Character]
    private var pos: Int = 0

    init(_ text: String) {
        chars = Array(text)
    }

    private var isAtEnd: Bool { pos >= chars.count }

    private func peek(_ offset: Int = 0) -> Character? {
        let idx = pos + offset
        return idx < chars.count ? chars[idx] : nil
    }

    private mutating func advance(_ count: Int = 1) {
        pos += count
    }

    private mutating func skipWhitespace() {
        while let c = peek(), c == " " || c == "\n" || c == "\r" || c == "\t" {
            advance()
        }
    }

    mutating func parseDocument() throws -> JSONValue {
        skipWhitespace()
        guard !isAtEnd else { throw CodeFormatterFailure(message: Self.emptyMessage) }
        let value = try parseValue()
        skipWhitespace()
        if !isAtEnd {
            throw CodeFormatterFailure(message: at("unexpected trailing content"))
        }
        return value
    }

    private static var emptyMessage: String {
        String(localized: "Nothing to format yet.")
    }

    private func at(_ detail: String) -> String {
        String(localized: "Invalid JSON: \(detail) at character \(pos + 1).")
    }

    private mutating func parseValue() throws -> JSONValue {
        guard let c = peek() else {
            throw CodeFormatterFailure(message: at("unexpected end of input"))
        }
        switch c {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return .string(try parseString())
        case "t": try expect("true"); return .boolean(true)
        case "f": try expect("false"); return .boolean(false)
        case "n": try expect("null"); return .null
        default: return .number(try parseNumber())
        }
    }

    private mutating func expect(_ literal: String) throws {
        for ch in literal {
            guard peek() == ch else {
                throw CodeFormatterFailure(message: at("expected “\(literal)”"))
            }
            advance()
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        advance() // {
        var members: [(key: String, value: JSONValue)] = []
        skipWhitespace()
        if peek() == "}" {
            advance()
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard peek() == "\"" else {
                throw CodeFormatterFailure(message: at("expected a quoted key"))
            }
            let key = try parseString()
            skipWhitespace()
            guard peek() == ":" else {
                throw CodeFormatterFailure(message: at("expected “:” after key “\(key)”"))
            }
            advance()
            skipWhitespace()
            members.append((key: key, value: try parseValue()))
            skipWhitespace()
            guard let c = peek() else {
                throw CodeFormatterFailure(message: at("unterminated object"))
            }
            if c == "," {
                advance()
                members.reserveCapacity(members.count + 4)
                continue
            }
            if c == "}" {
                advance()
                return .object(members)
            }
            throw CodeFormatterFailure(message: at("expected “,” or “}”"))
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        advance() // [
        var values: [JSONValue] = []
        skipWhitespace()
        if peek() == "]" {
            advance()
            return .array(values)
        }
        while true {
            skipWhitespace()
            values.append(try parseValue())
            skipWhitespace()
            guard let c = peek() else {
                throw CodeFormatterFailure(message: at("unterminated array"))
            }
            if c == "," {
                advance()
                continue
            }
            if c == "]" {
                advance()
                return .array(values)
            }
            throw CodeFormatterFailure(message: at("expected “,” or “]”"))
        }
    }

    private mutating func parseString() throws -> String {
        guard peek() == "\"" else {
            throw CodeFormatterFailure(message: at("expected a string"))
        }
        advance()
        var result = ""
        while let c = peek() {
            if c == "\"" {
                advance()
                return result
            }
            if c == "\\" {
                advance()
                guard let escape = peek() else { break }
                advance()
                switch escape {
                case "\"": result += "\""
                case "\\": result += "\\"
                case "/": result += "/"
                case "b": result += "\u{08}"
                case "f": result += "\u{0C}"
                case "n": result += "\n"
                case "r": result += "\r"
                case "t": result += "\t"
                case "u":
                    let first = try parseHexQuad()
                    var codepoint = UInt32(first)
                    if (0xD800...0xDBFF).contains(first), peek() == "\\", peek(1) == "u" {
                        let saved = pos
                        advance(2)
                        if let second = try? parseHexQuad(), (0xDC00...0xDFFF).contains(second) {
                            codepoint = 0x10_000 + UInt32((first - 0xD800) * 0x400 + (second - 0xDC00))
                        } else {
                            pos = saved
                        }
                    }
                    if let scalar = Unicode.Scalar(codepoint) {
                        result.unicodeScalars.append(scalar)
                    }
                default:
                    throw CodeFormatterFailure(message: at("unknown escape “\\\(escape)”"))
                }
                continue
            }
            result.append(c)
            advance()
        }
        throw CodeFormatterFailure(message: at("unterminated string"))
    }

    private mutating func parseHexQuad() throws -> Int {
        var value = 0
        for _ in 0..<4 {
            guard let c = peek(), let digit = c.hexDigitValue else {
                throw CodeFormatterFailure(message: at("invalid “\\u” escape"))
            }
            value = value * 16 + digit
            advance()
        }
        return value
    }

    private mutating func parseNumber() throws -> String {
        let start = pos
        if let c = peek(), c == "-" || c == "+" { advance() }
        var digits = 0
        while let c = peek() {
            if c.isNumber {
                digits += 1
            } else if c != "." && c != "e" && c != "E" && c != "+" && c != "-" {
                break
            }
            advance()
        }
        guard digits > 0 else {
            throw CodeFormatterFailure(message: at("expected a value"))
        }
        return String(chars[start..<pos])
    }
}

private enum JSONWriter {
    static func write(_ value: JSONValue, indentWidth: Int, compact: Bool) -> String {
        var out = ""
        writeValue(value, indentWidth: indentWidth, level: 0, compact: compact, into: &out)
        return out
    }

    private static func writeValue(
        _ value: JSONValue,
        indentWidth: Int,
        level: Int,
        compact: Bool,
        into out: inout String
    ) {
        switch value {
        case .null:
            out += "null"
        case .boolean(let flag):
            out += flag ? "true" : "false"
        case .number(let literal):
            out += literal
        case .string(let text):
            out += escape(text)
        case .array(let items):
            guard !items.isEmpty else {
                out += "[]"
                return
            }
            if compact {
                out += "["
                for (index, item) in items.enumerated() {
                    if index > 0 { out += "," }
                    writeValue(item, indentWidth: indentWidth, level: 0, compact: true, into: &out)
                }
                out += "]"
                return
            }
            out += "[\n"
            let inner = indentString(level + 1, width: indentWidth)
            for (index, item) in items.enumerated() {
                out += inner
                writeValue(item, indentWidth: indentWidth, level: level + 1, compact: false, into: &out)
                if index < items.count - 1 { out += "," }
                out += "\n"
            }
            out += indentString(level, width: indentWidth) + "]"
        case .object(let members):
            guard !members.isEmpty else {
                out += "{}"
                return
            }
            if compact {
                out += "{"
                for (index, member) in members.enumerated() {
                    if index > 0 { out += "," }
                    out += escape(member.key) + ":"
                    writeValue(member.value, indentWidth: indentWidth, level: 0, compact: true, into: &out)
                }
                out += "}"
                return
            }
            out += "{\n"
            let inner = indentString(level + 1, width: indentWidth)
            for (index, member) in members.enumerated() {
                out += inner + escape(member.key) + ": "
                writeValue(member.value, indentWidth: indentWidth, level: level + 1, compact: false, into: &out)
                if index < members.count - 1 { out += "," }
                out += "\n"
            }
            out += indentString(level, width: indentWidth) + "}"
        }
    }

    private static func escape(_ raw: String) -> String {
        var out = "\""
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

// MARK: - YAML

/// Rebuilds YAML indentation without attempting a full document model.
///
/// A full YAML parser is out of scope here; instead the re-indenter keeps every
/// line's text untouched and only repairs the indentation *relationships*
/// between lines, which is what actually breaks when YAML is hand-edited or
/// pasted around. Block scalars and their contents are preserved verbatim.
private struct YAMLReindenter {
    let indentWidth: Int
    let dropBlankLines: Bool

    init(indentWidth: Int, dropBlankLines: Bool = false) {
        self.indentWidth = indentWidth
        self.dropBlankLines = dropBlankLines
    }

    /// Marker guarding a `key: |` block whose body must be copied verbatim.
    private struct BlockContext {
        let sourceIndent: Int
        let outputIndent: Int
    }

    func reindent(_ source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var stack: [Int] = [0]
        var output: [String] = []
        var block: BlockContext?
        var lastWasBlank = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if dropBlankLines { continue }
                if lastWasBlank { continue }
                output.append("")
                lastWasBlank = true
                continue
            }
            lastWasBlank = false

            let sourceIndent = Self.leadingSpaces(in: line)

            if let context = block {
                if sourceIndent > context.sourceIndent {
                    // Inside the block scalar: keep the relative indent, rebase the origin.
                    let relative = sourceIndent - context.sourceIndent
                    output.append(String(repeating: " ", count: context.outputIndent + relative) + trimmed)
                    continue
                }
                block = nil
            }

            var isSequenceItem = false
            var content = trimmed
            if trimmed == "-" {
                isSequenceItem = true
                content = ""
            } else if trimmed.hasPrefix("- ") {
                isSequenceItem = true
                content = String(trimmed.dropFirst(2))
            }

            let depth = resolveDepth(for: sourceIndent, stack: &stack)
            let pad = indentString(depth, width: indentWidth)
            let rendered = isSequenceItem ? (content.isEmpty ? "-" : "- " + content) : content
            output.append(pad + rendered)

            if isSequenceItem {
                // Children of a sequence item align with its text, past the "- ".
                let contentIndent = sourceIndent + 2
                if contentIndent > (stack.last ?? 0) {
                    stack.append(contentIndent)
                }
            }

            if content.range(of: #"^[^#]*:\s*[|>][+-]?\d*$"#, options: .regularExpression) != nil {
                block = BlockContext(sourceIndent: sourceIndent, outputIndent: pad.count)
            }
        }

        while output.last?.isEmpty == true {
            output.removeLast()
        }
        return output.joined(separator: "\n")
    }

    private func resolveDepth(for indent: Int, stack: inout [Int]) -> Int {
        if indent > (stack.last ?? 0) {
            stack.append(indent)
            return stack.count - 1
        }
        while stack.count > 1 && indent < stack[stack.count - 1] {
            stack.removeLast()
        }
        if stack.count > 1 && stack[stack.count - 1] != indent {
            // Indentation that does not line up exactly: snap the level instead of
            // pushing a phantom one.
            stack[stack.count - 1] = indent
        }
        return stack.count - 1
    }

    private static func leadingSpaces(in line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 } else { break }
        }
        return count
    }
}

// MARK: - SQL

private enum SQLToken {
    case word(String)
    case number(String)
    case stringLiteral(String)
    case quotedIdentifier(String)
    case bindVariable(String)
    case punctuation(String)
    case lineComment(String)
    case blockComment(String)

    var isLineComment: Bool {
        if case .lineComment = self { return true }
        return false
    }
}

private struct SQLTokenizer {
    private let chars: [Character]
    private var pos = 0

    init(_ text: String) {
        chars = Array(text)
    }

    private var isAtEnd: Bool { pos >= chars.count }
    private var current: Character? { pos < chars.count ? chars[pos] : nil }

    private func peek(_ offset: Int = 0) -> Character? {
        let idx = pos + offset
        return idx < chars.count ? chars[idx] : nil
    }

    func tokenize() -> [SQLToken] {
        var scanner = self
        return scanner.run()
    }

    private mutating func run() -> [SQLToken] {
        var tokens: [SQLToken] = []
        while !isAtEnd {
            if let c = current, c == " " || c == "\n" || c == "\t" || c == "\r" {
                pos += 1
                continue
            }
            guard let c = current else { break }

            switch c {
            case "-" where peek(1) == "-":
                tokens.append(.lineComment(collectLineComment()))
            case "/" where peek(1) == "*":
                tokens.append(.blockComment(collectBlockComment()))
            case "'":
                tokens.append(.stringLiteral(collectQuoted(quote: "'", doubledEscapes: true)))
            case "\"":
                tokens.append(.quotedIdentifier(collectQuoted(quote: "\"", doubledEscapes: true)))
            case "`":
                tokens.append(.quotedIdentifier(collectQuoted(quote: "`", doubledEscapes: false)))
            case "[":
                tokens.append(.quotedIdentifier(collectBracketed()))
            case "@", ":":
                tokens.append(.bindVariable(collectBindVariable(start: c)))
            default:
                if c.isNumber {
                    tokens.append(.number(collectNumber()))
                } else if c.isLetter || c == "_" {
                    tokens.append(.word(collectWord()))
                } else {
                    tokens.append(.punctuation(collectOperator()))
                }
            }
        }
        return tokens
    }

    private mutating func collectLineComment() -> String {
        let start = pos
        while !isAtEnd, current != "\n" { pos += 1 }
        return String(chars[start..<pos])
    }

    private mutating func collectBlockComment() -> String {
        let start = pos
        pos += 2
        while !isAtEnd {
            if current == "*", peek(1) == "/" {
                pos += 2
                break
            }
            pos += 1
        }
        return String(chars[start..<pos])
    }

    private mutating func collectQuoted(quote: Character, doubledEscapes: Bool) -> String {
        let start = pos
        pos += 1
        while !isAtEnd {
            if current == quote {
                if doubledEscapes, peek(1) == quote {
                    pos += 2
                    continue
                }
                pos += 1
                break
            }
            if current == "\\" {
                pos += 2
                continue
            }
            pos += 1
        }
        return String(chars[start..<min(pos, chars.count)])
    }

    private mutating func collectBracketed() -> String {
        let start = pos
        pos += 1
        while !isAtEnd, current != "]" { pos += 1 }
        if !isAtEnd { pos += 1 }
        return String(chars[start..<min(pos, chars.count)])
    }

    private mutating func collectBindVariable(start: Character) -> String {
        let from = pos
        pos += 1
        if start == "@", peek() == "@" { pos += 1 }
        while let c = current, c.isLetter || c.isNumber || c == "_" || c == "$" { pos += 1 }
        return String(chars[from..<pos])
    }

    private mutating func collectNumber() -> String {
        let start = pos
        while let c = current, c.isNumber || c == "." { pos += 1 }
        return String(chars[start..<pos])
    }

    private mutating func collectWord() -> String {
        let start = pos
        while let c = current, c.isLetter || c.isNumber || c == "_" || c == "$" || c == "." { pos += 1 }
        return String(chars[start..<pos])
    }

    private mutating func collectOperator() -> String {
        let start = pos
        let c = chars[pos]
        pos += 1
        // Two character operators, longest first.
        let pairs = ["<=", ">=", "<>", "!=", "||", "::", "->", "=>"]
        if let next = peek(-1) {
            let pair = String([c, next])
            if pairs.contains(pair) {
                pos += 1
                return pair
            }
        }
        return String(chars[start..<pos])
    }
}

private enum SQLKeywords {
    /// Single keywords that always start a new line at the block indent.
    static let singleWordClauses: Set<String> = [
        "SELECT", "FROM", "WHERE", "HAVING", "LIMIT", "OFFSET", "UNION", "INTERSECT",
        "EXCEPT", "VALUES", "RETURNING", "WINDOW", "WITH", "UPDATE", "SET"
    ]

    /// Two word clauses recognised through lookahead during rendering.
    static let twoWordClauses: Set<String> = [
        "GROUP BY", "ORDER BY", "INSERT INTO", "DELETE FROM", "UNION ALL", "PARTITION BY"
    ]

    /// Join variants rendered on their own line at the block indent.
    static let joins: Set<String> = [
        "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN", "CROSS JOIN",
        "LEFT OUTER JOIN", "RIGHT OUTER JOIN", "FULL OUTER JOIN", "NATURAL JOIN",
        "OUTER APPLY", "CROSS APPLY"
    ]

    /// Words that get their own line at the current indent (inside CASE blocks).
    static let continuations: Set<String> = ["WHEN", "ELSE"]

    /// Boolean connectors: own line, one step deeper than the clause.
    static let connectors: Set<String> = ["AND", "OR"]

    /// `ON` / `USING` sit one step deeper under their JOIN.
    static let joinConditions: Set<String> = ["ON", "USING"]

    static func isClauseStarter(_ phrase: String) -> Bool {
        singleWordClauses.contains(phrase) || twoWordClauses.contains(phrase)
    }

    static func isJoin(_ phrase: String) -> Bool {
        joins.contains(phrase)
    }
}

private final class SQLRenderer {
    private let indentWidth: Int
    private let uppercaseKeywords: Bool
    private let compact: Bool

    private var out = ""
    private var indentLevel = 0
    private var atLineStart = true
    private var previous = ""
    private var caseDepth = 0

    /// One frame per paren nesting level; frame 0 holds the statement itself.
    private var frames: [Frame] = [Frame()]

    /// Whether a SELECT column list is open at this level, and whether the
    /// matching indent step is currently applied.
    private struct Frame {
        var selectColumns = false
        var columnIndentApplied = false
    }

    init(indentWidth: Int, uppercaseKeywords: Bool, compact: Bool) {
        self.indentWidth = indentWidth
        self.uppercaseKeywords = uppercaseKeywords
        self.compact = compact
    }

    func render(_ tokens: [SQLToken]) -> String {
        var index = 0
        while index < tokens.count {
            let token = tokens[index]

            if case .word = token {
                let word = SQLRenderer.text(of: token).uppercased()

                if let matched = SQLRenderer.matchPhrase(in: tokens, at: index) {
                    emitClause(matched.phrase)
                    index += matched.length
                    continue
                }

                switch word {
                case "CASE":
                    emit(token, spaceBefore: true)
                    caseDepth += 1
                    indentLevel += 1
                case "END":
                    if caseDepth > 0 {
                        caseDepth -= 1
                        indentLevel = max(0, indentLevel - 1)
                    }
                    emit(token, spaceBefore: true)
                case "WHEN", "ELSE":
                    newline()
                    emit(token, spaceBefore: true)
                default:
                    if SQLKeywords.connectors.contains(word) || SQLKeywords.joinConditions.contains(word) {
                        newline()
                        indentLevel += 1
                        emit(token, spaceBefore: true)
                        indentLevel = max(0, indentLevel - 1)
                    } else {
                        emit(token, spaceBefore: true)
                    }
                }
                index += 1
                continue
            }

            switch token {
            case .punctuation("("):
                emit(token, spaceBefore: SQLRenderer.wantsSpaceBeforeParen(previous: previous))
                indentLevel += 1
                frames.append(Frame())
            case .punctuation(")"):
                if let closing = frames.last, closing.columnIndentApplied {
                    indentLevel = max(0, indentLevel - 1)
                }
                indentLevel = max(0, indentLevel - 1)
                if frames.count > 1 { frames.removeLast() }
                emit(token, spaceBefore: false)
            case .punctuation(","):
                emit(token, spaceBefore: false)
                if frames.last?.selectColumns == true {
                    newline()
                }
            case .punctuation(";"):
                emit(token, spaceBefore: false)
                if frames.count == 1 {
                    frames[0] = Frame()
                    newline()
                }
            case .punctuation("."):
                emit(token, spaceBefore: false)
            case .lineComment:
                newline()
                emit(token, spaceBefore: false)
                newline()
            default:
                emit(token, spaceBefore: true)
            }

            index += 1
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Rendering primitives

    private func newline() {
        guard !compact, !atLineStart else { return }
        out += "\n"
        atLineStart = true
    }

    private func emit(_ token: SQLToken, spaceBefore: Bool) {
        let raw = SQLRenderer.text(of: token)
        let rendered = SQLRenderer.rendering(of: token, uppercaseKeywords: uppercaseKeywords)
        emitRaw(rendered, spaceBefore: spaceBefore)
        _ = raw
    }

    private func emitRaw(_ text: String, spaceBefore: Bool) {
        if atLineStart {
            out += indentString(indentLevel, width: indentWidth)
            atLineStart = false
        } else if spaceBefore, SQLRenderer.needsSpace(previous: previous, next: text) {
            out += " "
        }
        out += text
        previous = text
    }

    /// Renders a clause starter or join onto its own line at the block indent.
    private func emitClause(_ phrase: String) {
        newline()
        if frames.isEmpty { frames.append(Frame()) }
        let level = frames.count - 1

        // Leaving an open SELECT column list releases its extra indent.
        if frames[level].columnIndentApplied {
            indentLevel = max(0, indentLevel - 1)
        }

        let opensColumns = phrase == "SELECT"
        frames[level] = Frame(selectColumns: opensColumns, columnIndentApplied: false)

        let rendered = uppercaseKeywords ? phrase.uppercased() : phrase.lowercased()
        emitRaw(rendered, spaceBefore: false)

        // Column lists read best one column per line, one step deeper.
        guard opensColumns, !compact else { return }
        indentLevel += 1
        frames[level].columnIndentApplied = true
        newline()
    }

    private static func rendering(of token: SQLToken, uppercaseKeywords: Bool) -> String {
        guard case .word(let word) = token else { return text(of: token) }
        guard isKeyword(word) else { return word }
        return uppercaseKeywords ? word.uppercased() : word.lowercased()
    }

    private static func needsSpace(previous: String, next: String) -> Bool {
        guard !previous.isEmpty else { return false }
        if next == ")" || next == "," || next == ";" || next == "." { return false }
        if previous == "(" || previous == "." || previous == "::" { return false }
        if next == "(" { return wantsSpaceBeforeParen(previous: previous) }
        return true
    }

    private static func wantsSpaceBeforeParen(previous: String) -> Bool {
        let controls: Set<String> = [
            "IN", "VALUES", "ALL", "AND", "OR", "NOT", "ON", "SET", "EXISTS", "OVER",
            "INTO", "USING", "BY", "SELECT", "FROM", "WHERE", "AS", "BETWEEN", "THEN",
            "ELSE", "WHEN", "RETURNING", "DISTINCT", "UNION", "JOIN"
        ]
        return controls.contains(previous.uppercased())
    }

    /// Matches the longest known clause or join phrase starting at `index`.
    private static func matchPhrase(in tokens: [SQLToken], at index: Int) -> (phrase: String, length: Int)? {
        for length in [2, 1] {
            guard index + length <= tokens.count else { continue }
            var parts: [String] = []
            for offset in 0..<length {
                guard case .word(let word) = tokens[index + offset] else {
                    // Not a run of words: fall back to the shorter phrase instead
                    // of giving up entirely, so `LIMIT 20;` still recognises LIMIT.
                    parts = []
                    break
                }
                parts.append(word.uppercased())
            }
            guard parts.count == length else { continue }
            let phrase = parts.joined(separator: " ")
            if SQLKeywords.isJoin(phrase) || SQLKeywords.isClauseStarter(phrase) {
                return (phrase, length)
            }
        }
        return nil
    }

    private static func text(of token: SQLToken) -> String {
        switch token {
        case .word(let text): return text
        case .number(let text): return text
        case .stringLiteral(let text): return text
        case .quotedIdentifier(let text): return text
        case .bindVariable(let text): return text
        case .punctuation(let text): return text
        case .lineComment(let text): return text
        case .blockComment(let text): return text
        }
    }

    private static func isKeyword(_ raw: String) -> Bool {
        let word = raw.uppercased()
        if SQLKeywords.singleWordClauses.contains(word) { return true }
        if SQLKeywords.joins.contains(word) { return true }
        if SQLKeywords.connectors.contains(word) { return true }
        if SQLKeywords.joinConditions.contains(word) { return true }
        return plainKeywords.contains(word)
    }

    /// Keywords rendered in canonical case that never change line position.
    private static let plainKeywords: Set<String> = [
        "AS", "ASC", "DESC", "DISTINCT", "NULL", "NOT", "IN", "IS", "LIKE", "BETWEEN",
        "EXISTS", "CASE", "END", "CAST", "INNER", "LEFT", "RIGHT", "FULL", "OUTER",
        "CROSS", "NATURAL", "APPLY", "ALL", "ANY", "SOME", "JOIN", "BY", "COUNT",
        "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF", "TRUE", "FALSE", "CREATE",
        "TABLE", "VIEW", "INDEX", "DROP", "ALTER", "ADD", "PRIMARY", "KEY", "FOREIGN",
        "REFERENCES", "UNIQUE", "DEFAULT", "CONSTRAINT", "BEGIN", "COMMIT", "ROLLBACK",
        "IF", "PARTITION", "OVER", "CASCADE", "REPLACE", "TRUNCATE", "THEN"
    ]
}

// MARK: - Markup (HTML / XML)

private enum MarkupToken {
    case openTag(String, attributes: String, selfClosing: Bool)
    case closeTag(String)
    case text(String)
    case comment(String)
    case doctype(String)
    case cdata(String)
    case processingInstruction(String)
}

private enum MarkupFormatter {
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr"
    ]

    private static let rawTextElements: Set<String> = ["script", "style", "pre", "textarea"]

    static func format(
        _ source: String,
        language: CodeFormatterLanguage,
        width: Int
    ) -> CodeFormatterResult {
        let tokens = MarkupTokenizer(source).tokenize()
        guard !tokens.isEmpty else {
            return .failure(String(localized: "Nothing to format yet."), fallback: source)
        }

        var out = ""
        var stack: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            switch token {
            case .openTag(let name, let attributes, let selfClosing):
                let pad = indentString(stack.count, width: width)
                out += newlineIfNeeded(&out) + pad + renderTag(token, language: language)
                if selfClosing || isVoid(name, language: language) {
                    break
                }
                // Inline a simple `<tag>text</tag>` trio onto one line.
                if case .text(let inline)? = element(at: index + 1, in: tokens),
                   case .closeTag(let closing)? = element(at: index + 2, in: tokens),
                   closing == name,
                   !inline.contains("\n") {
                    out += collapseWhitespace(inline)
                    out += "</\(preserveCase(name, language: language))>"
                    index += 3
                    continue
                }
                // Verbatim bodies (script/style/pre/textarea) are copied untouched.
                if rawTextElements.contains(name.lowercased()), language == .html,
                   case .text(let body)? = element(at: index + 1, in: tokens),
                   case .closeTag(let closing)? = element(at: index + 2, in: tokens),
                   closing == name {
                    out += rebase(body, to: stack.count + 1, width: width)
                    out += indentString(stack.count, width: width) + "</\(preserveCase(name, language: language))>"
                    index += 3
                    continue
                }
                stack.append(name)
                _ = attributes
            case .closeTag(let name):
                if let last = stack.last, last == name {
                    stack.removeLast()
                } else if let position = stack.lastIndex(of: name) {
                    // Unclosed tags: rewind rather than emitting negative depth.
                    stack.removeSubrange(position...)
                }
                let pad = indentString(stack.count, width: width)
                out += newlineIfNeeded(&out) + pad + renderTag(token, language: language)
            case .text(let body):
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    index += 1
                    continue
                }
                let pad = indentString(stack.count, width: width)
                out += newlineIfNeeded(&out) + pad + collapseWhitespace(trimmed)
            case .comment, .doctype, .cdata, .processingInstruction:
                let pad = indentString(stack.count, width: width)
                out += newlineIfNeeded(&out) + pad + renderTag(token, language: language)
            }

            index += 1
        }

        return .success(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func minify(_ source: String, language: CodeFormatterLanguage) -> CodeFormatterResult {
        let tokens = MarkupTokenizer(source).tokenize()
        guard !tokens.isEmpty else {
            return .failure(String(localized: "Nothing to minify yet."), fallback: source)
        }
        var out = ""
        for token in tokens {
            switch token {
            case .text(let body):
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let previous = out.last
                let previousNeedsSpace = previous.map { !$0.isNewline && $0 != ">" } ?? false
                if previousNeedsSpace, case .text = token, !(out.hasSuffix(">") || out.isEmpty) {
                    out += collapseWhitespace(trimmed)
                } else {
                    out += collapseWhitespace(trimmed)
                }
            case .comment:
                continue // Comments carry no meaning once minified.
            default:
                out += renderTag(token, language: language)
            }
        }
        return .success(out)
    }

    private static func element(at index: Int, in tokens: [MarkupToken]) -> MarkupToken? {
        index < tokens.count ? tokens[index] : nil
    }

    private static func isVoid(_ name: String, language: CodeFormatterLanguage) -> Bool {
        language == .html && voidElements.contains(name.lowercased())
    }

    private static func preserveCase(_ name: String, language: CodeFormatterLanguage) -> String {
        language == .xml ? name : name.lowercased()
    }

    /// Re-indents a verbatim block by the specified amount without altering its
    /// internal relative structure.
    private static func rebase(_ body: String, to level: Int, width: Int) -> String {
        var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }

        let indents = lines.compactMap { line -> Int? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : Self.leadingWidth(of: line)
        }
        let baseline = indents.min() ?? 0

        let pad = indentString(level, width: width)
        return lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return "" }
            let relative = max(0, Self.leadingWidth(of: line) - baseline)
            return String(repeating: " ", count: relative) + trimmed
        }
        .map { $0.isEmpty ? $0 : pad + $0 }
        .joined(separator: "\n") + "\n"
    }

    private static func leadingWidth(of line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " || ch == "\t" { count += 1 } else { break }
        }
        return count
    }

    private static func collapseWhitespace(_ text: String) -> String {
        let parts = text.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    private static func newlineIfNeeded(_ out: inout String) -> String {
        guard !out.isEmpty else { return "" }
        return "\n"
    }

    private static func renderTag(_ token: MarkupToken, language: CodeFormatterLanguage) -> String {
        switch token {
        case .openTag(let name, let attributes, let selfClosing):
            let displayName = language == .xml ? name : name.lowercased()
            let attrs = attributes.trimmingCharacters(in: .whitespacesAndNewlines)
            if attrs.isEmpty {
                return selfClosing ? "<\(displayName) />" : "<\(displayName)>"
            }
            return selfClosing ? "<\(displayName) \(attrs) />" : "<\(displayName) \(attrs)>"
        case .closeTag(let name):
            return "</\(language == .xml ? name : name.lowercased())>"
        case .comment(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .doctype(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        case .cdata(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .processingInstruction(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .text:
            return ""
        }
    }
}

private struct MarkupTokenizer {
    private let chars: [Character]
    private var pos = 0

    init(_ text: String) {
        chars = Array(text)
    }

    private var isAtEnd: Bool { pos >= chars.count }
    private var current: Character? { pos < chars.count ? chars[pos] : nil }

    private func peek(_ offset: Int = 0) -> Character? {
        let idx = pos + offset
        return idx < chars.count ? chars[idx] : nil
    }

    func tokenize() -> [MarkupToken] {
        var scanner = self
        return scanner.run()
    }

    private mutating func run() -> [MarkupToken] {
        var tokens: [MarkupToken] = []
        while !isAtEnd {
            guard current == "<" else {
                tokens.append(.text(collectText()))
                continue
            }

            if hasPrefix("<!--") {
                tokens.append(.comment(collectUntil("-->")))
            } else if hasPrefix("<![CDATA[") {
                tokens.append(.cdata(collectUntil("]]>")))
            } else if hasPrefix("<!") {
                tokens.append(.doctype(collectTagBody()))
            } else if hasPrefix("<?") {
                tokens.append(.processingInstruction(collectTagBody()))
            } else if peek(1) == "/" {
                tokens.append(.closeTag(collectCloseTag()))
            } else {
                let opened = collectOpenTag()
                if opened.name.isEmpty {
                    // Stray "<": keep it as text rather than dropping content.
                    pos += 1
                    tokens.append(.text("<"))
                    continue
                }
                tokens.append(.openTag(opened.name, attributes: opened.attributes, selfClosing: opened.selfClosing))
                if !opened.selfClosing, Self.rawElements.contains(opened.name.lowercased()) {
                    tokens.append(.text(collectRawBody(until: opened.name)))
                }
            }
        }
        return tokens
    }

    /// Elements whose children are not markup and must never be re-indented.
    private static let rawElements: Set<String> = ["script", "style", "pre", "textarea"]

    private func hasPrefix(_ token: String) -> Bool {
        let pattern = Array(token)
        guard chars.count - pos >= pattern.count else { return false }
        for (offset, ch) in pattern.enumerated() {
            if chars[pos + offset] != ch { return false }
        }
        return true
    }

    private mutating func collectText() -> String {
        let start = pos
        while !isAtEnd, current != "<" { pos += 1 }
        return String(chars[start..<pos])
    }

    private mutating func collectUntil(_ terminator: String) -> String {
        let start = pos
        let pattern = Array(terminator)
        pos += pattern.count
        while !isAtEnd {
            if hasPrefix(terminator) {
                pos += pattern.count
                break
            }
            pos += 1
        }
        return String(chars[start..<min(pos, chars.count)])
    }

    private mutating func collectTagBody() -> String {
        let start = pos
        var depth = 0
        while !isAtEnd {
            if current == "<" { depth += 1 }
            if current == ">" {
                pos += 1
                if depth > 0 { break }
            }
            pos += 1
        }
        return String(chars[start..<min(pos, chars.count)])
    }

    private mutating func collectCloseTag() -> String {
        let start = pos
        pos += 2 // </
        while !isAtEnd, current != ">" { pos += 1 }
        let body = String(chars[min(start + 2, chars.count)..<min(pos, chars.count)])
        if !isAtEnd { pos += 1 }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func collectOpenTag() -> (name: String, attributes: String, selfClosing: Bool) {
        let start = pos
        pos += 1 // <
        var name = ""
        while let c = current, c != ">" && c != " " && c != "/" && c != "\n" && c != "\t" {
            name.append(c)
            pos += 1
        }

        var attributes = ""
        var selfClosing = false
        var quote: Character?

        while !isAtEnd {
            let c = chars[pos]
            if let open = quote {
                if c == open { quote = nil }
                attributes.append(c)
                pos += 1
                continue
            }
            if c == "\"" || c == "'" {
                quote = c
                attributes.append(c)
                pos += 1
                continue
            }
            if c == "/" && peek(1) == ">" {
                selfClosing = true
                pos += 1
                continue
            }
            if c == ">" {
                pos += 1
                break
            }
            attributes.append(c)
            pos += 1
        }

        guard isAtEnd || pos > start else { return ("", "", false) }
        return (name, attributes, selfClosing)
    }

    /// Reads the untouched body of a `<script>`, `<style>`, `<pre>` element.
    private mutating func collectRawBody(until name: String) -> String {
        let pattern = Array("</" + name.lowercased())
        var search = pos
        while search + pattern.count <= chars.count {
            var matched = true
            for (offset, piece) in pattern.enumerated() {
                if String(chars[search + offset]).lowercased() != String(piece) {
                    matched = false
                    break
                }
            }
            if matched {
                let body = String(chars[pos..<search])
                pos = search
                return body
            }
            search += 1
        }
        let body = String(chars[pos...])
        pos = chars.count
        return body
    }
}

// MARK: - CSS

private enum CSSToken {
    case text(String)
    case quoted(String)
    case comment(String)
    case punctuation(String)
}

private enum CSSFormatter {
    static func format(_ source: String, width: Int) -> String {
        let tokens = CSSTokenizer(source).tokenize()
        var lines: [String] = []
        var buffer: [String] = []
        var depth = 0
        var bufferHasCommentOnly = true

        func flush(_ terminator: String?) {
            let joined = buffer.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = []
            bufferHasCommentOnly = true
            guard !joined.isEmpty else {
                if let terminator { lines.append(indentString(depth, width: width) + terminator) }
                return
            }
            lines.append(contentsOf: renderStatement(joined, terminator: terminator, depth: depth, width: width))
        }

        for token in tokens {
            switch token {
            case .punctuation(let symbol) where symbol == "{":
                flush("{")
                depth += 1
            case .punctuation(let symbol) where symbol == "}":
                flush(nil)
                depth = max(0, depth - 1)
                lines.append(indentString(depth, width: width) + "}")
            case .punctuation(let symbol) where symbol == ";":
                flush(";")
            case .comment(let body):
                // Comments on their own line read better than trailing on selectors.
                if bufferHasCommentOnly {
                    buffer.append(body)
                } else {
                    flush(nil)
                    buffer.append(body)
                    bufferHasCommentOnly = true
                }
            default:
                buffer.append(Self.text(of: token))
                bufferHasCommentOnly = false
            }
        }
        flush(nil)

        var result: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    static func minify(_ source: String) -> String {
        let tokens = CSSTokenizer(source).tokenize()
        var out = ""
        for token in tokens {
            switch token {
            case .comment:
                continue
            case .punctuation(let symbol):
                let previous = out.last
                if symbol == ";" || symbol == "}" || symbol == "{" {
                    // Drop redundant separators that immediately follow another one.
                    if previous == ";" && symbol == ";" { continue }
                    out += symbol
                } else {
                    let needsSpace = Self.punctuationNeedsSpace(previous: previous, symbol: symbol)
                    if needsSpace { out += " " }
                    out += symbol
                }
            default:
                let text = Self.text(of: token)
                let previous = out.last
                if let previous, previous != "{", previous != ";" {
                    let previousIsPunctuation = "{};:,".contains(previous)
                    let nextIsPunctuation = text.first.map { "{};:,)".contains($0) } ?? false
                    if !previousIsPunctuation && !nextIsPunctuation {
                        out += " "
                    }
                }
                out += Self.collapse(text)
            }
        }
        return out.replacingOccurrences(of: ";}", with: "}")
            .replacingOccurrences(of: "; }", with: "}")
    }

    private static func punctuationNeedsSpace(previous: Character?, symbol: String) -> Bool {
        guard symbol == "," else { return false }
        return previous != ","
    }

    private static func renderStatement(_ text: String, terminator: String?, depth: Int, width: Int) -> [String] {
        let pad = indentString(depth, width: width)
        let compact = Self.collapse(text)

        guard terminator == "{" else {
            return [pad + Self.normalizeDeclaration(compact) + (terminator ?? "")]
        }

        guard compact.contains(",") else {
            return [pad + compact + " {"]
        }

        // Multi-selector rules read better with one selector per line.
        var selectors: [String] = []
        var currentPiece = ""
        var quote: Character?
        var parenDepth = 0
        for ch in compact {
            if let open = quote {
                currentPiece.append(ch)
                if ch == open { quote = nil }
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch
                currentPiece.append(ch)
                continue
            }
            if ch == "(" { parenDepth += 1 }
            if ch == ")" { parenDepth = max(0, parenDepth - 1) }
            if ch == ",", parenDepth == 0 {
                let piece = currentPiece.trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { selectors.append(piece) }
                currentPiece = ""
                continue
            }
            currentPiece.append(ch)
        }
        let tail = currentPiece.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { selectors.append(tail) }
        guard selectors.count > 1 else { return [pad + compact + " {"] }

        var rendered: [String] = []
        for (index, selector) in selectors.enumerated() {
            let suffix = index == selectors.count - 1 ? " {" : ","
            rendered.append(pad + selector + suffix)
        }
        return rendered
    }

    /// Collapses runs of whitespace and guarantees the usual `name: value` form
    /// even when the source omitted the space.
    private static func normalizeDeclaration(_ text: String) -> String {
        let compact = Self.collapse(text)
        var quote: Character?
        var depth = 0
        for (offset, character) in compact.enumerated() {
            if let open = quote {
                if character == open { quote = nil }
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
            case "(":
                depth += 1
            case ")":
                depth = max(0, depth - 1)
            case ":" where depth == 0:
                let index = compact.index(compact.startIndex, offsetBy: offset)
                let name = String(compact[compact.startIndex..<index]).trimmingCharacters(in: .whitespaces)
                let value = String(compact[compact.index(after: index)...]).trimmingCharacters(in: .whitespaces)
                if value.isEmpty { return compact }
                return name + ": " + value
            default:
                break
            }
        }
        return compact
    }

    private static func collapse(_ text: String) -> String {
        let parts = text.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    private static func text(of token: CSSToken) -> String {
        switch token {
        case .text(let value): return value
        case .quoted(let value): return value
        case .comment(let value): return value
        case .punctuation(let value): return value
        }
    }
}

private struct CSSTokenizer {
    private let chars: [Character]
    private var pos = 0

    init(_ text: String) {
        chars = Array(text)
    }

    private var isAtEnd: Bool { pos >= chars.count }
    private var current: Character? { pos < chars.count ? chars[pos] : nil }

    func tokenize() -> [CSSToken] {
        var scanner = self
        return scanner.run()
    }

    private mutating func run() -> [CSSToken] {
        var tokens: [CSSToken] = []
        var text = ""

        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(.text(text))
            text = ""
        }

        while !isAtEnd {
            guard let c = current else { break }

            if c == "/", chars.count > pos + 1, chars[pos + 1] == "*" {
                flushText()
                tokens.append(.comment(collectComment()))
                continue
            }
            if c == "\"" || c == "'" {
                flushText()
                tokens.append(.quoted(collectQuoted(quote: c)))
                continue
            }
            if c == "{" || c == "}" || c == ";" || c == "," {
                flushText()
                tokens.append(.punctuation(String(c)))
                pos += 1
                continue
            }
            text.append(c)
            pos += 1
        }
        flushText()
        return tokens
    }

    private mutating func collectComment() -> String {
        let start = pos
        pos += 2
        while !isAtEnd {
            if current == "*", chars.count > pos + 1, chars[pos + 1] == "/" {
                pos += 2
                break
            }
            pos += 1
        }
        return String(chars[start..<min(pos, chars.count)])
    }

    private mutating func collectQuoted(quote: Character) -> String {
        let start = pos
        pos += 1
        while !isAtEnd {
            if current == "\\" {
                pos += 2
                continue
            }
            if current == quote {
                pos += 1
                break
            }
            pos += 1
        }
        return String(chars[start..<min(pos, chars.count)])
    }
}

// MARK: - JavaScript

private enum JSToken {
    case word(String)
    case number(String)
    case stringLiteral(String)
    case templateLiteral(String)
    case regexLiteral(String)
    case lineComment(String)
    case blockComment(String)
    case punctuation(String)
}

private enum JSFormatter {
    /// Words that may continue a line straight after a closing brace.
    private static let braceFollowers: Set<String> = ["else", "catch", "finally", "while"]

    /// Words that take a space before an opening parenthesis.
    private static let controlKeywords: Set<String> = [
        "if", "for", "while", "switch", "catch", "return", "typeof", "instanceof",
        "in", "of", "new", "delete", "void", "case", "do", "else", "yield", "await"
    ]

    private static let noSpaceBefore: Set<String> = [")", "]", ",", ";", ".", ":", "?"]
    private static let noSpaceAfter: Set<String> = ["(", "[", ".", "!"]

    static func format(_ source: String, width: Int) -> String {
        let tokens = JSTokenizer(source).tokenize()
        guard !tokens.isEmpty else { return "" }

        var out = ""
        var stack: [Frame] = []
        var atLineStart = true
        var previous: String?

        /// Indent follows brace/bracket nesting only; parentheses never indent,
        /// which keeps ordinary call arguments on a single line.
        func currentIndent() -> Int {
            stack.filter { $0.kind == .brace || $0.kind == .bracket }.count
        }

        func applyLineStart() {
            guard atLineStart else { return }
            out += indentString(currentIndent(), width: width)
            atLineStart = false
        }

        func breakLine() {
            guard !atLineStart else { return }
            out += "\n"
            atLineStart = true
        }

        func put(_ text: String, spaceBefore: Bool = true) {
            // The padding we just emitted counts as the separator; without this
            // guard every continued line picked up a stray leading space.
            let openedLine = atLineStart
            applyLineStart()
            if !openedLine, let previous, spaceBefore, Self.wantsSpace(previous: previous, next: text) {
                out += " "
            }
            out += text
            previous = text
        }

        /// True when the token after `index` belongs on the current line.
        func inlineFollower(at index: Int) -> Bool {
            guard index < tokens.count else { return false }
            if case .punctuation(let symbol) = tokens[index] {
                // Any operator continues the line; only a fresh `{` starts one.
                return symbol != "{"
            }
            if case .word(let word) = tokens[index] {
                return braceFollowers.contains(word)
            }
            return false
        }

        /// Keeps `{}` and `[]` together when there is nothing in between.
        func emptiesImmediately(at index: Int, closing: String) -> Bool {
            guard index < tokens.count else { return false }
            if case .punctuation(let symbol) = tokens[index] {
                return symbol == closing
            }
            return false
        }

        for (index, token) in tokens.enumerated() {
            let text = Self.text(of: token)

            if case .lineComment = token {
                breakLine()
                put(text)
                breakLine()
                continue
            }
            if case .blockComment = token {
                breakLine()
                put(text)
                if !inlineFollower(at: index + 1) { breakLine() }
                continue
            }

            switch text {
            case "{":
                put(text, spaceBefore: true)
                let empty = emptiesImmediately(at: index + 1, closing: "}")
                stack.append(Frame(kind: .brace, openedEmpty: empty))
                if !empty { breakLine() }
            case "}":
                let wasEmpty = stack.last?.openedEmpty == true
                Self.unwind(&stack, to: .brace)
                if !wasEmpty { breakLine() }
                put(text, spaceBefore: !wasEmpty)
                if !wasEmpty, !inlineFollower(at: index + 1) { breakLine() }
            case "[":
                put(text)
                let empty = emptiesImmediately(at: index + 1, closing: "]")
                stack.append(Frame(kind: .bracket, openedEmpty: empty))
                if !empty { breakLine() }
            case "]":
                // Closing brackets never take their own line, empty or not.
                Self.unwind(&stack, to: .bracket)
                put(text, spaceBefore: false)
            case "(":
                put(text, spaceBefore: Self.spaceBeforeParen(previous: previous))
                stack.append(Frame(kind: .paren))
            case ")":
                Self.unwind(&stack, to: .paren)
                put(text, spaceBefore: false)
            case ";":
                put(text, spaceBefore: false)
                if stack.last?.kind != .paren { breakLine() }
            case ",":
                put(text, spaceBefore: false)
                if let top = stack.last, top.kind == .brace || top.kind == .bracket { breakLine() }
            case ".":
                put(text, spaceBefore: false)
            default:
                put(text, spaceBefore: true)
            }
        }

        return Self.tidied(out)
    }

    static func minify(_ source: String) -> String {
        let tokens = JSTokenizer(source).tokenize()
        var out = ""
        var previous: String?

        for token in tokens {
            if case .lineComment = token { continue }
            if case .blockComment = token { continue }

            let text = Self.text(of: token)
            var needsSpace = false
            if let previous {
                let previousEndsWordy = Self.isWordy(previous.last)
                let nextStartsWordy = Self.isWordy(text.first)
                needsSpace = previousEndsWordy && nextStartsWordy
                if previous == ")" && nextStartsWordy { needsSpace = true }
                // "x++ + ++y" must not collapse into "x+++++y".
                if let previousLast = previous.last, let nextFirst = text.first,
                   (previousLast == "+" || previousLast == "-"),
                   (nextFirst == "+" || nextFirst == "-") {
                    needsSpace = true
                }
            }
            if needsSpace { out += " " }
            out += text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            previous = text
        }
        return out
    }

    private struct Frame {
        enum Kind {
            case brace
            case bracket
            case paren
        }

        let kind: Kind
        /// Whether this brace/bracket was opened and closed with nothing between.
        let openedEmpty: Bool

        init(kind: Kind, openedEmpty: Bool = false) {
            self.kind = kind
            self.openedEmpty = openedEmpty
        }
    }

    private static func unwind(_ stack: inout [Frame], to kind: Frame.Kind) {
        while let last = stack.last, last.kind != kind {
            stack.removeLast()
        }
        if !stack.isEmpty { stack.removeLast() }
    }

    private static func isWordy(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    private static func spaceBeforeParen(previous: String?) -> Bool {
        guard let previous else { return false }
        if controlKeywords.contains(previous) { return true }
        // Assignment and arrow forms read better with breathing room:
        // `function mount(options = {})`, `rows.map(n => ({ id: n }))`.
        if previous == "=" || previous == "=>" || previous == ":" { return true }
        return previous == ")" || previous == "]" || previous == "}" || previous == ","
    }

    private static func wantsSpace(previous: String, next: String) -> Bool {
        if previous.isEmpty { return false }
        if noSpaceBefore.contains(next) { return false }
        if noSpaceAfter.contains(previous) { return false }
        if next == "(" { return spaceBeforeParen(previous: previous) }
        return true
    }

    /// Trims trailing whitespace and collapses runs of blank lines without
    /// touching the leading indentation we just produced.
    private static func tidied(_ text: String) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression) }

        var result: [String] = []
        var previousBlank = false
        for line in lines {
            if line.isEmpty {
                if previousBlank { continue }
                previousBlank = true
            } else {
                previousBlank = false
            }
            result.append(line)
        }
        while result.first?.isEmpty == true { result.removeFirst() }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }

    private static func text(of token: JSToken) -> String {
        switch token {
        case .word(let value): return value
        case .number(let value): return value
        case .stringLiteral(let value): return value
        case .templateLiteral(let value): return value
        case .regexLiteral(let value): return value
        case .lineComment(let value): return value
        case .blockComment(let value): return value
        case .punctuation(let value): return value
        }
    }
}

private struct JSTokenizer {
    private let chars: [Character]
    private var pos = 0
    private var previousSignificant: String?

    init(_ text: String) {
        chars = Array(text)
    }

    private var isAtEnd: Bool { pos >= chars.count }
    private var current: Character? { pos < chars.count ? chars[pos] : nil }

    private func peek(_ offset: Int = 0) -> Character? {
        let idx = pos + offset
        return idx < chars.count ? chars[idx] : nil
    }

    private func precededByWhitespaceOrNewline() -> Bool {
        guard pos > 0 else { return true }
        let before = chars[pos - 1]
        return before == " " || before == "\n" || before == "\t" || before == "\r"
    }

    func tokenize() -> [JSToken] {
        var scanner = self
        return scanner.run()
    }

    private mutating func run() -> [JSToken] {
        var tokens: [JSToken] = []
        while !isAtEnd {
            guard let c = current else { break }

            if c.isWhitespace {
                pos += 1
                continue
            }
            if c == "/", peek(1) == "/" {
                tokens.append(.lineComment(collectLineComment()))
                previousSignificant = nil
                continue
            }
            if c == "/", peek(1) == "*" {
                tokens.append(.blockComment(collectBlockComment()))
                previousSignificant = nil
                continue
            }
            if c == "/" && Self.canPrecedeRegex(previousSignificant) {
                if let literal = tryCollectRegex() {
                    tokens.append(.regexLiteral(literal))
                    previousSignificant = "regex"
                    continue
                }
            }
            if c == "\"" || c == "'" {
                let literal = collectQuoted(quote: c)
                tokens.append(.stringLiteral(literal))
                previousSignificant = "string"
                continue
            }
            if c == "`" {
                tokens.append(.templateLiteral(collectTemplate()))
                previousSignificant = "string"
                continue
            }
            if c.isNumber {
                let number = collectNumber()
                tokens.append(.number(number))
                previousSignificant = "number"
                continue
            }
            if c.isLetter || c == "_" || c == "$" {
                let word = collectWord()
                tokens.append(.word(word))
                previousSignificant = word
                continue
            }

            let symbol = collectOperator()
            tokens.append(.punctuation(symbol))
            previousSignificant = symbol
        }
        return tokens
    }

    private static func canPrecedeRegex(_ previous: String?) -> Bool {
        guard let previous else { return true }
        if previous.isEmpty { return true }
        let operators: Set<String> = ["(", "{", "[", ",", ";", ":", "=", "!", "&", "|", "?", "+", "-", "*", "%", "~", "^", "<", ">", "return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "case", "do", "else", "yield", "await"]
        if previous.count == 1, let first = previous.first, "([{,;:=!&|?+-*%~^<>".contains(first) {
            return true
        }
        return operators.contains(previous)
    }

    private mutating func tryCollectRegex() -> String? {
        let start = pos
        pos += 1
        var inClass = false
        while !isAtEnd {
            let c = chars[pos]
            if c == "\\" {
                pos += 2
                continue
            }
            if c == "\n" {
                pos = start
                return nil
            }
            if c == "[" { inClass = true }
            if c == "]" { inClass = false }
            if c == "/", !inClass {
                pos += 1
                while let flag = peek(), flag.isLetter { pos += 1 }
                return String(chars[start..<pos])
            }
            pos += 1
        }
        pos = start
        return nil
    }

    private mutating func collectLineComment() -> String {
        let start = pos
        while !isAtEnd, current != "\n" { pos += 1 }
        return String(chars[start..<pos])
    }

    private mutating func collectBlockComment() -> String {
        let start = pos
        pos += 2
        while !isAtEnd {
            if current == "*", peek(1) == "/" {
                pos += 2
                break
            }
            pos += 1
        }
        return String(chars[start..<min(pos, chars.count)])
    }

    private mutating func collectQuoted(quote: Character) -> String {
        let start = pos
        pos += 1
        while !isAtEnd {
            if current == "\\" {
                pos += 2
                continue
            }
            if current == quote {
                pos += 1
                break
            }
            if current == "\n" {
                // Unterminated string: stop rather than swallowing the rest of the file.
                break
            }
            pos += 1
        }
        return String(chars[start..<min(pos, chars.count)])
    }

    private mutating func collectTemplate() -> String {
        let start = pos
        pos += 1
        while !isAtEnd {
            if current == "\\" {
                pos += 2
                continue
            }
            if current == "`" {
                pos += 1
                break
            }
            pos += 1
        }
        return String(chars[start..<min(pos, chars.count)])
    }

    private mutating func collectNumber() -> String {
        let start = pos
        while let c = current, c.isNumber || c == "." || c == "x" || c == "X" || c == "e" || c == "E" || c == "_" {
            pos += 1
        }
        if let c = current, c == "+" || c == "-" {
            if let before = peek(-1), before == "e" || before == "E" {
                pos += 1
                while let c = current, c.isNumber { pos += 1 }
            }
        }
        return String(chars[start..<pos])
    }

    private mutating func collectWord() -> String {
        let start = pos
        while let c = current, c.isLetter || c.isNumber || c == "_" || c == "$" { pos += 1 }
        return String(chars[start..<pos])
    }

    private mutating func collectOperator() -> String {
        let start = pos
        let triples = [">>>=", "...", "**=", "&&=", "||=", "??="]
        let pairs = ["=>", "==", "===", "!=", "!==", "<=", ">=", "&&", "||", "??", "?.", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "++", "--", "**", "<<", ">>", ">>>"]
        if pos + 3 <= chars.count {
            let candidate = String(chars[pos..<pos + 3])
            if triples.contains(candidate) {
                pos += 3
                return candidate
            }
        }
        if pos + 2 <= chars.count {
            let candidate = String(chars[pos..<pos + 2])
            if pairs.contains(candidate) {
                pos += 2
                return candidate
            }
        }
        pos += 1
        return String(chars[start..<pos])
    }
}
