import SwiftUI
import LabelSageCore

/// Everything about one product, for everyone you shop for (spec 04, boards 30 and 31). One view used
/// two ways: pushed as a page (from a list, a go-to, Compare) or shown as a sheet (from the camera
/// with the photo hidden, and from the chat).
///
/// The flag comes only from `VerdictEngine`: the initial `verdict`, or a re-check when a "What you
/// avoid" switch is turned off for this check. `ExplanationService` may then rewrite the reason in
/// place (crossfade); the level never changes with it.
///
/// As a sheet it brings its own `NavigationStack`, medium and large detents, grabber and Close.
/// Present it with `.sheet(item:) { ProductPage(..., presentation: .sheet) }`.
struct ProductPage: View {
    nonisolated enum Presentation: Equatable, Sendable { case page, sheet }
    nonisolated enum Photo: Equatable, Sendable { case shown, hidden }

    /// What the page asks its host to do. Every action has a no-op default, so a host wires only what it has.
    struct Actions {
        /// "Compare" in a Healthier alternatives tile's menu.
        var compare: (Product) -> Void = { _ in }
        /// A "Healthier alternatives" tile. nil pushes that product's page in the current navigation stack
        /// (the sheet's own stack, or the host's for a page).
        var openOption: ((Product) -> Void)? = nil
        /// "See all" next to Healthier alternatives.
        var seeAllOptions: () -> Void = {}
        /// The heart: `true` when saved, `false` when removed. The page shows the toast.
        var setGoTo: (Bool) -> Void = { _ in }
        /// "View" in the "Saved to go-tos" toast.
        var viewGoTos: () -> Void = {}
        /// "Ask LabelSage" (nil) or "More about sunflower oil" (the question): the chat with this product.
        var ask: (String?) -> Void = { _ in }
        /// "Check another": the camera. From a sheet over the camera, the host closes the sheet.
        var checkAnother: () -> Void = {}
        /// "Photo the ingredients" when there is no ingredient list.
        var photoIngredients: () -> Void = {}
        /// Close on the sheet. nil dismisses the sheet.
        var close: (() -> Void)? = nil
    }

    let product: Product
    let household: Household
    var presentation: Presentation = .page
    var photo: Photo = .shown
    var actions = Actions()

    @Environment(\.verdictService) private var verdictService
    @Environment(\.explanationService) private var explanationService
    @Environment(\.productSource) private var productSource
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The engine's verdict for the full household; rows and their levels come from it.
    private let baseVerdict: HouseholdVerdict
    @State private var verdict: HouseholdVerdict
    /// "What you avoid" rows switched off for this check only. Never saved.
    @State private var switchedOff: Set<String> = []
    /// The deterministic reason, then the model's rewrite.
    @State private var reason: String
    @State private var options: [ProductOption] = []
    @State private var isGoTo: Bool
    @State private var toast: ToastMessage?
    @State private var miniHeader: Double = 0
    @State private var detent: PresentationDetent
    /// The option pushed when the host does not handle `openOption`.
    @State private var pushedOption: String?

    /// - Parameters:
    ///   - verdict: the engine's verdict for `household` (from `VerdictService`).
    ///   - isGoTo: whether the product is already in the go-tos.
    ///   - sheetDetent: the sheet's first detent; medium by default.
    init(product: Product, verdict: HouseholdVerdict, household: Household, presentation: Presentation = .page,
         photo: Photo = .shown, isGoTo: Bool = false, sheetDetent: PresentationDetent = .medium, actions: Actions = Actions()) {
        self.product = product
        self.household = household
        self.presentation = presentation
        self.photo = photo
        self.actions = actions
        self.baseVerdict = verdict
        _verdict = State(initialValue: verdict)
        _reason = State(initialValue: Self.worst(in: verdict)?.reason ?? "")
        _isGoTo = State(initialValue: isGoTo)
        _detent = State(initialValue: sheetDetent)
    }

    private var catalog: Catalog { VerdictService.bundledCatalog }
    private var avoidRows: [AvoidRow] { AvoidRow.rows(for: household, verdict: baseVerdict, catalog: catalog) }
    private var layout: ProductPageLayout {
        ProductPageLayout.make(product: product, verdict: verdict, photo: photo, options: options)
    }
    private var pose: MascotState { VerdictService.pose(for: verdict.overall) }
    /// Spec 04: hero 600 tall, 520 on small phones; 380 in a sheet (prototype).
    private func heroHeight(_ visible: CGFloat) -> CGFloat {
        presentation == .sheet ? 380 : (visible < 740 ? 520 : 600)
    }

    var body: some View {
        switch presentation {
        case .page:
            content
        case .sheet:
            NavigationStack { content }
                .presentationDetents([.medium, .large], selection: $detent)
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.screenTint.product)
        }
    }

    private var content: some View {
        // Built once per body and handed down, not once per use.
        let layout = self.layout
        let avoidRows = self.avoidRows
        let miniHeaderStart: CGFloat = layout.showsHero ? (presentation == .sheet ? 240 : 400) : 60
        return ScrollView {
            VStack(spacing: 0) {
                if layout.showsHero {
                    ProductHero(product: product, level: verdict.overall, names: verdict.people.map(\.name),
                                showsSignal: layout.signalOnHero)
                        .containerRelativeFrame(.vertical) { length, _ in heroHeight(length) }
                        // Sticky: the hero cancels its own scroll offset, so the content slides over it.
                        .visualEffect { content, proxy in
                            let minY = proxy.frame(in: .scrollView).minY
                            return content.offset(y: minY < 0 ? -minY : 0)
                        }
                        .zIndex(0)
                }
                pageContent(layout, avoidRows: avoidRows)
                    .background(Theme.screenTint.product,
                                in: UnevenRoundedRectangle(topLeadingRadius: layout.showsHero ? Theme.radius.phoneSheet : 0,
                                                           topTrailingRadius: layout.showsHero ? Theme.radius.phoneSheet : 0))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: layout.showsHero ? Theme.radius.phoneSheet : 0,
                                                      topTrailingRadius: layout.showsHero ? Theme.radius.phoneSheet : 0))
                    // Spec 04: the content sheet overlaps the photo by 28 pt.
                    .padding(.top, layout.showsHero ? -Theme.radius.phoneSheet : 0)
                    .zIndex(1)
            }
        }
        // The white hero runs up under the glass nav bar, as on board 30.
        .ignoresSafeArea(.container, edges: layout.showsHero ? .top : [])
        .background(Theme.screenTint.product)
        // Spec 04: the mini header comes in between 400 and 480 pt (after the name without a hero).
        // In 5 % steps, so the action runs a few times per pass, not on every scroll frame.
        .onScrollGeometryChange(for: Double.self) { geometry in
            let y = geometry.contentOffset.y + geometry.contentInsets.top
            return (Double(min(max((y - miniHeaderStart) / 80, 0), 1)) * 20).rounded() / 20
        } action: { _, progress in
            miniHeader = progress
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        // Only the glass buttons float over the content (board 30), no bar background.
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar { toolbar }
        .safeAreaBar(edge: .bottom) { bottomBar }
        .toast($toast)
        .task(id: product.id) { await loadOptions() }
        .task(id: verdict) { await explain() }
        .navigationDestination(item: $pushedOption) { id in
            if let option = options.first(where: { $0.id == id }) {
                ProductPage(product: option.product, verdict: option.verdict, household: household,
                            photo: photo, actions: actions)
            }
        }
    }

    // MARK: Content

    private func pageContent(_ layout: ProductPageLayout, avoidRows: [AvoidRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ProductTitleBlock(product: product, flag: layout.signalOnHero ? nil : verdict.overall,
                              names: verdict.people.map(\.name))
            forYou(layout)
                .padding(.horizontal, Theme.spacing.l)
                .padding(.top, Theme.spacing.l)
            if layout.showsAlternatives {
                AlternativesSection(options: options, household: household, open: open,
                                    compare: actions.compare, seeAll: actions.seeAllOptions)
                    .padding(.top, Theme.spacing.l)
            }
            AvoidRowsCard(product: product, label: verdict.label, rows: avoidRows, switchedOff: switchedOff) { id, isOn in
                if isOn { switchedOff.remove(id) } else { switchedOff.insert(id) }
                recheck()
            }
            .padding(.horizontal, Theme.spacing.l)
            .padding(.top, Theme.spacing.s)
            KeyIngredientsSection(rows: IngredientRow.rows(verdict: verdict, avoidRows: avoidRows, catalog: catalog),
                                  hasList: layout.hasIngredients, ask: actions.ask, photoIngredients: actions.photoIngredients)
                .padding(.horizontal, Theme.spacing.l)
                .padding(.top, Theme.spacing.xxl)
            NutritionSection(nutrition: layout.hasNutrition ? product.nutrition : nil,
                             servingGrams: NutritionFacts.grams(inServing: product.servingSize),
                             addedSugarFlagged: NutritionFacts.isFlagged(.addedSugarsG, verdict: verdict),
                             sodiumFlagged: NutritionFacts.isFlagged(.sodiumMg, verdict: verdict))
                .padding(.horizontal, Theme.spacing.l)
                .padding(.top, Theme.spacing.xxl)
        }
        .padding(.bottom, Theme.spacing.xxl)
    }

    private func forYou(_ layout: ProductPageLayout) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            HStack(alignment: .bottom) {
                SectionHeader("For you")
                // He moves here from the chat dock: the presence shows one LabelSage per screen.
                MascotView(state: pose, size: Theme.size.mascotSectionHeading, host: .sheet)
                    .padding(.trailing, Theme.spacing.s)
            }
            .padding(.leading, Theme.spacing.xxs)
            VerdictBanner(level: verdict.overall, title: Self.bannerTitle(verdict), reason: reason)
            if let age = layout.dataAge {
                Text(age).themeText(.footnote).foregroundStyle(Theme.color.muted).padding(.leading, Theme.spacing.xxs)
            }
        }
    }

    // MARK: Bars

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if presentation == .sheet {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) {
                    if let close = actions.close { close() } else { dismiss() }
                }
            }
        }
        ToolbarItem(placement: .principal) {
            MiniHeader(product: product, level: verdict.overall)
                .opacity(miniHeader)
                .accessibilityHidden(miniHeader < 0.5)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(isGoTo ? "Remove from go-tos" : "Add to go-tos", systemImage: isGoTo ? "heart.fill" : "heart") {
                toggleGoTo()
            }
            .symbolEffect(.bounce, value: isGoTo)
            .tint(isGoTo ? Theme.verdict.notFor.color : Theme.color.ink)
        }
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: Theme.spacing.s) {
            // Spec 04: the two buttons stack at AX sizes.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.spacing.s)) : AnyLayout(HStackLayout(spacing: Theme.spacing.s))
            layout { askButton; checkAnotherButton }
        }
        // 8 pt sides keep "Check another" on one line next to Ask on a 402 pt phone.
        .padding(.horizontal, Theme.spacing.s)
        .padding(.bottom, Theme.spacing.xs)
    }

    private var askButton: some View {
        Button { actions.ask(nil) } label: {
            Label("Ask \(Brand.mascot)", systemImage: "sparkles")
                // Prototype: 16/600.
                .themeText(.productRowName)
                .lineLimit(1)
                .foregroundStyle(Theme.color.ink)
                .frame(minHeight: 52)
        }
        .buttonStyle(.glass)
        .fixedSize()
    }

    private var checkAnotherButton: some View {
        PrimaryButton(title: "Check another", systemImage: "barcode.viewfinder", showsChevron: false, action: actions.checkAnother)
            .layoutPriority(1)
    }

    // MARK: Actions

    /// An alternative tile: the host's handler, else push that product's page.
    private func open(_ product: Product) {
        if let openOption = actions.openOption { openOption(product) } else { pushedOption = product.id }
    }

    /// Re-runs the engine without the switched-off choices. The flag, the banner and the reason follow.
    private func recheck() {
        let checked = AvoidRow.household(household, without: switchedOff, rows: avoidRows)
        let result = verdictService.check(product, for: checked).verdict
        withAnimation(Theme.motion.reasonCrossfade) {
            verdict = result
            reason = Self.worst(in: result)?.reason ?? ""
        }
    }

    /// The model's rewrite of the worst person's reason; keeps the engine line when it fails or is off.
    private func explain() async {
        guard let worst = Self.worst(in: verdict) else { return }
        let explanation = await explanationService.explain(worst, product: product)
        guard !Task.isCancelled, explanation.fromModel else { return }
        reason = explanation.text
    }

    private func loadOptions() async {
        do {
            // Ask for more than we show, so ranking can pick the best of the category.
            let found = try await productSource.options(like: product, region: household.region, store: household.store, limit: 40)
            let checked = found.map { verdictService.option($0, for: household) }
            options = ProductOption.alternatives(checked, to: product)
        } catch {
            // The section hides; the page is complete without it.
            Log.lookup.notice("Healthier alternatives unavailable: \(String(describing: ProductSourceError(error)), privacy: .public)")
            options = []
        }
    }

    private func toggleGoTo() {
        isGoTo.toggle()
        actions.setGoTo(isGoTo)
        if isGoTo {
            toast = ToastMessage(text: "Saved to go-tos", actionTitle: "View", action: actions.viewGoTos)
        } else {
            toast = ToastMessage(text: "Removed from go-tos", actionTitle: "Undo") { [actions] in
                isGoTo = true
                actions.setGoTo(true)
            }
        }
    }

    // MARK: Copy

    /// The person whose verdict is the household's: the first one at the overall level.
    nonisolated static func worst(in verdict: HouseholdVerdict) -> PersonVerdict? {
        verdict.decidingPerson
    }

    /// One person: "Not for you", "OK for you". More: the person line, "Not for you · OK for Mia".
    nonisolated static func bannerTitle(_ verdict: HouseholdVerdict) -> String {
        verdict.people.count > 1 ? verdict.line : Copy.flag(verdict.overall, names: verdict.people.map(\.name))
    }
}
