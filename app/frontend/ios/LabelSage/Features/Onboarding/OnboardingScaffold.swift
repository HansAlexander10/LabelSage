import SwiftUI

/// The skeleton of every question step (spec 01 › Every question step): glass back, section dots,
/// Skip; LabelSage at 74 pt with his line as the title; the answers; the amber button pinned at
/// the bottom. The step's content slides 24 pt and fades on Continue (Back mirrors it); LabelSage
/// stays in place and only crossfades his pose.
// Custom container: the mascot stays put while the content slides, which a NavigationStack push
// cannot do (native-components.md › Step skeleton).
struct OnboardingScaffold<Content: View>: View {
    /// Identifies the content for the step transition.
    let stepID: String
    let section: Int
    let pose: MascotState
    let line: String
    let tint: Color
    var skipTitle: String?
    var forward = true
    let primaryTitle: String
    /// nil when Continue is enabled, else what is missing (VoiceOver hint).
    var missing: String?
    let back: () -> Void
    var skip: () -> Void = {}
    let primary: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MascotView(state: pose, size: dynamicTypeSize.isAccessibilitySize ? 56 : Theme.size.mascotOnboarding)
                ZStack {
                    VStack(spacing: Theme.spacing.xl) {
                        OnboardingTitle(line: line)
                        content()
                    }
                    .id(stepID)
                    .transition(stepTransition)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.spacing.screenGutter)
            .padding(.bottom, Theme.spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(tint.ignoresSafeArea())
        .themeAnimation(Theme.motion.onboardingStep, value: stepID)
        .safeAreaBar(edge: .top) { topBar }
        .safeAreaBar(edge: .bottom) {
            PrimaryButton(title: primaryTitle, status: missing.map { .disabled(hint: $0) } ?? .enabled, action: primary)
                .padding(.horizontal, Theme.spacing.screenGutter)
                .padding(.bottom, Theme.spacing.s)
        }
    }

    /// Content slides 24 pt in from the side it travels from and fades; Reduce Motion fades only.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .offset(x: forward ? 24 : -24).combined(with: .opacity), removal: .opacity)
    }

    private var topBar: some View {
        HStack {
            GlassButton(systemImage: "chevron.left", label: "Back", action: back)
            Spacer()
            if let skipTitle {
                Button(action: skip) {
                    Text(skipTitle)
                        .themeText(.body)
                        .foregroundStyle(Theme.color.ink)
                        .padding(.horizontal, Theme.spacing.xs)
                        .frame(minHeight: Theme.size.minTap - 12)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(skipTitle == "Skip" ? "Skip this step" : "Set up the store later")
            }
        }
        .overlay { SectionDots(section: section) }
        .padding(.horizontal, Theme.spacing.l)
        .padding(.top, Theme.spacing.xs)
    }
}

/// LabelSage's line as the screen title: `type.mascotTitle`, 27 pt over 34 characters, 24 over 58
/// (tokens.json note), read first by VoiceOver.
struct OnboardingTitle: View {
    let line: String

    var body: some View {
        Text(line)
            .themeText(Self.style(for: line))
            .foregroundStyle(Theme.color.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.spacing.s)
            .accessibilityAddTraits(.isHeader)
            .accessibilitySortPriority(1)
    }

    static func style(for line: String) -> Theme.TypeStyle {
        line.count > 58 ? .mascotTitleSmall : line.count > 34 ? .mascotTitleMedium : .mascotTitle
    }
}

/// Three dots, one per section; the current one is ink (color crossfade 200 ms).
// Custom: TabView page dots track pages, not sections (native-components.md).
struct SectionDots: View {
    let section: Int
    private static let names = ["who you shop for", "their allergies", "your store"]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == section ? Theme.color.ink : Theme.color.ink.opacity(0.12))
                    .frame(width: 11, height: 11)
            }
        }
        .animation(Theme.motion.progressDotCrossfade, value: section)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Part \(section + 1) of 3: \(Self.names[min(max(section, 0), 2)])")
    }
}

/// A small muted line under the answers, with a leading symbol (13 pt).
struct OnboardingFootnote: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
        .themeText(.footnote)
        .foregroundStyle(Theme.color.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.spacing.xxs)
    }
}

nonisolated extension Theme.TypeStyle {
    /// `mascotTitle` for lines over 34 characters (tokens.json note: 27).
    static let mascotTitleMedium = Theme.TypeStyle(
        size: 27, weight: .heavy, trackingEm: -0.02, lineHeightMultiplier: 1.16, relativeTo: .largeTitle
    )
    /// `mascotTitle` for lines over 58 characters (tokens.json note: 24).
    static let mascotTitleSmall = Theme.TypeStyle(
        size: 24, weight: .heavy, trackingEm: -0.02, lineHeightMultiplier: 1.16, relativeTo: .largeTitle
    )
    /// Field labels and list headers on onboarding steps: prototype 18/700.
    static let onboardingLabel = Theme.TypeStyle(size: 18, weight: .bold, relativeTo: .headline)
    /// The name field: prototype 20/400.
    static let onboardingField = Theme.TypeStyle(size: 20, weight: .regular, relativeTo: .title3)
}

#Preview("Scaffold") {
    OnboardingScaffold(stepID: "x", section: 1, pose: .point, line: "What should I check for?",
                       tint: Theme.screenTint.goal, skipTitle: "Skip", primaryTitle: "Continue",
                       missing: "Pick at least one", back: {}, primary: {}) {
        OptionCard(iconKey: "notfor", title: "Allergies and ingredients", mode: .multi, isOn: false) {}
    }
}
