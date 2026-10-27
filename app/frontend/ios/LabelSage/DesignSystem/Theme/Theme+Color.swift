import SwiftUI
import LabelSageCore

nonisolated extension Theme {
    /// Flat colors from tokens.json `color`. Names and values match the tokens exactly.
    enum color {
        /// All text and icons on light grounds; selected outlines; checked boxes.
        static let ink = Color(hex: "#1d2b22")
        /// Secondary text.
        static let inkSecondary = Color(hex: "#3d4a42")
        /// Captions, meta, placeholders (5.5:1 on white).
        static let muted = Color(hex: "#6b6656")
        /// Captions on green and white cards.
        static let mutedGreen = Color(hex: "#6f7a73")
        /// Separators inside cards.
        static let hairline = Color(hex: "#e5e5ea")
        /// Unchecked checkbox and radio.
        static let controlBorder = Color(hex: "#e3e1df")
        /// Cards, tiles, fields.
        static let surface = Color(hex: "#ffffff")
        /// The one primary button per screen. Text on it is `ink` (7:1). Never white text on
        /// amber, never on a verdict.
        static let amber = Color(hex: "#eb9d15")
        /// Primary button while the step has no answer.
        static let amberDisabled = Color(hex: "#efe6d3")
        /// Not its own tokens.json key: quoted from `color.amberDisabled.usage`
        /// ("Primary button while the step has no answer; text #a89f8a").
        static let amberDisabledText = Color(hex: "#a89f8a")
        /// Switch on, links, brand moments.
        static let brandGreen = Color(hex: "#26834e")
        /// Small green text and links.
        static let brandGreenDeep = Color(hex: "#1b6b3e")
        /// Brand cream (splash wordmark, app icon).
        static let cream = Color(hex: "#fefbdc")
        /// Icon fallback tile background; the letter on it is `letterTileInk`.
        static let letterTile = Color(hex: "#f3ead8")
        static let letterTileInk = Color(hex: "#8a6a3a")
        /// LabelSage's bubble edge, and its red tint on a guard verdict (prototype `Chat.dc.html` `bubble`).
        static let bubbleEdge = Color(hex: "#4f2c1e").opacity(0.14)
        static let bubbleGuard = Color(hex: "#fff1ef")
        static let bubbleGuardEdge = Color(hex: "#c0352b").opacity(0.28)
    }

    /// One verdict's color, wash and symbol from tokens.json `verdict`. "Color and symbol always
    /// travel together; the word appears wherever there is room. These colors are for verdicts
    /// only, never decoration." (tokens.json verdict.rule)
    nonisolated struct VerdictStyle: Sendable {
        let color: Color
        let wash: Color
        /// SF Symbol name.
        let symbol: String
        /// Template string with a `{names}` placeholder; use `word(names:)` rather than reading
        /// this directly.
        private let wordTemplate: String

        init(color: Color, wash: Color, symbol: String, wordTemplate: String) {
            self.color = color
            self.wash = wash
            self.symbol = symbol
            self.wordTemplate = wordTemplate
        }

        /// Fills tokens.json's `{names}` placeholder, e.g. `Theme.verdict.ok.word(names: "Mia")`
        /// -> "OK for Mia". A no-op replace for levels whose word has no placeholder
        /// (`checkFirst`, `cantConfirm`), so every verdict can be called the same way.
        func word(names: String) -> String {
            wordTemplate.replacingOccurrences(of: "{names}", with: names)
        }
    }

    enum verdict {
        static let ok = VerdictStyle(
            color: Color(hex: "#1dbf73"),
            wash: Color(hex: "#e4f7ee"),
            symbol: "checkmark.circle",
            wordTemplate: "OK for {names}"
        )
        static let checkFirst = VerdictStyle(
            color: Color(hex: "#ffd449"),
            wash: Color(hex: "#fff5cc"),
            symbol: "exclamationmark.triangle",
            wordTemplate: "Check first"
        )
        static let notFor = VerdictStyle(
            color: Color(hex: "#ef4b3f"),
            wash: Color(hex: "#ffe9e6"),
            symbol: "nosign",
            wordTemplate: "Not for {names}"
        )
        /// Stone wash, muted ink symbol. Never styled like `ok`. Color is `Theme.color.muted`
        /// (tokens.json gives both the same `#6b6656`, so this reuses the one constant).
        static let cantConfirm = VerdictStyle(
            color: Theme.color.muted,
            wash: Color(hex: "#f4f0d8"),
            symbol: "questionmark.circle.fill",
            wordTemplate: "Can\u{2019}t confirm"
        )

        /// Maps an engine `Level` (`LabelSageCore`) to its `VerdictStyle`. The engine decides the
        /// level; this only decides how that level looks.
        static func style(for level: Level) -> VerdictStyle {
            switch level {
            case .ok: ok
            case .checkFirst: checkFirst
            case .notFor: notFor
            case .cantConfirm: cantConfirm
            }
        }
    }

    /// One chip kind's background and badge tint from tokens.json `chips`.
    nonisolated struct ChipStyle: Sendable {
        let background: Color
        let badge: Color
    }

    enum chip {
        /// Avoid (hides it).
        static let avoid = ChipStyle(background: Color(hex: "#fbe9e5"), badge: Color(hex: "#fbe1dc"))
        /// Prefer not (shows it lower).
        static let preferNot = ChipStyle(background: Color(hex: "#fdf3da"), badge: Color(hex: "#fdf0cf"))
        /// Diet, goal.
        static let dietGoal = ChipStyle(background: Color(hex: "#e9f4ec"), badge: Color(hex: "#e6f2ea"))
    }

    /// Per-screen background "room" colors from tokens.json `screenTint`. "Each kind of screen
    /// sits on its own tint, like a room. White cards float on it."
    enum screenTint {
        static let welcome = Color(hex: "#eaf3f8")
        static let region = Color(hex: "#eaf3f8")
        static let store = Color(hex: "#eaf3f8")
        static let household = Color(hex: "#ffffff")
        static let goal = Color(hex: "#f3f1fb")
        static let why = Color(hex: "#fdf6ea")
        static let allergens = Color(hex: "#fbf1ef")
        static let severity = Color(hex: "#fbf1ef")
        static let medical = Color(hex: "#fbf1ef")
        static let strict = Color(hex: "#fbf1ef")
        static let diet = Color(hex: "#eef8f1")
        static let religion = Color(hex: "#eef8f1")
        static let avoid = Color(hex: "#fdf6ea")
        static let numbers = Color(hex: "#f3f1fb")
        static let summary = Color(hex: "#eef8f1")
        static let chat = Color(hex: "#eef8f1")
        static let scan = Color(hex: "#000000")
        static let product = Color(hex: "#fdf6ea")
        static let compareWith = Color(hex: "#f3f1fb")
        static let compare = Color(hex: "#f3f1fb")
        static let family = Color(hex: "#fdf6ea")
        /// Avatar tint rotation (household members without a photo).
        static let avatarTints: [Color] = [
            Color(hex: "#ffe3b3"),
            Color(hex: "#d8ecdf"),
            Color(hex: "#e6e0fb"),
            Color(hex: "#fbdcd6"),
        ]
    }
}

/// `Color(hex:)` is private to this file: the only place in the app allowed to parse a raw hex
/// string. Every other file reads `Theme.color.*`, `Theme.verdict.*`, `Theme.chip.*` or
/// `Theme.screenTint.*`; views never use raw hex.
private nonisolated extension Color {
    init(hex: String) {
        var scanned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if scanned.hasPrefix("#") { scanned.removeFirst() }

        assert(
            scanned.count == 6 || scanned.count == 8,
            "Theme Color(hex:) expects 6 (#RRGGBB) or 8 (#RRGGBBAA) hex digits, got \"\(hex)\" (\(scanned.count))"
        )

        var value: UInt64 = 0
        Scanner(string: scanned).scanHexInt64(&value)

        let r: Double
        let g: Double
        let b: Double
        let a: Double
        switch scanned.count {
        case 8: // #RRGGBBAA
            r = Double((value & 0xFF00_0000) >> 24) / 255
            g = Double((value & 0x00FF_0000) >> 16) / 255
            b = Double((value & 0x0000_FF00) >> 8) / 255
            a = Double(value & 0x0000_00FF) / 255
        default: // #RRGGBB (every tokens.json color is this shape)
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }
}
