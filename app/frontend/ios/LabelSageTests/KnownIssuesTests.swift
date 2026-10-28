import Testing
import LabelSageCore
@testable import LabelSage

/// The device walkthrough of 2026-10-28 (`app/docs/labelsage-handoff/docs/known-issues-2026-10-28.md`):
/// targets from height, weight and age (1), the ZIP directory behind the region step (2, 4, 5), the
/// store list (3) and the chat composer's placeholder (7). The ZIP hint (6) is view logic.
@MainActor
struct KnownIssuesTests {
    private let directory = ZipDirectory(tsv: """
        S\tTX\tTexas
        S\tMN\tMinnesota
        S\tNY\tNew York
        78701\tAustin\tTX\tTravis\t30.271\t-97.743
        78702\tAustin\tTX\tTravis\t30.264\t-97.715
        55912\tAustin\tMN\tMower\t43.667\t-92.975
        10001\tNew York\tNY\tNew York\t40.748\t-73.997
        """)

    // MARK: 4, 5: ZIP and city search

    @Test func aZipGivesItsCityAndState() throws {
        let place = try #require(directory.place(zip: "78701"))
        #expect(place.cityLine == "Austin, TX")
        #expect(place.state == "Texas")
        #expect(place.area == "Travis County")
        #expect(directory.place(zip: "99999") == nil)
    }

    @Test func aCityGivesOneRowPerCityBiggestFirst() {
        let hits = directory.places(matching: "austin")
        #expect(hits.map(\.cityLine) == ["Austin, TX", "Austin, MN"])
        #expect(hits.first?.zip == "78701")
    }

    @Test func aStateCodeAfterTheCityNarrowsIt() {
        #expect(directory.places(matching: "Austin, MN").map(\.zip) == ["55912"])
        #expect(directory.places(matching: "austin mn").map(\.zip) == ["55912"])
    }

    @Test func digitsSearchZipCodes() {
        #expect(directory.places(matching: "787").map(\.zip) == ["78701", "78702"])
        #expect(directory.places(matching: "7").isEmpty)
    }

    @Test func theBundledDirectoryCoversTheUS() throws {
        let shared = ZipDirectory.shared
        #expect(shared.entries.count > 40_000)
        #expect(try #require(shared.place(zip: "10001")).cityLine == "New York, NY")
    }

    // MARK: 2: location to ZIP

    @Test func aLocationGivesTheNearestZip() {
        #expect(directory.nearest(latitude: 30.27, longitude: -97.74)?.zip == "78701")
        #expect(directory.nearest(latitude: 43.6, longitude: -93.0)?.zip == "55912")
        #expect(ZipDirectory(entries: [], stateNames: [:]).nearest(latitude: 0, longitude: 0) == nil)
    }

    // MARK: 3: stores

    @Test func theFallbackStoreListHasFourStores() async throws {
        let stores = try await FixtureProductSource(delayMilliseconds: 0...0).stores(near: Region(zip: "78701"))
        #expect(stores.count == 4)
    }

    // MARK: 1: targets from height, weight and age

    @Test func helpMeSetThemAsksForBodyStats() {
        let m = OnboardingModel()
        m.current.goals = [.numbers]
        m.current.source = .know
        #expect(!m.path.contains(.body))
        m.current.source = .help
        #expect(m.path.contains(.body))
        m.show(.body)
        #expect(!m.canContinue)
        m.current.body = .init(age: 34, heightInches: 65, weightPounds: 150, sex: .female, activity: .light)
        #expect(m.canContinue)
    }

    @Test func targetsComeFromTheBodyStats() {
        let woman = OnboardingModel.BodyStats(age: 34, heightInches: 65, weightPounds: 150, sex: .female, activity: .light)
        let w = woman.targets(for: [.cut])
        #expect(w?.protein == 135 && w?.kcal == 1_500)
        let man = OnboardingModel.BodyStats(age: 30, heightInches: 70, weightPounds: 180, sex: .male, activity: .moderate)
        let m = man.targets(for: [.bulk])
        #expect(m?.protein == 145 && m?.kcal == 3_000)
        #expect(OnboardingModel.BodyStats(age: 30).targets(for: []) == nil)
    }

    @Test func theTargetsStepStartsFromTheEstimate() {
        let m = OnboardingModel()
        m.current.goals = [.numbers]
        m.current.phases = [.cut]
        m.current.source = .help
        m.current.body = .init(age: 34, heightInches: 65, weightPounds: 150, sex: .female, activity: .light)
        #expect(m.protein == 135 && m.kcal == 1_500)
        m.current.source = .know
        #expect(m.protein == 160 && m.kcal == 1_900)
    }

    // MARK: 7: composer placeholder

    @Test func thePlaceholderFollowsTheLatestAnswer() {
        #expect(ChatModel.placeholder(after: nil, exampleName: "Mia") == "Ask \(Brand.mascot)\u{2026}")
        #expect(ChatModel.placeholder(after: .preferences, exampleName: "Mia") == "Add sesame for Mia\u{2026}")
        #expect(ChatModel.placeholder(after: .text, exampleName: "Mia") == "Message \(Brand.mascot)\u{2026}")
        // Every placeholder fits the composer: 24 characters at most.
        let kinds: [ChatMessage.Kind?] = [nil, .preferences, .text, .familyLink, .choices([]), .options(anchor: nil, [])]
        #expect(kinds.allSatisfy { ChatModel.placeholder(after: $0, exampleName: "Mia").count <= 24 })
    }
}
