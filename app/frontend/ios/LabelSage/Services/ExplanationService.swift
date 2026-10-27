import Foundation
import FoundationModels
import LabelSageCore

/// The reason under a person's flag, and whether the on-device model wrote it.
nonisolated struct Explanation: Sendable, Equatable {
    var text: String
    var fromModel: Bool
}

/// Rewrites the engine's reason in LabelSage's voice with the on-device model
/// (`spike-foundation-models-ios27-prompts-tools-2026-10-23.md`, Q2 to Q8).
///
/// - The level never changes: this returns text only, and the engine's reason is the fallback.
/// - A fresh `LanguageModelSession` per call, static bundled instructions, no tools, tool calling disallowed.
/// - The prompt carries product and ingredient facts and the engine's reason with the person's name
///   replaced by `[person]`. No names, no profile, no user text.
/// - `ExplanationCheck` validates the output; any failure shows the template, with no retry.
nonisolated struct ExplanationService: Sendable {
    /// Sends the prompt to a model and returns its text, or nil when no model is available.
    typealias Rewriter = @Sendable (_ prompt: String) async throws -> String?

    private let rewrite: Rewriter

    /// - Parameter rewrite: the model call; tests pass a stub. Defaults to the on-device model.
    init(rewrite: @escaping Rewriter = ExplanationService.onDeviceModel) {
        self.rewrite = rewrite
    }

    /// Stands in for the person's name in the prompt; put back after the check.
    static let personToken = "[person]"

    /// The explanation for one person's verdict on `product`. Falls back to `verdict.reason`.
    func explain(_ verdict: PersonVerdict, product: Product) async -> Explanation {
        let fallback = Explanation(text: verdict.reason, fromModel: false)
        let facts = Self.facts(for: verdict, product: product)
        let started = ContinuousClock.now
        let output: String?
        do {
            output = try await rewrite(facts.prompt)
        } catch is CancellationError {
            return fallback  // the sheet closed; nothing to report
        } catch {
            Log.model.error("Explanation failed: \(String(describing: type(of: error)), privacy: .public)")
            return fallback
        }
        guard let output else {
            Log.model.notice("Explanation skipped: model unavailable")
            return fallback
        }
        if let failure = ExplanationCheck.failure(output, facts: facts) {
            Log.model.error("Explanation rejected: \(failure.rawValue, privacy: .public)")
            return fallback
        }
        let ms = Int((ContinuousClock.now - started) / .milliseconds(1))
        Log.model.info("Explanation accepted, prompt flag-explanation-v1, \(ms, privacy: .public) ms")
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: Self.personToken, with: verdict.name)
        return Explanation(text: text, fromModel: true)
    }

    // MARK: facts and prompt

    /// What the model may see, and what the check compares against.
    struct Facts: Sendable, Equatable {
        var level: Level
        /// The engine's reason with the name masked.
        var reason: String
        /// The matched label words ("whey"); the output must name them.
        var matched: String?
        var prompt: String
    }

    static func facts(for verdict: PersonVerdict, product: Product) -> Facts {
        let finding = verdict.findings.first
        let reason = mask(verdict.name, in: verdict.reason)
        var lines = [
            "flag: \(Copy.flag(verdict.level, names: [personToken]))",
            "reason: \(reason)",
            "product: \(product.name)",
        ]
        if let matched = finding?.matched { lines.append("matched label words: \(matched)") }
        if let index = finding?.index { lines.append("position: \(Copy.position(index))") }
        let prompt = """
            Rewrite the reason in one or two short sentences.
            FACTS
            \(lines.joined(separator: "\n"))
            END FACTS
            """
        return Facts(level: verdict.level, reason: reason, matched: finding?.matched, prompt: prompt)
    }

    /// Replaces the person's name with `personToken` where no letter or digit touches it, so "Al"
    /// leaves "almond" alone and names with dots or spaces ("Leo Jr.", "Mary Ann") work. The owner's
    /// "you" is no name.
    static func mask(_ name: String, in text: String) -> String {
        guard name != "you", !name.isEmpty else { return text }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}])"
        return text.replacingOccurrences(of: pattern, with: personToken, options: .regularExpression)
    }

    // MARK: on-device model

    /// Static and bundled: no product, person or user text ever goes into the instructions (Q4).
    static let instructions = """
        You rewrite one reason line for a food label check. The flag is ALREADY DECIDED by code. \
        NEVER change it, soften it or add advice. Use ONLY the facts between FACTS and END FACTS. \
        Name the matched label words exactly as given. Keep [person] exactly as written. \
        Write at most two short, plain sentences. Never use the words safe, safer, unsafe, guaranteed, \
        protected, allergy-proof or 100%. Do not use dashes.
        """

    /// One fresh session per call; nil when the model is unavailable.
    static let onDeviceModel: Rewriter = { prompt in
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let session = LanguageModelSession(model: model, tools: [], instructions: instructions)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 80, toolCallingMode: .disallowed)
        return try await session.respond(to: prompt, options: options).content
    }
}

/// Code checks the model's text before anyone sees it (FM spike Q3).
nonisolated enum ExplanationCheck {
    enum Failure: String, Sendable, Equatable {
        case empty, tooLong, denyWord, otherLevel, missingMatchedTerm, missingPerson, refusal, dash
    }

    /// The never-list (CLAUDE.md hard rules, voice-and-strings.md).
    static let denyWords = ["safe", "safer", "unsafe", "100%", "guaranteed", "allergy-proof", "protected"]
    static let refusalPhrases = ["sorry", "i can't", "i can’t", "i cannot", "as an ai"]
    static let maxCharacters = 240

    /// nil when `text` may replace the reason, else the first rule it breaks.
    static func failure(_ text: String, facts: ExplanationService.Facts) -> Failure? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if trimmed.isEmpty { return .empty }
        if trimmed.count > maxCharacters { return .tooLong }
        if containsDenyWord(lower) { return .denyWord }
        if containsOtherLevel(lower, level: facts.level) { return .otherLevel }
        if refusalPhrases.contains(where: lower.contains) { return .refusal }
        if trimmed.contains("\u{2014}") || trimmed.contains("\u{2013}") { return .dash }
        if let matched = facts.matched, !matched.isEmpty, !lower.contains(matched.lowercased()) {
            return .missingMatchedTerm
        }
        if facts.reason.contains(ExplanationService.personToken), !trimmed.contains(ExplanationService.personToken) {
            return .missingPerson
        }
        return nil
    }

    /// Whole-word match on words split at anything but letters, digits and "%": "safflower" passes;
    /// "safe", "Safe.", "safe-to-eat", "not-safe" and "100%-safe" fail. Multi-part terms
    /// ("allergy-proof") match as a phrase, so "allergy proof" fails too.
    static func containsDenyWord(_ lower: String) -> Bool {
        let words = tokens(lower)
        return denyWords.contains { containsPhrase(words, tokens($0)) }
    }

    /// True when `parts` appear in `words` as consecutive whole tokens.
    static func containsPhrase(_ words: [String], _ parts: [String]) -> Bool {
        guard !parts.isEmpty, parts.count <= words.count else { return false }
        return (0...(words.count - parts.count)).contains { Array(words[$0 ..< $0 + parts.count]) == parts }
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "%") }.map(String.init)
    }

    /// The flag wording of every level except `level` ("Not for", "OK for", "Check first",
    /// "Can’t confirm"), from `Copy.flag`. Model text that uses one would contradict the engine.
    /// Matched as whole words, so "look for" is not "ok for". Paraphrases ("fine for", "cannot
    /// confirm") are not caught; the template covers those.
    static func containsOtherLevel(_ lower: String, level: Level) -> Bool {
        let words = tokens(lower)
        return Level.allCases.filter { $0 != level }.contains { other in
            containsPhrase(words, tokens(Copy.flag(other, names: [])))
        }
    }
}
