import SwiftUI
import LabelSageCore

// The cards and full-screen states of "Check a product" (spec 03 states 2, 5 to 8, boards 60 and 61).

/// The white card over the dimmed camera (`ScanStateCard`, radius 28). Content layer: no glass.
// Custom card: no system bottom card without a sheet; a sheet would hide the frame (board 61).
struct ScanStateCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            Capsule()
                .fill(Theme.color.controlBorder)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            content
        }
        .padding(.horizontal, Theme.spacing.xl)
        .padding(.top, Theme.spacing.s)
        .padding(.bottom, Theme.spacing.section)
        .foregroundStyle(Theme.color.ink)
        .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.phoneSheet, style: .continuous))
        .environment(\.colorScheme, .light)
        .padding(Theme.spacing.s)
    }
}

/// The two light buttons under a card: "Report it", "Check another" (prototype `secondary`).
struct ScanSecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .themeText(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Theme.color.brandGreenDeep)
    }
}

/// Two secondary buttons side by side; stacked at accessibility sizes.
private struct SecondaryPair<A: View, B: View>: View {
    @ViewBuilder let first: A
    @ViewBuilder let second: B

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.spacing.m) { first; second }
            VStack(spacing: Theme.spacing.s) { first; second }
        }
    }
}

/// State 2: "Looking up 0 28400 59031 8…" with a placeholder row.
struct ScanCheckingCard: View {
    /// "Looking up …" or "Reading the ingredients…".
    let line: String

    var body: some View {
        ScanStateCard {
            HStack(spacing: Theme.spacing.m) {
                MascotView(state: .reading, size: 24, animates: false)
                Text(line)
                    .themeText(.callout)
                    .monospacedDigit()
                    .foregroundStyle(Theme.color.inkSecondary)
            }
            // Native placeholder look for the row that is on its way.
            HStack(spacing: Theme.spacing.m) {
                RoundedRectangle(cornerRadius: 14).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: Theme.spacing.s) {
                    Text("Product name placeholder")
                    Text("Brand placeholder")
                }
            }
            .redacted(reason: .placeholder)
            .foregroundStyle(Theme.color.hairline)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// State 5: the barcode is new to the source.
struct ScanNotFoundCard: View {
    /// The headline, also announced when the card appears.
    static let headline = "This one’s new to me. Photo the ingredients and I’ll read them."
    let barcode: String
    let reported: Bool
    let onPhoto: () -> Void
    let onReport: () -> Void
    let onCheckAnother: () -> Void

    var body: some View {
        ScanStateCard {
            HStack(alignment: .top, spacing: Theme.spacing.m) {
                MascotView(state: .disguise, size: 40)
                VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                    Text(Self.headline)
                        .themeText(Theme.TypeStyle(size: 20, weight: .semibold, relativeTo: .title3))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Barcode \(BarcodeFormat.display(barcode))")
                        .themeText(.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.color.muted)
                }
            }
            PrimaryButton(title: "Photo the ingredients", systemImage: "camera", showsChevron: false, action: onPhoto)
            if reported { ScanThanksRow() }
            SecondaryPair {
                if !reported { ScanSecondaryButton(title: "Report it", systemImage: "paperclip", action: onReport) }
            } second: {
                ScanSecondaryButton(title: "Check another", systemImage: "barcode.viewfinder", action: onCheckAnother)
            }
        }
    }
}

/// "Thanks. We’ll add it." after a report.
struct ScanThanksRow: View {
    var body: some View {
        Label("Thanks. We’ll add it.", systemImage: "checkmark.circle")
            .themeText(.callout)
            .padding(.horizontal, Theme.spacing.l)
            .padding(.vertical, Theme.spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.verdict.ok.wash, in: .rect(cornerRadius: 16, style: .continuous))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// State 6: found, but no ingredient list yet. The level comes from the engine (Can’t confirm).
struct ScanNoIngredientsCard: View {
    let result: ScanResult
    let reported: Bool
    let onPhoto: () -> Void
    let onReport: () -> Void
    let onCheckAnother: () -> Void

    private var style: Theme.VerdictStyle { Theme.verdict.style(for: result.verdict.verdict.overall) }

    /// "Data updated Oct 2026 · not medical advice".
    private var dataLine: String {
        guard let date = result.product.dataUpdatedAt else { return VerdictBanner.disclaimer }
        return "\(DataAge.updatedLine(date)) · not medical advice"
    }

    var body: some View {
        ScanStateCard {
            HStack(spacing: Theme.spacing.m) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.color.hairline.opacity(0.5))
                    .strokeBorder(Theme.color.hairline)
                    .frame(width: 64, height: 64)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: style.symbol)
                            .font(.system(size: 22))
                            .foregroundStyle(style.color)
                            .background(Circle().fill(Theme.color.surface).padding(-3))
                            .offset(x: 6, y: 6)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let brand = result.product.brand {
                        Text(brand).themeText(.footnote).foregroundStyle(Theme.color.muted)
                    }
                    Text([result.product.name, result.product.size].compactMap { $0 }.joined(separator: ", "))
                        .themeText(Theme.TypeStyle(size: 18, weight: .semibold, relativeTo: .headline))
                }
            }
            HStack(alignment: .top, spacing: Theme.spacing.m) {
                MascotView(state: result.verdict.pose, size: 30, animates: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.flag(result.verdict.verdict.overall, names: []))
                        .themeText(.bodyStrong)
                    Text("No ingredient list for this one yet. Check the package, or photo the ingredients and I’ll read them.")
                        .themeText(.callout)
                        .foregroundStyle(Theme.color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(dataLine)
                        .themeText(Theme.TypeStyle(size: 12, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Theme.color.muted)
                        .padding(.top, Theme.spacing.xxs)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.screenTint.why, in: .rect(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .combine)
            // Spec 03 lists "Photo the ingredients" here; board 61 draws only the two buttons (Q-T8-1).
            PrimaryButton(title: "Photo the ingredients", systemImage: "camera", showsChevron: false, action: onPhoto)
            SecondaryPair {
                ScanSecondaryButton(title: reported ? "Reported" : "Report it", systemImage: "doc.text", action: onReport)
                    .disabled(reported)
            } second: {
                ScanSecondaryButton(title: "Check another", systemImage: "barcode.viewfinder", action: onCheckAnother)
            }
        }
    }
}

/// Edge case: the photo had no ingredient list.
struct ScanUnreadableCard: View {
    /// The headline, also announced when the card appears.
    static let headline = "I couldn’t read the ingredients. Try closer, with more light."
    let onRetake: () -> Void
    let onCheckAnother: () -> Void

    var body: some View {
        ScanStateCard {
            HStack(alignment: .top, spacing: Theme.spacing.m) {
                MascotView(state: .thinking, size: 40)
                Text(Self.headline)
                    .themeText(Theme.TypeStyle(size: 20, weight: .semibold, relativeTo: .title3))
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: "Retake", systemImage: "camera", showsChevron: false, action: onRetake)
            ScanSecondaryButton(title: "Check another", systemImage: "barcode.viewfinder", action: onCheckAnother)
        }
    }
}

/// State 7: camera access off. Full screen, light (board 61).
struct ScanCameraOffView: View {
    let onClose: () -> Void
    let onOpenSettings: () -> Void
    let onTypeName: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CameraGlassButton(systemImage: "xmark", label: "Close", onDark: false, action: onClose)
                Spacer()
            }
            .padding(.horizontal, Theme.spacing.l)
            ContentUnavailableView {
                VStack(spacing: Theme.spacing.l) {
                    HStack(spacing: Theme.spacing.s) {
                        MascotView(state: .listen, size: 74)
                        Image(systemName: "camera")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Theme.color.brandGreen)
                            .frame(width: 96, height: 96)
                            .background(Theme.color.surface, in: .rect(cornerRadius: 26, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    Text("Allow the camera to check products")
                        .themeText(Theme.TypeStyle(size: 28, weight: .bold, relativeTo: .title))
                        .foregroundStyle(Theme.color.ink)
                }
            } description: {
                Text("The barcode is read on your iPhone. No photos are saved or sent.")
                    .themeText(.body)
                    .foregroundStyle(Theme.color.inkSecondary)
            }
            VStack(spacing: Theme.spacing.m) {
                PrimaryButton(title: "Open Settings", showsChevron: false, action: onOpenSettings)
                Button("Type a name instead", action: onTypeName)
                    .themeText(.body)
                    .foregroundStyle(Theme.color.brandGreen)
                    .frame(minHeight: Theme.size.minTap)
            }
            .padding(.horizontal, Theme.spacing.screenGutter)
            .padding(.bottom, Theme.spacing.xl)
        }
        .background(Theme.screenTint.welcome.opacity(0.4).ignoresSafeArea())
        .background(Theme.color.surface.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }
}

/// State 8: offline, with the products checked before (re-checked against today's allergies).
struct ScanOfflineView: View {
    /// The headline, also announced when the screen appears.
    static let headline = "You’re offline"
    let checkedBefore: [ScanResult]
    let onBack: () -> Void
    let onTryAgain: () -> Void
    let onOpen: (Product) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.l) {
                CameraGlassButton(systemImage: "chevron.left", label: "Back", onDark: false, action: onBack)
                HStack(alignment: .top, spacing: Theme.spacing.m) {
                    MascotView(state: .thinking, size: 44)
                    VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                        Text(Self.headline).themeText(.cardTitle)
                        Text("Products you checked before still work. A new product needs a connection.")
                            .themeText(.callout)
                            .foregroundStyle(Theme.color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: onTryAgain) {
                            Label("Try again", systemImage: "arrow.clockwise")
                                .themeText(.callout)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.color.brandGreen)
                        .padding(.top, Theme.spacing.s)
                    }
                }
                .padding(Theme.spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)

                if !checkedBefore.isEmpty {
                    SectionHeader("Checked before")
                    VStack(spacing: 0) {
                        ForEach(checkedBefore) { result in
                            ProductRow(product: result.product, level: result.verdict.verdict.overall,
                                       names: result.verdict.verdict.people.map(\.name),
                                       notes: [ProductRow.Note(level: result.verdict.verdict.overall, text: result.verdict.verdict.line)],
                                       style: .compact) { onOpen(result.product) }
                            if result.id != checkedBefore.last?.id { Divider().padding(.leading, 72) }
                        }
                    }
                    .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.tile, style: .continuous))
                    Text("Saved checks use what you avoid today. Check the package. Not medical advice.")
                        .themeText(.footnote)
                        .foregroundStyle(Theme.color.muted)
                }
            }
            .foregroundStyle(Theme.color.ink)
            .padding(.horizontal, Theme.spacing.l)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }
}

/// A 44 pt circle on clear glass over the camera, white symbol (spec 03 top bar). On the light
/// states it uses regular glass with an ink symbol, like `GlassButton`.
// Custom: `GlassButton` draws an ink symbol on regular glass, unreadable over the dark feed.
struct CameraGlassButton: View {
    let systemImage: String
    let label: String
    var onDark = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(onDark ? Color.white : Theme.color.ink)
                .frame(width: Theme.size.minTap, height: Theme.size.minTap)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(onDark ? .clear.interactive() : .regular.interactive(), in: .circle)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer()
    }
}

// MARK: - Previews

#Preview("Card - checking") {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        ScanCheckingCard(line: "Looking up \(BarcodeFormat.display("028400590318"))…")
    }
}

#Preview("Card - not found") {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        ScanNotFoundCard(barcode: "012345678905", reported: false, onPhoto: {}, onReport: {}, onCheckAnother: {})
    }
}

#Preview("Card - unreadable") {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        ScanUnreadableCard(onRetake: {}, onCheckAnother: {})
    }
}

#Preview("Camera off") {
    ScanCameraOffView(onClose: {}, onOpenSettings: {}, onTypeName: {})
}
