import Foundation
import LabelSageCore

/// What one chat message asks for (`docs/logic/chat-agent.md` › Intents, board 71). The six MVP
/// intents plus small talk. `IntentRouter` reads it; `ChatModel` acts on it in plain Swift.
nonisolated enum ChatIntent: Equatable, Sendable {
    /// Check a product: a name to search ("popped corn chips"), or nil to open the camera.
    case check(product: String?)
    /// Ask about one ingredient ("what is tahini?"): the phrase after the question words.
    case ingredient(String)
    /// Other options: a category as written ("kettle chips"), or nil for the last product's category,
    /// and what to leave out ("seed oils"), if the person said so.
    case otherOptions(query: String?, without: String?)
    /// Compare the last two products.
    case compare
    /// Add an item to someone's rules. Only a proposal: nothing is saved without Confirm (D14).
    case changeAllergies(person: String?, item: String, severity: Severity?)
    /// Change the last result in place; never start from scratch.
    case pivot(Pivot)
    /// Venting or anything else: one line, listen pose, no sales.
    case smallTalk(vent: Bool)

    /// The pivots on board 71.
    enum Pivot: Equatable, Sendable {
        /// "undo": reverts the last saved change.
        case undo
        /// "what about Leo?": the last product for that person.
        case person(String)
        /// "intolerance only": the pending change card's severity.
        case severity(Severity)
        /// "go back to the first one".
        case firstProduct
        /// "check another".
        case checkAnother
    }
}

/// The deterministic keyword router: text in, `ChatIntent` out. The fallback the spec asks for when
/// the on-device model is unavailable, and today the only reader (the model path is optional).
/// Runs on the device; the names it receives never leave it.
nonisolated enum IntentRouter {
    /// - Parameters:
    ///   - text: the person's message as typed.
    ///   - names: the household's names ("Alex", "Mia"), to spot who a message is about.
    static func read(_ text: String, names: [String]) -> ChatIntent {
        let s = normalize(text)
        let lowerNames = names.map { $0.lowercased() }
        guard !s.isEmpty else { return .smallTalk(vent: false) }
        // "Hi", "thanks": small talk, not a product search ("hi" is inside "chips").
        if greetings.contains(s.trimmingCharacters(in: CharacterSet(charactersIn: "?,"))) { return .smallTalk(vent: false) }

        if let pivot = pivot(s, names: lowerNames) { return .pivot(pivot) }
        if let change = change(s, names: lowerNames) { return change }
        if has(s, ["compare", " vs ", " versus ", "which is better", "which one is better"]) { return .compare }
        if has(s, ["other option", "options", "instead", "alternative", "find one", "find me", "something else",
                   "without ", " free of ", "-free", "show me other", "try instead", "find "]) {
            let (query, without) = optionsQuery(s, names: lowerNames)
            return .otherOptions(query: query, without: without)
        }
        if let phrase = ingredientQuestion(s) { return .ingredient(phrase) }
        if has(s, ["every label", "tired", "exhausting", "ugh", "hate ", "so hard", "frustrat"]) {
            return .smallTalk(vent: true)
        }
        if has(s, ["ok for", "okay for", "safe", "check", "can i eat", "can she", "can he", "is this", "is it",
                   "are the", "is the", "good for", "fine for", "ok?", "okay?"]) || s.hasSuffix(" ok") {
            let name = productName(s, names: lowerNames)
            return .check(product: name)
        }
        // A short message is most likely a product name ("peanut butter").
        let words = s.split(separator: " ")
        if words.count <= 5 { return .check(product: productName(s, names: lowerNames)) }
        return .smallTalk(vent: false)
    }

    /// True when the router only fell through to small talk: not a greeting, not venting, more than
    /// two words. The on-device model then gets a turn (`ModelIntentReader`).
    static func isMiss(_ intent: ChatIntent, text: String) -> Bool {
        guard intent == .smallTalk(vent: false) else { return false }
        let s = normalize(text).trimmingCharacters(in: CharacterSet(charactersIn: "?,"))
        return !greetings.contains(s) && s.split(separator: " ").count > 2
    }

    private static let greetings: Set<String> = [
        "hi", "hey", "hello", "hiya", "yo", "hi there", "hey there", "hello there", "good morning",
        "good afternoon", "good evening", "thanks", "thank you", "thx", "ty", "ok", "okay", "cool", "great", "nice",
    ]

    // MARK: pieces

    /// Lowercased, curly quotes made straight, end punctuation and spare spaces removed.
    static func normalize(_ text: String) -> String {
        var s = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!")))
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func has(_ s: String, _ keys: [String]) -> Bool {
        keys.contains { s.contains($0) }
    }

    private static func pivot(_ s: String, names: [String]) -> ChatIntent.Pivot? {
        let bare = s.trimmingCharacters(in: CharacterSet(charactersIn: "?"))
        if ["undo", "undo that", "undo it", "take that back", "revert"].contains(bare) { return .undo }
        if has(bare, ["first one", "go back to the first"]) { return .firstProduct }
        if ["check another", "scan another", "check another one", "scan another one"].contains(bare) { return .checkAnother }
        if has(bare, ["intolerance only", "only intolerance", "just intolerance", "make it an intolerance",
                      "it's an intolerance", "intolerance, not"]) { return .severity(.intolerance) }
        if has(bare, ["allergy only", "make it an allergy", "it's an allergy", "a real allergy"]) { return .severity(.allergy) }
        for prefix in ["what about ", "and for ", "how about ", "and "] where bare.hasPrefix(prefix) {
            let rest = String(bare.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            let word = rest.split(separator: " ").first.map(String.init) ?? ""
            if rest == "me" || rest == "you" { return .person("you") }
            // A single word: a household name, or another name ("Leo") the screen answers about.
            if rest.split(separator: " ").count == 1, !word.isEmpty, !stopWords.contains(word) || names.contains(word) {
                return .person(word.capitalized)
            }
        }
        return nil
    }

    /// "Add sesame to Mia's allergies", "Mia is allergic to sesame", "I'm intolerant to lactose",
    /// "Mia reacted to hummus".
    private static func change(_ s: String, names: [String]) -> ChatIntent? {
        let triggers = ["allerg", "intoleran", "reacted to", "react to"]
        guard has(s, triggers) else { return nil }
        let severity: Severity? = s.contains("intoleran") ? .intolerance : (s.contains("allerg") ? .allergy : nil)
        var item: String?
        // The explicit item wins over the food someone reacted to.
        for pattern in ["add (.+?) to ", "add (.+)$", "allergic to (.+)$", "intolerant to (.+)$",
                        "intolerant of (.+)$", "allergy to (.+)$", "reacted to (.+?)(?:\\.|,|$)", "react to (.+?)(?:\\.|,|$)"] {
            if let found = firstGroup(pattern, in: s) { item = found; break }
        }
        guard var item else { return nil }
        item = item.replacingOccurrences(of: "\\b(her|his|my|their|the|some|to|allergies|allergy|list)\\b",
                                         with: " ", options: .regularExpression)
        item = item.split(separator: " ").joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ?,"))
        guard !item.isEmpty else { return nil }

        var person: String?
        let words = Set(s.split { !$0.isLetter }.map(String.init))
        if let name = names.first(where: { words.contains($0) || words.contains($0 + "s") }) {
            person = name
        } else if has(s, ["i'm ", "i am ", " my ", "my ", " me"]) {
            person = "you"
        } else if let other = firstGroup("([a-z]+)'s (?:allerg|intoleran)", in: s) {
            // "Leo's allergies": a name outside the household; the screen says to add them first.
            person = other
        }
        return .changeAllergies(person: person, item: item, severity: severity)
    }

    private static func ingredientQuestion(_ s: String) -> String? {
        for prefix in ["what is ", "what's ", "whats ", "what are ", "what does ", "tell me about ", "is there "] where s.hasPrefix(prefix) {
            return String(s.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
        }
        // "is sunflower oil a seed oil?"
        if s.hasPrefix("is "), s.contains(" a "), !has(s, ["ok", "okay", "safe", "good", "fine"]) {
            return String(s.dropFirst(3)).trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
        }
        if s.contains("ingredient") {
            return s.replacingOccurrences(of: "ingredients?", with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
        }
        return nil
    }

    /// Category and "without" for other options. "kettle chips without seed oils" → ("kettle chips", "seed oils").
    static func optionsQuery(_ s: String, names: [String]) -> (String?, String?) {
        var text = s.trimmingCharacters(in: CharacterSet(charactersIn: "?"))
        var without: String?
        for cut in [" without ", " with no ", " free of ", " but no "] {
            if let range = text.range(of: cut) {
                without = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                text = String(text[..<range.lowerBound])
                break
            }
        }
        if without == nil, let free = firstGroup("([a-z ]+?)-free", in: text) {
            without = free.split(separator: " ").last.map(String.init)
            text = text.replacingOccurrences(of: "\(without ?? "")-free", with: "")
        }
        let optionWords: Set<String> = ["find", "other", "options", "option", "show", "some", "any", "instead",
                                        "alternative", "alternatives", "something", "else", "one", "ones", "like",
                                        "similar", "better", "more", "get", "give", "want", "need", "looking",
                                        "try", "that", "make", "us"]
        let kept = words(text).filter { !stopWords.contains($0) && !optionWords.contains($0) && !names.contains($0) }
        let query = kept.joined(separator: " ")
        return (query.isEmpty ? nil : query, without?.isEmpty == true ? nil : without)
    }

    /// The product words of a "check" message: "are the popped corn chips ok for me?" → "popped corn chips".
    static func productName(_ s: String, names: [String]) -> String? {
        let kept = words(s).filter { !stopWords.contains($0) && !names.contains($0) }
        let name = kept.joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    private static func words(_ s: String) -> [String] {
        s.split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "%") }
            .map { String($0).replacingOccurrences(of: "'s", with: "") }
    }

    /// Words that are never part of a product name.
    static let stopWords: Set<String> = [
        "are", "is", "the", "a", "an", "ok", "okay", "for", "me", "my", "i", "can", "eat", "have", "this", "these",
        "those", "it", "they", "safe", "check", "good", "fine", "to", "of", "still", "please", "and", "you", "we",
        "our", "family", "kids", "son", "daughter", "whether", "if", "do", "does", "them", "with", "she", "he",
        "her", "his", "go", "what", "about", "how", "would", "will", "be", "should", "could", "everyone",
    ]

    private static func firstGroup(_ pattern: String, in s: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: s) else { return nil }
        let found = String(s[range]).trimmingCharacters(in: .whitespaces)
        return found.isEmpty ? nil : found
    }
}
