import SwiftUI

#if DEBUG

/// T5 mascot: the 13 states at 74 (board 80) and the sizes in use.
extension DesignGallery {
    @ViewBuilder var mascotSections: some View {
        GallerySection("Mascot") {
            GalleryState("13 states at 74 (reading shows 2 found lines)") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.spacing.s), count: 4),
                          spacing: Theme.spacing.m) {
                    ForEach(MascotState.allCases, id: \.self) { state in
                        VStack(spacing: Theme.spacing.xs) {
                            MascotView(state: state, size: 74, found: state == .reading ? 2 : 0)
                            Text(state.rawValue)
                                .themeText(.footnote)
                                .foregroundStyle(Theme.color.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing.s)
                        .background(state == .guard ? Theme.verdict.notFor.wash : Theme.color.surface,
                                    in: .rect(cornerRadius: Theme.radius.tile, style: .continuous))
                    }
                }
            }
            GalleryState("sizes 64 (dock), 56 (Family), 40 (camera), 30 (headings)") {
                HStack(alignment: .bottom, spacing: Theme.spacing.l) {
                    ForEach([64.0, 56, 40, 30], id: \.self) { size in
                        MascotView(state: .idle, size: size)
                    }
                }
            }
        }
    }
}

#endif
