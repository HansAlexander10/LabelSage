import SwiftUI
import LabelSageCore

// The product page's parts, top to bottom (spec 04 "Layout").

// MARK: - Hero and header

/// The white photo hero: the pack photo, or a pack tile with the brand initial, and the 60 pt photo signal.
struct ProductHero: View {
    let product: Product
    let level: Level
    let names: [String]
    let showsSignal: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.color.surface
            ProductPhoto(product: product)
                // Spec 04: pack photo 380 × 400, centered.
                .frame(maxWidth: 380, maxHeight: 400)
                .padding(.top, 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsSignal {
                // Hidden from VoiceOver: the banner says it (spec 04).
                VerdictFlag(level: level, names: names, size: .large)
                    .accessibilityHidden(true)
                    .padding(.trailing, Theme.spacing.l)
                    .padding(.bottom, 44)
            }
        }
    }
}

/// The product photo, or the pack tile when there is none or it fails.
struct ProductPhoto: View {
    let product: Product

    var body: some View {
        // shortcut: one photo, no paging dots; the data has one imageURL. Add a paged TabView with up to 3 photos when a source has more.
        AsyncImage(url: product.imageURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().blendMode(.multiply)
            } else {
                PackTile(initial: ProductRowFormat.packInitial(brand: product.brand, name: product.name))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A pack-shaped tile with the brand's initial (spec 04 "No photo").
// Custom: a placeholder shape; no system view draws a product pack.
struct PackTile: View {
    let initial: String

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.6, proxy.size.height * 0.6)
            RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                .fill(Theme.color.letterTile)
                .overlay {
                    Text(initial)
                        .font(.custom("Outfit", fixedSize: width * 0.46).weight(.bold))
                        .foregroundStyle(Theme.color.letterTileInk)
                }
                .frame(width: width, height: width * 1.3)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

/// The board 65 title treatment: brand, the name semibold in 2 lines, then the meta line led by the
/// price ("$4.29 · 3 oz · 3 servings of 28 g"), then the category. Without the photo signal the flag
/// sits next to the name (spec 04 "No photo").
struct ProductTitleBlock: View {
    let product: Product
    /// The flag next to the name; nil when it is on the photo.
    let flag: Level?
    let names: [String]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                if let brand = product.brand {
                    Text(brand).themeText(.callout).foregroundStyle(Theme.color.muted)
                }
                Text(product.name)
                    .themeText(.productName)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .accessibilityAddTraits(.isHeader)
                metaLine.padding(.top, Theme.spacing.xxs)
                if let category = product.category {
                    Text(category).themeText(.footnote).foregroundStyle(Theme.color.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let flag {
                VerdictFlag(level: flag, names: names, size: .medium).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.spacing.screenGutter)
        .padding(.top, Theme.spacing.l)
        .padding(.bottom, 18)
        .background(Theme.color.surface)
    }

    /// Price first, then size and servings.
    @ViewBuilder private var metaLine: some View {
        let price = ProductRowFormat.price(product.price)
        let size = ProductHeader.sizeLine(size: product.size, servingSize: product.servingSize)
        if price != nil || size != nil {
            let priceText = Text(verbatim: price.map { size == nil ? $0 : $0 + " \u{00B7} " } ?? "")
                .font(Theme.TypeStyle.bodyStrong.font).foregroundStyle(Theme.color.ink)
            let sizeText = Text(verbatim: size ?? "").font(Theme.TypeStyle.body.font).foregroundStyle(Theme.color.inkSecondary)
            Text("\(priceText)\(sizeText)")
        }
    }
}

/// The nav bar's principal item after scrolling: 36 pt thumb, the name and a small flag symbol.
struct MiniHeader: View {
    let product: Product
    let level: Level

    var body: some View {
        let style = Theme.verdict.style(for: level)
        HStack(spacing: Theme.spacing.s) {
            ProductPhoto(product: product)
                .frame(width: 36, height: 36)
                .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.productThumb))
            Text(product.name).themeText(.bodyStrong).foregroundStyle(Theme.color.ink).lineLimit(1)
            Image(systemName: style.symbol).foregroundStyle(style.color).fontWeight(.semibold).accessibilityHidden(true)
        }
        .frame(maxWidth: 240)
    }
}

// MARK: - For you

/// "May contain" and "What you avoid" with a per-check switch per row (spec 04 "Rows").
struct AvoidRowsCard: View {
    let product: Product
    let label: ParsedLabel
    let rows: [AvoidRow]
    let switchedOff: Set<String>
    let setOn: (String, Bool) -> Void

    @State private var isOpen = false
    @State private var showsMayContainInfo = false

    /// The pack's "may contain" line, or nil when the pack says nothing.
    private var mayContain: String? {
        if !label.mayContain.isEmpty { return label.mayContain.joined(separator: ", ") }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.spacing.s) {
                Text("May contain").themeText(.body).foregroundStyle(Theme.color.ink)
                Spacer(minLength: Theme.spacing.s)
                Text(mayContain ?? "Not on the pack")
                    .themeText(.body).foregroundStyle(Theme.color.muted).multilineTextAlignment(.trailing)
                if mayContain == nil {
                    Button("About may contain", systemImage: "questionmark.circle.fill") { showsMayContainInfo = true }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.color.muted)
                        .frame(minWidth: Theme.size.minTap, minHeight: Theme.size.minTap)
                        .popover(isPresented: $showsMayContainInfo) {
                            Text("US labels don\u{2019}t have to print \u{2018}may contain\u{2019}. No line on the pack doesn\u{2019}t mean none.")
                                .themeText(.callout)
                                .padding()
                                .frame(idealWidth: 280)
                                .presentationCompactAdaptation(.popover)
                        }
                }
            }
            .frame(minHeight: 48)
            .padding(.horizontal, Theme.spacing.l)
            Divider().padding(.horizontal, Theme.spacing.l)
            if rows.isEmpty {
                Text("Nothing to avoid is set. General check only.")
                    .themeText(.callout).foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, Theme.spacing.l)
            } else {
                DisclosureGroup(isExpanded: $isOpen) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            Divider()
                            Toggle(isOn: Binding(get: { !switchedOff.contains(row.id) }, set: { setOn(row.id, $0) })) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(row.label).themeText(.body).foregroundStyle(Theme.color.ink)
                                    if rows.contains(where: { $0.personId != row.personId }) {
                                        Text("For \(row.personName) \u{00B7} \(Copy.flag(row.level, names: [row.personName]))")
                                            .themeText(.footnote).foregroundStyle(Theme.color.muted)
                                    }
                                }
                            }
                            .tint(Theme.color.brandGreen)
                            .frame(minHeight: 48)
                            .accessibilityHint("Turning it off changes this check only.")
                        }
                        if !switchedOff.isEmpty {
                            Text("For this check only")
                                .themeText(.footnote).foregroundStyle(Theme.color.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Theme.spacing.xxs)
                                .transition(.opacity)
                        }
                    }
                    .padding(.bottom, Theme.spacing.s)
                } label: {
                    HStack(spacing: Theme.spacing.s) {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.color.brandGreen).accessibilityHidden(true)
                        Text("What you avoid").themeText(.bodyStrong).foregroundStyle(Theme.color.brandGreenDeep)
                        Spacer(minLength: Theme.spacing.xs)
                        Text(AvoidRow.summary(rows)).themeText(.caption).foregroundStyle(Theme.color.inkSecondary)
                    }
                    .frame(minHeight: 52)
                }
                .tint(Theme.color.muted)
                .padding(.horizontal, Theme.spacing.l)
                .background(Theme.screenTint.product.opacity(0.6))
            }
        }
        .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
        .clipShape(.rect(cornerRadius: Theme.radius.card, style: .continuous))
        .themeAnimation(Theme.motion.reasonCrossfade, value: switchedOff)
    }
}

// MARK: - Healthier alternatives

/// "Healthier alternatives": one carousel of product tiles (board 65) right under the verdict, OK for
/// everyone first, then Check first (`ProductOption.alternatives`). A tile opens its product page; its
/// context menu offers Compare. Hidden by the page when none fit.
struct AlternativesSection: View {
    let options: [ProductOption]
    let household: Household
    let open: (Product) -> Void
    let compare: (Product) -> Void
    let seeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { title; Spacer(minLength: Theme.spacing.s); seeAllButton }
                VStack(alignment: .leading, spacing: Theme.spacing.xxs) { title; seeAllButton }
            }
            .padding(.horizontal, Theme.spacing.screenGutter)
            ProductTileCarousel(items: options) { option in
                ProductTile(product: option.product, verdict: option.verdict, household: household) {
                    open(option.product)
                }
                .contextMenu {
                    Button("Compare", systemImage: "arrow.left.arrow.right") { compare(option.product) }
                }
            }
        }
    }

    private var title: some View {
        Text("Healthier alternatives")
            .themeText(.cardTitle)
            .foregroundStyle(Theme.color.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private var seeAllButton: some View {
        Button("See all", action: seeAll)
            .themeText(.bodyStrong)
            .foregroundStyle(Theme.color.brandGreenDeep)
            .accessibilityHint("Compares this product with others")
    }
}

// MARK: - Key ingredients

/// "Key ingredients 4": three rows, then "See all"; a row opens in place (spec 04).
struct KeyIngredientsSection: View {
    let rows: [IngredientRow]
    let hasList: Bool
    let ask: (String?) -> Void
    let photoIngredients: () -> Void

    @State private var openRow: Int?
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            Text("Key ingredients \(Text(hasList ? "\(rows.count)" : "").fontWeight(.regular).foregroundStyle(Theme.color.muted))")
                .themeText(.sectionTitle)
                .foregroundStyle(Theme.color.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, Theme.spacing.xxs)
            VStack(spacing: 0) {
                if hasList {
                    let shown = showsAll ? rows : Array(rows.prefix(IngredientRow.collapsedCount))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { offset, row in
                        if offset > 0 { Divider().padding(.leading, 50) }
                        rowView(row)
                    }
                    if rows.count > IngredientRow.collapsedCount {
                        Divider()
                        seeAll
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.spacing.m) {
                        Text("No ingredient list for this one yet. Photo the ingredients and I\u{2019}ll read them.")
                            .themeText(.callout).foregroundStyle(Theme.color.inkSecondary)
                        Button("Photo the ingredients", systemImage: "camera", action: photoIngredients)
                            .themeText(.bodyStrong)
                            .foregroundStyle(Theme.color.brandGreenDeep)
                            .frame(minHeight: Theme.size.minTap)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.spacing.l)
                }
            }
            .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
        }
    }

    @ViewBuilder private var seeAll: some View {
        if rows.count > IngredientRow.pushListAfter {
            NavigationLink {
                IngredientListView(rows: rows)
            } label: {
                Text("See all \(rows.count) ingredients").frame(maxWidth: .infinity, minHeight: 48)
            }
            .themeText(.callout).foregroundStyle(Theme.color.brandGreen)
        } else {
            Button {
                withAnimation(Theme.motion.easeOut(duration: 0.22)) { showsAll.toggle() }
            } label: {
                Label(showsAll ? "Show fewer" : "See all \(rows.count) ingredients",
                      systemImage: showsAll ? "chevron.up" : "chevron.down")
                    .labelStyle(TrailingIconLabelStyle())
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .themeText(.callout).foregroundStyle(Theme.color.brandGreen)
        }
    }

    private func rowView(_ row: IngredientRow) -> some View {
        let style = Theme.verdict.style(for: row.level)
        let isOpen = openRow == row.id
        return VStack(alignment: .leading, spacing: Theme.spacing.xs) {
            Button {
                withAnimation(Theme.motion.easeOut(duration: 0.22)) { openRow = isOpen ? nil : row.id }
            } label: {
                HStack(spacing: Theme.spacing.m) {
                    Image(systemName: style.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(style.color)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).themeText(.body).foregroundStyle(Theme.color.ink)
                        Text(row.tone).themeText(.footnote).foregroundStyle(Theme.color.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(Theme.color.muted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .frame(minHeight: 60)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.name), \(row.tone)")
            .accessibilityValue(isOpen ? "Open" : "Closed")
            if isOpen {
                VStack(alignment: .leading, spacing: Theme.spacing.xs) {
                    Text(row.why).themeText(.callout).foregroundStyle(Theme.color.inkSecondary)
                    Button("More about \(row.name.lowercased())") { ask("More about \(row.name.lowercased())") }
                        .themeText(.callout)
                        .foregroundStyle(Theme.color.brandGreen)
                }
                .padding(.leading, 34)
                .padding(.bottom, Theme.spacing.m)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.spacing.l)
    }
}

/// The full list for 40+ ingredients (spec 04 "Many ingredients").
struct IngredientListView: View {
    let rows: [IngredientRow]

    var body: some View {
        List(rows) { row in
            let style = Theme.verdict.style(for: row.level)
            Label {
                VStack(alignment: .leading) {
                    Text(row.name).themeText(.body)
                    Text(row.tone).themeText(.footnote).foregroundStyle(Theme.color.muted)
                }
            } icon: {
                Image(systemName: style.symbol).foregroundStyle(style.color)
            }
        }
        .navigationTitle("Ingredients")
    }
}

/// Text then icon: "See all 4 ingredients ⌄".
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.spacing.xs) { configuration.title; configuration.icon.imageScale(.small) }
    }
}
