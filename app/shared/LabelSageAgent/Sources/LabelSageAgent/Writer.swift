import Foundation
import FoundationModels

/// Rewrites the deterministic line in LabelSage's voice with the on-device model, then validates it.
/// Any failure, twice, gives the deterministic line (chat-agent.md, "Guardrails").
public struct Writer: Sendable {
    public var useModel: Bool

    public init(useModel: Bool = true) { self.useModel = useModel }

    /// Words LabelSage never uses (voice-and-strings.md): "safe" in any form and promises of an outcome.
    static let neverSubstrings = ["safe", "100%", "guarantee", "allergy-proof", "allergy-friendly"]
    static let neverWords: Set<String> = ["protected", "approved", "cleared", "good", "bad", "warning"]

    public func write(_ result: ChatActions.Result) async -> (line: String, fromModel: Bool) {
        guard useModel, IntentReader.modelAvailable, !result.line.isEmpty else { return (result.line, false) }
        for _ in 0..<2 {
            guard let candidate = try? await rewrite(result) else { continue }
            if Self.isValid(candidate, mustKeep: result.mustKeep, original: result.line) { return (candidate, true) }
        }
        return (result.line, false)
    }

    /// Words a rewrite may add without adding a fact. Any other new word (an ingredient, a food, a brand) is a
    /// fact the engine did not state, so the line is rejected: the model once wrote "Almonds in it" about Cheerios.
    static let connectingWords: Set<String> = [
        "a", "an", "the", "it", "its", "it's", "this", "these", "that", "those", "there", "here", "is", "are", "was",
        "in", "on", "of", "for", "to", "and", "or", "but", "so", "no", "not", "any", "all", "has", "have", "with",
        "list", "label", "ingredients", "ingredient", "says", "say", "found", "find", "spotted", "see", "i", "we",
        "you", "your", "me", "my", "her", "his", "their", "just", "one", "check", "first", "ok", "can't", "confirm",
        "nothing", "none", "avoids", "avoid", "contains", "contain", "listed", "here's", "looks", "clear", "of",
    ]

    /// The words of `line` that are not in `original` and not connecting words: new facts.
    static func newFacts(_ line: String, original: String) -> [String] {
        let words = { (s: String) in
            s.replacingOccurrences(of: "’", with: "'").lowercased()
                .split { !$0.isLetter && $0 != "'" && $0 != "-" }.map { String($0) }
        }
        let known = Set(words(original))
        return words(line).filter { !known.contains($0) && !connectingWords.contains($0) && !known.contains($0 + "s")
                                    && !($0.hasSuffix("s") && known.contains(String($0.dropLast()))) }
    }

    private func rewrite(_ result: ChatActions.Result) async throws -> String {
        let session = LanguageModelSession(instructions: """
            You are LabelSage, a calm label-checking hero. Rewrite the line below in at most 20 words, one idea, \
            plain words. Keep these words exactly: \(result.mustKeep.map { "\"\($0)\"" }.joined(separator: ", ")). \
            Keep the ingredient named in the line. Never use the word safe or promise an outcome. Reply with the line only.
            """)
        return try await session.respond(to: result.line, options: GenerationOptions(sampling: .greedy))
            .content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The model's line must keep the person and flag words, add no new facts, avoid the never-list, and stay short.
    public static func isValid(_ line: String, mustKeep: [String], original: String) -> Bool {
        newFacts(line, original: original).isEmpty && isValid(line, mustKeep: mustKeep)
    }

    static func isValid(_ line: String, mustKeep: [String]) -> Bool {
        let normalized = line.replacingOccurrences(of: "’", with: "'").lowercased()
        let words = normalized.split { !$0.isLetter && $0 != "-" }.map(String.init)
        guard !line.isEmpty, words.count <= 20 else { return false }
        guard !neverSubstrings.contains(where: normalized.contains), neverWords.isDisjoint(with: words) else { return false }
        return mustKeep.allSatisfy { normalized.contains($0.replacingOccurrences(of: "’", with: "'").lowercased()) }
    }
}
