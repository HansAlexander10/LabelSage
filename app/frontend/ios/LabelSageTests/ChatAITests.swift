import Foundation
import Testing
import LabelSageAgent
import LabelSageCore
@testable import LabelSage

/// The chat's model paths (`ChatAI.swift`): when the model gets a turn, how its reading maps onto
/// `ChatIntent`, and what the mock `findProducts` tool returns. No model runs here.
struct ChatAITests {
    @Test func onlyRealMissesGoToTheModel() {
        let longMiss = "something crunchy for the lunchbox please"
        #expect(IntentRouter.isMiss(IntentRouter.read(longMiss, names: ["Mia"]), text: longMiss))
        #expect(!IntentRouter.isMiss(.smallTalk(vent: false), text: "hi there"))
        #expect(!IntentRouter.isMiss(.smallTalk(vent: false), text: "thanks"))
        #expect(!IntentRouter.isMiss(.smallTalk(vent: true), text: "ugh every label is so hard"))
        #expect(!IntentRouter.isMiss(.compare, text: "compare these two products please"))
    }

    @Test func readingsMapOntoChatIntents() {
        #expect(ModelIntentReader.map(ReadIntent(intent: "ask", product: "granola"), text: "is the granola fine")
                == .check(product: "granola"))
        #expect(ModelIntentReader.map(ReadIntent(intent: "otherOptions", product: "kettle chips"),
                                      text: "show me kettle chips without seed oils")
                == .otherOptions(query: "kettle chips", without: "seed oils"))
        #expect(ModelIntentReader.map(ReadIntent(intent: "changeAllergies", item: "sesame", severity: "allergy"),
                                      text: "turns out my body hates sesame")
                == .changeAllergies(person: "you", item: "sesame", severity: .allergy))
        #expect(ModelIntentReader.map(ReadIntent(intent: "pivot", people: ["Mia"]), text: "and for Mia")
                == .pivot(.person("Mia")))
        // A change without an item, a pivot without a person and small talk keep the router's answer.
        #expect(ModelIntentReader.map(ReadIntent(intent: "changeAllergies"), text: "change her allergies") == nil)
        #expect(ModelIntentReader.map(ReadIntent(intent: "pivot"), text: "make it different") == nil)
        #expect(ModelIntentReader.map(ReadIntent(intent: "smallTalk"), text: "what a day") == nil)
    }

    @Test func findProductsSearchesThenFallsBackToTheDemoPicks() async throws {
        let source = FixtureProductSource(delayMilliseconds: 0...0)
        let chips = try await FindProductsTool.products(for: "kettle chips", in: source)
        #expect(!chips.isEmpty)
        #expect(chips.allSatisfy { "\($0.name) \($0.brand ?? "")".lowercased().contains("kettle") })

        // No match at all: always the same demo picks, in order.
        let none = try await FindProductsTool.products(for: "zzqx", in: source)
        #expect(none.compactMap(\.barcode) == FindProductsTool.demoPicks)
        #expect(try await FindProductsTool.products(for: "zzqx", in: source) == none)
    }

    @Test func toolRecordsWhatItReturned() async throws {
        let found = FoundProducts()
        let tool = FindProductsTool(source: FixtureProductSource(delayMilliseconds: 0...0), found: found)
        let text = try await tool.call(arguments: .init(query: "peanut butter"))
        #expect(text.contains("Creamy Peanut Butter"))
        #expect(await found.query == "peanut butter")
        #expect(await found.products.map(\.barcode) == ["0000000000062"])
    }

    /// Runs the real on-device model when Apple Intelligence is on (the simulator uses the Mac's).
    @Test(.enabled(if: ChatAI.isAvailable), .timeLimit(.minutes(1)))
    func modelCallsTheToolAndReadsMisses() async throws {
        let source = FixtureProductSource(delayMilliseconds: 0...0)
        let clock = ContinuousClock()
        var result: (query: String, products: [Product])?
        let took = await clock.measure { result = await ProductFinder.find("find me kettle chips without seed oils", source: source) }
        print("findProducts took", took)
        let found = try #require(result)
        #expect(found.query.lowercased().contains("chips"))
        #expect(!found.products.isEmpty)

        let household = try SampleData.household()
        let read = await ModelIntentReader.read("could you look for a different hummus for Mia", household: household)
        print("model read:", String(describing: read), "tool query:", found.query, found.products.map(\.name))
        #expect(read != nil)
    }

    @Test func sampleProductsCarryTheirPackPhotos() throws {
        let products = try SampleData.products()
        #expect(products.count == 100)
        #expect(products.allSatisfy { $0.imageURL?.isFileURL == true })
    }
}
