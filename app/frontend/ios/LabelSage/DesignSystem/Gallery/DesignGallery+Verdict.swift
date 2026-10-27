import SwiftUI
import LabelSageCore

#if DEBUG

/// T4 verdict, product and message components, with the product row stress cases (spec 07).
extension DesignGallery {
    @ViewBuilder var verdictSections: some View {
        GallerySection("VerdictFlag") {
            GalleryState("ok, checkFirst, notFor, cantConfirm × small 36, medium 48, large 60") {
                Grid(horizontalSpacing: Theme.spacing.l, verticalSpacing: Theme.spacing.m) {
                    ForEach(VerdictFlag.Size.allCases, id: \.self) { size in
                        GridRow {
                            ForEach([Level.ok, .checkFirst, .notFor, .cantConfirm], id: \.self) { level in
                                VerdictFlag(level: level, names: ["Mia"], size: size)
                            }
                        }
                    }
                }
                .id(flagReplay)
                Button("Show again (pulse, Not for haptic)") { flagReplay += 1 }
                    .themeText(.callout)
            }
        }

        GallerySection("VerdictBanner") {
            GalleryState("4 levels") {
                VerdictBanner(level: .notFor, title: "Not for you",
                              reason: "Sunflower oil is the 2nd ingredient, so it\u{2019}s not for you. Watch 4 g added sugar per serving.")
                VerdictBanner(level: .checkFirst, title: "Check first", reason: "Cane sugar is the 3rd ingredient.")
                VerdictBanner(level: .ok, title: "OK for you and Mia", reason: "Nothing you or Mia avoid is in these ingredients.")
                VerdictBanner(level: .cantConfirm, title: "Can\u{2019}t confirm",
                              reason: "\u{2018}Natural flavors\u{2019} isn\u{2019}t specific.")
            }
            GalleryState("reason crossfade (tap to swap)") {
                VerdictBanner(level: .notFor, title: "Not for you \u{00B7} OK for Mia",
                              reason: bannerSummarized
                                ? "Sunflower oil is a seed oil you avoid. Mia\u{2019}s peanut and tree nuts are not in it."
                                : "Sunflower oil is the 2nd ingredient, so it\u{2019}s not for you.")
                    .onTapGesture { bannerSummarized.toggle() }
            }
        }

        GallerySection("PersonLine") {
            GalleryState("one segment per person, worst first") {
                PersonLine(level: .notFor, line: "Not for Mia \u{00B7} OK for you")
                PersonLine(level: .checkFirst, line: "Check first for you \u{00B7} OK for Mia")
                PersonLine(level: .ok, line: "OK for everyone")
                PersonLine(level: .cantConfirm, line: "Can\u{2019}t confirm")
            }
        }
    }

    @ViewBuilder var productSections: some View {
        GallerySection("ProductRow") {
            GalleryState("row: demo data") {
                ProductRow(product: ProductRowSamples.yogurt, level: .ok,
                           notes: [.init(level: .ok, text: "17 g protein"), .init(level: .ok, text: "2 ingredients")]) {}
                ProductRow(product: ProductRowSamples.chips, level: .notFor,
                           notes: [.init(level: .notFor, text: "Sunflower oil"), .init(level: .checkFirst, text: "Cane sugar")]) {}
                ProductRow(product: ProductRowSamples.oatBar, level: .checkFirst,
                           notes: [.init(level: .checkFirst, text: "Cane syrup"), .init(level: .ok, text: "No seed oils")]) {}
            }
            GalleryState("row: worst case (long name, over $999, no price, no brand, one letter, non-Latin, failed photo)") {
                ProductRow(product: ProductRowSamples.longName, level: .checkFirst,
                           notes: [.init(level: .checkFirst, text: "Contains added cane sugar and natural flavors"),
                                   .init(level: .ok, text: "No seed oils")]) {}
                ProductRow(product: ProductRowSamples.unbreakable, level: .cantConfirm,
                           notes: [.init(level: .cantConfirm, text: "No ingredient list in our data")]) {}
                ProductRow(product: ProductRowSamples.oneLetter, level: .ok) {}
                ProductRow(product: ProductRowSamples.nonLatin, level: .notFor, names: ["Mia", "Leo"],
                           notes: [.init(level: .notFor, text: "Milk \u{00B7} Mia and Leo are allergic")]) {}
                ProductRow(product: ProductRowSamples.failedPhoto, level: .notFor) {}
            }
            GalleryState("compact: worst case") {
                ProductRow(product: ProductRowSamples.longName, level: .checkFirst, style: .compact) {}
                ProductRow(product: ProductRowSamples.make(name: "Creamy Peanut Butter, 16 oz"), level: .notFor,
                           notes: [.init(level: .notFor, text: "Peanut, tree nuts and sesame \u{00B7} Mia, Leo and Sam are allergic")],
                           style: .compact) {}
                ProductRow(product: ProductRowSamples.make(name: "Q"), level: .cantConfirm, style: .compact) {}
            }
            GalleryState("card 204: options scroller") {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Theme.spacing.m) {
                        ProductRow(product: ProductRowSamples.kettle, level: .ok, names: ["you", "Mia"],
                                   notes: [.init(level: .ok, text: "OK for you and Mia")], style: .card) {}
                        ProductRow(product: ProductRowSamples.chips, level: .notFor,
                                   notes: [.init(level: .notFor, text: "Sunflower oil")], style: .card) {}
                        ProductRow(product: ProductRowSamples.unbreakable, level: .cantConfirm, style: .card) {}
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, Theme.spacing.m)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
            GalleryState("zero items") {
                ContentUnavailableView {
                    Label {
                        Text("Nothing here fits Mia yet. Want me to check something else?")
                            .themeText(.bodyStrong)
                    } icon: {
                        MascotView(state: .thinking, size: 74)
                    }
                } actions: {
                    PrimaryButton(title: "Check a product", systemImage: "barcode.viewfinder", showsChevron: false) {}
                }
                .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.tile, style: .continuous))
            }
        }
    }

    @ViewBuilder var messageSections: some View {
        GallerySection("Bubble") {
            GalleryState("mascot") {
                Bubble(speaker: .mascot, text: "Check a product, or ask me about one.")
                Bubble(speaker: .mascot,
                       text: "Tip: ask me anything, like \u{201C}is this OK for Mia?\u{201D} I answer with a flag and the reason.")
            }
            GalleryState("user") {
                Bubble(speaker: .user, text: "Is this OK for Mia?")
            }
        }

        GallerySection("Toast") {
            GalleryState("info, with action") {
                Toast(message: ToastMessage(text: "Saved to go-tos")) {}
                Toast(message: ToastMessage(text: "Removed from go-tos", actionTitle: "Undo")) {}
            }
            GalleryState("live: 4 s, swipe down to dismiss") {
                Button("Show a toast") {
                    toastMessage = ToastMessage(text: "Saved to go-tos", actionTitle: "View")
                }
                .themeText(.callout)
            }
        }

        GallerySection("PersonCard") {
            GalleryState("closed (tap Edit), open (tap Done), empty") {
                PersonCard(name: "Alex", isOwner: true, index: 0, items: $alexItems, isOpen: $alexOpen)
                PersonCard(name: "Mia", index: 1, items: $miaItems, isOpen: $miaOpen)
                PersonCard(name: "Sam", index: 2, items: .constant([]), isOpen: .constant(false))
            }
        }

        GallerySection("SegmentedPicker") {
            GalleryState("2 options on clear glass over the camera") {
                SegmentedPicker(label: "Mode",
                                options: [("barcode", "Barcode"), ("ingredients", "Ingredients")],
                                selection: $scanMode)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing.xxl)
                    .background(Theme.screenTint.scan, in: .rect(cornerRadius: Theme.radius.tile, style: .continuous))
            }
        }
    }
}
#endif
