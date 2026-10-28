## Handoff Spec: Launch and onboarding

> **Changed on 2026-10-27 by the product owner.** The app now differs from this page in these points; the rest of the page stands.
> 1. First-time onboarding sets up only the owner ("you"): Welcome, the owner's questions, region, store, summary. The "Who do you shop for?" step, the first-profile names, "Same allergies for anyone else?" and the next-person hand-over are gone from the first run.
> 2. The "allergy or intolerance?" step is gone. Every allergen is saved as an allergy (a hard filter), and "may contain" is always on. `Severity` stays in `LabelSageCore` for old data; the app never asks it.
> 3. The "'May contain' labels?" step is gone (see 2).
> 4. Other people are added later in Family, now titled "Preferences & settings". A card "Add someone you shop for" stays at the top until a second person exists. It runs: name, then one tick between "Start from <Name>'s preferences" (for each person) and "Start fresh", then the same per-person questions to add on top or edit, then "Save <Name>". Each person gets a copy; profiles are never linked.
> 5. The "Add a name" field has no leading plus. Its "Add" button is green with a white label when a name is typed, light grey with a muted label when empty.
> 6. Colors changed for contrast: see `docs/app-engineering/spikes/spike-contrast-audit-2026-10-27.md` in the main repo.


### Overview
First open. LabelSage welcomes the person, asks who they shop for, then asks about each person's allergies one at a time. After that he asks where they are and where they shop, shows one card per person, and ends on "Check my first product", which opens the camera (D1). He guides every step: **his line is the title**, the screen holds only the answers and one button.

Boards: `design/screens/00-launch.png`, `design/screens/onboarding/01…14.png`, `72-onboarding-decision-tree.png`. Logic: `docs/logic/onboarding-tree.md`. Source: `design/prototype/OnboardSimple.dc.html`, `Splash.dc.html`.

### Layout
**Launch (Splash):** full-screen green mesh (brand), LabelSage waving at center, the wordmark, "Check the ingredients for everyone you shop for.", subline "Built for food allergies, celiac and dairy-free households". Any tap or 1.5 s → Welcome. It's a SwiftUI view after the system launch screen (the static launch screen is the green background only).

**Welcome (step 1):** tinted `#eaf3f8`. Two trust pills at the top ("Stays on your iPhone", "Whole family"). A tilted collage: LabelSage large with two floating cards ("Checks every ingredient" with the magnifier icon, "For everyone you shop for" with sparkles). Wordmark, line "I check the ingredients for everyone you shop for. Hidden names too.", legal line with Terms of Use and Privacy Policy links, primary "Get started".

**Every question step (the skeleton):**
```
[ ‹ glass back ]      ● ● ●  (section dots)       [ Skip ]   ← 54 pt from top
                LabelSage (74 pt, pose per step)
          His line as the title (mascotTitle, centered)
   ┌──────────────────────────────────────────────┐
   │ answers: option cards / 2-column tiles / list │  ← scrolls, 20 pt gutter
   └──────────────────────────────────────────────┘
   small footnote (13 pt, muted) when the step has one
   [            Continue  ›            ]          ← primary, 66 pt, pinned bottom
```
Background tint per step (`screenTint`). No separate title and description block (the voice rule "LabelSage explains, the interface doesn't").

### Design Tokens Used
| Token | Value | Usage |
|-------|-------|-------|
| `type.mascotTitle` | Outfit 30/800 (27 or 24 for long lines) | LabelSage's line |
| `screenTint.*` | per step | Background |
| `radius.card` / `radius.tile` | 26 / 22 | Option cards / tiles and leaves |
| `size.mascotOnboarding` | 74 | Mascot above the title |
| `color.amber` | #eb9d15 | Continue, Get started, Check my first product |
| `chips.*` | | Summary chips (Avoid, Prefer not, Diet) |

### Steps (copy and pose)
| # | Step | LabelSage says (pose) | Answers | Notes |
|---|---|---|---|---|
| 1 | welcome | (wave) "I check the ingredients for everyone you shop for. Hidden names too." | Get started | |
| 2 | household | "Who do you shop for?" (listen) | Just me · "Just my allergies and diets"; My family · "Everyone at home, one at a time" | single choice, cards |
| 3 | firstprofile | "What should I call them? Add everyone at home." (listen); after the first name: "Heads up: I’ll ask a few questions for each person, one at a time." (talk) | Name field; quick picks Me, My child, My partner; "Anyone else at home?" add names as chips | footnote "Every product is checked for everyone you add." |
| 4 | goal | "What should I check for?" / "…for Mia?" (point) | Allergies and ingredients · "Allergies, diets and anything you avoid"; Macros and calories · "Protein and calories for a goal" | checklist |
| 5 | why | "Why does Mia avoid some foods? Pick all that fit." (listen) | Medical diet; Allergy or intolerance; Diet choice; Religion or culture; I just don’t like some foods | footnote "Allergies and medical diets are always avoided. Dislikes only move products down." |
| 6 | allergens | "What does Mia avoid?" (point) | 9 group cards: Peanuts, Tree nuts ▸, Milk, Eggs, Soy, Wheat, Fish and shellfish ▸, Sesame, Other ▸ (Mustard, Celery, Lupin, Sulfites, Corn, Coconut); search field "Search, like prawns or mustard" | groups open in place; peanut suggests Tree nuts and Lupin in a sheet, never pre-ticked |
| 7 | severity | "For Mia: allergy or intolerance? Pick one for each." (thinking) | per allergen: Allergy · "Avoid it, and “may contain” too" (default) / Intolerance · "Only when it’s in the ingredients" | D3 |
| 8 | diet | "Any diet for Mia?" (listen) | tiles: Vegan, Vegetarian, Keto, Paleo or whole food | optional |
| 9 | religion | "Halal, kosher or other? I’ll catch hidden gelatin too." (listen) | tiles: Halal, Kosher, No beef, Other (text) | optional |
| 10 | medical | "Which medical diet for Mia?" (listen) | Celiac or gluten-free; Heart health; Blood sugar; Something else (text) | |
| 11 | avoid | "Anything else Mia avoids? I’ll catch it under other names too." (point) | search "Anything, e.g. nightshades or red dye"; Common groups list with checkboxes (Added sugars, Natural flavors, Seed oils…) | search result "Make ‘…’ a custom filter" runs the resolver: Matching, then High/Medium/Low match with keyword chips to untick |
| 12 | strict | "‘May contain’ labels for Mia?" (thinking) | switch "Also avoid “may contain”" with "On because of your answers."; "Same allergies for anyone else?" names | skipped when the only reason is dislike |
| 13 | source / phase / targets | "Where do your targets come from?" (thinking) · "What are you working toward right now?" (listen) · "Here are your daily targets. Change them if your coach set others." (talk) | | only for Macros and calories; Apple Health is requested only on "Help me set them" |
| 14 | nextperson | "Mia’s allergies are set. Now Leo: same questions, Leo’s answers." (talk) | list of people with status; primary "Start Leo’s questions" | |
| 15 | **region** | "Where are you? Products differ by area." (point) | "Use my location" (fills the ZIP), or "Or search a city or ZIP code" with suggestions; footnote "Only your ZIP code is kept, on this iPhone." | **required** (D6) |
| 16 | **store** | "Where do you shop? I’ll find other options there." (point) | stores near the ZIP: name + "1.2 mi · Downtown"; footnote "Stores near your ZIP code. You can set this up later." | single choice, optional: top-right "Set up later" (D6) |
| 17 | depth | "Allergies are set. Fine-tune now, or start?" (talk) | Start now · "Show my summary; I’ll learn as you shop"; Fine-tune more · "Budget and preferences · about 1 min" | |
| 18 | prefs | "Anything you’d rather skip? I’ll show it lower, never hide it." (listen) | Prefer organic, Avoid ultra-processed, Prefer store brands, Prefer local | ranking only |
| 19 | summary | "Here’s what I’ll watch for your family." / "…for Mia." (done) | one card per person (see below); region and store row; "Try it" preview; notes; primary "Check my first product" | |

**Summary card per person:** avatar (initial on a tint from `avatarTints`), name, "3 to avoid · 1 other", Edit. One person: rows with icon, label, detail, `KindBadge` (Avoid / Prefer not / Diet / Goal) that flips Avoid and Prefer not. Three or more people: compact cards with chips so everyone fits. "Same for Dad" line when others share a person's allergies. Then a white row with the storefront symbol: "Austin, TX 78701" / "Whole Foods Market · change in Profile". Then "Try it: [product] would be **Not for Mia**: sunflower oil is a seed oil." from the engine over a sample product. Notes: "Avoid hides it. Prefer not only shows it lower. Tap to switch." and "Check the package. Not medical advice."

### Components
| Component | Variant | Props | Notes |
|-----------|---------|-------|-------|
| `OnboardingScaffold` | | step, mascotPose, line, canSkip, canContinue, primaryTitle | The skeleton above; owns back, skip, dots, primary |
| `OptionCard` / `OptionTile` | single, multi | from `00-foundations.md` | Cards for long labels, tiles for short choices (diet, religion, medical) |
| `GroupCard` + `LeafTile` | | | Allergens |
| `RelatedSheet` | | allergen, suggestions | Bottom sheet: "Peanut is added. Some people with a peanut allergy also react to tree nuts or lupin. Add either? Nothing is added unless you tick it." Unticked rows; primary "Add selected" ("Add 1 more" once ticked); text button "Just peanut" |
| `ResolverCard` | matching, ambiguous, matched | term | "Matching…", then choices when ambiguous ("oil": Seed oils / Palm oil / All added oils), then keyword chips |
| `PersonSummaryCard` | full, compact | person, rules | |
| `PlaceSearch` | | query, suggestions | City, state or ZIP prefix matching; 4 suggestions max |

### States and Interactions
| Element | State | Behavior |
|---------|-------|----------|
| Continue | No answer yet | Disabled (amberDisabled); VoiceOver hint names what is missing |
| Skip | Optional step | Jumps toward summary, never past the region; on the store step it reads "Set up later" |
| Back | Any step | Previous step in the computed path; answers kept |
| Group card | Tap | Opens/closes in place; count pill "2/9" |
| Peanut | First tick | Related sheet (Tree nuts, Lupin), nothing pre-ticked |
| Use my location | Tap | Location permission (when in use); on success fills ZIP and city and selects the card; on denial shows the search field focused |
| Place search | 2+ characters | Suggestions by city prefix, state name, state code or ZIP prefix; none: "No US city or ZIP code matches “…”." |
| Store card | Tap | Selects (single) |
| Summary badge | Tap | Flips Avoid ↔ Prefer not |
| Check my first product | Tap | Saves the Household, marks onboarding done, opens the chat with the camera presented (D1) |

### Responsive Behavior
| Breakpoint | Changes |
|------------|---------|
| Small phones (375 pt) | Title steps down one size when over two lines |
| AX sizes | Tiles become full-width cards; mascot 56 pt; footnotes wrap |

### Edge Cases
- **One person, Just me:** no firstprofile, no nextperson; summary title "Here’s what I’ll watch for." with the owner as "You".
- **Only dislikes:** no strict step; all groups default to Prefer not.
- **Macros only:** no allergens; summary shows the goal rows; verdicts are informational.
- **Diet covers an allergen:** hidden from the list, named in the footnote (Q3).
- **No location permission:** search only. Non-US ZIP: Q10 copy.
- **No stores near the ZIP (fixture source):** "No stores found near 99999. Try another ZIP code." with Back.
- **Long names** (people, stores): one line, tail truncation; full name read by VoiceOver.
- **Killing the app mid-onboarding:** resume at the last step with answers kept (store the state in SwiftData or `@SceneStorage`).

### Animation / Motion
| Element | Trigger | Animation | Duration | Easing |
|---------|---------|-----------|----------|--------|
| Step content | Continue | slide 24 pt left + fade; Back mirrors | 280 ms | easeOut |
| LabelSage | Step change | stays in place; pose crossfade | 150 ms | ease |
| Welcome collage | Appear | cards float in with 60 ms stagger, slight rotation settle | 400 ms | easeOut |
| Summary | Appear | LabelSage "done" (jump, then hops); cards fade up with 40 ms stagger | 600 ms | easeOut |
| Progress dots | Section change | color crossfade | 200 ms | ease |

### Accessibility Notes
- The mascot line is the screen title: `.accessibilityAddTraits(.isHeader)`, read first.
- Cards are single elements with role (checkbox or radio) and state.
- Group cards: "Tree nuts, 2 of 9 selected, collapsed. Button."
- Skip reads "Skip this step".
- The place suggestions are a list with "Matching places" label.
- All copy is in the Steps table; strings live in the String Catalog with the person's name as an argument.

### Decisions made in build
(The coding agent lists here anything the spec didn't cover, for design review.)
