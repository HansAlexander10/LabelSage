import SwiftUI
import LabelSageCore

/// A vertical product card for horizontal carousels (board 65 "Product tiles"): the photo on top with
/// the flag badge on it, the name in 2 lines, the household verdict line, one reason chip, then the
/// price and size at the bottom. The whole tile is one button and one VoiceOver element. The
/// basket plus and stepper on the board are parked (Q16).
///
/// Used by "Healthier alternatives" on the product page and by the chat's other-options answer.
// Custom: no system cell carries a flag badge on a photo (native-components.md, "Product row").
struct ProductTile: View {
    let product: Product
    /// From `VerdictService` only.
    let verdict: HouseholdVerdict
    /// Whose rules give the green chips ("No seed oils"). nil reads the app's household.
    var household: Household? = nil
    var hint = "Opens the product page"
    let action: () -> Void

    @Environment(AppModel.self) private var appModel: AppModel?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Board 65 tiles: about 170 pt wide; grows with the text size so the words don't clip.
    @ScaledMetric(relativeTo: .body) private var scaledWidth: CGFloat = 168

    static let imageHeight: CGFloat = 120

    private var width: CGFloat { min(scaledWidth, 300) }
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }
    private var note: ProductRow.Note? {
        ProductFacts.notes(product: product, verdict: verdict, household: household ?? appModel?.household,
                           catalog: VerdictService.bundledCatalog, limit: 1).first
    }

    var body: some View {
        let note = self.note
        let price = ProductRowFormat.price(product.price)
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.spacing.xs) {
                ProductImage(product: product)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.imageHeight)
                    .overlay(alignment: .bottomTrailing) {
                        VerdictBadge(level: verdict.overall, side: 32, symbolSize: 22).offset(x: -2, y: -2)
                    }
                Text(product.name)
                    .themeText(.productRowName)
                    .foregroundStyle(Theme.color.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isLarge ? 5 : 2, reservesSpace: !isLarge)
                verdictLine
                if let note {
                    NoteChip(note: note, wraps: isLarge)
                }
                Spacer(minLength: 0)
                bottomLine(price: price)
            }
            .padding(Theme.spacing.s)
            .frame(width: width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .themeCardBackground(cornerRadius: Theme.radius.tile, isSelected: false)
            .contentShape(.rect(cornerRadius: Theme.radius.tile))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProductFacts.spokenLabel(name: product.name, verdictLine: verdict.line, price: price,
                                                     notes: note.map { [$0.text] } ?? [], extra: [product.size]))
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }

    private var verdictLine: some View {
        Text(verdict.line)
            .themeText(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.color.inkSecondary)
            .lineLimit(isLarge ? 4 : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "$4.49 · 5.25 oz": price first, then the size.
    @ViewBuilder private func bottomLine(price: String?) -> some View {
        let layout = isLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.spacing.xs))
        layout {
            if let price {
                Text(price).themeText(.price).foregroundStyle(Theme.color.ink).lineLimit(1).fixedSize()
            }
            if let size = product.size, !size.isEmpty {
                Text(size).themeText(.footnote).foregroundStyle(Theme.color.muted).lineLimit(isLarge ? 2 : 1)
            }
        }
    }
}

/// A horizontal carousel of `ProductTile`s whose height follows the tallest tile (so Dynamic Type
/// grows it instead of clipping).
struct ProductTileCarousel<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    var horizontalPadding: CGFloat = Theme.spacing.l
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Theme.spacing.m) {
                ForEach(items) { tile($0) }
            }
            // Ideal height = the tallest tile; every tile then stretches to it.
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, Theme.spacing.s)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }
}

// MARK: - Previews

#if DEBUG
/// Fixture products in every verdict state for the demo household (Alex and Mia).
enum ProductTilePreviewData {
    struct Item: Identifiable {
        let product: Product
        let verdict: HouseholdVerdict
        var id: String { product.id }
    }

    static let household = (try? SampleData.household()) ?? Household(people: [Person(id: "you", name: "you", isOwner: true)])

    /// The first fixture at each level, OK first.
    static func items(levels: [Level] = [.ok, .checkFirst, .notFor, .cantConfirm]) -> [Item] {
        let service = VerdictService()
        let checked = ((try? SampleData.products()) ?? []).map {
            Item(product: $0, verdict: service.check($0, for: household).verdict)
        }
        return levels.compactMap { level in checked.first { $0.verdict.overall == level } }
    }
}

#Preview("ProductTile - verdict states") {
    ProductTileCarousel(items: ProductTilePreviewData.items()) { item in
        ProductTile(product: item.product, verdict: item.verdict, household: ProductTilePreviewData.household) {}
    }
    .background(Theme.screenTint.product)
}

#Preview("ProductTile - AX5") {
    ProductTileCarousel(items: ProductTilePreviewData.items()) { item in
        ProductTile(product: item.product, verdict: item.verdict, household: ProductTilePreviewData.household) {}
    }
    .background(Theme.screenTint.product)
    .dynamicTypeSize(.accessibility5)
}
#endif
