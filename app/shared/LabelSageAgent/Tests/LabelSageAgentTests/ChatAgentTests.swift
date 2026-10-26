import Foundation
import LabelSageCatalog
import LabelSageCore
import Testing
@testable import LabelSageAgent

/// The fixture is the 23-product cut of the 2026-10-25 catalog (see LabelSageCatalog/Scripts/make_fixture.py):
/// Cheerios, 20 products in its category, and two recalled products without ingredients.
/// Most tests run without the model (keyword router + deterministic lines), so they pass on any machine.
@Suite("Chat agent")
struct ChatAgentTests {
    let catalog: CatalogProductSource
    let engine: VerdictEngine
    let household = Household(people: [
        Person(id: "alex", name: "Alex", isOwner: true),
        Person(id: "mia", name: "Mia", profile: Profile(allergens: [AllergenChoice(id: "milk"), AllergenChoice(id: "peanut")])),
    ])

    init() throws {
        let url = try #require(Bundle.module.url(forResource: "catalog-fixture", withExtension: "sqlite"))
        catalog = try CatalogProductSource(url: url)
        engine = VerdictEngine(catalog: try Catalog.bundled())
    }

    func agent(useModel: Bool = false) -> ChatAgent {
        ChatAgent(household: household, catalog: catalog, engine: engine, useModel: useModel)
    }

    // MARK: - Keyword fallback

    @Test func keywordRouterReadsTheMVPIntents() {
        let context = ChatContext(household: household)
        let ask = KeywordRouter.read("Are the Cheerios OK for Mia?", context: context)
        #expect(ask.kind == .ask && ask.product == "cheerios" && ask.people == ["Mia"])
        #expect(KeywordRouter.read("find other options", context: context).kind == .otherOptions)
        #expect(KeywordRouter.read("compare these two", context: context).kind == .compare)
        let change = KeywordRouter.read("Mia reacted to hummus. Add sesame to her allergies", context: context)
        #expect(change.kind == .changeAllergies && change.item == "sesame" && change.people == ["Mia"])
        #expect(KeywordRouter.read("every label, every time", context: context).kind == .smallTalk)
    }

    // MARK: - Actions through the agent, deterministic lines

    @Test func askFindsTheProductAndTheEngineDecides() async throws {
        let reply = try await agent().send("Are the Cheerios OK for Mia?")
        let product = try #require(reply.products.first)
        #expect(product.name == "Cheerios Cereal")
        #expect(reply.verdicts.first == engine.check(product, for: household))   // the engine's verdict, untouched
        #expect(reply.line.contains("Mia"))
        #expect(!reply.lineFromModel)
    }

    @Test func otherOptionsKeepOnlyWhatFitsEveryone() async throws {
        let chat = agent()
        _ = try await chat.send("Are the Cheerios OK for Mia?")
        let reply = try await chat.send("find other options")
        #expect(reply.intent.kind == .otherOptions)
        #expect(reply.products.count <= 3)
        #expect(reply.verdicts.allSatisfy { $0.overall == .ok || $0.overall == .checkFirst })
        #expect(reply.line.hasPrefix("Found") || reply.line.hasPrefix("Nothing here fits"))
    }

    @Test func scannedRecallShowsTheRecallAndCantConfirm() async throws {
        let reply = try await agent().scanned(barcode: "666186277621")
        #expect(reply.verdicts.first?.overall == .cantConfirm)                 // no ingredient list
        #expect(reply.recalls["0666186277621"]?.first?.reason?.contains("soy") == true)
    }

    @Test func compareUsesTheLastTwoProducts() async throws {
        let chat = agent()
        _ = try await chat.scanned(barcode: "0016000275287")
        _ = try await chat.scanned(barcode: "666186277621")
        let reply = try await chat.send("compare these two")
        #expect(reply.products.map(\.barcode) == ["0016000275287", "0666186277621"])
        #expect(reply.verdicts.count == 2)
    }

    @Test func allergyChangesAreProposalsNeverSaves() async throws {
        let chat = agent()
        let reply = try await chat.send("Mia reacted to hummus. Add sesame to her allergies")
        #expect(reply.proposal == ProfileChangeProposal(personName: "Mia", item: "sesame", severity: "allergy"))
        #expect(await chat.context.household == household)                    // nothing saved without Confirm
    }

    @Test func unknownBarcodeOffersToReportIt() async throws {
        let reply = try await agent().scanned(barcode: "0000000000017")
        #expect(reply.products.isEmpty && reply.line.contains("Report"))
    }

    // MARK: - Writer validation

    @Test func writerRejectsTheNeverListAndLostNames() {
        let keep = ["Not for", "Mia"]
        #expect(Writer.isValid("Not for Mia. Whey is milk.", mustKeep: keep))
        #expect(!Writer.isValid("Not safe for Mia. Whey is milk.", mustKeep: keep))      // never "safe"
        #expect(!Writer.isValid("Not for her. Whey is milk.", mustKeep: keep))           // lost the name
        #expect(!Writer.isValid("This is bad for Mia, not for her.", mustKeep: keep))    // never "bad"
        #expect(!Writer.isValid(String(repeating: "word ", count: 21) + "Not for Mia", mustKeep: keep))
        #expect(Writer.isValid("Can't confirm. Natural flavors isn't specific.", mustKeep: ["Can’t confirm"]))
    }

    @Test func writerRejectsFactsTheEngineDidNotState() {
        let original = "OK for Mia. No milk or peanuts in these ingredients."
        #expect(Writer.isValid("OK for Mia: no milk or peanuts in the list.", mustKeep: ["OK for", "Mia"], original: original))
        #expect(!Writer.isValid("OK for Mia. Almonds in it.", mustKeep: ["OK for", "Mia"], original: original))   // seen in testing
        #expect(!Writer.isValid("OK for Mia. No garlic in it.", mustKeep: ["OK for", "Mia"], original: original))
    }

    // MARK: - On-device model (runs only where Apple Intelligence is available)

    @Test(.enabled(if: IntentReader.modelAvailable))
    func modelReadsTheIntentButNeverTheVerdict() async throws {
        let reply = try await agent(useModel: true).send("Are the Cheerios OK for Mia?")
        print("model line:", reply.line, "| from model:", reply.lineFromModel, "| intent:", reply.intent)
        #expect(reply.intent.kind == .ask)
        let product = try #require(reply.products.first)
        #expect(reply.verdicts.first == engine.check(product, for: household))
        let deterministic = try #require(reply.verdicts.first?.people.first { $0.name == "Mia" }?.reason)
        print("engine line:", deterministic)
        #expect(!reply.lineFromModel || Writer.newFacts(reply.line, original: deterministic).isEmpty)
    }
}
