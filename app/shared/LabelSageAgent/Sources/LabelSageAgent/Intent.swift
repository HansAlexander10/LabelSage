import Foundation
import FoundationModels
import LabelSageCatalog
import LabelSageCore

/// What the person wants, read from their message. The model fills it with guided generation;
/// `KeywordRouter` fills the same shape when the model is unavailable.
@Generable
public struct ReadIntent: Sendable, Equatable {
    @Guide(description: "What the person wants", .anyOf(["check", "ask", "otherOptions", "compare", "changeAllergies", "pivot", "smallTalk"]))
    public var intent: String
    @Guide(description: "Product name or category as written, if any")
    public var product: String?
    @Guide(description: "Names of people from the household this is about; empty means everyone")
    public var people: [String]
    @Guide(description: "Ingredient or allergen to add or avoid, as written")
    public var item: String?
    @Guide(description: "allergy or intolerance if the person said so")
    public var severity: String?

    public init(intent: String, product: String? = nil, people: [String] = [], item: String? = nil, severity: String? = nil) {
        self.intent = intent; self.product = product; self.people = people; self.item = item; self.severity = severity
    }

    public var kind: IntentKind { IntentKind(rawValue: intent) ?? .smallTalk }
}

public enum IntentKind: String, Sendable, CaseIterable {
    case check, ask, otherOptions, compare, changeAllergies, pivot, smallTalk
}

/// What the agent keeps per chat (chat-agent.md, "Context the agent keeps per chat"). A new chat starts empty.
public struct ChatContext: Sendable {
    public var household: Household
    /// Up to 3, newest first.
    public var lastProducts: [Product] = []
    public var lastResult: HouseholdVerdict?

    public init(household: Household) { self.household = household }

    mutating func remember(_ products: [Product]) {
        lastProducts = Array((products + lastProducts).prefix(3))
    }
}

/// A profile change the agent proposes. Never saved without the person's Confirm (D14).
public struct ProfileChangeProposal: Sendable, Equatable {
    public var personName: String?
    public var item: String
    public var severity: String?
}

/// What the chat shows: LabelSage's line, the product cards with their verdicts, recalls, and a change to confirm.
public struct Reply: Sendable {
    public var intent: ReadIntent
    public var line: String
    /// True when the on-device model wrote `line` and it passed validation; false for the deterministic line.
    public var lineFromModel: Bool
    public var products: [Product]
    public var verdicts: [HouseholdVerdict]
    /// Recalls that name a product's barcode, by barcode. Shown first on the product card.
    public var recalls: [String: [Recall]]
    public var proposal: ProfileChangeProposal?
}
