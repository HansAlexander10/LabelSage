#if DEBUG
import SwiftUI
import LabelSageCore

/// `-onboardingScript family` (DEBUG): answers onboarding through the model's own actions, one
/// step at a time on screen, then presses "Check my first product", so the real save path runs
/// (`OnboardingFlow.onFinish` → `AppModel.save`). For simulator runs where nothing can tap.
///
/// `-onboardingScriptStop <step>` answers that step and stops there (for a screenshot), for
/// example `welcome`, `region` or `summary`. Use with `-resetHousehold` so onboarding shows.
///
/// - `family`: first run, the owner only (product owner, 2026-10-27): peanut, then tree nuts from
///   the related sheet; seed oils and gluten from "Anything else"; Austin 78701; the first store.
/// - `addPerson`: on a saved household (run `family` first, or with `-demoHousehold`), RootView
///   opens Family's "Add someone you shop for": Mia, starting from your preferences, adds sesame
///   on top, then "Save Mia".
enum OnboardingScript {
    /// One answer: the step it expects, and what it does there.
    struct Move {
        let step: OnboardingModel.Step
        let answer: (OnboardingModel, _ loadStores: (Region) async throws -> [Store]) async -> Void
    }

    static var requested: String? { argument("-onboardingScript") }
    static var stop: OnboardingModel.Step? { argument("-onboardingScriptStop").flatMap(OnboardingModel.Step.init(rawValue:)) }

    private static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// The moves for a script name, when it fits the flow on screen.
    static func moves(_ name: String, mode: OnboardingModel.Mode) -> [Move]? {
        switch (name, mode) {
        case ("family", .firstRun): owner
        case ("addPerson", .addPerson): addPerson
        default: nil
        }
    }

    private static var owner: [Move] { [
        Move(step: .welcome) { _, _ in },
        Move(step: .goal) { m, _ in m.current.goals.toggle(.avoid) },
        Move(step: .why) { m, _ in m.current.why.toggle(.allergy) },
        Move(step: .allergens) { m, _ in
            m.toggleAllergen("peanut")
            try? await Task.sleep(for: .milliseconds(900))
            m.addRelated(["treenuts"])
        },
        Move(step: .avoid) { m, _ in m.toggleAvoid("seed"); m.toggleAvoid("gluten") },
        Move(step: .region) { m, _ in m.region = OnboardingCatalog.places(matching: "78701").first?.region },
        Move(step: .store) { m, loadStores in
            guard let region = m.region else { return }
            try? await Task.sleep(for: .milliseconds(900))
            m.store = (try? await loadStores(region))?.first
        },
        Move(step: .depth) { m, _ in m.depth = .start },
        Move(step: .summary) { _, _ in },
    ] }

    private static var addPerson: [Move] { [
        Move(step: .name) { m, _ in m.name = "Mia" },
        Move(step: .startFrom) { m, _ in
            if let owner = m.existing.first(where: \.isOwner) { m.chooseStart(owner.id) }
        },
        Move(step: .goal) { _, _ in },
        Move(step: .why) { _, _ in },
        Move(step: .allergens) { m, _ in if !m.current.allergens.contains("sesame") { m.toggleAllergen("sesame") } },
        Move(step: .avoid) { _, _ in },
        Move(step: .summary) { _, _ in },
    ] }

    /// Plays `moves` on `model`. Returns true when every move ran (the caller then finishes);
    /// false when it stopped on purpose or the path went somewhere the script did not expect.
    @MainActor
    static func play(_ moves: [Move], on model: OnboardingModel,
                     loadStores: @escaping (Region) async throws -> [Store]) async -> Bool {
        for move in moves {
            guard model.step == move.step else {
                Log.data.error("onboardingScript: expected \(move.step.rawValue, privacy: .public), on \(model.step.rawValue, privacy: .public)")
                return false
            }
            await move.answer(model, loadStores)
            try? await Task.sleep(for: .milliseconds(700))
            if move.step == stop {
                Log.data.notice("onboardingScript: stopped on \(move.step.rawValue, privacy: .public)")
                return false
            }
            if move.step == .summary { break }
            guard model.canContinue else {
                Log.data.error("onboardingScript: \(move.step.rawValue, privacy: .public) is missing \(model.missingAnswer ?? "", privacy: .public)")
                return false
            }
            withAnimation(Theme.motion.onboardingStep) { model.next() }
            try? await Task.sleep(for: .milliseconds(500))
        }
        Log.data.notice("onboardingScript: finished, saving")
        return true
    }
}
#endif
