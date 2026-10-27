import SwiftUI
import LabelSageCore

/// "Compare" (spec 05, board 41): two products side by side for everyone you shop for. Differences
/// (default) shows only what differs; Everything shows equal rows too. "Save to go-tos" saves the
/// better one (or the picked one when both have the same verdict).
///
/// Both flags come from `VerdictService` (the engine), checked here for `household`; nothing else
/// sets a level. One view used two ways: pushed as a page, or shown as a large sheet with its own
/// `NavigationStack` and Close.
struct CompareScreen: View {
    nonisolated enum Presentation: Equatable, Sendable { case page, sheet }
    nonisolated enum Filter: Hashable, Sendable { case differences, everything }

    let household: Household
    var presentation: Presentation = .page
    /// "Save to go-tos": the product saved.
    let onSaveGoTo: (Product) -> Void
    /// "Undo" in the saved toast: the product to remove again.
    let onUndoSave: (Product) -> Void
    /// A product column: that product's page.
    let onOpen: (Product) -> Void
    /// Close on the sheet, Back on "That's the same product". nil dismisses.
    let onClose: (() -> Void)?

    private let summary: CompareSummary
    @State private var filter: Filter = .differences
    @State private var isSaved: Bool
    @State private var toast: ToastMessage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - left: the product you started from.
    ///   - right: the one picked in Compare with.
    ///   - isGoTo: whether a product is already a go-to; asked for the bar's product.
    init(left: Product, right: Product, household: Household, verdictService: VerdictService,
         presentation: Presentation = .page, isGoTo: (Product) -> Bool = { _ in false },
         onSaveGoTo: @escaping (Product) -> Void = { _ in }, onUndoSave: @escaping (Product) -> Void = { _ in },
         onOpen: @escaping (Product) -> Void = { _ in }, onClose: (() -> Void)? = nil) {
        self.household = household
        self.presentation = presentation
        self.onSaveGoTo = onSaveGoTo
        self.onUndoSave = onUndoSave
        self.onOpen = onOpen
        self.onClose = onClose
        let summary = Self.summary(left: verdictService.option(left, for: household),
                                   right: verdictService.option(right, for: household),
                                   household: household, catalog: verdictService.engine.catalog)
        self.summary = summary
        _isSaved = State(initialValue: isGoTo(summary.option(summary.barSide).product))
    }

    /// The last summary made, so the host re-running this init (every body of the sheet's host)
    /// does not build it again for the same two products and household.
    private static var lastSummary: (left: ProductOption, right: ProductOption, household: Household, summary: CompareSummary)?

    private static func summary(left: ProductOption, right: ProductOption, household: Household,
                                catalog: Catalog) -> CompareSummary {
        if let last = lastSummary, last.left == left, last.right == right, last.household == household {
            return last.summary
        }
        let summary = CompareSummary.make(left: left, right: right, household: household, catalog: catalog)
        lastSummary = (left, right, household, summary)
        return summary
    }

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }
    private var leftName: String { CompareSummary.shortName(summary.left.product) }
    private var rightName: String { CompareSummary.shortName(summary.right.product) }
    private var barOption: ProductOption { summary.option(summary.barSide) }

    var body: some View {
        switch presentation {
        case .page:
            content
        case .sheet:
            NavigationStack { content }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.screenTint.compare)
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            if summary.isSameProduct {
                ContentUnavailableView {
                    Label("That\u{2019}s the same product.", systemImage: "equal.circle")
                } description: {
                    Text("Pick another one to compare.")
                } actions: {
                    Button("Back", action: close).buttonStyle(.glass)
                }
            } else {
                scroll
            }
        }
        .background(Theme.screenTint.compare)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentation == .sheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close, action: close)
                }
            }
        }
        .toast($toast)
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.l) {
                columns
                Picker("Show", selection: $filter) {
                    Text("Differences").tag(Filter.differences)
                    Text("Everything").tag(Filter.everything)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: filter)
                CompareWhyCard(title: summary.whyTitle, lines: summary.whyLines)
                tableSection("Key ingredients", rows: summary.ingredientRows, header: nil, isNutrition: false)
                tableSection("Nutrition", rows: summary.nutritionRows, header: summary.servingNote, isNutrition: true)
            }
            .padding(.horizontal, Theme.spacing.l)
            .padding(.bottom, Theme.spacing.xxl)
            .themeAnimation(Theme.motion.easeOut(duration: 0.22), value: filter)
        }
        .safeAreaBar(edge: .bottom) { bottomBar }
    }

    // MARK: Columns

    @ViewBuilder private var columns: some View {
        let layout = isStacked ? AnyLayout(VStackLayout(spacing: Theme.spacing.m))
                               : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.spacing.m))
        layout {
            CompareColumn(option: summary.left, isBest: summary.better == .left) { onOpen(summary.left.product) }
            CompareColumn(option: summary.right, isBest: summary.better == .right) { onOpen(summary.right.product) }
        }
    }

    // MARK: Tables

    private func tableSection(_ title: String, rows: [CompareRow], header: String?, isNutrition: Bool) -> some View {
        let shown = filter == .everything ? rows : rows.filter(\.differs)
        return VStack(alignment: .leading, spacing: Theme.spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing.xs) {
                SectionHeader(title)
                // Spec 05: the count always shows.
                Text(CompareSummary.differCount(rows))
                    .themeText(.callout)
                    .foregroundStyle(Theme.color.muted)
            }
            CompareTable(rows: shown, header: header, leftName: leftName, rightName: rightName,
                         isNutrition: isNutrition, isStacked: isStacked)
            if isNutrition {
                Text("Bold marks the better value for what you avoid and your goals.")
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, Theme.spacing.xxs)
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        let option = barOption
        let layout = isStacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.spacing.s))
                               : AnyLayout(HStackLayout(spacing: Theme.spacing.s))
        return layout {
            HStack(spacing: Theme.spacing.s) {
                ProductPhoto(product: option.product)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.product.name)
                        .themeText(.productRowName)
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    PersonLine(option.verdict)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            saveButton
        }
        .padding(Theme.spacing.s)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.radius.card, style: .continuous))
        .padding(.horizontal, Theme.spacing.m)
        .padding(.bottom, Theme.spacing.xs)
    }

    @ViewBuilder private var saveButton: some View {
        if isSaved {
            VStack(alignment: .leading, spacing: 0) {
                Label("Saved to go-tos", systemImage: "checkmark")
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.color.brandGreenDeep)
                Text("Checked again every time")
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.muted)
            }
            .frame(minHeight: Theme.size.primaryButtonHeight)
            .padding(.horizontal, Theme.spacing.m)
            .accessibilityElement(children: .combine)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            PrimaryButton(title: "Save to go-tos", systemImage: "heart", showsChevron: false, action: save)
                .fixedSize(horizontal: !isStacked, vertical: false)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    // MARK: Actions

    private func save() {
        let product = barOption.product
        withAnimation(Theme.motion.easeOut(duration: 0.2)) { isSaved = true }
        onSaveGoTo(product)
        toast = ToastMessage(text: "Saved \(CompareSummary.shortName(product)) to your go-tos. I check it again every time.",
                             actionTitle: "Undo") {
            withAnimation(Theme.motion.easeOut(duration: 0.2)) { isSaved = false }
            onUndoSave(product)
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

// MARK: - Parts

/// One product column: image with the flag, brand, name (2 lines), size and NOVA. The better one gets
/// a green outline and "Works for you" when it is OK for everyone.
private struct CompareColumn: View {
    let option: ProductOption
    let isBest: Bool
    let open: () -> Void

    private var showsBadge: Bool { isBest && option.verdict.overall == .ok }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                ProductPhoto(product: option.product)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .overlay(alignment: .bottomTrailing) {
                        VerdictFlag(level: option.verdict.overall, names: option.verdict.people.map(\.name),
                                    size: .small, playsHaptic: false)
                    }
                    .overlay(alignment: .topLeading) {
                        if showsBadge {
                            Text("Works for you")
                                .themeText(.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, Theme.spacing.s)
                                .padding(.vertical, Theme.spacing.xxs)
                                .background(Theme.color.brandGreen, in: .capsule)
                        }
                    }
                if let brand = option.product.brand {
                    Text(brand)
                        .themeText(.caption)
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                }
                Text(option.product.name)
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(2, reservesSpace: true)
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing.xs) {
                    if let size = option.product.size {
                        Text(size).themeText(.bodyStrong).foregroundStyle(Theme.color.ink)
                    }
                    if let nova = option.product.nova {
                        Text("NOVA \(nova)").themeText(.footnote).foregroundStyle(Theme.color.muted)
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .padding(Theme.spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.tile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous)
                    .strokeBorder(isBest ? Theme.verdict.ok.color : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([showsBadge ? "Works for you" : nil, option.product.brand, option.product.name,
                             option.product.size, option.verdict.line].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens the product")
    }
}

/// "Why Canyon Kettle works for you": up to three lines from the engine findings, then the disclaimer.
struct CompareWhyCard: View {
    let title: String
    let lines: [CompareWhyLine]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            HStack(alignment: .bottom, spacing: Theme.spacing.s) {
                // The one LabelSage on this screen (board 41 puts him on the why card).
                MascotView(state: .compare, size: Theme.size.mascotSectionHeading, host: .sheet)
                Text(title)
                    .themeText(.cardTitle)
                    .foregroundStyle(Theme.color.brandGreenDeep)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(lines, id: \.self) { line in
                Label {
                    Text(line.text).themeText(.body).foregroundStyle(Theme.color.ink)
                } icon: {
                    Image(systemName: Theme.verdict.style(for: line.level).symbol)
                        .foregroundStyle(Theme.verdict.style(for: line.level).color)
                }
            }
            Text("Check the packages. Not medical advice.")
                .themeText(.footnote)
                .foregroundStyle(Theme.color.muted)
        }
        .padding(Theme.spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.card, style: .continuous))
    }
}

/// A compare table (spec 05 `CompareTable`). Ingredients: the row label above two colored cells.
/// Nutrition: label and two value columns, the better value bold and green with a check.
/// At accessibility sizes each cell is on its own line, labeled with its product.
struct CompareTable: View {
    let rows: [CompareRow]
    /// "Per 28 g serving" for nutrition.
    let header: String?
    let leftName: String
    let rightName: String
    let isNutrition: Bool
    let isStacked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isStacked { headerRow }
            if rows.isEmpty {
                Text("Nothing differs here.")
                    .themeText(.callout)
                    .foregroundStyle(Theme.color.muted)
                    .padding(Theme.spacing.l)
            }
            ForEach(rows) { row in
                Divider().overlay(Theme.color.hairline)
                rowView(row)
                    .padding(.horizontal, Theme.spacing.l)
                    .padding(.vertical, Theme.spacing.s)
                    .frame(minHeight: 42)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.spoken(leftName: leftName, rightName: rightName))
                    .transition(.opacity)
            }
        }
        .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.card, style: .continuous))
        .clipShape(.rect(cornerRadius: Theme.radius.card, style: .continuous))
    }

    private var headerRow: some View {
        Grid(horizontalSpacing: Theme.spacing.m) {
            GridRow {
                if isNutrition {
                    Text(header ?? "").frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(leftName).lineLimit(1).frame(maxWidth: .infinity, alignment: isNutrition ? .trailing : .leading)
                Text(rightName).lineLimit(1).frame(maxWidth: .infinity, alignment: isNutrition ? .trailing : .leading)
            }
        }
        .themeText(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(Theme.color.inkSecondary)
        .padding(.horizontal, Theme.spacing.l)
        .padding(.vertical, Theme.spacing.m)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func rowView(_ row: CompareRow) -> some View {
        if isStacked {
            VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                Text(row.label).themeText(.callout).foregroundStyle(Theme.color.muted)
                cell("\(leftName): \(row.left)", level: row.leftLevel, isBetter: row.better == .left)
                cell("\(rightName): \(row.right)", level: row.rightLevel, isBetter: row.better == .right)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isNutrition {
            Grid(horizontalSpacing: Theme.spacing.m) {
                GridRow {
                    Text(row.label).themeText(.body).foregroundStyle(Theme.color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    cell(row.left, level: nil, isBetter: row.better == .left)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    cell(row.right, level: nil, isBetter: row.better == .right)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label).themeText(.footnote).foregroundStyle(Theme.color.muted)
                Grid(horizontalSpacing: Theme.spacing.m) {
                    GridRow {
                        cell(row.left, level: row.leftLevel, isBetter: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        cell(row.right, level: row.rightLevel, isBetter: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// An ingredient cell carries its level symbol; a better nutrition value is bold, green and checked
    /// (spec 05: bold is never the only cue).
    @ViewBuilder private func cell(_ text: String, level: Level?, isBetter: Bool) -> some View {
        if let level {
            let style = Theme.verdict.style(for: level)
            Label {
                Text(text).themeText(.body).foregroundStyle(Theme.color.ink)
            } icon: {
                Image(systemName: style.symbol).foregroundStyle(style.color)
            }
        } else {
            HStack(spacing: 3) {
                if isBetter {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold))
                }
                Text(text).themeText(.number)
            }
            .fontWeight(isBetter ? .bold : .regular)
            .foregroundStyle(isBetter ? Theme.color.brandGreen : Theme.color.inkSecondary)
        }
    }
}

// MARK: - Previews

#if DEBUG
private extension View {
    func comparePreviewEnvironment() -> some View { environment(MascotPresence()) }
}

private func comparePreview(_ left: Product, _ right: Product, presentation: CompareScreen.Presentation = .page,
                            isSaved: Bool = false) -> CompareScreen {
    CompareScreen(left: left, right: right, household: ProductPagePreviewData.household, verdictService: VerdictService(),
                  presentation: presentation, isGoTo: { _ in isSaved })
}

#Preview("Compare - page, Not for vs OK") {
    NavigationStack { comparePreview(ProductPagePreviewData.chips, ProductPagePreviewData.oliveOilChips) }
        .comparePreviewEnvironment()
}

#Preview("Compare - sheet") {
    Color.clear.sheet(isPresented: .constant(true)) {
        comparePreview(ProductPagePreviewData.poppedChips, ProductPagePreviewData.oliveOilChips, presentation: .sheet)
    }
    .comparePreviewEnvironment()
}

#Preview("Compare - can't confirm on one side") {
    NavigationStack { comparePreview(ProductPagePreviewData.riceCrackers, ProductPagePreviewData.oliveOilChips) }
        .comparePreviewEnvironment()
}

#Preview("Compare - no nutrition on one side") {
    NavigationStack { comparePreview(ProductPagePreviewData.trailMix, ProductPagePreviewData.chips) }
        .comparePreviewEnvironment()
}

#Preview("Compare - saved") {
    NavigationStack { comparePreview(ProductPagePreviewData.chips, ProductPagePreviewData.oliveOilChips, isSaved: true) }
        .comparePreviewEnvironment()
}

#Preview("Compare - same product") {
    NavigationStack { comparePreview(ProductPagePreviewData.chips, ProductPagePreviewData.chips) }
        .comparePreviewEnvironment()
}

#Preview("Compare - AX5") {
    NavigationStack { comparePreview(ProductPagePreviewData.chips, ProductPagePreviewData.oliveOilChips) }
        .comparePreviewEnvironment()
        .dynamicTypeSize(.accessibility5)
}
#endif
