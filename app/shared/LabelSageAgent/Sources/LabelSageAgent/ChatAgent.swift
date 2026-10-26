import Foundation
import LabelSageCatalog
import LabelSageCore

/// The chat pipeline: IntentReader -> Actions -> Writer (docs/logic/chat-agent.md).
/// One agent per chat; it keeps the chat's context. Code decides, LabelSage explains (D8).
public actor ChatAgent {
    public private(set) var context: ChatContext
    let reader: IntentReader
    let actions: ChatActions
    let writer: Writer

    public init(household: Household, catalog: CatalogProductSource, engine: VerdictEngine, useModel: Bool = true) {
        context = ChatContext(household: household)
        reader = IntentReader(useModel: useModel)
        actions = ChatActions(catalog: catalog, engine: engine)
        writer = Writer(useModel: useModel)
    }

    /// A typed message.
    public func send(_ text: String) async throws -> Reply {
        let intent = await reader.read(text, context: context)
        return try await run(intent)
    }

    /// A scan from the camera: the check intent with a barcode.
    public func scanned(barcode: String) async throws -> Reply {
        let intent = ReadIntent(intent: IntentKind.check.rawValue)
        let result = try await actions.check(barcode: barcode, household: context.household)
        return await finish(intent, result)
    }

    private func run(_ intent: ReadIntent) async throws -> Reply {
        let household = context.household
        let result: ChatActions.Result
        switch intent.kind {
        case .ask:
            result = try await actions.ask(intent.product ?? "", household: household, focus: intent.people)
        case .otherOptions:
            if let name = intent.product {
                result = try await actions.otherOptions(for: name, household: household)
            } else if let last = context.lastProducts.first {
                result = try await actions.otherOptions(like: last, household: household)
            } else {
                result = .init(line: "Which product should I find other options for?")
            }
        case .compare:
            if context.lastProducts.count >= 2 {
                result = try await actions.compare(context.lastProducts[1], context.lastProducts[0], household: household)
            } else {
                result = .init(line: "Check two products first, then I’ll compare them.")
            }
        case .changeAllergies:
            result = actions.proposeChange(intent)
        case .check:
            result = .init(line: "Point the camera at the barcode or the ingredient list.")
        case .pivot:
            result = .init(line: "Tell me what to change about the last check.")
        case .smallTalk:
            result = .init(line: "Every label, every time. I’m here for the checking part.")
        }
        return await finish(intent, result)
    }

    private func finish(_ intent: ReadIntent, _ result: ChatActions.Result) async -> Reply {
        if !result.products.isEmpty {
            context.remember(result.products)
            context.lastResult = result.verdicts.first
        }
        let written = await writer.write(result)
        return Reply(intent: intent, line: written.line, lineFromModel: written.fromModel, products: result.products,
                     verdicts: result.verdicts, recalls: result.recalls, proposal: result.proposal)
    }
}
