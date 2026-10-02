/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import Defaults
import CoreGraphics
import SwiftUI

public enum Style {
    case notch
    case floating
}

/// Controls how Atoll renders on external and non-notched displays.
/// - `notch`: Standard notch shape (concave top corners blending into the screen edge).
/// - `dynamicIsland`: Pill-shaped island with continuously rounded corners,
///   inspired by DynamicNotchKit's floating style. Only applies to screens
///   that do NOT have a physical notch.
enum ExternalDisplayStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case notch = "Standard Notch"
    case dynamicIsland = "Dynamic Island"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .notch:
            return String(localized: "Standard Notch")
        case .dynamicIsland:
            return String(localized: "Dynamic Island")
        }
    }

    var description: String {
        switch self {
        case .notch:
            return String(localized: "Classic notch shape that blends into the top screen edge")
        case .dynamicIsland:
            return String(localized: "Pill-shaped island with rounded corners, similar to iPhone's Dynamic Island")
        }
    }
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf
    case timer
    case stats
    case llmUsage
    case colorPicker
    case notes
    case clipboard
    case terminal
    case extensionExperience
}

/// Every entry point that can appear in the expanded notch tab bar.
///
/// Visibility is stored as a `[String: Bool]` map so new entries do not need a
/// dedicated `Defaults` key each. A missing key means "use the default", which is
/// visible — entries only ever disappear when the user explicitly hides them.
enum NotchEntry: String, CaseIterable, Identifiable {
    case home
    case shelf
    case timer
    case stats
    case llmUsage
    case notes
    case clipboard
    case terminal
    case codeFormatter
    case passwordGenerator

    var id: String { rawValue }

    /// Display order in Settings. Mirrors the tab bar so both read the same way.
    static let displayOrder: [NotchEntry] = [
        .home, .shelf, .timer, .stats, .llmUsage, .notes,
        .clipboard, .terminal, .codeFormatter, .passwordGenerator
    ]

    var localizedName: String {
        switch self {
        case .home: return String(localized: "Home")
        case .shelf: return String(localized: "Shelf")
        case .timer: return String(localized: "Timer")
        case .stats: return String(localized: "Stats")
        case .llmUsage: return String(localized: "Usage")
        case .notes: return String(localized: "Notes")
        case .clipboard: return String(localized: "Clipboard")
        case .terminal: return String(localized: "Terminal")
        case .codeFormatter: return String(localized: "Code Formatter")
        case .passwordGenerator: return String(localized: "Password Generator")
        }
    }

    /// Symbol used in Settings so the toggle row matches what sits in the tab bar.
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.fill"
        case .timer: return "timer"
        case .stats: return "chart.xyaxis.line"
        case .llmUsage: return "chart.bar.doc.horizontal"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .terminal: return "apple.terminal"
        case .codeFormatter: return "curlybraces"
        case .passwordGenerator: return "key.fill"
        }
    }

    /// One-line hint shown under each row in Settings.
    var localizedDescription: String {
        switch self {
        case .home: return String(localized: "Media controls, calendar and mirror widgets")
        case .shelf: return String(localized: "Dropped files held beside the notch")
        case .timer: return String(localized: "Countdown timers and presets")
        case .stats: return String(localized: "CPU, GPU, memory, network and disk insight")
        case .llmUsage: return String(localized: "LLM usage tracking")
        case .notes: return String(localized: "Quick notes captured from the notch")
        case .clipboard: return String(localized: "Clipboard history")
        case .terminal: return String(localized: "Drop-down terminal tab")
        case .codeFormatter: return String(localized: "Format JSON, YAML, SQL, HTML, CSS and JavaScript")
        case .passwordGenerator: return String(localized: "Generate a password matching your rules")
        }
    }

    /// The feature switch that must also be on for the entry to appear.
    /// `nil` means the entry has no separate feature gate.
    var requiresFeatureEnabled: Bool {
        switch self {
        case .codeFormatter: return Defaults[.enableCodeFormatter]
        case .passwordGenerator: return Defaults[.enablePasswordGenerator]
        default: return true
        }
    }

    var isHidden: Bool {
        NotchEntry.isHidden(self)
    }

    static func isHidden(_ entry: NotchEntry) -> Bool {
        Defaults[.notchEntryVisibility][entry.rawValue] ?? false
    }

    /// Whether the entry currently reaches the tab bar: the user has not hidden it
    /// and its backing feature (if any) is enabled.
    var isVisibleInTabBar: Bool {
        !isHidden && requiresFeatureEnabled
    }

    static func setHidden(_ hidden: Bool, for entry: NotchEntry) {
        var visibility = Defaults[.notchEntryVisibility]
        visibility[entry.rawValue] = hidden
        Defaults[.notchEntryVisibility] = visibility
    }

    /// Binding helper for SwiftUI toggles.
    static func hiddenBinding(for entry: NotchEntry) -> Binding<Bool> {
        Binding(
            get: { NotchEntry.isHidden(entry) },
            set: { NotchEntry.setHidden($0, for: entry) }
        )
    }

    /// Clears every stored override, restoring the default "show everything" state.
    static func resetAllVisibility() {
        Defaults[.notchEntryVisibility] = [:]
    }

    /// True when at least one entry has been explicitly hidden.
    static var hasCustomizations: Bool {
        Defaults[.notchEntryVisibility].contains { $0.value }
    }
}

/// Languages offered by the code formatter tool.
enum CodeFormatterLanguage: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case json
    case yaml
    case sql
    case html
    case css
    case javascript
    case xml

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .json: return String(localized: "JSON")
        case .yaml: return String(localized: "YAML")
        case .sql: return String(localized: "SQL")
        case .html: return String(localized: "HTML")
        case .css: return String(localized: "CSS")
        case .javascript: return String(localized: "JavaScript")
        case .xml: return String(localized: "XML")
        }
    }

    /// Lowercase file extensions that should map back onto this language.
    var aliases: [String] {
        switch self {
        case .json: return ["json", "jsonc"]
        case .yaml: return ["yaml", "yml"]
        case .sql: return ["sql"]
        case .html: return ["html", "htm", "vue", "svelte"]
        case .css: return ["css", "scss", "sass"]
        case .javascript: return ["js", "jsx", "ts", "tsx", "mjs", "cjs"]
        case .xml: return ["xml", "plist", "svg", "xhtml"]
        }
    }

    /// Best guess for a file name or extension string.
    static func language(forExtensionOrName value: String) -> CodeFormatterLanguage? {
        let cleaned = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let exact = allCases.first(where: { $0.rawValue == cleaned }) {
            return exact
        }
        return allCases.first { $0.aliases.contains(cleaned) }
    }

    /// Placeholder shown in the editor before anything is typed.
    var editorPlaceholder: String {
        switch self {
        case .json:
            return "{\n  \"name\": \"atoll\",\n  \"version\": \"2.3.3\"\n}"
        case .yaml:
            return "service:\n  image: nginx:latest\n  ports:\n    - \"80:80\""
        case .sql:
            return "select id, name from users where active = 1 order by created_at desc;"
        case .html:
            return "<div class=\"card\">\n  <h1>Atoll</h1>\n</div>"
        case .css:
            return ".card { display: flex; color: #fff; }"
        case .javascript:
            return "const greet = name => {\n  console.log(`hi ${name}`);\n};"
        case .xml:
            return "<note>\n  <to>team</to>\n  <body>hello</body>\n</note>"
        }
    }
}

enum NotesLayoutState: Equatable {
    case list
    case split
    case editor

    var preferredHeight: CGFloat {
        switch self {
        case .list:
            return 240
        case .split:
            return 260
        case .editor:
            return 320
        }
    }
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
    case circle = "Circle"
    
    var localizedName: String {
        switch self {
            case .progress:
                return String(localized: "Progress")
            case .percentage:
                return String(localized: "Percentage")
            case .circle:
                return String(localized: "Circle")
        }
    }
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
    
    var localizedName: String {
        switch self {
            case .white:
                return String(localized: "White")
            case .albumArt:
                return String(localized: "Match album art")
            case .accent:
                return String(localized: "Accent color")
        }
    }
}

enum LockScreenGlassStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case liquid = "Liquid Glass"
    case frosted = "Frosted Glass"
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .liquid:
            return String(localized: "Liquid Glass")
        case .frosted:
            return String(localized: "Frosted Glass")
        }
    }
}

enum LockScreenGlassCustomizationMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case standard = "Standard"
    case customLiquid = "Custom Liquid"

    var id: String { rawValue }

    var allowsVariantSelection: Bool {
        self == .customLiquid
    }
    
    var localizedName: String {
        switch self {
            case .standard:
                return String(localized: "Standard")
            case .customLiquid:
                return String(localized: "Custom Liquid")
        }
    }
}

enum LockScreenTimerSurfaceMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case classic = "Classic"
    case glass = "Glass"

    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .classic:
            return String(localized: "Classic")
        case .glass:
            return String(localized: "Glass")
        }
    }
}

enum LockScreenWeatherWidgetStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case inline = "Inline"
    case circular = "Circular"

    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .inline:
            return String(localized: "Inline")
        case .circular:
            return String(localized: "Circular")
        }
    }
}

enum LockScreenWeatherProviderSource: String, CaseIterable, Defaults.Serializable, Identifiable {
    case wttr = "wttr.in"
    case openMeteo = "Open Meteo"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var supportsAirQuality: Bool {
        switch self {
        case .wttr:
            return false
        case .openMeteo:
            return true
        }
    }
}

enum LockScreenWeatherTemperatureUnit: String, CaseIterable, Defaults.Serializable, Identifiable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"

    var id: String { rawValue }

    /// What macOS itself would show.
    ///
    /// The Temperature control in Language & Region is set independently of the
    /// measurement system, so this has to read the temperature preference rather
    /// than infer it: a US-region Mac can be set to Celsius and a metric one to
    /// Fahrenheit, and both happen. `UnitTemperature(forLocale:)` reports that
    /// preference; deriving it from a formatted measurement follows the
    /// measurement system instead and gets both of those cases backwards.
    ///
    /// Used only as the initial value: once someone picks a unit, that choice
    /// is stored and this is not consulted again.
    static var matchingSystemPreference: LockScreenWeatherTemperatureUnit {
        UnitTemperature(forLocale: .current) == .fahrenheit ? .fahrenheit : .celsius
    }

    var usesMetricSystem: Bool { self == .celsius }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    var openMeteoTemperatureParameter: String? {
        switch self {
        case .celsius: return nil
        case .fahrenheit: return "fahrenheit"
        }
    }

    var localizedName: String {
        switch self {
        case .celsius: return String(localized: "Celsius")
        case .fahrenheit: return String(localized: "Fahrenheit")
        }
    }
}

enum LockScreenWeatherAirQualityScale: String, CaseIterable, Defaults.Serializable, Identifiable {
    case us = "U.S. AQI"
    case european = "EAQI"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var compactLabel: String {
        switch self {
        case .us:
            return String(localized: "AQI")
        case .european:
            return String(localized: "EAQI")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .us:
            return String(localized: "AQI")
        case .european:
            return String(localized: "EAQI")
        }
    }

    var queryParameter: String {
        switch self {
        case .us:
            return "us_aqi"
        case .european:
            return "european_aqi"
        }
    }

    var gaugeRange: ClosedRange<Double> {
        switch self {
        case .us:
            return 0...500
        case .european:
            return 0...120
        }
    }
}

enum LockScreenReminderChipStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case eventColor = "Event color"
    case monochrome = "White"

    var id: String { rawValue }
    
    var localizedName: String {
            switch self {
            case .eventColor:
                return String(localized: "Event color")
            case .monochrome:
                return String(localized: "White")
            }
        }
}

/// Glyph contrast for lock-screen widgets sitting on the wallpaper.
/// Dark = light glyphs (default). Light = dark glyphs for bright wallpapers.
enum LockScreenWidgetAppearance: String, CaseIterable, Defaults.Serializable, Identifiable {
    case dark = "Dark"
    case light = "Light"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .dark:
            return String(localized: "Dark")
        case .light:
            return String(localized: "Light")
        }
    }

    /// When true, widgets use light (white) glyphs.
    var usesLightGlyphs: Bool { self == .dark }
}

enum TimerInputStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case ruler = "Ruler"
    case manual = "Manual"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ruler: return String(localized: "Ruler")
        case .manual: return String(localized: "Manual")
        }
    }
}
