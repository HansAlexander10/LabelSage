import SwiftUI
import LabelSageCore

/// The full product row for a chat answer (board 65 "Product row", plus the facts a person needs to
/// decide): the photo with the flag badge, the name in 2 lines, "$4.29 Brand · 3 oz", the household
/// verdict line naming people, up to 3 reason chips, and calories, protein and added sugar per serving.
/// Everything comes from the product data and `VerdictService`; no model text. The whole card is one
/// button and one VoiceOver element. At accessibility sizes the photo moves above the text.
// Custom: no system cell carries a flag badge on a thumbnail (native-components.md, "Product row").
struct ProductSummaryCard: View {
    let product: Product
    /// From `VerdictService` only.
    let verdict: HouseholdVerdict
    /// Whose rules give the green chips ("No seed oils"). nil reads the app's household.
    var household: Household? = nil
    var hint = "Opens the product page"
    let action: () -> Void

    @Environment(AppModel.self) private var appModel: AppModel?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Board 65 draws a 72 pt thumbnail in the row.
    private static let thumbSide: CGFloat = 72

    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let notes = ProductFacts.notes(product: product, verdict: verdict, household: household ?? appModel?.household,
                                       catalog: VerdictService.bundledCatalog, limit: 3)
        let price = ProductRowFormat.price(product.price)
        let meta = ProductRowFormat.meta(brand: product.brand, size: product.size)
        let nutrition = ProductFacts.nutritionLine(product.nutrition)
        let layout = isLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.spacing.m))
                             : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.spacing.m))
        Button(action: action) {
            layout {
                thumbnail
                VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                    Text(product.name)
                        .themeText(.productRowName)
                        .foregroundStyle(Theme.color.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isLarge ? 5 : 2)
                    priceAndMeta(price: price, meta: meta)
                    verdictLine.padding(.top, 2)
                    if !notes.isEmpty {
                        ChipFlowLayout(spacing: Theme.spacing.xxs) {
                            ForEach(notes, id: \.self) { NoteChip(note: $0, wraps: isLarge) }
                        }
                        .padding(.top, 2)
                    }
                    if let nutrition {
                        Text(nutrition)
                            .themeText(.footnote)
                            .foregroundStyle(Theme.color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
            .contentShape(.rect(cornerRadius: Theme.radius.card))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProductFacts.spokenLabel(name: product.name, verdictLine: verdict.line, price: price,
                                                     notes: notes.map(\.text), extra: [meta, nutrition]))
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }

    private var thumbnail: some View {
        ProductImage(product: product)
            .frame(width: Self.thumbSide, height: Self.thumbSide)
            .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.productThumb, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius.productThumb, style: .continuous)
                    .strokeBorder(Theme.color.hairline, lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                VerdictBadge(level: verdict.overall, side: 26, symbolSize: 19).offset(x: 5, y: 5)
            }
            .padding([.trailing, .bottom], 5)
    }

    /// Price leads, then "Brand · size".
    private func priceAndMeta(price: String?, meta: String) -> some View {
        let priceText = Text(verbatim: price.map { $0 + "  " } ?? "").font(Theme.TypeStyle.price.font).foregroundStyle(Theme.color.ink)
        let metaText = Text(verbatim: meta).font(Theme.TypeStyle.footnote.font).foregroundStyle(Theme.color.muted)
        return Text("\(priceText)\(metaText)")
            .lineLimit(isLarge ? 3 : 1)
            .truncationMode(.tail)
    }

    /// "Not for you · OK for Mia" with the worst level's symbol: the words carry the verdict, not the color.
    private var verdictLine: some View {
        let style = Theme.verdict.style(for: verdict.overall)
        return Label {
            Text(verdict.line)
                .themeText(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.color.ink)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: style.symbol).foregroundStyle(style.color).fontWeight(.semibold)
        }
        .labelStyle(.titleAndIcon)
        .font(Theme.TypeStyle.footnote.font)
    }
}

/// Lays chips left to right and wraps to the next line when a chip doesn't fit.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(Int, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
                size.width = min(size.width, width)
            }
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

#if DEBUG
#Preview("ProductSummaryCard - verdict states") {
    ScrollView {
        VStack(spacing: Theme.spacing.m) {
            ForEach(ProductTilePreviewData.items()) { item in
                ProductSummaryCard(product: item.product, verdict: item.verdict, household: ProductTilePreviewData.household) {}
            }
        }
        .padding(Theme.spacing.screenGutter)
    }
    .background(Theme.screenTint.chat)
}

#Preview("ProductSummaryCard - AX5") {
    ScrollView {
        VStack(spacing: Theme.spacing.m) {
            ForEach(ProductTilePreviewData.items(levels: [.notFor, .ok])) { item in
                ProductSummaryCard(product: item.product, verdict: item.verdict, household: ProductTilePreviewData.household) {}
            }
        }
        .padding(Theme.spacing.screenGutter)
    }
    .background(Theme.screenTint.chat)
    .dynamicTypeSize(.accessibility5)
}
#endif
