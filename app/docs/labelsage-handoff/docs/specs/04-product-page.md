## Handoff Spec: Product page

### Overview
Everything about one product, for everyone you shop for. It is **one view** used two ways: as a **page** (from a list, a go-to, Compare) and as a **sheet** (from the camera with the photo hidden, and from the chat). The flag and the reason render at once from the engine. When the on-device model is ready, its summary replaces the reason in place (D8).

Boards: `design/screens/30-product-page-top.png`, `31-product-page-full.png`. Source: `design/prototype/Main.dc.html` (props: `as` page|sheet, `photo` show|hide, `from` chat|scan|page, `away`).

### Layout (top to bottom, page)
1. **Photo hero** (600 pt tall, white, sticky behind the content): pack photo 380 × 400 centered, `multiply` blend. Floating glass circles: Back (left), Favorite heart (right, "Add to go-tos"). Page dots for up to 3 photos (glass pill, bottom center). **Photo signal**: a 60 pt `VerdictFlag` bottom-right of the photo, symbol only.
2. **Content sheet** overlapping the photo by 28 pt, radius 28 top, background `screenTint.product` (#fdf6ea):
   - Brand (15, muted), **name** (26/700), "3 oz · 3 servings of 28 g", "Chips & snacks · Crunchwell" (13, muted).
   - **For you** section heading (22/700) with LabelSage 30 pt at the right edge (pose from the overall level: notFor → guard, checkFirst → thinking, ok → done, cantConfirm → thinking). If the page is a sheet over the chat, he is here and the chat dock is empty.
   - **Verdict banner** (white card, the level's wash on top): symbol, title ("Not for you", "OK for you and Mia", "Check first", "Can’t confirm"), reason ("Sunflower oil is the 2nd ingredient, so it’s not for you. Watch 4 g added sugar per serving."). With more than one person the title is the person line ("Not for you · OK for Mia") and the reason covers the worst one.
   - **Try instead** row inside the banner (when not OK): thumb, "Try instead" / product name, "Compare" link.
   - "Check the package. Not medical advice." (13, muted).
   - **Rows** (white card): "May contain · Not on the pack" with an info button (explains that US labels don't have to print it), then **What you avoid** "1 to avoid · 1 to check" ⌄ which opens one row per rule with a switch to turn that rule off **for this check only** (the flag updates live and the reason re-renders).
3. **Other options for you** (22/700) with "See all": horizontal cards (204 pt): image, flag line "OK for you and Mia", name (2 lines), "Brand · size · olive oil", price, "Compare". Options come from the household store (D6) via `ProductSource`; hidden when there are none.
4. **Key ingredients 4**: rows with level symbol, ingredient name, "Not for you · Avoid seed oils" / "Check first · Limit added sugar" / "OK · seasoning". Tap opens the row: one line why ("Seed oil, 2nd ingredient. Most of the 4.5 g fat."), link "More about sunflower oil" (opens the chat with that question). Shows 3, then "See all 4 ingredients".
5. **Nutrition**: donut of calories by macro (carbs #eb9d15, fat #7e9086, protein #26834e; never verdict colors), 120 Calories per serving in the middle, three macro chips (g, kcal, %), facts row "4 g added sugar" (flagged amber when a rule cares) and "105 mg sodium". "Full nutrition facts" ⌄ with a segmented "per serving | per 100 g".
6. **Toolbar** (sticky bottom, glass): "Ask LabelSage" (secondary, sparkles) and **"Check another"** (amber primary, `barcode.viewfinder`).
7. **Mini header** after scrolling 400 to 480 pt: white glass bar with a 36 pt thumb, the name and a small flag.

**As a sheet:** grabber, photo hidden (`photo: hide`), starts at "For you", medium detent then large; Close replaces Back.

### Design Tokens Used
| Token | Value | Usage |
|-------|-------|-------|
| `screenTint.product` | #fdf6ea | Content background |
| `verdict.*` | | Banner wash, symbol, signal ring |
| `type.productName` | 26/700 | Name |
| `type.sectionTitle` | 22/700 | Section headings |
| `size.verdictSignal` | 60 | Photo signal |
| `size.mascotSectionHeading` | 30 | LabelSage in "For you" |

### Components
| Component | Variant | Props | Notes |
|-----------|---------|-------|-------|
| `ProductPage` | page, sheet; photo shown, hidden | product, verdict, origin (chat, scan, page) | One view for both |
| `VerdictBanner` | 4 levels | verdict, tryInstead? | |
| `RuleRows` | collapsed, open | rules, per-check overrides | Overrides never persist |
| `OptionCard204` | | product, verdict | Also used in Compare with |
| `IngredientRow` | ok, checkFirst, notFor, cantConfirm; open | finding | |
| `NutritionDonut` | | nutrition | Accessible summary string |
| `ProductToolbar` | | | Glass bar |

### States and Interactions
| Element | State | Behavior |
|---------|-------|----------|
| Reason | Initial | Deterministic `PersonVerdict.reason`, rendered immediately |
| Reason | Model ready | Crossfade (200 ms) to the model summary; no skeleton, no shimmer. Model fails or is off: keep the deterministic line |
| Favorite | Tap | Adds to go-tos; toast "Saved to go-tos" with "View"; again: "Removed from go-tos" with "Undo" |
| What you avoid | Switch off a rule | Flag and banner re-evaluate; a note "For this check only" appears |
| Try instead / Compare | Tap | Compare (page, or sheet when this is a sheet) |
| Other option card | Tap | That product's page |
| Ingredient row | Tap | Opens in place |
| Ask LabelSage | Tap | Chat with this product as context |
| Check another | Tap | Camera (from a sheet over the camera: close the sheet) |
| Photo signal | Appear | Ring pulses twice (none with Reduce Motion) |
| Not for (allergy) | Appear | `.warning` haptic once; LabelSage guard |

### Responsive Behavior
| Breakpoint | Changes |
|------------|---------|
| Small phones | Hero 520 tall |
| AX sizes | Option cards become a vertical list; donut chips stack; toolbar buttons stack |

### Edge Cases
- **No photo:** hero becomes a pack-shaped tile with the brand initial; the photo signal moves next to the name.
- **No ingredient list:** flag Can’t confirm, Key ingredients replaced by "No ingredient list for this one yet. Photo the ingredients and I’ll read them." with a button.
- **No nutrition:** Nutrition section shows "No nutrition facts yet." Limits give Can’t confirm (engine).
- **One person household:** title "OK for you", no person line.
- **Long names:** product name wraps to 3 lines then truncates; option cards 2 lines.
- **Many ingredients (40+):** "See all" pushes a full list screen.
- **Data age:** "Data updated Oct 2026" under the disclaimer when older than 90 days.

### Animation / Motion
| Element | Trigger | Animation | Duration | Easing |
|---------|---------|-----------|----------|--------|
| Hero | Scroll | photo stays (sticky), content slides over it | | |
| Mini header | Scroll 400 to 480 pt | fades and slides in | scroll-linked | linear |
| Reason | Model ready | crossfade | 200 ms | ease |
| Rule switch | Toggle | banner color crossfade, reason swap | 200 ms | ease |
| Ingredient row | Open | height + fade | 220 ms | easeOut |

### Accessibility Notes
- Order: name, verdict banner (level, reason), disclaimer, What you avoid, Other options, Key ingredients, Nutrition, toolbar.
- Photo signal: hidden from VoiceOver (the banner says it).
- Donut: one element, "120 calories per serving. Carbs 64%, fat 33%, protein 3% of calories."
- Rule switches: "Avoid seed oils, on. Turning it off changes this check only."

### Decisions made in build
(The coding agent lists here anything the spec didn't cover.)
