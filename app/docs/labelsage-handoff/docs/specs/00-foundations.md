## Handoff Spec: Foundations

### Overview
The shared layer every screen uses: tokens, type, components, motion and accessibility. Values live in `design/tokens.json`; this file explains how to use them. Reference boards: `design/screens/62-states-verdict-flags.png`, `65-components-cards-composer.png`, `64-product-row-stress-test.png`, `81-icon-library.png`.

### Layout
- **iPhone only for the MVP**, portrait. Design width 390 pt (iPhone 16/17). Must work from 375 pt (SE) to 440 pt (Pro Max) without horizontal scroll.
- **Screen gutter** `spacing.screenGutter` (20). Cards go edge to gutter.
- **Safe areas:** the primary button and the chat composer sit above the home indicator; content scrolls under the floating glass controls.
- **One primary (amber) button per screen**, at the bottom. Secondary actions are text buttons or glass circles.
- No iPad or landscape layout in the MVP (iPad runs the iPhone layout).

### Design Tokens Used
| Token | Value | Usage |
|-------|-------|-------|
| `color.ink` | #1d2b22 | All text and icons on light grounds; selected outline |
| `color.muted` | #6b6656 | Captions, meta |
| `color.amber` | #eb9d15 | The single primary button; ink text on it |
| `color.surface` | #ffffff | Cards, tiles |
| `verdict.ok/checkFirst/notFor/cantConfirm` | see tokens | Flags only, never decoration |
| `screenTint.*` | per screen | The background "room" for each kind of screen |
| `radius.card` | 26 | Cards and option cards |
| `radius.tile` | 22 | Tiles and leaf tiles |
| `shadow.card` | two-layer soft | Unselected cards |
| `shadow.selected` | 2 pt ink outline | Selected option card or tile |
| `type.mascotTitle` | Outfit 30/800, -0.02em | LabelSage's line as the onboarding title (27 or 24 for long lines) |
| `type.body` | Outfit 17/400 | Body |
| `type.primaryButton` | Outfit 20/600 | Primary button label |

All Outfit styles use `Font.custom("Outfit", size:, relativeTo:)` so they scale with Dynamic Type. Numbers (prices, grams) use tabular figures.

### Components
| Component | Variant | Props | Notes |
|-----------|---------|-------|-------|
| `PrimaryButton` | enabled, disabled, loading | title, systemImage?, action | Height 66, capsule, amber with ink label and amber glow. Disabled: #efe6d3 with #a89f8a label, still focusable, announces "dimmed". Optional trailing chevron. |
| `OptionCard` | single, multi; on, off | icon key, title, detail?, isOn | Min height 80, white, radius 26. Multi: 30 pt rounded-square checkbox (radius 9). Single: 30 pt circle. Selected: 2 pt ink outline replaces the shadow. Whole card is the tap target. |
| `OptionTile` | on, off | icon key, title, detail? | 2-column grid tile, min height 158, icon 64, checkbox top-right. For short choices (diet, religion, medical). |
| `GroupCard` | closed, open | icon, title, count "2/9" | Allergen group that opens in place into a 2-column grid of `LeafTile`s; first leaf "All tree nuts" spans both columns. Count pill turns ink when any leaf is on. |
| `LeafTile` | on, off | title | Min height 64, radius 22, 26 pt checkbox. |
| `Chip` | avoid, preferNot, dietGoal | icon key, text | Height 36, capsule, 22 pt icon. Tinted by kind. |
| `KindBadge` | Avoid, Prefer not, Diet, Goal | tap to flip | On summary and Family cards; tapping flips Avoid and Prefer not (D12). |
| `VerdictFlag` | ok, checkFirst, notFor, cantConfirm; small (36), medium (48), large (60) | level | White circle, 3 pt ring in the verdict color, SF Symbol inside. Never color alone. |
| `VerdictBanner` | 4 levels | level, title ("Not for you"), reason | Wash background of the level, symbol, title, reason, then "Check the package. Not medical advice." |
| `PersonLine` | | `HouseholdVerdict.line` | "Not for Mia · OK for you" in the product card and sheet header. |
| `ProductRow` | row, card (204 wide), compact | product, verdict, price?, action | Image 48 (row) or 120 (card) with pack fallback (brand initial on a pack-shaped tile) when the photo is missing or fails. Name 2 lines max, then truncate. |
| `IconView` | auto, loading, missing, failed | key, size | See `docs/icons.md`. Never shows an error. |
| `Bubble` | mascot, user | text | LabelSage's speech bubble: white, radius 22, tail toward him, max 20 words. Real text, read first by VoiceOver. |
| `Toast` | info, with action | text, action title ("Undo", "View") | Bottom, above the toolbar, 4 s, dark (#232323) with white text. |
| `GlassButton` | circle 44 | systemImage, label | Back, favorite, close, new chat. Liquid Glass. |
| `SegmentedPicker` | 2 options | Barcode / Ingredients; per serving / per 100 g | System segmented style on glass over the camera. |

### States and Interactions
| Element | State | Behavior |
|---------|-------|----------|
| Any card or tile | Pressed | Scale 0.98, 120 ms ease-out; release springs back. No color change. |
| `OptionCard` | Selected | 2 pt ink outline, checkbox fills ink with a white check; light haptic (`.selection`). |
| `PrimaryButton` | Disabled | No action; VoiceOver hint says what is missing ("Pick at least one"). |
| `PrimaryButton` | Loading | Label stays, a small spinner replaces the chevron; not tappable. |
| `VerdictFlag` | Appears | One gentle pulse of the ring (2 × 1 s) on first show; none with Reduce Motion. Not for: `.warning` haptic once. |
| `KindBadge` | Tap | Flips Avoid ↔ Prefer not; VoiceOver: "Seed oils: always avoided. Double-tap to only show it lower." |
| `Toast` | Action | Runs the action and dismisses; swipe down dismisses. |

### Responsive Behavior
| Breakpoint | Changes |
|------------|---------|
| 440 pt wide | Cards keep the 20 pt gutter; tiles grow; nothing else changes |
| 375 pt wide | Tiles keep 2 columns; mascot title drops one size step when over 2 lines |
| Dynamic Type AX1 to AX5 | Tiles become full-width cards; chips wrap; the toolbar becomes two rows; the mascot shrinks to 56 and the title wraps freely |

### Edge Cases
- **Long names** (person, product, store): one line with tail truncation in chips and rows; full text in VoiceOver.
- **Missing photos:** pack fallback with brand initial (`ProductRow`), letter tile (`IconView`).
- **No verdict yet:** show the product with "Checking the ingredients…" and the reading mascot; never an empty flag.

### Animation / Motion
| Element | Trigger | Animation | Duration | Easing |
|---------|---------|-----------|----------|--------|
| Card press | Touch down | scale 0.98 | 120 ms | `easeOut` (0.23, 1, 0.32, 1) |
| Onboarding step | Continue / Back | content slides 24 pt and fades; mascot stays put and changes pose | 280 ms | `easeOut` |
| Progress dots | Section change | dot color crossfade | 200 ms | ease |
| Group card | Open | leaves fade in with 30 ms stagger; card height animates | 240 ms | `easeOut` |
| Reason line | Model summary ready | opacity crossfade | 200 ms | ease |
| Sheet | Open product | native sheet, medium then large detent | system | system |
| Mascot | Pose change | crossfade 150 ms between poses; loops per `mascot.md` | per state | per state |

Reduce Motion: no slides (fades only), mascot holds the pose, no pulse.

### Accessibility Notes
- **Contrast:** ink on every tint passes 12:1; muted (#6b6656) on white is 5.5:1; ink on amber 7:1. Never white text on amber or on a verdict color.
- **Touch targets** 44 × 44 minimum, including the checkbox area (the whole card is the target).
- **VoiceOver:** cards are one element: "Milk, whey, casein, butter. Selected. Checkbox." The flag reads as "Verdict: Not for Mia". The mascot is decorative (`accessibilityHidden`); his bubble text is the screen's first element.
- **Focus order:** mascot line, then the question's options top to bottom, then the primary button, then Back and Skip.
- **Dynamic Type** to AX5 without clipping; test every screen at AX3.
- **Color is never alone:** verdicts always carry a symbol and, where there's room, the word.
