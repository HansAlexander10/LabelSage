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
/// The `family` script is the hand test from the onboarding brief: "Me" avoids seed oils and
/// gluten; Mia has peanut and tree nut allergies; Austin 78701; the first store near it.
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

    static func moves(_ name: String) -> [Move]? {
        guard name == "family" else { return nil }
        return [
            Move(step: .welcome) { _, _ in },
            Move(step: .household) { m, _ in m.household = .family },
            Move(step: .firstProfile) { m, _ in m.firstName = "Me"; m.addTeamMember("Mia") },
            // You: seed oils and gluten, from "Anything else".
            Move(step: .goal) { m, _ in m.current.goals.toggle(.avoid) },
            Move(step: .why) { m, _ in m.current.why.toggle(.diet) },
            Move(step: .diet) { _, _ in },
            Move(step: .avoid) { m, _ in m.toggleAvoid("seed"); m.toggleAvoid("gluten") },
            Move(step: .strict) { _, _ in },
            Move(step: .nextPerson) { _, _ in },
            // Mia: peanut, then tree nuts from the related sheet; both allergies.
            Move(step: .goal) { m, _ in m.current.goals.toggle(.avoid) },
            Move(step: .why) { m, _ in m.current.why.toggle(.allergy) },
            Move(step: .allergens) { m, _ in
                m.toggleAllergen("peanut")
                try? await Task.sleep(for: .milliseconds(900))
                m.addRelated(["treenuts"])
            },
            Move(step: .severity) { m, _ in
                for choice in m.allergenChoices { m.setSeverity(.allergy, for: choice.id) }
            },
            Move(step: .avoid) { _, _ in },
            Move(step: .strict) { m, _ in m.mayContain = true },
            Move(step: .region) { m, _ in m.region = OnboardingCatalog.places(matching: "78701").first?.region },
            Move(step: .store) { m, loadStores in
                guard let region = m.region else { return }
                try? await Task.sleep(for: .milliseconds(900))
                m.store = (try? await loadStores(region))?.first
            },
            Move(step: .depth) { m, _ in m.depth = .start },
            Move(step: .summary) { _, _ in },
        ]
    }

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
