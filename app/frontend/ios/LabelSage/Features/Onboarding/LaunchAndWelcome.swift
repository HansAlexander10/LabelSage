import SwiftUI

/// The splash after the system launch screen (spec 01 › Launch, board `00-launch.png`): the brand
/// mesh, LabelSage waving on a tilted glassy tile, the wordmark, one promise and the subline.
/// Any tap or 1.5 s moves on.
struct LaunchView: View {
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            // Mesh from Splash.dc.html, on token colors: no raw hex in views (open-questions Q-T7-1).
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                Theme.color.brandGreen, Theme.color.brandGreenDeep, Theme.color.ink,
                Theme.color.brandGreenDeep, Theme.color.ink, Theme.color.amber.mix(with: Theme.color.ink, by: 0.55),
                Theme.color.brandGreenDeep.mix(with: Theme.color.ink, by: 0.4), Theme.color.ink, Theme.color.ink,
            ])
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 72, style: .continuous)
                        .fill(Theme.color.surface.opacity(0.10))
                        .frame(width: 220, height: 240)
                        .rotationEffect(.degrees(-6))
                    MascotView(state: .wave, size: 200)
                }
                .frame(height: 262)
                Text(Brand.app)
                    .font(.custom("Outfit", size: 54, relativeTo: .largeTitle).weight(.heavy))
                    .tracking(-1.6)
                    .padding(.top, 18)
                Text("Check the ingredients for everyone you shop for.")
                    .themeText(.welcomeLine)
                    .foregroundStyle(Theme.color.surface.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 32)
                Spacer()
                Text("Built for food allergies, celiac and dairy-free households")
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.surface.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacing.xl)
                    .padding(.bottom, Theme.spacing.xl)
            }
            .foregroundStyle(Theme.color.surface)
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
        }
        .contentShape(.rect)
        .onTapGesture(perform: onDone)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Continues to the welcome")
        .task {
            withAnimation(Theme.motion.easeOut(duration: 0.7)) { shown = true }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { onDone() }
        }
    }
}

/// Welcome, step 1 (board `onboarding/01-welcome.png`): two trust pills, the tilted collage with
/// LabelSage and two floating cards, the wordmark, his line, the legal line and "Get started".
struct WelcomeView: View {
    let onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: Theme.spacing.s) {
                    trustPill(icon: "private", text: "Stays on your iPhone")
                    trustPill(icon: "family", text: "Whole family")
                }
                .padding(.top, Theme.spacing.s)
                collage
                    .padding(.top, 14)
                Text(Brand.app)
                    .font(.custom("Outfit", size: 52, relativeTo: .largeTitle).weight(.heavy))
                    .tracking(-1.56)
                    .foregroundStyle(Theme.color.ink)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
                Text("I check the ingredients for everyone you shop for. Hidden names too.")
                    .themeText(.welcomeLine)
                    .foregroundStyle(Theme.color.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
                    .padding(.top, 14)
                // shortcut: no Terms or Privacy URLs exist yet (open-questions Q-T7-2); the words are
                // underlined like links but not tappable.
                Text("By continuing you agree to the\n\(Text("Terms of Use").underline()) and \(Text("Privacy Policy").underline())")
                    .themeText(.caption)
                    .foregroundStyle(Theme.color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.spacing.l)
            }
            .padding(.horizontal, Theme.spacing.screenGutter)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.screenTint.welcome.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            PrimaryButton(title: "Get started", showsChevron: false, action: onStart)
                .padding(.horizontal, Theme.spacing.screenGutter)
                .padding(.bottom, Theme.spacing.s)
        }
        .onAppear {
            withAnimation(Theme.motion.easeOut(duration: 0.4)) { settled = true }
        }
    }

    private func trustPill(icon: String, text: String) -> some View {
        HStack(spacing: Theme.spacing.xs) {
            IconView(key: icon, size: 22, decorative: true)
            Text(text).themeText(.caption).fontWeight(.medium)
        }
        .foregroundStyle(Theme.color.inkSecondary)
        .frame(minHeight: 34)
        .padding(.horizontal, Theme.spacing.xs)
    }

    /// Prototype geometry: a 350 × 392 box, a green and an amber tile behind LabelSage, two
    /// frosted cards that float in with a 60 ms stagger and settle their rotation.
    private var collage: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 64, style: .continuous)
                .fill(Theme.screenTint.avatarTints[1])
                .frame(width: 230, height: 230)
                .rotationEffect(.degrees(-8))
                .offset(x: 70, y: 30)
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .fill(Theme.screenTint.avatarTints[0])
                .frame(width: 170, height: 170)
                .rotationEffect(.degrees(10))
                .offset(x: 150, y: 196)
            MascotView(state: .wave, size: 200)
                .offset(x: 92, y: 46)
            floatingCard(icon: "check", text: "Checks every\ningredient", angle: -12, index: 0)
                .offset(y: 70)
            floatingCard(icon: "options", text: "For everyone you\nshop for", angle: 9, index: 1)
                .frame(width: 350, alignment: .trailing)
                .offset(y: 268)
        }
        .frame(width: 350, height: 392, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checks every ingredient, for everyone you shop for.")
    }

    private func floatingCard(icon: String, text: String, angle: Double, index: Int) -> some View {
        let still = settled || reduceMotion
        return HStack(spacing: 10) {
            IconView(key: icon, size: 40, decorative: true)
            Text(text)
                .font(.custom("Outfit", size: 18, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Theme.color.ink)
                .fixedSize()
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 18))
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.color.surface.opacity(0.55)))
        .rotationEffect(.degrees(still ? angle : angle * 1.6))
        .opacity(still ? 1 : 0)
        .offset(y: still ? 0 : 10)
        .animation(Theme.motion.easeOut(duration: 0.4).delay(0.06 * Double(index)), value: settled)
    }
}

nonisolated extension Theme.TypeStyle {
    /// The promise under the wordmark on Launch and Welcome: prototype 20/400, line height 1.35.
    static let welcomeLine = Theme.TypeStyle(size: 20, weight: .regular, lineHeightMultiplier: 1.35, relativeTo: .title3)
}

#Preview("Launch") {
    LaunchView {}
}

#Preview("Welcome") {
    WelcomeView {}
}
