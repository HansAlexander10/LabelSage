## Handoff Spec: States, explainers and shared components

### Overview
The cross-screen states and the guiding layer: verdict flags, explainers (welcome sheet, coach marks, inline tips), loading, empty and error states, and the product row stress cases.

Boards: `design/screens/62-states-verdict-flags.png`, `63-explainer-and-coach-marks.png`, `64-product-row-stress-test.png`, `65-components-cards-composer.png`, `61-states-scan-edge-cases.png`. Source: `States.dc.html`, `ExplainerStates.dc.html`, `Explainer.dc.html`, `ProductRow.dc.html`, `ProductRowStress.dc.html`, `Cards.dc.html`.

### Verdict flags
| Level | Symbol | Color / wash | Word | Meaning |
|---|---|---|---|---|
| ok | `checkmark.circle` | #1dbf73 / #e4f7ee | OK for {names} | Nothing they avoid is in these ingredients |
| checkFirst | `exclamationmark.triangle` | #ffd449 / #fff5cc | Check first | Worth a look: a Prefer not item, a "may contain" with the switch off, or a serving over a daily limit |
| notFor | `nosign` | #ef4b3f / #ffe9e6 | Not for {names} | Contains something on their Avoid list |
| cantConfirm | `questionmark.circle.fill` | #6b6656 / #f4f0d8 | Can’t confirm | The label is missing a fact a rule needs. Never styled like OK |

Color and symbol always travel together. Every verdict shows "Check the package. Not medical advice." The household flag is the worst person's level.

### Explainers (LabelSage guides)
One component, three forms; same bubble, voice and buttons:
1. **Welcome sheet** (first run, step 1 of 3, over the chat): LabelSage waving, "Hi, I’m LabelSage" / "I read the ingredients so you don’t have to, for everyone you shop for.", Skip and **Show me how**.
2. **Coach mark** (spotlight on one element, steps 2 and 3): on the camera frame "Point at the barcode" / "Hold steady. I check the ingredients, Mia’s allergies first." (Skip, Next); on the photo signal "One flag, one reason" / "This symbol is the verdict. Tap it and I show what I found, and who it’s not for." (Got it).
3. **Inline tip** said from the dock: "Tip: ask me anything, like “is this OK for Mia?” I answer with a flag and the reason." (Got it).

Rules (from the board): a 3-step tour on first run; one tip the first time each screen opens, shown once; new features; empty states. One idea per message, title up to 5 words, text under 20. Next or Got it is primary; Skip ends the whole tour. Tips never cover a flag or block a decision, and never appear on an allergy result (he stands guard there). Announced as a dialog, focus starts on the message. "Show tips again" lives in Family > Settings.

### Loading
- **While the agent works:** LabelSage `reading` in the thread with "Checking the ingredients…" and the people it checks for ("For you and Mia"). No spinners, no skeletons.
- **Product page:** content renders with the deterministic reason at once; the model summary crossfades in later (D8).
- **Icons:** see `docs/icons.md` (shimmer tile for at most 600 ms).

### Product row stress cases (`64-…`)
| Case | Rule |
|---|---|
| Very long name | 2 lines, tail truncation; card 2 lines |
| Unbreakable brand ("SuperLongBrandNameWithoutSpaces") | character wrap, then truncate |
| No price | price hidden, layout keeps its height |
| No photo or failed photo | pack-shaped tile with the brand initial |
| No brand | initial from the product name |
| Zero items | empty state with LabelSage and one action |
| Price over $999 | formatted, tabular, never wraps |

### Empty and error states
| Where | Copy | Pose | Action |
|---|---|---|---|
| Not found | "This one’s new to me. Photo the ingredients and I’ll read them." | disguise | Photo the ingredients |
| No ingredients yet | "No ingredient list for this one yet. Check the package, or photo the ingredients and I’ll read them." | thinking | Photo the ingredients |
| Camera off | "Allow the camera to check products" / "The barcode is read on your iPhone. No photos are saved or sent." | listen | Open Settings |
| Offline | "You’re offline" / "Products you checked before still work. A new product needs a connection." | thinking | Try again |
| No options | "Nothing here fits Mia yet. Want me to check something else?" | thinking | Check a product |
| No go-tos | "No go-tos yet. Save a product you buy often and I’ll check it again every time." | idle | none |
| Model unavailable | (silent) deterministic lines | | |

### Accessibility Notes
- Explainers: VoiceOver focus moves to the bubble; the spotlighted element is described ("Highlighted: Open the camera").
- Coach marks never trap focus; Skip is always reachable.

### Decisions made in build
(The coding agent lists here anything the spec didn't cover.)
- T3 controls (`DesignSystem/Components/`): the selected outline sits fully outside the card edge (prototype `box-shadow: 0 0 0 2px`), so selecting never shifts content.
- `PressableStyle` does not scale with Reduce Motion on (prototype `prefers-reduced-motion: transform: none`); release uses a short system spring (0.3 s), since tokens.json has no release curve.
- Cards and tiles read as one VoiceOver button with the Selected trait ("Allergies and ingredients, Allergies, diets and anything you avoid. Selected. Button."), not "Checkbox": SwiftUI has no checkbox trait.
- `GroupCard` header reads "Tree nuts, 2 of 9 selected, expanded"; the count pill turns ink and the header gets the ink outline when any leaf is on (prototype `cardS(n > 0)`). The first leaf "All tree nuts" picks every leaf, or clears them when all are on. At accessibility text sizes the leaf grid is one column.
- `LeafTile` names stay on one line and shrink to 75% in the 2-column grid ("Macadamia"), so a single word never breaks; at accessibility sizes they wrap.
- `Chip` adds its kind for VoiceOver ("Peanut, Avoid"), since the tint alone carries it on screen.
- `KindBadge`: Diet and Goal have no chevron and do not flip; the flippable badges get a 44 pt tap area around the 32 pt capsule. Hints: "Double-tap to only show it lower." / "Double-tap to always avoid it."
- `PrimaryButton` loading adds the VoiceOver value "Loading". `SectionHeader` is the title only for now; the 30 pt mascot beside "For you" comes with the mascot task.
