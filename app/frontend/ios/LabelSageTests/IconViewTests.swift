import Testing
@testable import LabelSage
import UIKit

/// `IconCatalog` and `IconView` resolve every key in `icons.json` to a bundled asset, resolve
/// aliases, are case-insensitive and whitespace-trimmed, and fall back cleanly for unknown keys.
/// See `app/docs/labelsage-handoff/docs/icons.md`.
struct IconViewTests {
    @Test func everyIconKeyResolvesToABundledAsset() {
        #expect(IconCatalog.allKeys.count >= 125)
        for key in IconCatalog.allKeys {
            let entry = IconCatalog.entry(for: key)
            #expect(entry != nil, "icons.json key \"\(key)\" did not resolve")
            guard let entry else { continue }
            #expect(
                UIImage(named: entry.asset) != nil,
                "icons.json key \"\(key)\" points at asset \"\(entry.asset)\", not found in the bundle"
            )
        }
    }

    @Test func everyAliasTargetResolves() {
        for aliasKey in IconCatalog.allAliasKeys {
            #expect(IconCatalog.entry(for: aliasKey) != nil, "alias \"\(aliasKey)\" did not resolve")
        }
    }

    @Test func standInDecodesTrueForAStandInNut() {
        // icons.json: the "treenuts" key itself has no `standIn` (it's the category icon, using
        // chestnut directly), but each individual nut under it (almond, cashew, walnut, ...)
        // does carry `standIn: true` (icons.md: "every tree nut uses the chestnut").
        #expect(IconCatalog.entry(for: "almond")?.standIn == true)
        #expect(IconCatalog.entry(for: "treenuts")?.standIn == false)
    }

    @Test func aliasResolvesToItsTarget() {
        // icons.md / icons.json: "prawn" -> "shrimp".
        let prawn = IconCatalog.entry(for: "prawn")
        let shrimp = IconCatalog.entry(for: "shrimp")
        #expect(prawn != nil)
        #expect(prawn?.asset == shrimp?.asset)
        #expect(prawn?.label == "Shrimp")
    }

    @Test func lookupIsCaseInsensitiveAndTrimsWhitespace() {
        let exact = IconCatalog.entry(for: "shrimp")
        #expect(IconCatalog.entry(for: "SHRIMP") == exact)
        #expect(IconCatalog.entry(for: "  shrimp  ") == exact)
        #expect(IconCatalog.entry(for: "  ShRiMp  ") == exact)

        // Same, through an alias.
        let prawnExact = IconCatalog.entry(for: "prawn")
        #expect(IconCatalog.entry(for: "PRAWN") == prawnExact)
        #expect(IconCatalog.entry(for: "  Prawn  ") == prawnExact)
    }

    @Test func unknownKeyResolvesToNothing() {
        #expect(IconCatalog.entry(for: "quinoa") == nil)
        #expect(IconCatalog.entry(for: "") == nil)
        #expect(IconCatalog.entry(for: "   ") == nil)
    }

    @MainActor
    @Test func unknownKeyGivesIconViewTheMissingState() {
        let view = IconView(key: "quinoa", size: 44)
        #expect(view.state == .missing)
    }

    @MainActor
    @Test func knownKeyGivesIconViewTheLoadedState() {
        let view = IconView(key: "shrimp", size: 44)
        #expect(view.state == .loaded(assetName: "shrimp"))
    }
}
