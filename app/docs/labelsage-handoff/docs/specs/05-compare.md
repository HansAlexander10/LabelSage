## Handoff Spec: Compare with, then Compare

### Overview
Two steps to answer "which one is better for us?". **Compare with** picks the second product (camera first, search one tap away, or tap an option). **Compare** shows only what differs, for everyone you shop for, and saves the better one to go-tos.

Boards: `design/screens/40-compare-with.png`, `41-compare.png`. Source: `design/prototype/Pick.dc.html`, `Compare.dc.html`.

### Layout: Compare with (sheet, large detent)
Background `screenTint.compareWith` (#f3f1fb).
- Header: Close (✕) left, title "Compare with".
- **Comparing row** (white, radius 18): thumb, "Comparing **Crunchwell Kettle**", small flag.
- **Card "Check the other one"**: magnifier icon, "Scan its barcode or photo the ingredients", primary "Open the camera". The camera returns straight into Compare.
- **Search by name**: a collapsed search field; tap expands with the keyboard and results as `ProductRow`s with flags.
- **Other options** heading with LabelSage (30, pose `point`) and "Tap one to compare" (muted, right). Rows: flag line ("OK for you and Mia"), name (1 line), "Brand · size · $0.86/oz", price, the deciding attribute on the right ("Olive oil", "2 g added sugar"). OK for everyone first, then Check first; Not for is not shown here.

### Layout: Compare (page or large sheet)
Background `screenTint.compare` (#f3f1fb).
- Header: Close, title "Compare", LabelSage 30 pt in pose `compare` (only mascot on screen).
- **Two columns**: image, brand, name (2 lines), size, NOVA chip; the better one gets a green "Works for you" badge.
- **Segmented**: Differences (default) | Everything.
- **Why card**: "Why Canyon Kettle works for you" with up to three lines from the engine findings and the model writer: "Cooked in olive oil instead of sunflower oil, so there are no seed oils." · "No added sugar. Crunchwell adds cane sugar (4 g a serving)." · "Trade-off: more fat and calories, 160 kcal vs 120 kcal per serving." Then "Check the packages. Not medical advice."
- **Key ingredients "3 of 4 differ"**: a two-column table by role (Base, Fat, Sweetener), each cell colored by its finding.
- **Nutrition "7 of 9 differ" · Per 28 g serving**: rows Calories, Total fat, Saturated fat, Sodium, Carbohydrate, Added sugar, Protein; **bold** marks the better value for what the household avoids and its goals. Footnote "Bold marks the better value for what you avoid and your goals."
- **Bottom bar** (glass): thumb, name, person line "OK for everyone", primary **Save to go-tos**.

### Design Tokens Used
| Token | Value | Usage |
|-------|-------|-------|
| `screenTint.compareWith` / `compare` | #f3f1fb | Backgrounds |
| `radius.card` | 26 | Cards |
| `verdict.*` | | Flags, cell colors |
| `color.amber` | | Open the camera, Save to go-tos |

### Components
| Component | Variant | Props | Notes |
|-----------|---------|-------|-------|
| `CompareWithView` | | base product | |
| `CompareView` | page, sheet; differences, everything | a, b products and verdicts | |
| `CompareTable` | ingredients, nutrition | rows, better side | "Differences" hides equal rows; the count "7 of 9 differ" always shows |
| `WhyCard` | | lines | 3 lines max |

### States and Interactions
| Element | State | Behavior |
|---------|-------|----------|
| Option row | Tap | Opens Compare with that product |
| Open the camera | Result | Compare opens with the scanned product; not found → the scan's not found state, then back |
| Search | Typing | Results after 2 characters, debounced 250 ms |
| Segmented | Everything | Shows equal rows too |
| Save to go-tos | Tap | Saves the better product (or the one in the bar); toast "Saved Canyon Kettle to your go-tos. I check it again every time." with Undo; button becomes "Saved to go-tos" ✓ with "Checked again every time" |
| Bar product is Not for someone | | The bar shows the person line ("Not for Mia · OK for you"). Save stays available: go-tos belong to the household and show their line (the Family board has a go-to marked "Not for Mia · peanut"). |
| Same product twice | | "That’s the same product." with Back |

### Responsive Behavior
| Breakpoint | Changes |
|------------|---------|
| AX sizes | Columns stack (A above B) with sticky product labels on each row |

### Edge Cases
- **Missing nutrition on one side:** "No data" in that cell, not counted as different.
- **Different serving sizes:** convert both to the smaller serving's grams and say "Per 28 g" in the header.
- **Can’t confirm on one side:** the why card leads with it: "Can’t confirm Crunchwell: ‘natural flavors’ isn’t specific."

### Animation / Motion
| Element | Trigger | Animation | Duration | Easing |
|---------|---------|-----------|----------|--------|
| Segmented | Switch | rows fade in or out, table height animates | 220 ms | easeOut |
| Save | Tap | button morphs to the saved state; `success` haptic | 200 ms | easeOut |
| LabelSage | Appear | `compare` loop (raises one product, then the other) | 3.6 s loop | easeInOut |

### Accessibility Notes
- Table rows read as "Sodium: Crunchwell 105 mg, Canyon Kettle 140 mg. Crunchwell is better."
- Bold is not the only cue: the better cell also gets a small check symbol for VoiceOver and color-blind users.

### Decisions made in build
(The coding agent lists here anything the spec didn't cover.)
