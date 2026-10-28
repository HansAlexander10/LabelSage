import Foundation
import FoundationModels
import LabelSageAgent
import LabelSageCore

/// The on-device model's jobs in the chat, next to `ExplanationService` (which rewords a reason line):
/// reading a message the keyword router can't place, and finding products through a tool call.
/// Code still decides every flag: the model only picks an intent or a search query
/// (spike-chat-agent-logic-and-pattern-2026-10-27.md, "Router, Reader, Actions, Writer").
nonisolated enum ChatAI {
    /// Apple Intelligence is on and the model is ready. Without it the router and templates answer.
    static var isAvailable: Bool { IntentReader.modelAvailable }

    /// Loads the model before the first message, so the first answer doesn't wait for it (about 8 s
    /// on the simulator otherwise).
    static func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession(instructions: ProductFinder.instructions).prewarm()
    }
}

// MARK: - Reader

/// Reads a message the router missed with the model (`LabelSageAgent.IntentReader`, guided generation,
/// checked in code) and maps it onto the app's `ChatIntent`. Runs on the device; nothing leaves it.
nonisolated enum ModelIntentReader {
    /// nil when the model is unavailable or reads small talk: the router's answer stands.
    static func read(_ text: String, household: Household) async -> ChatIntent? {
        guard ChatAI.isAvailable else { return nil }
        let reading = Perf.begin("chat.modelRead")
        defer { Perf.end(reading) }
        let read = await IntentReader().read(text, context: ChatContext(household: household))
        let intent = map(read, text: text)
        Log.model.info("Model read \(read.intent, privacy: .public) -> \(intent == nil ? "router" : "model", privacy: .public)")
        return intent
    }

    static func map(_ read: ReadIntent, text: String) -> ChatIntent? {
        let s = IntentRouter.normalize(text)
        switch read.kind {
        case .check, .ask:
            return .check(product: read.product)
        case .otherOptions:
            // The reader keeps the product; "without seed oils" comes from the words as written.
            let (_, without) = IntentRouter.optionsQuery(s, names: [])
            return .otherOptions(query: read.product, without: without)
        case .compare:
            return .compare
        case .changeAllergies:
            guard let item = read.item else { return nil }
            let owner = s.hasPrefix("i ") || s.contains("i'm ") || s.contains(" my ") || s.hasPrefix("my ")
            return .changeAllergies(person: read.people.first ?? (owner ? "you" : nil), item: item,
                                    severity: read.severity.flatMap(Severity.init(rawValue:)))
        case .pivot:
            return read.people.first.map { .pivot(.person($0)) }
        case .smallTalk:
            return nil
        }
    }
}

// MARK: - Tool call

/// The product retrieval the model calls. A mock for now: it searches the fixture products and, when
/// nothing matches, always returns the same demo picks. The real retrieval (the ETL's `catalog.sqlite`
/// through `LabelSageCatalog`) replaces `products(for:)` once D4 is decided.
nonisolated struct FindProductsTool: Tool {
    let name = "findProducts"
    let description = "Finds grocery products by product name or category. Returns product names and brands."

    @Generable
    struct Arguments {
        @Guide(description: "A short product name or category as the shopper wrote it, like kettle chips or granola bars")
        var query: String
    }

    let source: any ProductSource
    let found: FoundProducts
    /// The finder needs only the call, not the model's reply: the tool ends the session once it has run,
    /// so a model that keeps calling tools can't loop.
    var endsSession = false

    /// Thrown by the tool to end the session after the first call.
    struct Done: Error {}

    func call(arguments: Arguments) async throws -> String {
        let products = try await Self.products(for: arguments.query, in: source)
        await found.record(query: arguments.query, products)
        Log.model.info("findProducts returned \(products.count, privacy: .public) products")
        if endsSession { throw Done() }
        // Names and brands only: the model never sees ingredients or verdicts, so it can't judge them.
        return products.map { "\($0.name), \($0.brand ?? "no brand")" }.joined(separator: "\n")
    }

    /// The demo picks returned when a query matches nothing: one per main aisle.
    static let demoPicks = ["0000000000024", "0000000000031", "0000000000055", "0000000000079", "0000000000109"]

    static func products(for query: String, in source: any ProductSource) async throws -> [Product] {
        let hits = try await source.search(query, region: nil, store: nil, limit: 10)
        if !hits.isEmpty { return hits }
        // One word at a time ("crunchy kettle chips" → "kettle", "chips"), then the demo picks.
        var byWord: [Product] = []
        for word in query.split(separator: " ") where word.count >= 4 {
            for product in try await source.search(String(word), region: nil, store: nil, limit: 10)
            where !byWord.contains(where: { $0.id == product.id }) {
                byWord.append(product)
            }
        }
        if !byWord.isEmpty { return Array(byWord.prefix(10)) }
        var picks: [Product] = []
        for code in demoPicks {
            if let product = try await source.product(barcode: code, region: nil) { picks.append(product) }
        }
        return picks
    }
}

/// What the tool returned during one answer, for the app to check with the engine.
actor FoundProducts {
    private(set) var query: String?
    private(set) var products: [Product] = []

    func record(query: String, _ found: [Product]) {
        self.query = query
        for product in found where !products.contains(where: { $0.id == product.id }) { products.append(product) }
    }
}

/// "Find me something like…": the model turns the message into a `findProducts` call; the products the
/// tool returned go to the verdict engine, which alone decides what fits. The model's own reply is dropped.
nonisolated enum ProductFinder {
    static let instructions = """
        You help a shopper find grocery products in a label-checking app. Always call findProducts once. \
        Pass a short product name or category from the request. Leave out people, allergies and words like \
        without, free or no. Never judge or recommend a product. After the tool answers, reply with: done.
        """

    /// How long the model may take before the keyword search answers instead.
    static let timeout: Duration = .seconds(12)

    /// nil when the model is unavailable, fails or calls no tool: the caller searches by keywords.
    static func find(_ request: String, source: any ProductSource) async -> (query: String, products: [Product])? {
        guard ChatAI.isAvailable else { return nil }
        let finding = Perf.begin("chat.findProducts")
        defer { Perf.end(finding) }
        let found = FoundProducts()
        let session = LanguageModelSession(tools: [FindProductsTool(source: source, found: found, endsSession: true)],
                                           instructions: instructions)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 60, toolCallingMode: .required)
        let started = ContinuousClock.now
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    _ = try await session.respond(to: request, options: options)
                } catch {
                    // The tool's `Done` lands here as a tool-call error: the expected way out.
                    Log.model.debug("findProducts session ended: \(String(describing: type(of: error)), privacy: .public)")
                }
            }
            // Backstop: a slow or stuck model gives the keyword search its turn.
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
        let ms = Int((ContinuousClock.now - started) / .milliseconds(1))
        guard !Task.isCancelled, let query = await found.query else {
            Log.model.notice("findProducts not called (\(ms, privacy: .public) ms); keyword search instead")
            return nil
        }
        Log.model.info("findProducts called in \(ms, privacy: .public) ms")
        return (query, await found.products)
    }
}
