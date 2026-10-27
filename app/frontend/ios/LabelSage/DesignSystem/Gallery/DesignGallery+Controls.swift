import SwiftUI

#if DEBUG

/// T3 controls: buttons, checkboxes, option cards and tiles, group cards, chips, badges.
extension DesignGallery {
    @ViewBuilder var controlsSections: some View {
        GallerySection("PrimaryButton") {
            GalleryState("enabled") { PrimaryButton(title: "Continue") {} }
            GalleryState("disabled, hint: Pick at least one") {
                PrimaryButton(title: "Continue", status: .disabled(hint: "Pick at least one")) {}
            }
            GalleryState("loading") { PrimaryButton(title: "Continue", status: .loading) {} }
            GalleryState("symbol, no chevron") {
                PrimaryButton(title: "Check a product", systemImage: "barcode.viewfinder", showsChevron: false) {}
            }
        }

        GallerySection("GlassButton") {
            GalleryState("back, favorite, close, new chat") {
                GlassEffectContainer(spacing: Theme.spacing.m) {
                    HStack(spacing: Theme.spacing.m) {
                        GlassButton(systemImage: "chevron.left", label: "Back") {}
                        GlassButton(systemImage: "heart", label: "Add to go-tos") {}
                        GlassButton(systemImage: "xmark", label: "Close") {}
                        GlassButton(systemImage: "square.and.pencil", label: "New chat") {}
                    }
                }
            }
        }

        GallerySection("Checkbox") {
            GalleryState("square, circle, leaf; off then on") {
                HStack(spacing: Theme.spacing.l) {
                    Checkbox(isOn: false, style: .square)
                    Checkbox(isOn: false, style: .circle)
                    Checkbox(isOn: false, style: .leaf)
                    Checkbox(isOn: true, style: .square)
                    Checkbox(isOn: true, style: .circle)
                    Checkbox(isOn: true, style: .leaf)
                }
            }
        }

        GallerySection("OptionCard") {
            GalleryState("multi: on, off (tap to toggle)") {
                OptionCard(iconKey: "notfor", title: "Allergies and ingredients",
                           detail: "Allergies, diets and anything you avoid", mode: .multi,
                           isOn: goals.contains("avoid")) { goals = goals.symmetricDifference(["avoid"]) }
                OptionCard(iconKey: "macros", title: "Macros and calories",
                           detail: "Protein and calories for a goal", mode: .multi,
                           isOn: goals.contains("numbers")) { goals = goals.symmetricDifference(["numbers"]) }
            }
            GalleryState("single: off, on (tap to pick)") {
                OptionCard(iconKey: "me", title: "Just me", detail: "Just my allergies and diets",
                           mode: .single, isOn: household == "me") { household = "me" }
                OptionCard(iconKey: "family", title: "My family", detail: "Everyone at home, one at a time",
                           mode: .single, isOn: household == "family") { household = "family" }
            }
        }

        GallerySection("OptionTile") {
            GalleryState("off, on (tap to toggle)") {
                tileGrid
            }
        }

        GallerySection("GroupCard") {
            GalleryState("closed, nothing picked") {
                GroupCard(iconKey: "peanut", title: "Peanuts and lupin", leaves: ["Peanut", "Lupin"],
                          selection: $peanutPicks, isOpen: $peanutOpen)
            }
            GalleryState("closed, 2 picked") {
                GroupCard(iconKey: "shellfish", title: "Shellfish", leaves: Self.shellfishLeaves,
                          selection: $fishPicks, isOpen: $fishOpen)
            }
            GalleryState("open (tap the header to close)") {
                GroupCard(iconKey: "treenuts", title: "Tree nuts", leaves: Self.treeNutLeaves,
                          selection: $treeNuts, isOpen: $treeNutsOpen)
            }
        }

        GallerySection("LeafTile") {
            GalleryState("off, on (second one toggles)") {
                HStack(spacing: Theme.spacing.m) {
                    LeafTile(title: "Almond", isOn: false) {}
                    LeafTile(title: "Walnut", isOn: leafOn) { leafOn.toggle() }
                }
            }
        }

        GallerySection("Chip") {
            GalleryState("avoid, preferNot, dietGoal") {
                HStack(spacing: Theme.spacing.s) {
                    Chip(kind: .avoid, iconKey: "peanut", text: "Peanut")
                    Chip(kind: .preferNot, iconKey: "sugar", text: "Added sugars")
                }
                Chip(kind: .dietGoal, iconKey: "vegetarian", text: "Vegetarian")
            }
            GalleryState("long text truncates") {
                Chip(kind: .avoid, iconKey: "seed", text: "Seed oils, sunflower, canola, rapeseed and cottonseed")
            }
        }

        GallerySection("KindBadge") {
            GalleryState("Avoid, Prefer not (tap to flip), Diet, Goal") {
                HStack(spacing: Theme.spacing.s) {
                    KindBadge(ruleName: "Seed oils", kind: $seedOils)
                    KindBadge(ruleName: "Added sugars", kind: $sugar)
                }
                HStack(spacing: Theme.spacing.s) {
                    KindBadge(ruleName: "Vegetarian", kind: .constant(.diet))
                    KindBadge(ruleName: "Protein", kind: .constant(.goal))
                }
            }
        }

        GallerySection("SectionHeader") {
            GalleryState("sectionTitle 22/700") {
                SectionHeader("For you")
            }
        }

        GallerySection("PressableStyle") {
            GalleryState("press and hold: scale 0.98, no color change") {
                Button {} label: {
                    Text("Press me")
                        .themeText(.cardTitle)
                        .foregroundStyle(Theme.color.ink)
                        .frame(maxWidth: .infinity, minHeight: Theme.size.optionCardMinHeight)
                        .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    /// Two columns of `OptionTile`s; one column at accessibility text sizes (00-foundations
    /// "Tiles become full-width cards").
    var tileGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.spacing.m),
                            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
        let tiles: [(key: String, title: String, detail: String)] = [
            ("vegan", "Vegan", "No meat, fish, dairy, eggs, honey"),
            ("vegetarian", "Vegetarian", "No meat or fish"),
        ]
        return LazyVGrid(columns: columns, spacing: Theme.spacing.m) {
            ForEach(tiles, id: \.key) { tile in
                OptionTile(iconKey: tile.key, title: tile.title, detail: tile.detail,
                           isOn: diets.contains(tile.key)) { diets = diets.symmetricDifference([tile.key]) }
            }
        }
    }
}
#endif
