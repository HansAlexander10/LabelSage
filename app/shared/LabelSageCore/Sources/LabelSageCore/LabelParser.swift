import Foundation

/// An ingredient as printed, with its position. Sub-ingredients ("chocolate chips (sugar, milkfat)") share the parent's index.
public struct Ingredient: Sendable, Equatable {
    public var index: Int
    public var text: String
    public var parent: String?
    var norm: String
}

/// What the label says, split into the ingredient list, the "Contains" line and the "May contain" line.
public struct ParsedLabel: Sendable, Equatable {
    public var ingredients: [Ingredient] = []
    public var contains: [String] = []
    public var mayContain: [String] = []
    /// A "Contains:" statement exists. For US major allergens it resolves ambiguous terms (they would be declared there).
    public var hasContainsStatement = false
    var containsNorm: [String] { contains.map(Text.norm) }
    var mayContainNorm: [String] { mayContain.map(Text.norm) }
    public var hasList: Bool { !ingredients.isEmpty || !contains.isEmpty }
}

public enum LabelParser {
    public static func parse(_ product: Product, catalog: Catalog) -> ParsedLabel {
        var label = ParsedLabel()
        if let extra = product.containsStatement, !extra.isEmpty {
            var s = Text.fold(extra)
            if let r = s.range(of: "contains") { s.removeSubrange(r) }
            label.contains += statementItems(s)
            label.hasContainsStatement = true
        }
        if let extra = product.mayContainStatement, !extra.isEmpty {
            label.mayContain += statementItems(Text.fold(extra))
        }
        let markers = catalog.mayContainMarkers.map(Text.fold).sorted(by: Matcher.longestFirst)
        var index = 1
        for sentence in sentences(Text.fold(product.ingredientsText ?? "")) {
            let s = stripPrefix(sentence.trimmingCharacters(in: .whitespaces))
            if let hit = markers.first(where: { s.contains($0) }), let r = s.range(of: hit) {
                label.mayContain += statementItems(String(s[r.upperBound...]))
                continue
            }
            if isContainsStatement(s) {
                label.contains += statementItems(dropContainsWord(s))
                label.hasContainsStatement = true
                continue
            }
            let (items, next) = parseItems(s, start: index, parent: nil)
            label.ingredients += items
            index = next
        }
        return label
    }

    // MARK: - pieces (each mirrors a function in tools/reference_engine.py)

    /// "Ingredients:" at the start of a sentence.
    static func stripPrefix(_ s: String) -> String {
        let regex = try! Regex(#"^ingredients?\s*:?\s*"#)
        return s.replacing(regex, with: "", maxReplacements: 1)
    }

    /// "Contains: milk" but not "contains 2% or less of".
    static func isContainsStatement(_ s: String) -> Bool {
        let regex = try! Regex(#"^contains\b(?!\s*\d)(?!\s+less)"#).wordBoundaryKind(.simple)
        return s.prefixMatch(of: regex) != nil
    }

    static func dropContainsWord(_ s: String) -> String {
        let regex = try! Regex(#"^contains\s*:?"#)
        return s.replacing(regex, with: "", maxReplacements: 1)
    }

    /// Split on "." or newline at bracket depth 0, but not inside a number like 2.5%.
    static func sentences(_ s: String) -> [String] {
        let chars = Array(s)
        var out: [String] = []
        var depth = 0
        var cur = ""
        for (i, ch) in chars.enumerated() {
            if "([{".contains(ch) { depth += 1 } else if ")]}".contains(ch) { depth = max(0, depth - 1) }
            let isDecimalPoint = ch == "." && i > 0 && chars[i - 1].isNumber && i + 1 < chars.count && chars[i + 1].isNumber
            if depth == 0 && (ch == "\n" || ch == "\r\n" || (ch == "." && !isDecimalPoint)) {
                out.append(cur); cur = ""
            } else {
                cur.append(ch)
            }
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func splitDepth0(_ s: String, separators: String = ",;") -> [String] {
        var parts: [String] = []
        var depth = 0
        var cur = ""
        for ch in s {
            if "([{".contains(ch) { depth += 1 } else if ")]}".contains(ch) { depth = max(0, depth - 1) }
            if separators.contains(ch) && depth == 0 {
                parts.append(cur); cur = ""
            } else {
                cur.append(ch)
            }
        }
        parts.append(cur)
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// "contains 2% or less of:" and "less than 2% of" in front of an item.
    static func dropLessThan(_ s: String) -> String {
        let regex = try! Regex(#"^(and |contains )?(\d+(\.\d+)?\s*% or less of|less than \d+(\.\d+)?\s*% of)\s*:?\s*"#)
        return s.replacing(regex, with: "", maxReplacements: 1)
    }

    static func parseItems(_ s: String, start: Int, parent: String?) -> ([Ingredient], Int) {
        var items: [Ingredient] = []
        var idx = start
        for raw in splitDepth0(s) {
            let part = dropLessThan(raw.trimmingCharacters(in: .whitespaces))
            var head = part
            var inner: String?
            // head ( inner ) with only spaces or * after the last closing bracket
            if let open = part.firstIndex(where: { "([{".contains($0) }),
               let close = part.lastIndex(where: { ")]}".contains($0) }), open < close,
               part[part.index(after: close)...].allSatisfy({ $0 == " " || $0 == "*" || $0.isNewline }) {
                head = String(part[..<open]).trimmingCharacters(in: .whitespaces)
                inner = String(part[part.index(after: open)..<close])
            }
            head = head.trimmingCharacters(in: CharacterSet(charactersIn: " *:"))
            if !head.isEmpty {
                items.append(Ingredient(index: idx, text: head, parent: parent, norm: Text.norm(head)))
            }
            if let inner {
                let (subs, _) = parseItems(inner, start: idx, parent: head.isEmpty ? parent : head)
                items += subs.map { var x = $0; x.index = idx; return x }
            }
            idx += 1
        }
        return (items, idx)
    }

    /// "Contains: milk, soy and wheat." -> ["milk", "soy", "wheat"]
    static func statementItems(_ s: String) -> [String] {
        let filler = try! Regex(#"\btraces? of\b|\bother\b|\bproducts?\b|\bingredients?\b"#).wordBoundaryKind(.simple)
        let cleaned = s.replacing(filler, with: " ")
        let joiners = try! Regex(#"\band\b|\bor\b|/"#).wordBoundaryKind(.simple)
        var out: [String] = []
        for p in splitDepth0(cleaned, separators: ",;") {
            for q in p.split(separator: joiners) {
                let item = String(q).trimmingCharacters(in: CharacterSet(charactersIn: " :.*"))
                if !item.isEmpty { out.append(item) }
            }
        }
        return out
    }
}
