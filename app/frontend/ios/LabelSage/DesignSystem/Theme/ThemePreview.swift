import SwiftUI

// Font verification note (task T1): the Outfit variable font's PostScript name is
// "Outfit-Thin" (its default named instance, wght 100), but its *family* name — the one
// `Font.custom("Outfit", ...)` needs — is "Outfit", confirmed by loading
// `Outfit-VariableFont_wght.ttf` through CoreText (the same mechanism `UIAppFonts` /
// `UIFont.familyNames` use) and reading `kCTFontFamilyNameKey`:
//   CGFont postscript name: Outfit-Thin
//   CTFont family name:     Outfit
//   Matches for family "Outfit": Outfit-Thin, Outfit-Thin_Light, Outfit-Thin_Regular,
//     Outfit-Thin_Medium, Outfit-Thin_SemiBold, Outfit-Thin_Bold, Outfit-Thin_ExtraBold, ...
// CoreText auto-generates a named instance per weight from the font's `wght` axis (100-900), so
// `Font.custom("Outfit", size:, relativeTo:).weight(.semibold)` resolves correctly, matching
// tokens.json's instruction exactly. Below, every `Theme.type.*` style renders with this font, so
// a regression (wrong name, font not bundled, `UIAppFonts` entry missing) shows up immediately as
// the system fallback face in this preview.

private struct ColorSwatch: View {
    let name: String
    let color: Color

    var body: some View {
        VStack(spacing: Theme.spacing.xxs) {
            RoundedRectangle(cornerRadius: Theme.radius.field, style: .continuous)
                .fill(color)
                .frame(width: 64, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius.field, style: .continuous)
                        .stroke(Theme.color.hairline, lineWidth: 1)
                )
            Text(name)
                .themeText(.footnote)
                .foregroundStyle(Theme.color.muted)
                .lineLimit(1)
        }
    }
}

private struct VerdictSwatch: View {
    let name: String
    let style: Theme.VerdictStyle

    var body: some View {
        HStack(spacing: Theme.spacing.s) {
            ZStack {
                Circle().fill(style.wash).frame(width: 44, height: 44)
                Image(systemName: style.symbol)
                    .foregroundStyle(style.color)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(name).themeText(.bodyStrong)
                Text(style.word(names: "Mia")).themeText(.footnote).foregroundStyle(Theme.color.muted)
            }
        }
    }
}

private struct TypeSwatch: View {
    let name: String
    let style: Theme.TypeStyle

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
            Text("\(name)  ·  \(Int(style.size)) pt")
                .themeText(.footnote)
                .foregroundStyle(Theme.color.muted)
            Text(name == "number" ? "$12.34 · 1,024 mg" : "LabelSage checks the label")
                .themeText(style)
        }
    }
}

private struct SectionHeading: View {
    let title: String
    var body: some View {
        Text(title)
            .themeText(.sectionTitle)
            .padding(.top, Theme.spacing.m)
    }
}

/// Compile-time proof that `Theme`'s layout tokens are safe to read from a `nonisolated` SwiftUI
/// primitive. `Shape.path(in:)` (like `Layout` and `Animatable` curves) runs off the main actor;
/// if `Theme`'s static tokens were still implicitly `@MainActor` (this target's default actor
/// isolation, `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`), reading `Theme.radius.checkbox` here
/// would fail to compile.
private struct ThemeIsolationCheckShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: Theme.radius.checkbox, style: .continuous)
    }
}

#Preview("Theme") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.spacing.l) {
            SectionHeading(title: "color")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: Theme.spacing.m) {
                ColorSwatch(name: "ink", color: Theme.color.ink)
                ColorSwatch(name: "inkSecondary", color: Theme.color.inkSecondary)
                ColorSwatch(name: "muted", color: Theme.color.muted)
                ColorSwatch(name: "mutedGreen", color: Theme.color.mutedGreen)
                ColorSwatch(name: "hairline", color: Theme.color.hairline)
                ColorSwatch(name: "controlBorder", color: Theme.color.controlBorder)
                ColorSwatch(name: "surface", color: Theme.color.surface)
                ColorSwatch(name: "amber", color: Theme.color.amber)
                ColorSwatch(name: "amberDisabled", color: Theme.color.amberDisabled)
                ColorSwatch(name: "amberDisabledText", color: Theme.color.amberDisabledText)
                ColorSwatch(name: "brandGreen", color: Theme.color.brandGreen)
                ColorSwatch(name: "brandGreenDeep", color: Theme.color.brandGreenDeep)
                ColorSwatch(name: "cream", color: Theme.color.cream)
                ColorSwatch(name: "letterTile", color: Theme.color.letterTile)
                ColorSwatch(name: "letterTileInk", color: Theme.color.letterTileInk)
            }

            SectionHeading(title: "verdict")
            VStack(alignment: .leading, spacing: Theme.spacing.s) {
                VerdictSwatch(name: "ok", style: Theme.verdict.ok)
                VerdictSwatch(name: "checkFirst", style: Theme.verdict.checkFirst)
                VerdictSwatch(name: "notFor", style: Theme.verdict.notFor)
                VerdictSwatch(name: "cantConfirm", style: Theme.verdict.cantConfirm)
            }

            SectionHeading(title: "chip")
            HStack(spacing: Theme.spacing.m) {
                ColorSwatch(name: "avoid", color: Theme.chip.avoid.background)
                ColorSwatch(name: "preferNot", color: Theme.chip.preferNot.background)
                ColorSwatch(name: "dietGoal", color: Theme.chip.dietGoal.background)
            }

            SectionHeading(title: "screenTint")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: Theme.spacing.m) {
                ColorSwatch(name: "welcome", color: Theme.screenTint.welcome)
                ColorSwatch(name: "region", color: Theme.screenTint.region)
                ColorSwatch(name: "store", color: Theme.screenTint.store)
                ColorSwatch(name: "household", color: Theme.screenTint.household)
                ColorSwatch(name: "goal", color: Theme.screenTint.goal)
                ColorSwatch(name: "why", color: Theme.screenTint.why)
                ColorSwatch(name: "allergens", color: Theme.screenTint.allergens)
                ColorSwatch(name: "severity", color: Theme.screenTint.severity)
                ColorSwatch(name: "medical", color: Theme.screenTint.medical)
                ColorSwatch(name: "strict", color: Theme.screenTint.strict)
                ColorSwatch(name: "diet", color: Theme.screenTint.diet)
                ColorSwatch(name: "religion", color: Theme.screenTint.religion)
                ColorSwatch(name: "avoid", color: Theme.screenTint.avoid)
                ColorSwatch(name: "numbers", color: Theme.screenTint.numbers)
                ColorSwatch(name: "summary", color: Theme.screenTint.summary)
                ColorSwatch(name: "chat", color: Theme.screenTint.chat)
                ColorSwatch(name: "scan", color: Theme.screenTint.scan)
                ColorSwatch(name: "product", color: Theme.screenTint.product)
                ColorSwatch(name: "compareWith", color: Theme.screenTint.compareWith)
                ColorSwatch(name: "compare", color: Theme.screenTint.compare)
                ColorSwatch(name: "family", color: Theme.screenTint.family)
            }
            HStack(spacing: Theme.spacing.s) {
                Text("avatarTints").themeText(.footnote).foregroundStyle(Theme.color.muted)
                ForEach(Array(Theme.screenTint.avatarTints.enumerated()), id: \.offset) { _, tint in
                    Circle().fill(tint).frame(width: 28, height: 28)
                }
            }

            SectionHeading(title: "type")
            VStack(alignment: .leading, spacing: Theme.spacing.m) {
                TypeSwatch(name: "mascotTitle", style: Theme.type.mascotTitle)
                TypeSwatch(name: "screenTitle", style: Theme.type.screenTitle)
                TypeSwatch(name: "sectionTitle", style: Theme.type.sectionTitle)
                TypeSwatch(name: "productName", style: Theme.type.productName)
                TypeSwatch(name: "cardTitle", style: Theme.type.cardTitle)
                TypeSwatch(name: "body", style: Theme.type.body)
                TypeSwatch(name: "bodyStrong", style: Theme.type.bodyStrong)
                TypeSwatch(name: "callout", style: Theme.type.callout)
                TypeSwatch(name: "caption", style: Theme.type.caption)
                TypeSwatch(name: "footnote", style: Theme.type.footnote)
                TypeSwatch(name: "chip", style: Theme.type.chip)
                TypeSwatch(name: "primaryButton", style: Theme.type.primaryButton)
                TypeSwatch(name: "number", style: Theme.type.number)
            }

            SectionHeading(title: "shadow + motion")
            HStack(spacing: Theme.spacing.l) {
                VStack(spacing: Theme.spacing.xxs) {
                    Color.clear
                        .frame(width: 130, height: 80)
                        .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
                    Text("card").themeText(.footnote).foregroundStyle(Theme.color.muted)
                }
                VStack(spacing: Theme.spacing.xxs) {
                    Color.clear
                        .frame(width: 130, height: 80)
                        .themeCardBackground(cornerRadius: Theme.radius.optionCard, isSelected: true)
                    Text("selected").themeText(.footnote).foregroundStyle(Theme.color.muted)
                }
                VStack(spacing: Theme.spacing.xxs) {
                    Text("Continue")
                        .themeText(.primaryButton)
                        .foregroundStyle(Theme.color.ink)
                        .frame(width: 130)
                        .frame(minHeight: Theme.size.primaryButtonHeight)
                        .background(Theme.color.amber, in: RoundedRectangle(cornerRadius: Theme.radius.button, style: .continuous))
                        .themePrimaryGlow()
                    Text("primary glow").themeText(.footnote).foregroundStyle(Theme.color.muted)
                }
                VStack(spacing: Theme.spacing.xxs) {
                    ThemeIsolationCheckShape()
                        .fill(Theme.color.brandGreen)
                        .frame(width: 44, height: 44)
                    Text("nonisolated Shape").themeText(.footnote).foregroundStyle(Theme.color.muted)
                }
            }
        }
        .padding(Theme.spacing.screenGutter)
    }
    .background(Theme.screenTint.welcome)
}
