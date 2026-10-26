import Foundation
import FoundationModels
import LabelSageCore

/// Turns a message into a `ReadIntent`. Uses the on-device model when it is available and falls back
/// to `KeywordRouter`. The model sees only what it needs: names, what each person avoids, the last product.
public struct IntentReader: Sendable {
    public var useModel: Bool

    public init(useModel: Bool = true) { self.useModel = useModel }

    public static var modelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func read(_ text: String, context: ChatContext) async -> ReadIntent {
        guard useModel, Self.modelAvailable else { return KeywordRouter.read(text, context: context) }
        do {
            let session = LanguageModelSession(instructions: Self.instructions(context))
            let response = try await session.respond(to: text, generating: ReadIntent.self,
                                                     options: GenerationOptions(sampling: .greedy))
            return Self.repair(response.content, text: text, context: context)
        } catch {
            return KeywordRouter.read(text, context: context)
        }
    }

    /// Code checks the model's reading: the model may misread, so slots it cannot know are dropped.
    static func repair(_ read: ReadIntent, text: String, context: ChatContext) -> ReadIntent {
        var intent = read
        let lower = text.lowercased()
        // a named product is a question about it, not a camera scan
        if intent.kind == .check, let product = intent.product, !product.isEmpty, lower.contains(product.lowercased()) {
            intent.intent = IntentKind.ask.rawValue
        }
        // only household names the person actually wrote
        let names = context.household.people.map(\.name)
        intent.people = intent.people.compactMap { said in
            names.first { $0.lowercased() == said.lowercased() && lower.contains($0.lowercased()) }
        }
        // an item and a severity belong to allergy changes only, and only when written
        if intent.kind != .changeAllergies {
            intent.item = nil
            intent.severity = nil
        } else {
            if let item = intent.item, !lower.contains(item.lowercased()) { intent.item = nil }
            if let severity = intent.severity, !["allergy", "intolerance"].contains(severity) { intent.severity = nil }
        }
        // a product the person did not write is dropped (except for pivots, which refer back)
        if let product = intent.product, !lower.contains(product.lowercased()), intent.kind != .pivot {
            intent.product = KeywordRouter.productWords(lower, context: context)
        }
        return intent
    }

    static func instructions(_ context: ChatContext) -> String {
        let people = context.household.people.map { person in
            let avoids = person.profile.allergens.map(\.id) + person.profile.avoid.map(\.id) + person.profile.diets
            return "\(person.displayName): avoids \(avoids.isEmpty ? "nothing set" : avoids.joined(separator: ", "))"
        }
        let last = context.lastProducts.first.map { "The last product was \($0.name)." } ?? "No product yet."
        return """
            You read what a shopper wants from a grocery-label checking app. Only classify the request and copy \
            names and words as written; never judge a product. Intents: check (scan or check a product), \
            ask (is a named product OK for someone), otherOptions (find something else like a product), \
            compare (compare products), changeAllergies (add or remove an allergy or avoid), \
            pivot (change the last request: "make it nut-free", "what about Leo", "undo"), smallTalk.
            Examples:
            "Are the Cheerios OK for Mia?" -> ask, product "Cheerios", people ["Mia"]
            "can I have the kettle chips" -> ask, product "kettle chips", people []
            "scan this" or "check this" -> check, no product
            "find other options" -> otherOptions, no product
            "Add sesame to Mia's allergies" -> changeAllergies, item "sesame", people ["Mia"]
            Leave item and severity empty unless the person asks to change allergies.
            Household: \(people.joined(separator: "; ")). \(last)
            """
    }
}

/// The keyword fallback from the handoff (D1/D7): no model, same output shape.
public enum KeywordRouter {
    public static func read(_ text: String, context: ChatContext) -> ReadIntent {
        let lower = text.lowercased()
        let people = context.household.people.filter { lower.contains($0.name.lowercased()) }.map(\.name)
        let has = { (words: [String]) in words.contains { lower.contains($0) } }

        // job order matters: the most specific phrases first
        if has(["compare", " vs ", "versus"]) {
            return ReadIntent(intent: IntentKind.compare.rawValue, people: people)
        }
        if has(["add ", "remove ", "reacted", "allergic to", "my allergies", "her allergies", "his allergies"]) {
            return ReadIntent(intent: IntentKind.changeAllergies.rawValue, people: people, item: lastWord(after: ["add", "to"], in: lower),
                              severity: lower.contains("intoleran") ? "intolerance" : (lower.contains("allerg") ? "allergy" : nil))
        }
        if has(["what about", "make it", "undo"]) {
            return ReadIntent(intent: IntentKind.pivot.rawValue, people: people)
        }
        if has(["other option", "instead", "alternative", "something else", "find one", "find me", "without "]) {
            return ReadIntent(intent: IntentKind.otherOptions.rawValue, product: productWords(lower, context: context), people: people)
        }
        if has(["scan", "check this", "check it"]) {
            return ReadIntent(intent: IntentKind.check.rawValue, people: people)
        }
        if let product = productWords(lower, context: context), has(["ok for", "okay for", "can ", "is ", "are ", "check", "?"]) {
            return ReadIntent(intent: IntentKind.ask.rawValue, product: product, people: people)
        }
        return ReadIntent(intent: IntentKind.smallTalk.rawValue, people: people)
    }

    static let filler: Set<String> = [
        "are", "is", "the", "a", "an", "these", "this", "those", "ok", "okay", "for", "me", "my", "us", "can", "i", "we",
        "have", "eat", "check", "please", "find", "other", "options", "option", "instead", "something", "else", "one",
        "that", "it", "any", "some", "you", "your", "to", "of", "and", "with", "without", "alternative", "alternatives",
        "safe", "good", "fine", "kids", "kid", "son", "daughter", "like",
    ]

    /// The words left after removing filler and household names: "Are the popped corn chips OK for me?" -> "popped corn chips".
    static func productWords(_ lower: String, context: ChatContext) -> String? {
        let names = Set(context.household.people.map { $0.name.lowercased() })
        let words = lower.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)
            .filter { !filler.contains($0) && !names.contains($0) }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    static func lastWord(after markers: [String], in lower: String) -> String? {
        let words = lower.split { !$0.isLetter }.map(String.init)
        for marker in markers { if let i = words.lastIndex(of: marker), i + 1 < words.count { return words[i + 1] } }
        return nil
    }
}
