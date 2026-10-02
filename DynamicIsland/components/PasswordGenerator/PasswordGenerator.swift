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

import AppKit
import Defaults
import Foundation
import Security
import SwiftUI

// MARK: - Strength

enum PasswordStrength: Comparable {
    case veryWeak
    case weak
    case fair
    case strong
    case veryStrong

    /// Entropy thresholds measured in bits, following the ranges commonly used
    /// by password managers.
    init(entropyBits: Double) {
        switch entropyBits {
        case ..<28: self = .veryWeak
        case ..<45: self = .weak
        case ..<60: self = .fair
        case ..<90: self = .strong
        default: self = .veryStrong
        }
    }

    /// Read from a dedicated table: "Fair" is also an air-quality level in the
    /// main catalog, and the two must not share a translation.
    var localizedName: String {
        switch self {
        case .veryWeak: return String(localized: "Very Weak", table: "PasswordGenerator")
        case .weak: return String(localized: "Weak", table: "PasswordGenerator")
        case .fair: return String(localized: "Fair", table: "PasswordGenerator")
        case .strong: return String(localized: "Strong", table: "PasswordGenerator")
        case .veryStrong: return String(localized: "Very Strong", table: "PasswordGenerator")
        }
    }

    /// Bar tint; red through green so the lead reads at a glance.
    var color: Color {
        switch self {
        case .veryWeak: return Color(red: 0.95, green: 0.28, blue: 0.30)
        case .weak: return Color(red: 0.96, green: 0.55, blue: 0.22)
        case .fair: return Color(red: 0.96, green: 0.78, blue: 0.24)
        case .strong: return Color(red: 0.42, green: 0.78, blue: 0.36)
        case .veryStrong: return Color(red: 0.24, green: 0.76, blue: 0.55)
        }
    }

    /// Fill fraction of the strength meter.
    var progress: Double {
        switch self {
        case .veryWeak: return 0.2
        case .weak: return 0.4
        case .fair: return 0.6
        case .strong: return 0.8
        case .veryStrong: return 1.0
        }
    }
}

// MARK: - Generator

/// Builds passwords that satisfy the rule set configured in Settings.
///
/// Randomness comes from `SecRandomCopyBytes` rather than the standard library
/// generators, which are not suitable for secrets.
final class PasswordGenerator: ObservableObject {
    static let shared = PasswordGenerator()

    private static let lowercaseSet = "abcdefghijklmnopqrstuvwxyz"
    private static let uppercaseSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let digitSet = "0123456789"
    /// Characters that look alike in common UI fonts and cause transcription errors.
    private static let ambiguousCharacters = Set("Il1O0o|`'")

    @Published private(set) var lastPassword: String = ""
    @Published private(set) var lastGenerationDate: Date?

    private init() {}

    // MARK: Rules

    struct Rules: Equatable {
        let length: Int
        let useLowercase: Bool
        let useUppercase: Bool
        let useDigits: Bool
        let useSymbols: Bool
        let customSymbols: String
        let excludeAmbiguous: Bool
        let requireEverySet: Bool
        let avoidRepeats: Bool
    }

    var currentRules: Rules {
        Rules(
            length: Int(Defaults[.passwordLength].rounded()),
            useLowercase: Defaults[.passwordIncludeLowercase],
            useUppercase: Defaults[.passwordIncludeUppercase],
            useDigits: Defaults[.passwordIncludeDigits],
            useSymbols: Defaults[.passwordIncludeSymbols],
            customSymbols: Defaults[.passwordCustomSymbols],
            excludeAmbiguous: Defaults[.passwordExcludeAmbiguous],
            requireEverySet: Defaults[.passwordRequireEverySet],
            avoidRepeats: Defaults[.passwordAvoidRepeats]
        )
    }

    /// The distinct character groups enabled by `rules`, filtered and de-duplicated.
    func groups(for rules: Rules) -> [String] {
        let explicitSymbols = Self.deduplicated(rules.customSymbols, filter: rules.excludeAmbiguous)
        var pools: [String] = []
        if rules.useLowercase { pools.append(Self.filtered(Self.lowercaseSet, excluding: rules.excludeAmbiguous)) }
        if rules.useUppercase { pools.append(Self.filtered(Self.uppercaseSet, excluding: rules.excludeAmbiguous)) }
        if rules.useDigits { pools.append(Self.filtered(Self.digitSet, excluding: rules.excludeAmbiguous)) }
        if rules.useSymbols { pools.append(explicitSymbols) }
        return pools.filter { !$0.isEmpty }
    }

    /// The symbols as they will actually be used: duplicates removed and, when
    /// requested, look-alikes dropped. Settings uses this to count the pool.
    func resolvedSymbolPreview(from symbols: String, excludeAmbiguous: Bool) -> String {
        Self.deduplicated(symbols, filter: excludeAmbiguous)
    }

    /// Message describing why generation cannot proceed, or `nil` when it can.
    func validationMessage(for rules: Rules) -> String? {
        guard Self.clampedLength(rules.length) >= 4 else {
            return String(localized: "Set a length of at least 4 characters.")
        }
        guard rules.length > 0 else {
            return String(localized: "Set a password length greater than zero.")
        }
        guard !groups(for: rules).isEmpty else {
            return String(localized: "Enable at least one character set.")
        }
        // Guaranteeing one of each class only makes sense when there is room for it.
        if rules.requireEverySet, rules.length < groups(for: rules).count {
            return String(localized: "Length is too short to include every selected character set.")
        }
        return nil
    }

    // MARK: Generation

    @discardableResult
    func generate() -> String {
        let rules = currentRules
        guard validationMessage(for: rules) == nil else {
            lastPassword = ""
            lastGenerationDate = nil
            return ""
        }

        let pools = groups(for: rules)
        let length = Self.clampedLength(rules.length)
        let characters = build(length: length, pools: pools, rules: rules)
        guard !characters.isEmpty else {
            lastPassword = ""
            return ""
        }

        let password = String(characters)
        lastPassword = password
        lastGenerationDate = Date()

        if Defaults[.passwordAutoCopyOnGenerate] {
            Self.copyToPasteboard(password)
        }
        return password
    }

    /// Entropy of the current password against the pool it was drawn from.
    func strength(for password: String) -> PasswordStrength {
        PasswordStrength(entropyBits: entropyBits(for: password))
    }

    /// Information content of `password`, assuming uniform draws from the
    /// combined character pool.
    func entropyBits(for password: String) -> Double {
        guard !password.isEmpty else { return 0 }
        let poolSize = Double(groups(for: currentRules).reduce(0) { $0 + $1.count })
        guard poolSize > 1 else { return 0 }
        return Double(password.count) * log2(poolSize)
    }

    // MARK: Private helpers

    private func build(length: Int, pools: [String], rules: Rules) -> [Character] {
        var characters: [Character] = []

        // Seed one character from each enabled set so "require every set" holds
        // even for short passwords.
        if rules.requireEverySet {
            for pool in pools where characters.count < length {
                characters.append(Self.pick(from: pool))
            }
        }

        let combined = pools.joined()
        while characters.count < length {
            characters.append(Self.pick(from: combined))
        }

        Self.shuffle(&characters)

        guard rules.avoidRepeats else { return Array(characters.prefix(length)) }
        return Self.smoothRepeats(characters, pools: pools)
    }

    /// Re-draws consecutive duplicate characters instead of leaving runs like "aa".
    private static func smoothRepeats(_ characters: [Character], pools: [String]) -> [Character] {
        var result = characters
        let combined = pools.joined()
        for index in stride(from: 1, to: result.count, by: 1) {
            guard result[index] == result[index - 1] else { continue }
            for _ in 0..<8 {
                let candidate = pick(from: combined)
                if candidate != result[index - 1] {
                    result[index] = candidate
                    break
                }
            }
        }
        return result
    }

    private static func clampedLength(_ length: Int) -> Int {
        min(max(length, 1), 256)
    }

    private static func pick(from pool: String) -> Character {
        let characters = Array(pool)
        guard !characters.isEmpty else { return "x" }
        return characters[secureIndex(characters.count)]
    }

    private static func shuffle(_ characters: inout [Character]) {
        guard characters.count > 1 else { return }
        for index in stride(from: characters.count - 1, to: 0, by: -1) {
            let other = secureIndex(index + 1)
            characters.swapAt(index, other)
        }
    }

    /// Uniform random index below `upperBound` using rejection sampling so every
    /// character is equally likely.
    private static func secureIndex(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        let bound = UInt32(upperBound)
        // The largest multiple of `bound` that fits; values at or above it are
        // discarded so the remainder never favours low indices.
        let limit = UInt32.max - (UInt32.max % bound)
        var bytes = [UInt8](repeating: 0, count: 4)
        repeat {
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                return Int.random(in: 0..<upperBound)
            }
            let value = bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
            if value < limit {
                return Int(value % bound)
            }
        } while true
    }

    private static func filtered(_ pool: String, excluding ambiguous: Bool) -> String {
        guard ambiguous else { return pool }
        return String(pool.filter { !ambiguousCharacters.contains($0) })
    }

    private static func deduplicated(_ symbols: String, filter ambiguous: Bool) -> String {
        var seen = Set<Character>()
        var result = ""
        for character in symbols {
            if ambiguous, ambiguousCharacters.contains(character) { continue }
            if seen.contains(character) { continue }
            seen.insert(character)
            result.append(character)
        }
        return result
    }

    static func copyToPasteboard(_ password: String) {
        guard !password.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
    }
}
