import Foundation
import Testing
import LabelSageCore
@testable import LabelSage

/// The real logic in the T4 components: level → symbol and spoken word, price formatting, the pack
/// initial, and the person card summary.
struct VerdictFlagLogicTests {
    @Test func everyLevelHasItsSymbol() {
        #expect(Theme.verdict.style(for: .ok).symbol == "checkmark.circle")
        #expect(Theme.verdict.style(for: .checkFirst).symbol == "exclamationmark.triangle")
        #expect(Theme.verdict.style(for: .notFor).symbol == "nosign")
        #expect(Theme.verdict.style(for: .cantConfirm).symbol == "questionmark.circle.fill")
    }

    @Test func voiceOverReadsTheVerdictWithNames() {
        #expect(VerdictFlag.spokenLabel(.notFor, names: ["Mia"]) == "Verdict: Not for Mia")
        #expect(VerdictFlag.spokenLabel(.ok, names: ["you", "Mia"]) == "Verdict: OK for you and Mia")
        #expect(VerdictFlag.spokenLabel(.checkFirst, names: ["Mia"]) == "Verdict: Check first")
        #expect(VerdictFlag.spokenLabel(.cantConfirm, names: ["Mia"]) == "Verdict: Can\u{2019}t confirm")
    }

    @Test func noVerdictWordSaysSafe() {
        for level in Level.allCases {
            #expect(!VerdictFlag.spokenLabel(level, names: ["Mia"]).lowercased().contains("safe"))
        }
        #expect(!VerdictBanner.disclaimer.lowercased().contains("safe"))
    }
}

struct ProductRowFormatTests {
    @Test func pricesAreUSDollarsWithGrouping() {
        #expect(ProductRowFormat.price(Decimal(string: "12499.99")) == "$12,499.99")
        #expect(ProductRowFormat.price(Decimal(string: "0.99")) == "$0.99")
        #expect(ProductRowFormat.price(34) == "$34.00")
    }

    @Test func noPriceIsHidden() {
        #expect(ProductRowFormat.price(nil) == nil)
    }

    @Test func packInitialPrefersBrandThenName() {
        #expect(ProductRowFormat.packInitial(brand: "hillside", name: "Greek Yogurt") == "H")
        #expect(ProductRowFormat.packInitial(brand: nil, name: "supercalifragilistic") == "S")
        #expect(ProductRowFormat.packInitial(brand: "   ", name: "Q") == "Q")
        #expect(ProductRowFormat.packInitial(brand: " \n\t", name: "  northfield") == "N")
        #expect(ProductRowFormat.packInitial(brand: nil, name: "\u{62B9}\u{8336}") == "\u{62B9}")
        #expect(ProductRowFormat.packInitial(brand: nil, name: " ") == "?")
    }

    @Test func voiceOverReadsNamePriceVerdictThenNotes() {
        let label = ProductRow.spokenLabel(name: "Popped Corn Chips", price: "$4.29", level: .notFor,
                                           names: ["Mia"], notes: ["Sunflower oil", "Cane sugar"])
        #expect(label == "Popped Corn Chips, $4.29, Verdict: Not for Mia, Sunflower oil, Cane sugar")
        let noPrice = ProductRow.spokenLabel(name: "Q", price: nil, level: .cantConfirm, names: ["you"], notes: [])
        #expect(noPrice == "Q, Verdict: Can\u{2019}t confirm")
    }

    @Test func metaSkipsMissingParts() {
        #expect(ProductRowFormat.meta(brand: "Hillside", size: "32 oz") == "Hillside \u{00B7} 32 oz")
        #expect(ProductRowFormat.meta(brand: nil, size: "3 oz") == "3 oz")
        #expect(ProductRowFormat.meta(brand: "", size: nil) == "")
    }
}

struct PersonSummaryTests {
    private func item(_ id: String, _ kind: KindBadge.Kind, on: Bool = true) -> PersonItem {
        PersonItem(id: id, iconKey: id, title: id, detail: "", kind: kind, isOn: on)
    }

    @Test func countsAvoidAndPreferNotThatAreOn() {
        let items = [item("seed", .avoid), item("gluten", .avoid), item("sugar", .preferNot), item("bio", .preferNot, on: false)]
        #expect(PersonSummary.line(items) == "2 to avoid \u{00B7} 1 prefer not")
        #expect(PersonSummary.line([item("sugar", .preferNot)]) == "1 prefer not")
    }

    @Test func dietsAndGoalsCount() {
        #expect(PersonSummary.line([item("vegan", .diet)]) == "1 diet")
        #expect(PersonSummary.line([item("peanut", .avoid), item("vegan", .diet), item("protein", .goal)])
                == "1 to avoid \u{00B7} 1 diet \u{00B7} 1 goal")
        #expect(PersonSummary.line([item("vegan", .diet), item("halal", .diet)]) == "2 diets")
    }

    @Test func nothingOnSaysNothingToAvoid() {
        #expect(PersonSummary.line([]) == "Nothing to avoid yet")
        #expect(PersonSummary.line([item("peanut", .avoid, on: false)]) == "Nothing to avoid yet")
    }

    @Test func ownerIsYouAndInitialFallsBack() {
        #expect(PersonSummary.title(name: "Alex", isOwner: true) == "Alex (you)")
        #expect(PersonSummary.title(name: "Mia", isOwner: false) == "Mia")
        #expect(PersonSummary.initial(" mia") == "M")
        #expect(PersonSummary.initial("") == "?")
    }
}
