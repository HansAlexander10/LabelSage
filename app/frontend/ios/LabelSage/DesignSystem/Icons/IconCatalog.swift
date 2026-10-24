import Foundation

/// One entry from `icons.json` (handoff `assets/icons.json`): a key's Fluent Emoji 3D asset,
/// VoiceOver label and category. See `app/docs/labelsage-handoff/docs/icons.md`.
nonisolated struct IconEntry: Decodable, Sendable, Equatable {
    /// VoiceOver label, e.g. "Shrimp".
    let label: String
    let category: String
    let source: String
    /// The image set name in `LabelSageIcons.xcassets`.
    let asset: String
    /// `true` when Fluent has no exact icon for this key and the nearest one is used instead
    /// (icons.md: "Nearest stand-ins", 15 keys).
    let standIn: Bool

    private enum CodingKeys: String, CodingKey {
        case label, category, source, asset, standIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        category = try container.decode(String.self, forKey: .category)
        source = try container.decode(String.self, forKey: .source)
        asset = try container.decode(String.self, forKey: .asset)
        standIn = try container.decodeIfPresent(Bool.self, forKey: .standIn) ?? false
    }
}

/// Loads `Resources/icons.json` once and resolves an icon key (or alias) to its `IconEntry`.
/// `IconView` is this catalog's only reader; look there for how a resolved entry becomes an image
/// or a fallback letter tile.
nonisolated enum IconCatalog {
    /// Mirrors the top-level shape of `icons.json`; only the two fields `IconView` needs.
    private struct File: Decodable {
        let icons: [String: IconEntry]
        let aliases: [String: String]
    }

    private static let file: File = {
        guard
            let url = Bundle.main.url(forResource: "icons", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            assertionFailure("IconCatalog: icons.json not found in the app bundle")
            return File(icons: [:], aliases: [:])
        }
        do {
            return try JSONDecoder().decode(File.self, from: data)
        } catch {
            assertionFailure("IconCatalog: failed to decode icons.json: \(error)")
            return File(icons: [:], aliases: [:])
        }
    }()

    /// Resolves `key`, or one of its aliases (icons.json `aliases`, e.g. "prawn" -> "shrimp"), to
    /// its `IconEntry`. Case-insensitive and trims whitespace. `nil` when `key` (and any alias it
    /// names) is unknown.
    static func entry(for key: String) -> IconEntry? {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if let direct = file.icons[normalized] {
            return direct
        }
        if let aliasTarget = file.aliases[normalized] {
            return file.icons[aliasTarget]
        }
        return nil
    }

    /// Every icon key in `icons.json`, for tests that need to check all of them. Not used by
    /// `IconView` itself.
    static var allKeys: [String] { Array(file.icons.keys) }

    /// Every alias key in `icons.json`, for tests that need to check all of them resolve. Not
    /// used by `IconView` itself.
    static var allAliasKeys: [String] { Array(file.aliases.keys) }
}
