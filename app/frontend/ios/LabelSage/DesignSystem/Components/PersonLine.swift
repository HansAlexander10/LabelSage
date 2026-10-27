import SwiftUI
import LabelSageCore

/// One line for everyone the product was checked for (00-foundations `PersonLine`): the worst
/// level's symbol, then `HouseholdVerdict.line`, e.g. "Not for Mia · OK for you". Used in the
/// product card and the sheet header. The text is ink (the verdict colors are too light for text);
/// the symbol carries the color.
struct PersonLine: View {
    let level: Level
    /// `HouseholdVerdict.line`, written by `Copy.householdLine`.
    let line: String

    init(level: Level, line: String) {
        self.level = level
        self.line = line
    }

    init(_ verdict: HouseholdVerdict) {
        self.init(level: verdict.overall, line: verdict.line)
    }

    var body: some View {
        let style = Theme.verdict.style(for: level)
        // Label keeps the symbol aligned with the first text line at every Dynamic Type size.
        Label {
            Text(line)
                .themeText(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.color.ink)
                .lineLimit(2)
        } icon: {
            Image(systemName: style.symbol)
                .foregroundStyle(style.color)
                .fontWeight(.semibold)
        }
        .labelStyle(.titleAndIcon)
        .font(Theme.TypeStyle.footnote.font)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line)
    }
}

#Preview("PersonLine") {
    VStack(alignment: .leading, spacing: Theme.spacing.m) {
        PersonLine(level: .notFor, line: "Not for Mia \u{00B7} OK for you")
        PersonLine(level: .checkFirst, line: "Check first for you \u{00B7} OK for Mia")
        PersonLine(level: .ok, line: "OK for you and Mia")
        PersonLine(level: .cantConfirm, line: "Can\u{2019}t confirm")
        PersonLine(level: .notFor, line: "Not for Mia, Leo and Sam \u{00B7} Check first for you \u{00B7} OK for Dad")
            .frame(width: 220, alignment: .leading)
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.color.surface)
}
