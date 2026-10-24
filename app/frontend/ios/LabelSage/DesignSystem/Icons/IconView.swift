import SwiftUI
import UIKit

/// Resolves `key` (or an alias, case-insensitively, trimmed) through `IconCatalog` to a Fluent
/// Emoji 3D icon in `LabelSageIcons.xcassets`, at `size` points square. See
/// `app/docs/labelsage-handoff/docs/icons.md`.
///
/// States (icons.md): `loaded` shows the 3D icon; `missing` (unknown key) and `failed` (the
/// resolved asset is not in the bundle) both show the same sand letter tile, never an error;
/// `loading` is a sand tile with a slow shimmer, shown only as a preview state, since the MVP
/// never fetches an icon remotely.
struct IconView: View {
    /// `IconView`'s four display states (icons.md).
    enum LoadState: Equatable {
        case loaded(assetName: String)
        case missing
        case failed
        case loading
    }

    let key: String
    let size: CGFloat
    /// `true` hides the icon from VoiceOver, for an icon that sits next to a text label which
    /// already announces it. `false` (default) makes the icon itself read `label` below.
    let decorative: Bool

    /// Preview-only override: shows this state directly instead of `resolved`. Used for
    /// `.loading` (unreachable in the MVP, no remote icons) and to show `.failed` without needing
    /// a deliberately broken catalog entry.
    private let stateOverride: LoadState?
    /// The catalog lookup and `UIImage(named:)` check, done once in `init` so `body` never
    /// re-queries `IconCatalog` or the bundle.
    private let resolved: LoadState
    /// VoiceOver label: the catalog's label when `key` resolves, otherwise `key` itself trimmed.
    private let label: String
    /// `true` when `decorative` was set, or when the trimmed `key` is empty: there is nothing
    /// meaningful to announce, so the icon is hidden rather than given an empty label.
    private let isHiddenFromVoiceOver: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(key: String, size: CGFloat, decorative: Bool = false) {
        self.key = key
        self.size = size
        self.decorative = decorative
        self.stateOverride = nil
        let resolution = Self.resolve(key: key)
        self.resolved = resolution.state
        self.label = resolution.label
        self.isHiddenFromVoiceOver = decorative || resolution.trimmedKeyIsEmpty
    }

    fileprivate init(previewState: LoadState, key: String, size: CGFloat, decorative: Bool = false) {
        self.key = key
        self.size = size
        self.decorative = decorative
        self.stateOverride = previewState
        let resolution = Self.resolve(key: key)
        self.resolved = resolution.state
        self.label = resolution.label
        self.isHiddenFromVoiceOver = decorative || resolution.trimmedKeyIsEmpty
    }

    /// Shared `init` work: the one catalog/bundle lookup for `key`, done once.
    private static func resolve(
        key: String
    ) -> (state: LoadState, label: String, trimmedKeyIsEmpty: Bool) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = IconCatalog.entry(for: key)
        let state: LoadState =
            if let entry {
                UIImage(named: entry.asset) != nil ? .loaded(assetName: entry.asset) : .failed
            } else {
                .missing
            }
        return (state, entry?.label ?? trimmedKey, trimmedKey.isEmpty)
    }

    /// Exposed (not `private`) so tests can check state resolution directly, e.g. an unknown key
    /// gives `.missing`.
    var state: LoadState { stateOverride ?? resolved }

    /// The fallback tile's letter: the label's first character, uppercased.
    private var letter: String {
        String(label.prefix(1)).uppercased()
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(isHiddenFromVoiceOver)
            .accessibilityLabel(isHiddenFromVoiceOver ? "" : label)
            .accessibilityAddTraits(isHiddenFromVoiceOver ? [] : .isImage)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loaded(let assetName):
            Image(assetName)
                .resizable()
                .scaledToFit()
        case .missing, .failed:
            letterTile
        case .loading:
            loadingTile
        }
    }

    private var letterTile: some View {
        RoundedRectangle(cornerRadius: Theme.radius.letterTile(size: size), style: .continuous)
            .fill(Theme.color.letterTile)
            .overlay(
                Text(letter)
                    .font(.custom("Outfit", fixedSize: Theme.radius.letterTileFont(size: size)).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.color.letterTileInk)
            )
    }

    @ViewBuilder
    private var loadingTile: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.radius.letterTile(size: size), style: .continuous)
            .fill(Theme.color.letterTile)
        if reduceMotion {
            tile
        } else {
            tile.phaseAnimator([false, true]) { view, isDim in
                view.opacity(isDim ? 0.55 : 1)
            } animation: { _ in
                Theme.motion.easeInOut(duration: 0.6)
            }
        }
    }
}

#Preview("IconView - loaded") {
    HStack(spacing: Theme.spacing.m) {
        IconView(key: "shrimp", size: Theme.size.iconInChip)
        IconView(key: "PRAWN", size: Theme.size.iconInCard) // alias, uppercase, resolves to shrimp
        IconView(key: "  treenuts  ", size: Theme.size.iconInTile) // trimmed, stand-in asset
    }
    .padding()
    .background(Theme.color.surface)
}

#Preview("IconView - missing") {
    HStack(spacing: Theme.spacing.m) {
        IconView(key: "quinoa", size: Theme.size.iconInChip)
        IconView(key: "quinoa", size: Theme.size.iconInCard)
        IconView(key: "quinoa", size: Theme.size.iconInTile)
    }
    .padding()
    .background(Theme.color.surface)
}

#Preview("IconView - failed") {
    IconView(previewState: .failed, key: "banana", size: Theme.size.iconInTile)
        .padding()
        .background(Theme.color.surface)
}

#Preview("IconView - loading") {
    IconView(previewState: .loading, key: "loading", size: Theme.size.iconInTile)
        .padding()
        .background(Theme.color.surface)
}

#Preview("IconView - decorative (hidden from VoiceOver)") {
    HStack(spacing: Theme.spacing.s) {
        IconView(key: "ok", size: Theme.size.iconInChip, decorative: true)
        Text("OK for Mia").themeText(.chip)
    }
    .padding()
    .background(Theme.color.surface)
}
