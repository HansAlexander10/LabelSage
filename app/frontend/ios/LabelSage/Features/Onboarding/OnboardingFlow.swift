import SwiftUI
import LabelSageCore

/// First open: Launch, Welcome, then the decision tree to the summary (spec 01). A self-contained
/// feature: it takes its services as closures and reports the household through `onFinish`; the
/// app shell (T13) saves it, marks onboarding done and opens the camera (D1).
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

    @State private var model: OnboardingModel
    @State private var showsLaunch: Bool

    init(model: OnboardingModel = OnboardingModel(),
         showsLaunch: Bool = true,
         tryItProduct: Product? = nil,
         loadStores: @escaping (Region) async throws -> [Store] = { _ in OnboardingCatalog.demoStores },
         locate: @escaping () async -> Region? = { nil },
         onFinish: @escaping (Household) -> Void) {
        _model = State(initialValue: model)
        _showsLaunch = State(initialValue: showsLaunch)
        self.tryItProduct = tryItProduct
        self.loadStores = loadStores
        self.locate = locate
        self.onFinish = onFinish
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
        guard let name = OnboardingScript.requested, let moves = OnboardingScript.moves(name) else { return }
        try? await Task.sleep(for: .milliseconds(1_200))
        withAnimation(Theme.motion.easeOut(duration: 0.4)) { showsLaunch = false }
        try? await Task.sleep(for: .milliseconds(800))
        if await OnboardingScript.play(moves, on: model, loadStores: loadStores) { primary() }
    }
    #endif

    private var scaffold: some View {
        OnboardingScaffold(
            stepID: "\(model.step.rawValue)-\(model.personIndex)",
            section: model.section,
            pose: model.pose,
            line: model.line,
            tint: Self.tint(model.step),
            skipTitle: model.canSkip ? (model.step == .store ? "Set up later" : "Skip") : nil,
            forward: model.movedForward,
            primaryTitle: model.primaryTitle,
            missing: model.missingAnswer,
            back: { withAnimation(Theme.motion.onboardingStep) { model.back() } },
            skip: { withAnimation(Theme.motion.onboardingStep) { model.skip() } },
            primary: primary
        ) {
            stepContent
        }
    }

    private func primary() {
        if model.step == .summary {
            if let household = model.makeHousehold() { onFinish(household) }
        } else {
            withAnimation(Theme.motion.onboardingStep) { model.next() }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .welcome: EmptyView()
        case .household: HouseholdStep(model: model)
        case .firstProfile: FirstProfileStep(model: model)
        case .goal: GoalStep(model: model)
        case .why: WhyStep(model: model)
        case .diet: DietStep(model: model)
        case .religion: ReligionStep(model: model)
        case .medical: MedicalStep(model: model)
        case .allergens: AllergensStep(model: model)
        case .severity: SeverityStep(model: model)
        case .avoid: AvoidStep(model: model)
        case .strict: StrictStep(model: model)
        case .source: SourceStep(model: model)
        case .phase: PhaseStep(model: model)
        case .targets: TargetsStep(model: model)
        case .nextPerson: NextPersonStep(model: model)
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
        case .household, .firstProfile, .nextPerson: Theme.screenTint.household
        case .goal: Theme.screenTint.goal
        case .why: Theme.screenTint.why
        case .allergens: Theme.screenTint.allergens
        case .severity: Theme.screenTint.severity
        case .medical: Theme.screenTint.medical
        case .strict: Theme.screenTint.strict
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
    /// Board 14: Mia (peanut, tree nuts, seed oils), Leo (milk, egg, vegetarian), Sam (sesame,
    /// halal, added sugars), in Austin at Whole Foods Market, on the summary.
    static func sampleFamily() -> OnboardingModel {
        let m = OnboardingModel()
        m.household = .family
        m.firstName = "Mia"
        m.team = ["Leo", "Sam"]
        m.show(.goal)
        m.current = Answers(goals: [.avoid], why: [.allergy], allergens: Set(["peanut"] + (OnboardingCatalog.allergenGroups[1].leaves ?? [])),
                            avoid: ["seed"])
        m.show(.nextPerson)
        m.next()
        m.current = Answers(goals: [.avoid], why: [.allergy, .diet], diets: ["vegetarian"], allergens: ["milk", "egg"],
                            severity: ["milk": .intolerance])
        m.show(.nextPerson)
        m.next()
        m.current = Answers(goals: [.avoid], why: [.allergy, .religion], religion: ["halal"], allergens: ["sesame"], avoid: ["sugar"])
        m.region = Region(zip: "78701", city: "Austin, TX")
        m.store = OnboardingCatalog.demoStores.first
        m.show(.summary)
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
        if step == .summary { return .sampleFamily() }
        let m = OnboardingModel()
        m.household = .family
        m.firstName = "Mia"
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
