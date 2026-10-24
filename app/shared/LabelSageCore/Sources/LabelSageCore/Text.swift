import Foundation

/// Text normalization shared by the parser and the matcher. Mirrors tools/reference_engine.py (fold, norm, variants).
enum Text {
    /// Lowercase, strip accents, unify quotes, "&" -> " and ".
    static func fold(_ s: String) -> String {
        let decomposed = s.lowercased().decomposedStringWithCompatibilityMapping
        var scalars = String.UnicodeScalarView()
        for u in decomposed.unicodeScalars where u.properties.canonicalCombiningClass == .notReordered {
            switch u {
            case "\u{2019}", "\u{2018}": scalars.append("'")
            default: scalars.append(u)
            }
        }
        return String(scalars).replacingOccurrences(of: "&", with: " and ")
    }

    /// Phrase form for matching: words of [a-z0-9'] joined by one space, padded with a space on each side.
    static func norm(_ s: String) -> String {
        let f = fold(s)
        var cleaned = ""
        for ch in f {
            if ("a"..."z").contains(ch) || ("0"..."9").contains(ch) || ch == "'" { cleaned.append(ch) } else { cleaned.append(" ") }
        }
        // keep an apostrophe only between letters (brewer's), drop stray quotes
        let chars = Array(cleaned)
        var out = ""
        for (i, ch) in chars.enumerated() {
            if ch == "'" {
                let prevLetter = i > 0 && ("a"..."z").contains(chars[i - 1])
                let nextLetter = i + 1 < chars.count && ("a"..."z").contains(chars[i + 1])
                // Python: drop when not followed by a letter, or when not preceded by a letter
                out.append(prevLetter && nextLetter ? "'" : " ")
            } else {
                out.append(ch)
            }
        }
        let words = out.split(separator: " ", omittingEmptySubsequences: true)
        return " " + words.joined(separator: " ") + " "
    }

    /// The term and a simple plural.
    static func variants(_ term: String) -> [String] {
        let t = norm(term).trimmingCharacters(in: .whitespaces)
        return t.hasSuffix("s") ? [t] : [t, t + "s"]
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        if (10...20).contains(n % 100) { suffix = "th" } else {
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
