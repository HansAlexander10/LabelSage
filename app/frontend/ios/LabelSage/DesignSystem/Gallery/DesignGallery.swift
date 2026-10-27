import SwiftUI
import LabelSageCore

#if DEBUG

/// Every design-system component in every state on one scrolling page, for visual checks against
/// the boards. Shown instead of the app when launched with `-gallery` (see `LabelSageApp`).
/// The interactive samples keep their own state, so taps, haptics and animations can be tried.
/// Sections live in one extension file per build task: `DesignGallery+Controls.swift` (T3),
/// `DesignGallery+Verdict.swift` (T4), `DesignGallery+Mascot.swift` (T5). State stays here, internal so those files can bind to it.
struct DesignGallery: View {
    @State var goals: Set<String> = ["avoid"]
    @State var household = "family"
    @State var diets: Set<String> = ["vegetarian"]
    @State var treeNuts: Set<String> = ["Cashew"]
    @State var treeNutsOpen = true
    @State var peanutPicks: Set<String> = []
    @State var peanutOpen = false
    @State var fishPicks: Set<String> = ["Shrimp", "Crab"]
    @State var fishOpen = false
    @State var leafOn = true
    @State var seedOils = KindBadge.Kind.avoid
    @State var sugar = KindBadge.Kind.preferNot
    @State var bannerSummarized = false
    @State var flagReplay = 0
    @State var toastMessage: ToastMessage?
    @State var scanMode = "barcode"
    @State var alexItems = PersonCardSamples.alex
    @State var miaItems = PersonCardSamples.mia
    @State var alexOpen = false
    @State var miaOpen = true
    /// `-gallerySection <name>` opens the gallery scrolled to that section, for screenshots.
    @State var position = ScrollPosition(idType: String.self)

    static let treeNutLeaves = ["Almond", "Cashew", "Walnut", "Pecan", "Pistachio", "Hazelnut", "Brazil nut", "Macadamia", "Pine nut"]
    static let shellfishLeaves = ["Shrimp", "Crab", "Lobster", "Oyster"]

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.section) {
                Text("\(Brand.app) components")
                    .themeText(.screenTitle)
                    .foregroundStyle(Theme.color.ink)

                controlsSections
                verdictSections
                productSections
                messageSections
                mascotSections
            }
            .padding(.horizontal, Theme.spacing.screenGutter)
            .padding(.vertical, Theme.spacing.xxl)
            .scrollTargetLayout()
        }
        .scrollPosition($position)
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "-gallerySection"), arguments.indices.contains(flag + 1) {
                // `-galleryBottom` lines the section's bottom up with the screen's, to see what is above it.
                position.scrollTo(id: arguments[flag + 1], anchor: arguments.contains("-galleryBottom") ? .bottom : .top)
            }
        }
        .background(Theme.screenTint.allergens)
        .toast($toastMessage)
    }
}

/// One component: its name as a `SectionHeader`, then its states.
struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            SectionHeader(title)
            content
        }
        .id(title)
    }
}

/// One state of a component, with a small caption naming it.
struct GalleryState<Content: View>: View {
    let name: String
    @ViewBuilder let content: Content

    init(_ name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            Text(name)
                .themeText(.footnote)
                .foregroundStyle(Theme.color.muted)
            content
        }
    }
}

#Preview("DesignGallery") {
    DesignGallery()
}
#endif
