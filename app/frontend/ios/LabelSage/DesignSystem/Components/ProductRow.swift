import SwiftUI
import LabelSageCore

/// Formatting and fallback rules behind `ProductRow`, kept apart from the view so they can be unit
/// tested (spec 07 "Product row stress cases").
nonisolated enum ProductRowFormat {
    /// US dollars with grouping and two decimals, "$12,499.99". `nil` when there is no price, so
    /// the row hides it. US only for the MVP (open question Q10).
    static func price(_ price: Decimal?) -> String? {
        price?.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    /// The letter on the pack fallback: the brand's first letter, else the name's, uppercased;
    /// "?" when both are blank.
    static func packInitial(brand: String?, name: String) -> String {
        for text in [brand, name] {
            if let first = text?.trimmingCharacters(in: .whitespacesAndNewlines).first {
                return String(first).uppercased()
            }
        }
        return "?"
    }

    /// "Brand · size", skipping what is missing.
    static func meta(brand: String?, size: String?) -> String {
        [brand, size]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
    }
}

/// The one shared product component (00-foundations `ProductRow`, boards 64 and 65): chat results,
/// search, go-tos, other options. Three styles:
/// - `.row`: 48 pt image, name in 2 lines, price then "Brand · size", finding chips.
/// - `.card`: 204 pt wide, 120 pt image, for horizontal "Other options" scrollers.
/// - `.compact`: one line for dense lists: name, then price and the first note or the meta.
///
/// The verdict sits on the image's bottom-right corner as a symbol on a white circle. A missing or
/// failed photo shows a pack-shaped tile with the brand's initial (the name's without a brand). A
/// missing price is hidden and the line keeps its height. Basket controls are parked (Q16).
// Custom row: no system cell carries a flag on a thumbnail (native-components.md, "Product row").
struct ProductRow: View {
    enum Style {
        case row
        case card
        case compact
    }

    /// One finding under the name: "Sunflower oil" at Not for, or the person line "Not for Mia · peanut".
    nonisolated struct Note: Hashable, Sendable {
        let level: Level
        let text: String
    }

    let product: Product
    /// The household's overall level, from `VerdictEngine`.
    let level: Level
    /// Who the verdict is for, for VoiceOver ("Verdict: Not for Mia").
    var names: [String] = ["you"]
    var notes: [Note] = []
    var style: Style = .row
    let action: () -> Void

    /// Spec 00: "Image 48 (row) or 120 (card)". The board draws 72 for the row (open question Q17).
    private static let thumbSide: CGFloat = 48
    private static let cardImageHeight: CGFloat = 120
    /// Spec 04: "horizontal cards (204 pt)".
    static let cardWidth: CGFloat = 204
    /// Prototype `ProductRow.dc.html`: chips 24 pt tall.
    private static let chipHeight: CGFloat = 24

    private var priceText: String? { ProductRowFormat.price(product.price) }
    private var metaText: String { ProductRowFormat.meta(brand: product.brand, size: product.size) }

    var body: some View {
        Button(action: action) {
            switch style {
            case .row: rowBody
            case .card: cardBody
            case .compact: compactBody
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Self.spokenLabel(name: product.name, price: priceText, level: level,
                                             names: names, notes: notes.map(\.text)))
    }

    // MARK: Styles

    private var rowBody: some View {
        HStack(spacing: Theme.spacing.m) {
            thumbnail(side: Self.thumbSide)
            VStack(alignment: .leading, spacing: 2) {
                name(lines: 2)
                priceAndMeta
                if !notes.isEmpty {
                    noteChips.padding(.top, Theme.spacing.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.spacing.m)
        .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.tile, style: .continuous))
    }

    private var compactBody: some View {
        HStack(spacing: Theme.spacing.m) {
            thumbnail(side: Self.thumbSide)
            VStack(alignment: .leading, spacing: 2) {
                name(lines: 1)
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing.xs) {
                    priceLabel()
                    if let note = notes.first {
                        Label {
                            Text(note.text)
                        } icon: {
                            Image(systemName: Theme.verdict.style(for: note.level).symbol)
                                .foregroundStyle(Theme.verdict.style(for: note.level).color)
                        }
                        .themeText(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    } else {
                        metaLabel
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.spacing.s)
        .padding(.horizontal, Theme.spacing.m)
        .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.tile, style: .continuous))
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xs) {
            ProductImage(product: product)
                .frame(maxWidth: .infinity)
                .frame(height: Self.cardImageHeight)
                .overlay(alignment: .bottomTrailing) {
                    // Prototype tiles: `right: 6px; bottom: 6px` inside the image.
                    VerdictBadge(level: level, side: 32, symbolSize: 22).offset(x: -6, y: -6)
                }
            Group {
                if let note = notes.first {
                    NoteChip(note: note, height: Self.chipHeight)
                }
                name(lines: 2)
                metaLabel
                priceLabel(inCard: true)
            }
            .padding(.horizontal, Theme.spacing.xxs)
        }
        .padding(Theme.spacing.s)
        .frame(width: Self.cardWidth, alignment: .topLeading)
        .themeCardBackground(cornerRadius: Theme.radius.tile, isSelected: false)
    }

    // MARK: Parts

    private func thumbnail(side: CGFloat) -> some View {
        ProductImage(product: product)
            .frame(width: side, height: side)
            .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.productThumb, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius.productThumb, style: .continuous)
                    .strokeBorder(Theme.color.hairline, lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                // Prototype: `right: -5px; bottom: -5px`, over the thumbnail's edge.
                VerdictBadge(level: level, side: 22, symbolSize: 16).offset(x: 5, y: 5)
            }
    }

    private func name(lines: Int) -> some View {
        Text(product.name)
            .themeText(lines == 1 ? .productLineName : .productRowName)
            .foregroundStyle(Theme.color.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(lines, reservesSpace: style == .card)
            .truncationMode(.tail)
    }

    /// Price leads, then "Brand · size". With neither, a hidden line keeps the row's height.
    private var priceAndMeta: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing.xs) {
            priceLabel()
            metaLabel
        }
    }

    /// The price, tabular, never wrapping (spec 07). In a row it keeps its full width; in the
    /// 204 pt card it shrinks to fit, and a missing price leaves a hidden line so cards line up.
    @ViewBuilder private func priceLabel(inCard: Bool = false) -> some View {
        if let priceText {
            let label = Text(priceText)
                .themeText(.price)
                .foregroundStyle(Theme.color.ink)
                .lineLimit(1)
            if inCard {
                label.minimumScaleFactor(0.7)
            } else {
                label.fixedSize()
            }
        } else if inCard {
            Text(verbatim: " ").themeText(.price).hidden()
        }
    }

    private var metaLabel: some View {
        // A space keeps the line's height when there is no price and no meta.
        Text(metaText.isEmpty && priceText == nil ? " " : metaText)
            .themeText(.footnote)
            .foregroundStyle(Theme.color.muted)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// One line of chips that fades out at the trailing edge instead of wrapping (prototype mask).
    private var noteChips: some View {
        // The chips sit in an overlay so their full width never widens the row.
        Text(verbatim: " ")
            .themeText(.noteChip)
            .frame(maxWidth: .infinity, minHeight: Self.chipHeight)
            .hidden()
            .overlay(alignment: .leading) {
                HStack(spacing: Theme.spacing.xxs) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { NoteChip(note: $0.element, height: Self.chipHeight) }
                }
                .fixedSize()
            }
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
    }

    /// Name, price, verdict, then the notes (spec 02: "name, price, then the person line").
    nonisolated static func spokenLabel(name: String, price: String?, level: Level, names: [String],
                                        notes: [String]) -> String {
        ([name, price, VerdictFlag.spokenLabel(level, names: names)] + notes)
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// A finding on the level's wash with its symbol (prototype `ProductRow.dc.html` chips).
/// `wraps` lets the text take more lines (cards and tiles at accessibility sizes) instead of truncating.
struct NoteChip: View {
    let note: ProductRow.Note
    var height: CGFloat = 24
    var wraps = false

    var body: some View {
        let style = Theme.verdict.style(for: note.level)
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing.xxs) {
            Image(systemName: style.symbol).foregroundStyle(style.color).fontWeight(.semibold)
            Text(note.text).lineLimit(wraps ? 4 : 1).fixedSize(horizontal: false, vertical: wraps)
        }
        .themeText(.noteChip)
        .foregroundStyle(Theme.color.ink)
        .padding(.horizontal, Theme.spacing.s)
        .padding(.vertical, wraps ? 3 : 0)
        .frame(minHeight: height)
        .background(RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(style.wash))
    }
}

/// The product photo, or the pack fallback when the photo is missing, loading or fails.
struct ProductImage: View {
    let product: Product

    var body: some View {
        // shortcut: native AsyncImage has no cache or retry; add them once a real ProductSource exists (D4).
        AsyncImage(url: product.imageURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().padding(Theme.spacing.xxs)
            } else {
                PackFallback(initial: ProductRowFormat.packInitial(brand: product.brand, name: product.name))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// The verdict on a product image: its symbol on a white circle, no ring and no text (board 62
/// "Photo signal", board 64 thumbnails). The row's VoiceOver label already reads the verdict.
struct VerdictBadge: View {
    let level: Level
    let side: CGFloat
    let symbolSize: CGFloat

    var body: some View {
        let style = Theme.verdict.style(for: level)
        Image(systemName: style.symbol)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(style.color)
            .frame(width: side, height: side)
            .background(Circle().fill(Theme.color.surface))
            .accessibilityHidden(true)
    }
}

/// A pack-shaped tile with the brand's initial (prototype `packStyle`: 58% × 78% of the image,
/// rounded more at the top than the bottom, a sand gradient and a soft bottom edge).
private struct PackFallback: View {
    let initial: String

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.58
            let height = min(proxy.size.height * 0.78, width * 1.6)
            let shape = UnevenRoundedRectangle(topLeadingRadius: width * 0.22, bottomLeadingRadius: width * 0.16,
                                               bottomTrailingRadius: width * 0.16, topTrailingRadius: width * 0.22,
                                               style: .continuous)
            shape
                .fill(LinearGradient(colors: [Theme.color.letterTile.mix(with: Theme.color.surface, by: 0.3),
                                              Theme.color.letterTile.mix(with: Theme.color.letterTileInk, by: 0.08)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottom) {
                    shape.stroke(Theme.color.letterTileInk.opacity(0.14), lineWidth: 1.5).mask(alignment: .bottom) {
                        Rectangle().frame(height: 3)
                    }
                }
                .overlay {
                    Text(initial)
                        .font(.custom("Outfit", fixedSize: min(width * 0.6, 40)).weight(.bold))
                        .foregroundStyle(Theme.color.letterTileInk)
                }
                .frame(width: width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

// MARK: - Previews

#if DEBUG
/// Demo products from `ProductRowStress.dc.html` and `Cards.dc.html`, with the made-up brands of
/// `sample-products.json` (real brands stay off the app).
enum ProductRowSamples {
    static func make(name: String, brand: String? = nil, size: String? = nil, imageURL: URL? = nil,
                     price: Decimal? = nil) -> Product {
        Product(name: name, brand: brand, size: size, ingredientsText: nil, imageURL: imageURL, price: price)
    }

    static let yogurt = ProductRowSamples.make(name: "Greek Yogurt, Plain 2%", brand: "Hillside", size: "32 oz", price: 5.49)
    static let chips = ProductRowSamples.make(name: "Popped Corn Chips, Kettle", brand: "Crunchwell", size: "3 oz", price: 4.29)
    static let oatBar = ProductRowSamples.make(name: "Oat Bar, Peanut Butter", brand: "Meadow", size: "1.8 oz", price: 1.99)
    static let kettle = ProductRowSamples.make(name: "Kettle Chips, Olive Oil & Sea Salt", brand: "Canyon Kettle", size: "5.25 oz", price: 4.49)
    static let longName = ProductRowSamples.make(
        name: "Organic Unsweetened Vanilla Almond and Coconut Barista Blend Plant-Based Beverage, Family Size, 96 fl oz",
        brand: "Some Really Long Brand Name Natural Foods Company", size: "96 fl oz", price: Decimal(string: "12499.99"))
    static let unbreakable = ProductRowSamples.make(name: "SupercalifragilisticProteinCrunchBarVarietyPackWithExtraLongUnbrokenName")
    static let oneLetter = ProductRowSamples.make(name: "Q", brand: "Q", price: 0.99)
    static let nonLatin = ProductRowSamples.make(name: "\u{62B9}\u{8336}\u{30E9}\u{30C6} \u{7121}\u{7CD6} Matcha Latte, Unsweetened, 12 \u{00D7} 330 ml",
                                  brand: "Kyoto Tea House", size: "12 pack", price: 34)
    static let failedPhoto = ProductRowSamples.make(name: "Creamy Peanut Butter, 16 oz", brand: "Northfield", size: "16 oz",
                                     imageURL: URL(string: "https://invalid.example/photo.png"), price: 3.29)
}

#Preview("ProductRow - row") {
    ScrollView {
        VStack(spacing: Theme.spacing.s) {
            ProductRow(product: ProductRowSamples.yogurt, level: .ok,
                       notes: [.init(level: .ok, text: "17 g protein"), .init(level: .ok, text: "2 ingredients")]) {}
            ProductRow(product: ProductRowSamples.chips, level: .notFor,
                       notes: [.init(level: .notFor, text: "Sunflower oil"), .init(level: .checkFirst, text: "Cane sugar")]) {}
            ProductRow(product: ProductRowSamples.oatBar, level: .checkFirst,
                       notes: [.init(level: .checkFirst, text: "Cane syrup"), .init(level: .ok, text: "No seed oils")]) {}
            ProductRow(product: ProductRowSamples.kettle, level: .ok) {}
        }
        .padding(Theme.spacing.l)
    }
    .background(Theme.screenTint.chat)
}

#Preview("ProductRow - stress") {
    ScrollView {
        VStack(spacing: Theme.spacing.s) {
            ProductRow(product: ProductRowSamples.longName, level: .checkFirst,
                       notes: [.init(level: .checkFirst, text: "Contains added cane sugar and natural flavors"),
                               .init(level: .ok, text: "No seed oils")]) {}
            ProductRow(product: ProductRowSamples.unbreakable, level: .cantConfirm,
                       notes: [.init(level: .cantConfirm, text: "No ingredient list in our data")]) {}
            ProductRow(product: ProductRowSamples.oneLetter, level: .ok) {}
            ProductRow(product: ProductRowSamples.nonLatin, level: .notFor, names: ["Mia", "Leo"],
                       notes: [.init(level: .notFor, text: "Milk \u{00B7} Mia and Leo are allergic")]) {}
            ProductRow(product: ProductRowSamples.failedPhoto, level: .notFor) {}
        }
        .padding(Theme.spacing.l)
    }
    .background(Theme.screenTint.chat)
}

#Preview("ProductRow - compact") {
    VStack(spacing: Theme.spacing.s) {
        ProductRow(product: ProductRowSamples.longName, level: .checkFirst, style: .compact) {}
        ProductRow(product: ProductRowSamples.make(name: "Creamy Peanut Butter, 16 oz", brand: "Northfield"), level: .notFor,
                   notes: [.init(level: .notFor, text: "Peanut, tree nuts and sesame \u{00B7} Mia, Leo and Sam are allergic")],
                   style: .compact) {}
        ProductRow(product: ProductRowSamples.make(name: "Q"), level: .cantConfirm, style: .compact) {}
    }
    .padding(Theme.spacing.l)
    .background(Theme.screenTint.chat)
}

#Preview("ProductRow - card") {
    ScrollView(.horizontal) {
        LazyHStack(spacing: Theme.spacing.m) {
            ProductRow(product: ProductRowSamples.kettle, level: .ok, names: ["you", "Mia"],
                       notes: [.init(level: .ok, text: "OK for you and Mia")], style: .card) {}
            ProductRow(product: ProductRowSamples.chips, level: .notFor,
                       notes: [.init(level: .notFor, text: "Sunflower oil")], style: .card) {}
            ProductRow(product: ProductRowSamples.unbreakable, level: .cantConfirm, style: .card) {}
        }
        .scrollTargetLayout()
        .padding(Theme.spacing.l)
    }
    .scrollTargetBehavior(.viewAligned)
    .background(Theme.screenTint.product)
}
#endif
