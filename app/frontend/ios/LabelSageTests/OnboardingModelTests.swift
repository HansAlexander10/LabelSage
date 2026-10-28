import Testing
import LabelSageCore
@testable import LabelSage

/// Onboarding after the product owner's changes of 2026-10-27: the first run sets up the owner
/// only, every allergen is a hard filter, and people are added one at a time from Family.
@MainActor
struct OnboardingModelTests {
    private func owner(allergens: Set<String> = ["peanut", "milk"]) -> OnboardingModel {
        let m = OnboardingModel()
        m.current.goals = [.avoid]
        m.current.why = [.allergy]
        m.current.allergens = allergens
        m.current.avoid = ["seed"]
        m.region = Region(zip: "78701", city: "Austin, TX")
        return m
    }

    @Test func firstRunAsksNoPeopleSeverityOrMayContain() {
        let path = owner().path
        #expect(path.first == .welcome)
        #expect(path[1] == .goal)
        #expect(!path.contains(.name) && !path.contains(.startFrom))
        #expect(path.contains(.allergens) && path.contains(.region) && path.contains(.store))
        #expect(path.firstIndex(of: .allergens)! + 1 == path.firstIndex(of: .avoid)!)
    }

    @Test func everyAllergenIsAnAllergyWithMayContain() {
        let household = owner().makeHousehold()
        #expect(household?.people.count == 1)
        let you = household?.people.first
        #expect(you?.isOwner == true)
        #expect(you?.profile.allergens.allSatisfy { $0.severity == .allergy } == true)
        #expect(you?.profile.allergens.count == 2)
        #expect(you?.profile.mayContain == true)
    }

    @Test func regionIsStillRequired() {
        let m = owner()
        m.region = nil
        #expect(m.makeHousehold() == nil)
    }

    @Test func addPersonStartsFromACopyThatIsNeverLinked() {
        let you = owner().makeHousehold()!.people[0]
        let m = OnboardingModel(addingTo: [you])
        #expect(m.step == .name)
        m.name = "Mia"
        m.next()
        #expect(m.step == .startFrom)
        #expect(!m.canContinue)
        m.chooseStart(you.id)
        #expect(m.current.allergens == ["peanut", "milk"])
        #expect(m.current.avoid == ["seed"])
        m.toggleAllergen("sesame")
        m.relatedFor = nil
        let mia = m.makePerson()
        #expect(mia?.name == "Mia")
        #expect(mia?.isOwner == false)
        #expect(mia?.profile.allergens.map(\.id).contains("sesame") == true)
        #expect(mia?.profile.mayContain == true)
        // The owner's profile is untouched.
        #expect(!you.profile.allergens.map(\.id).contains("sesame"))
        #expect(!m.path.contains(.region))
    }

    @Test func startFreshClearsTheCopy() {
        let you = owner().makeHousehold()!.people[0]
        let m = OnboardingModel(addingTo: [you])
        m.chooseStart(you.id)
        m.chooseStart(OnboardingModel.freshStart)
        #expect(m.current == OnboardingModel.Answers())
    }

    @Test func takenNamesAreRefused() {
        let you = Person(id: "you", name: "You", isOwner: true)
        let mia = Person(id: "p1", name: "Mia")
        let m = OnboardingModel(addingTo: [you, mia])
        m.name = "mia"
        #expect(m.missingAnswer != nil)
        m.name = "Me"
        #expect(m.missingAnswer != nil)
        m.name = "Leo"
        #expect(m.missingAnswer == nil)
    }

    @Test func profileRoundTripsThroughAnswers() {
        let p = Profile(allergens: [AllergenChoice(id: "peanut"), AllergenChoice(id: "treenuts", leaves: ["almond"])],
                        diets: ["vegetarian", "halal"],
                        avoid: [AvoidChoice(id: "seed", strength: .preferNot)])
        let back = OnboardingModel.profile(OnboardingModel.answers(from: p))
        #expect(back.allergens.map(\.id) == p.allergens.map(\.id))
        #expect(Set(back.diets) == Set(p.diets))
        #expect(back.avoid == p.avoid)
    }
}
