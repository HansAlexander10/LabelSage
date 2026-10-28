import SwiftUI
import LabelSageCore

/// "Compare with" (spec 05, board 40): picks the second product. The camera comes first, search by
/// name is one tap away, then recent products and other options. Every pick calls `onPick`; the host
/// then shows `CompareScreen`.
///
/// It is a sheet's content: it brings its own `NavigationStack`, large detent and Close.
/// Present it with `.sheet { CompareWithScreen(...) }`.
struct CompareWithScreen: View {
    let base: Product
    let source: any ProductSource
    let verdictService: VerdictService
    let household: Household
    let region: Region?
    /// Products checked before, shown first in the list (T13 passes the SwiftData history).
    var recent: [Product] = []
    let onPick: (Product) -> Void
    let onClose: () -> Void

    @State private var options: [ProductOption] = []
    @State private var query = ""
    @State private var results: [ProductOption] = []
    @State private var isSearching = false
    @State private var showCamera = false
    @FocusState private var searchFocused: Bool

    /// Spec 05: results after 2 characters, debounced 250 ms.
    static let minQuery = 2
    static let debounce: Duration = .milliseconds(250)

    init(base: Product, source: any ProductSource, verdictService: VerdictService, household: Household, region: Region?,
         recent: [Product] = [], onPick: @escaping (Product) -> Void, onClose: @escaping () -> Void) {
        self.base = base
        self.source = source
        self.verdictService = verdictService
        self.household = household
        self.region = region
        self.recent = recent
        self.onPick = onPick
        self.onClose = onClose
        baseVerdict = verdictService.check(base, for: household).verdict
    }

    /// The base product's verdict, checked once per init (a memo hit when the host re-runs it).
    private let baseVerdict: HouseholdVerdict
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsResults: Bool { trimmedQuery.count >= Self.minQuery }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing.l) {
                    if !showsResults {
                        comparingRow
                        cameraCard
                    }
                    list
                }
                .padding(.horizontal, Theme.spacing.l)
                .padding(.bottom, Theme.spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.screenTint.compareWith)
            .navigationTitle("Compare with")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close, action: onClose)
                }
            }
            .searchable(text: $query, isPresented: $isSearching,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name")
            .searchFocused($searchFocused)
            .task { await loadOptions() }
            .task(id: trimmedQuery) { await search() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.screenTint.compareWith)
        .fullScreenCover(isPresented: $showCamera) {
            // The camera returns straight into Compare; not found stays in the scan's own state.
            ScanScreen(source: source, verdictService: verdictService, household: household, region: region,
                       onClose: { showCamera = false },
                       onTypeName: {
                           showCamera = false
                           searchFocused = true
                       },
                       onResult: { product in
                           showCamera = false
                           onPick(product)
                       })
        }
    }

    // MARK: Parts

    private var comparingRow: some View {
        HStack(spacing: Theme.spacing.m) {
            ProductPhoto(product: base)
                .frame(width: 48, height: 48)
            Text("\(Text("Comparing ").foregroundStyle(Theme.color.muted))\(Text(base.name).fontWeight(.semibold))")
                .themeText(.body)
                .foregroundStyle(Theme.color.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            VerdictFlag(level: baseVerdict.overall, names: baseVerdict.people.map(\.name), size: .small, playsHaptic: false)
        }
        .padding(Theme.spacing.m)
        .background(Theme.color.surface, in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.l) {
            HStack(alignment: .top, spacing: Theme.spacing.m) {
                IconView(key: "check", size: Theme.size.iconInCard, decorative: true)
                VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                    Text("Check the other one")
                        .themeText(.sectionTitle)
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Scan its barcode or photo the ingredients")
                        .themeText(.callout)
                        .foregroundStyle(Theme.color.muted)
                }
            }
            PrimaryButton(title: "Open the camera", systemImage: "barcode.viewfinder", showsChevron: false) {
                showCamera = true
            }
        }
        .padding(Theme.spacing.l)
        .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.card, style: .continuous))
    }

    @ViewBuilder private var list: some View {
        let items = showsResults ? results : CompareWithLogic.offered(options, base: base)
        HStack(alignment: .lastTextBaseline) {
            if !showsResults {
                // The one LabelSage on this sheet.
                MascotView(state: .point, size: Theme.size.mascotSectionHeading, host: .sheet)
            }
            SectionHeader(showsResults ? "Results" : "Other options")
            Spacer(minLength: Theme.spacing.s)
            if !items.isEmpty {
                Text("Tap one to compare")
                    .themeText(.caption)
                    .foregroundStyle(Theme.color.muted)
            }
        }
        .padding(.top, Theme.spacing.s)
        if items.isEmpty {
            Text(showsResults ? "No products match \u{201C}\(trimmedQuery)\u{201D}." : "No other options yet. Open the camera to check one.")
                .themeText(.callout)
                .foregroundStyle(Theme.color.muted)
        }
        LazyVStack(spacing: Theme.spacing.m) {
            ForEach(items) { option in
                ProductRow(product: option.product, level: option.verdict.overall,
                           names: option.verdict.people.map(\.name), notes: notes(option)) {
                    onPick(option.product)
                }
                .accessibilityHint("Compare with \(base.name)")
            }
        }
    }

    /// The person line, then the deciding attribute ("Olive oil").
    private func notes(_ option: ProductOption) -> [ProductRow.Note] {
        var notes = [ProductRow.Note(level: option.verdict.overall, text: option.verdict.line)]
        if let attribute = CompareWithLogic.decidingAttribute(option, base: baseVerdict) {
            notes.append(ProductRow.Note(level: option.verdict.overall, text: attribute))
        }
        return notes
    }

    // MARK: Loading

    private func loadOptions() async {
        var found: [Product] = recent
        do {
            found += try await source.options(like: base, region: region, store: household.store, limit: 8)
        } catch {
            // Recent products still show; the list is complete without options.
            Log.lookup.notice("Compare options unavailable: \(String(describing: ProductSourceError(error)), privacy: .public)")
        }
        var seen: Set<String> = []
        options = found.filter { seen.insert($0.id).inserted }.map(check)
    }

    private func search() async {
        guard showsResults else {
            results = []
            return
        }
        do {
            try await Task.sleep(for: Self.debounce)
            let found = try await source.search(trimmedQuery, region: region, store: household.store, limit: 20)
            results = found.filter { $0.id != base.id }.map(check)
        } catch {
            let mapped = ProductSourceError(error)
            guard mapped != .cancelled else { return }
            Log.lookup.notice("Compare search failed: \(String(describing: mapped), privacy: .public)")
            results = []
        }
    }

    private func check(_ product: Product) -> ProductOption {
        verdictService.option(product, for: household)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Compare with - other options") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CompareWithScreen(base: ProductPagePreviewData.chips, source: FixtureProductSource(), verdictService: VerdictService(),
                          household: ProductPagePreviewData.household, region: ProductPagePreviewData.household.region,
                          onPick: { _ in }, onClose: {})
    }
    .environment(MascotPresence())
}

#Preview("Compare with - with recent") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CompareWithScreen(base: ProductPagePreviewData.oliveOilChips, source: FixtureProductSource(), verdictService: VerdictService(),
                          household: ProductPagePreviewData.household, region: nil,
                          recent: [ProductPagePreviewData.poppedChips, ProductPagePreviewData.riceCrackers],
                          onPick: { _ in }, onClose: {})
    }
    .environment(MascotPresence())
}
#endif
