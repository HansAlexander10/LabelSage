import SwiftUI
import LabelSageCore

/// First open: Launch, Welcome, then the owner's questions, region and store, to the summary
/// (spec 01, changed 2026-10-27). A self-contained feature: it takes its services as closures and
/// reports the household through `onFinish`; the app shell (T13) saves it and opens chat home (D1).
///
/// With `OnboardingModel(addingTo:)` it is the "Add someone you shop for" flow from Family: it
/// reports the new person through `onSavePerson`, and Back on its first step calls `onCancel`.
struct OnboardingFlow: View {
    /// A sample product for the summary's "Try it" line; hidden when nil.
    var tryItProduct: Product?
    /// Stores near the region for the store step (`ProductSource.stores(near:)`).
    var loadStores: (Region) async throws -> [Store]
    /// "Use my location": the region from the location, or nil when denied or failed (then the
    /// search field takes focus).
    var locate: () async -> Region?
    /// "Check my first product": the household, with its region (always set) and store (optional).
    let onFinish: (Household) -> Void
    /// Add a person: the new person to append to the saved household.
    var onSavePerson: (Person) -> Void = { _ in }
    /// Add a person: Back on the name step closes the flow.
    var onCancel: () -> Void = {}

    @State private var model: OnboardingModel
    @State private var showsLaunch: Bool

    init(model: OnboardingModel = OnboardingModel(),
         showsLaunch: Bool = true,
         tryItProduct: Product? = nil,
         loadStores: @escaping (Region) async throws -> [Store] = { _ in OnboardingCatalog.demoStores },
         locate: @escaping () async -> Region? = { nil },
         onSavePerson: @escaping (Person) -> Void = { _ in },
         onCancel: @escaping () -> Void = {},
         onFinish: @escaping (Household) -> Void) {
        _model = State(initialValue: model)
        _showsLaunch = State(initialValue: showsLaunch)
        self.tryItProduct = tryItProduct
        self.loadStores = loadStores
        self.locate = locate
        self.onFinish = onFinish
        self.onSavePerson = onSavePerson
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            if showsLaunch {
                LaunchView { withAnimation(Theme.motion.easeOut(duration: 0.4)) { showsLaunch = false } }
                    .transition(.opacity)
            } else if model.step == .welcome {
                WelcomeView { withAnimation(Theme.motion.onboardingStep) { model.next() } }
                    .transition(.opacity)
            } else {
                scaffold.transition(.opacity)
            }
        }
        #if DEBUG
        .task { await playScriptIfAsked() }
        #endif
    }

    #if DEBUG
    /// `-onboardingScript <name>`: plays the answers through the model, then finishes like the
    /// summary's primary button (see `OnboardingScript`).
    private func playScriptIfAsked() async {
        guard let name = OnboardingScript.requested, let moves = OnboardingScript.moves(name, mode: model.mode) else { return }
        try? await Task.sleep(for: .milliseconds(model.isAddingPerson ? 800 : 1_200))
        withAnimation(Theme.motion.easeOut(duration: 0.4)) { showsLaunch = false }
        try? await Task.sleep(for: .milliseconds(800))
        if await OnboardingScript.play(moves, on: model, loadStores: loadStores) { primary() }
    }
    #endif

    private var scaffold: some View {
        OnboardingScaffold(
            stepID: model.step.rawValue,
            section: model.section,
            sectionNames: model.sectionNames,
            pose: model.pose,
            line: model.line,
            tint: Self.tint(model.step),
            skipTitle: model.canSkip ? (model.step == .store ? "Set up later" : "Skip") : nil,
            forward: model.movedForward,
            primaryTitle: model.primaryTitle,
            missing: model.missingAnswer,
            back: {
                let moved = withAnimation(Theme.motion.onboardingStep) { model.back() }
                if !moved { onCancel() }
            },
            skip: { withAnimation(Theme.motion.onboardingStep) { model.skip() } },
            primary: primary
        ) {
            stepContent
        }
    }

    private func primary() {
        if model.step == .summary {
            if model.isAddingPerson {
                if let person = model.makePerson() { onSavePerson(person) }
            } else if let household = model.makeHousehold() {
                onFinish(household)
            }
        } else {
            withAnimation(Theme.motion.onboardingStep) { model.next() }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .welcome: EmptyView()
        case .name: PersonNameStep(model: model) { primary() }
        case .startFrom: StartFromStep(model: model)
        case .goal: GoalStep(model: model)
        case .why: WhyStep(model: model)
        case .diet: DietStep(model: model)
        case .religion: ReligionStep(model: model)
        case .medical: MedicalStep(model: model)
        case .allergens: AllergensStep(model: model)
        case .avoid: AvoidStep(model: model)
        case .source: SourceStep(model: model)
        case .phase: PhaseStep(model: model)
        case .targets: TargetsStep(model: model)
        case .region: RegionStep(model: model, locate: locate)
        case .store: StoreStep(model: model, loadStores: loadStores)
        case .depth: DepthStep(model: model)
        case .prefs: PrefsStep(model: model)
        case .summary: SummaryStep(model: model, tryItProduct: tryItProduct)
        }
    }

    /// Background tint per step (tokens.json `screenTint`, prototype `BG`).
    static func tint(_ step: OnboardingModel.Step) -> Color {
        switch step {
        case .welcome: Theme.screenTint.welcome
        case .name, .startFrom: Theme.screenTint.household
        case .goal: Theme.screenTint.goal
        case .why: Theme.screenTint.why
        case .allergens: Theme.screenTint.allergens
        case .medical: Theme.screenTint.medical
        case .diet: Theme.screenTint.diet
        case .religion: Theme.screenTint.religion
        case .avoid, .depth, .prefs: Theme.screenTint.avoid
        case .source, .phase, .targets: Theme.screenTint.numbers
        case .region: Theme.screenTint.region
        case .store: Theme.screenTint.store
        case .summary: Theme.screenTint.summary
        }
    }
}

#if DEBUG
extension OnboardingModel {
    /// The owner on the summary: peanut, tree nuts and seed oils, in Austin at Whole Foods Market.
    static func sampleOwner() -> OnboardingModel {
        let m = OnboardingModel()
        m.current = Answers(goals: [.avoid], why: [.allergy], allergens: Set(["peanut"] + (OnboardingCatalog.allergenGroups[1].leaves ?? [])),
                            avoid: ["seed"])
        m.region = Region(zip: "78701", city: "Austin, TX")
        m.store = OnboardingCatalog.demoStores.first
        m.show(.summary)
        return m
    }

    /// Adding Leo to the sample household (`sample-household.json`), on `step`.
    static func sampleAddPerson(_ step: Step = .name) -> OnboardingModel {
        let people = (try? SampleData.household().people) ?? [Person(id: "you", name: "You", isOwner: true)]
        let m = OnboardingModel(addingTo: people)
        m.name = step == .name ? "" : "Leo"
        if step != .name, let first = people.last { m.chooseStart(first.id) }
        m.show(step)
        return m
    }
}

/// `-onboarding` launch argument (DEBUG): the whole flow from the splash, with the demo stores and
/// a location stand-in, so it can be run and screenshot before the app shell wires it.
/// `-onboardingStep <step>` opens one step with sample answers.
struct OnboardingDebugHost: View {
    @State private var finished: Household?
    @State private var start = Self.startModel()

    var body: some View {
        if let finished {
            VStack(spacing: Theme.spacing.m) {
                Text("Saved \(finished.people.count) people").themeText(.sectionTitle)
                Text(finished.people.map(\.name).joined(separator: ", ")).themeText(.body)
                Text(finished.region.map { "ZIP \($0.zip)" } ?? "").themeText(.body)
            }
        } else {
            OnboardingFlow(model: start, showsLaunch: start.step == .welcome,
                           tryItProduct: try? SampleData.products().first,
                           locate: { Region(zip: "78701", city: "Austin, TX") }) { finished = $0 }
        }
    }

    private static func startModel() -> OnboardingModel {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-onboardingStep"), i + 1 < args.count,
              let step = OnboardingModel.Step(rawValue: args[i + 1]) else { return OnboardingModel() }
        if step == .summary { return .sampleOwner() }
        if step == .name || step == .startFrom { return .sampleAddPerson(step) }
        let m = OnboardingModel()
        m.current.goals = [.avoid]
        m.current.why = [.allergy]
        m.show(step)
        return m
    }
}

#Preview("Onboarding flow") {
    OnboardingFlow(tryItProduct: try? SampleData.products().first,
                   locate: { Region(zip: "78701", city: "Austin, TX") }) { _ in }
}
#endif
