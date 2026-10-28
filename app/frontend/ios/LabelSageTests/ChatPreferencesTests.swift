import Foundation
import Testing
import LabelSageCore
@testable import LabelSage

/// Chat changes are always a hard filter (D-31): an allergen is saved as an allergy with
/// "may contain" on, whatever the person said; the toast says so.
@MainActor
struct ChatPreferencesTests {
    private func proposal(severity: Severity) -> ChangeProposal {
        ChangeProposal(personID: "mia", personName: "Mia", familyID: "sesame", label: "sesame",
                       isAllergen: true, severity: severity, currentItems: [])
    }

    @Test func anAllergenIsAlwaysAnAllergyWithMayContain() {
        var profile = Profile(allergens: [AllergenChoice(id: "peanut", severity: .intolerance)], mayContain: false)
        ChatModel.apply(proposal(severity: .intolerance), to: &profile)
        #expect(profile.allergens.first { $0.id == "sesame" }?.severity == .allergy)
        #expect(profile.mayContain)

        var existing = Profile(allergens: [AllergenChoice(id: "sesame", severity: .intolerance)])
        ChatModel.apply(proposal(severity: .intolerance), to: &existing)
        #expect(existing.allergens.map(\.severity) == [.allergy])
    }

    @Test func toastNamesMayContain() {
        #expect(ChatModel.savedToast(proposal(severity: .allergy), mayContain: true)
                == "Saved: Mia avoids sesame, “may contain” too.")
        #expect(!ChatModel.savedToast(proposal(severity: .allergy), mayContain: true).contains("intolerance"))
    }

    @Test func intolerancePivotKeepsTheHardFilter() async throws {
        let household = try SampleData.household()
        let model = ChatModel(household: household, source: FixtureProductSource(delayMilliseconds: 0...0),
                              verdictService: VerdictService(), explanationService: ExplanationService { _ in nil })
        await model.handle(.changeAllergies(person: "Mia", item: "sesame", severity: .intolerance))
        guard case .change(let p) = model.thread.messages.last?.kind else {
            Issue.record("no change card")
            return
        }
        #expect(p.severity == .allergy)
        await model.handle(.pivot(.severity(.intolerance)))
        #expect(model.dockLine.contains("even for an intolerance"))
    }

    @Test func preferencesStartAPreferencesThread() throws {
        let model = ChatModel(household: try SampleData.household(), source: FixtureProductSource(delayMilliseconds: 0...0),
                              verdictService: VerdictService(), explanationService: ExplanationService { _ in nil })
        model.showPreferences()
        #expect(model.thread.title == "Preferences")
        #expect(model.openingLine.contains("each person"))
        #expect(model.dockLine.contains("Mia"))
    }
}
