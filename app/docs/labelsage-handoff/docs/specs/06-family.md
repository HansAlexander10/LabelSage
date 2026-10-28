## Handoff Spec: Family (preferences and settings)

> **Changed on 2026-10-27 by the product owner.** The app now differs from this page in these points; the rest of the page stands.
> 1. First-time onboarding sets up only the owner ("you"): Welcome, the owner's questions, region, store, summary. The "Who do you shop for?" step, the first-profile names, "Same allergies for anyone else?" and the next-person hand-over are gone from the first run.
> 2. The "allergy or intolerance?" step is gone. Every allergen is saved as an allergy (a hard filter), and "may contain" is always on. `Severity` stays in `LabelSageCore` for old data; the app never asks it.
> 3. The "'May contain' labels?" step is gone (see 2).
> 4. Other people are added later in Family, now titled "Preferences & settings". A card "Add someone you shop for" stays at the top until a second person exists. It runs: name, then one tick between "Start from <Name>'s preferences" (for each person) and "Start fresh", then the same per-person questions to add on top or edit, then "Save <Name>". Each person gets a copy; profiles are never linked.
> 5. The "Add a name" field has no leading plus. Its "Add" button is green with a white label when a name is typed, light grey with a muted label when empty.
> 6. Colors changed for contrast: see `docs/app-engineering/spikes/spike-contrast-audit-2026-10-27.md` in the main repo.


### Overview
Everything LabelSage knows about the household, in one scroll: one card per person (what they avoid, Avoid or Prefer not), macros and calories, go-tos, and settings including the **region and store** (D6). Opened from the chat header avatar. Most edits also work from the chat ("Add sesame to Mia’s allergies"), always with a confirm.

Board: `design/screens/50-family-preferences.png`. Source: `design/prototype/Profile.dc.html` (prop `open`: none, me, mia).

### Layout
Background `screenTint.family` (#fdf6ea). Glass "‹ Chat" back button.
- Title **Family** (34/700), line "I check every product for you and Mia." LabelSage (56 pt, pose `sit` the first time, then `idle`) at the top right; he is the only mascot here.
- **Person cards** (white, radius 26), one per person, owner first ("Alex (you)"):
  - Closed: avatar initial on a tint, name, "2 to avoid · 1 prefer not", Edit; chips for each item (Avoid red-tint, Prefer not amber-tint, Diet green-tint) with 3D icons.
  - Open (Edit → Done; 2 pt ink outline): one row per item: icon, name, detail ("Allergy · “may contain” too", "Allergy · almond, cashew, walnut and the rest"), `KindBadge` (Avoid / Prefer not), and a switch to turn the item off without deleting it. Footer link "+ Add an allergy by telling LabelSage" (opens the chat with "Add an allergy for Mia"), note "Avoid hides it. Prefer not only shows it lower. Tap to switch."
- **+ Add a person** (dashed card): runs the onboarding questions for one person (goal → … → strict) and returns here. Note "Every product is checked for everyone here."
- **Macros and calories**: rows with steppers ("Protein per meal · 25 g").
- **Go-tos** with a heart and "3 products": `ProductRow`s with the person line under the price when not OK ("Not for Mia · peanut"). Note "Checked again every time, in case the ingredients changed."
- **Settings** (grouped list): **Region** "Austin, TX 78701" ›, **Store** "Whole Foods Market" ›, Language "English" ›, Units "US" ›, Apple Health (switch), Show tips again. Note "Runs on your iPhone. Your data stays here."

### Design Tokens Used
| Token | Value | Usage |
|-------|-------|-------|
| `screenTint.family` | #fdf6ea | Background |
| `chips.avoid / preferNot / dietGoal` | | Item chips and badges |
| `screenTint.avatarTints` | 4 tints | Avatars by position |
| `radius.card` | 26 | Cards |

### Components
| Component | Variant | Props | Notes |
|-----------|---------|-------|-------|
| `PersonCard` | closed, open | person | Reused by the onboarding summary (compact chips variant for 3+ people) |
| `ItemRow` | | item, strength, isOn | |
| `GoToRow` | | product, verdict | Re-evaluated on appear |
| `SettingsList` | | | Region and Store push the onboarding region/store steps as standalone screens |

### States and Interactions
| Element | State | Behavior |
|---------|-------|----------|
| Edit | Tap | Card opens in place; other cards stay closed |
| KindBadge | Tap | Avoid ↔ Prefer not; saved at once; go-tos re-checked |
| Item switch | Off | Item kept but ignored by the engine; chip shows struck through |
| Remove an item | Swipe left on the row | Confirm "Remove peanut from Mia’s allergies?" with **Remove** and **Keep** |
| Add a person | Done | New card animates in; go-tos re-checked |
| Region | Tap | The region step (location or search); saving re-loads the store list and asks for a store if the old one is not near |
| Store | Tap | The store step for the current region |
| Go-to | Ingredients changed since saved | Row shows "Heads up: ingredients changed" and the new person line; the chat gets "Heads up: Mia’s granola changed. It now contains egg." (D15) |
| Go-to | Tap | Product page |
| Apple Health | On | Requests height, weight, age only (for targets); off clears them |

### Responsive Behavior
| Breakpoint | Changes |
|------------|---------|
| AX sizes | Chips wrap; badges move under the item name |

### Edge Cases
- **One person:** the line reads "I check every product for you."; "Add a person" stays.
- **Person with nothing set:** "Nothing to avoid yet. Add allergies any time."
- **No go-tos:** "No go-tos yet. Save a product you buy often and I’ll check it again every time."
- **Removing the last person who isn't the owner:** allowed; the owner can't be removed.
- **Long names:** truncate in the card title, full in VoiceOver.

### Animation / Motion
| Element | Trigger | Animation | Duration | Easing |
|---------|---------|-----------|----------|--------|
| Person card | Edit / Done | height + outline | 240 ms | easeOut |
| Badge | Flip | background crossfade | 160 ms | ease |
| Go-to re-check | Appear | rows show a tiny reading spinner, then the line | ≤ 600 ms | ease |

### Accessibility Notes
- Person card closed: "Mia. 2 to avoid: peanut, tree nuts. Edit, button."
- Badge: "Peanut: always avoided. Double-tap to only show it lower." (Allergies are always Avoid: the badge is static for allergies and medical diets.)
- Settings rows are standard list rows with values read after labels.

### Decisions made in build
(The coding agent lists here anything the spec didn't cover.)
- Item rows swipe to remove with the confirm from the states table; a non-owner person card swipes to remove with "Remove Mia from your family?" (Remove, Keep).
- "Add an allergy by telling LabelSage" calls `onEditPerson(person)`; the shell opens the chat.
- The protein stepper runs 5 to 60 g in steps of 5 (prototype) and saves to the owner's `goals.proteinG`.
- With unreadable profiles (`needsProfileRecheck`) a banner asks to add each person again and go-tos show Can’t confirm.
- See Q-T12-1 to Q-T12-7 in `open-questions.md`.
