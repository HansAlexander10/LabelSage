---
type: reference
entity: LabelSage open questions
owner: Artem
status: current
updated: 2026-10-23
---

# Open questions

Each has a **build default** so work can continue. The team decides; then update the default and `decisions.md`.

| # | Question | Build default | Who decides |
|---|---|---|---|
| D4 | **Which product data and availability source?** Known so far: the Walmart API is not available; Amazon was raised. Other candidates to evaluate (not a decision): Open Food Facts, USDA FoodData Central Branded Foods, a retailer or Instacart catalog API, a paid label-data provider. Needs: barcode lookup, the ingredient text as printed, Contains/May contain lines, nutrition per serving, a photo, freshness date, and availability by store or ZIP for "Other options". | `ProductSource` protocol; `FixtureProductSource` over `data/sample-products.json`; a feature flag `useLiveProductSource` that is off. | Product + legal |
| Q1 | **The chat's "Other options" without D4.** | Fixtures only; when nothing fits say so ("Nothing here fits Mia yet.") and offer to check another. | Product |
| Q2 | **"May contain" with an allergy:** Not for, Check first, or Can’t confirm (the default in `PRD_front_end.md`, 19 Oct)? The engine gives **Not for** when the person's "may contain" switch is on, and **Check first** when it's off. The voice doc's example line uses Check first ("Check first: says ‘may contain milk’. Mia avoids these."). | As built: switch on = Not for. | Product + clinician |
| Q3 | **Vegan or vegetarian hides allergens in onboarding.** The allergen list hides milk, egg and fish when the person picked vegan (fish for vegetarian). Diets don't check "may contain", so a vegan with a milk allergy would lose that check. | As designed (hidden), with the list of covered allergens shown in the footnote. Recommendation for the team: show them again with a note "Also an allergy? Add it so I check ‘may contain’ too." The engine already supports both rules at once. | Design |
| Q4 | **Per-serving thresholds for daily limits** (heart: sodium 1,500 mg a day; blood sugar: added sugar 25 g a day; keto: net carbs 20 g a day). | Check first when one serving is over 20% of the daily limit (`servingShare = 0.2`). | Clinician |
| Q5 | **Kosher and halal certification.** The data rarely has the mark. | Flag forbidden ingredients; plain "gelatin" and "mono and diglycerides" are Can’t confirm for halal. Add "Look for a kosher mark on the package." under kosher verdicts. | Product + community review |
| Q6 | **Share-in-products percentages** shown in onboarding ("Milk · 31%", "Hides about 44% of products"). Their source must be confirmed before they ship. | Show them only behind a flag `showShares`, off by default. | Product |
| Q7 | **Clinical review of `data/catalog.json`** (terms, look-alikes, ambiguous terms) for the US market. | Demo catalog; banner in Settings > About in debug builds: "Demo ingredient catalog". | Clinician / dietitian (required before launch) |
| Q8 | **Minimum iOS.** Foundation Models and Liquid Glass need an Apple Intelligence device for the model. **Answered 2026-10-23: iOS 27 is the target and the minimum (register D-29).** | iOS 27 (per `PRD_front_end.md`); keyword-router fallback when the model is unavailable. | Engineering + product |
| Q9 | **Analytics.** | None in the MVP. | Product |
| Q10 | **Region outside the US.** The catalog and "may contain" wording are US-only. | ZIP must be 5 digits; non-US: "LabelSage checks US labels for now." | Product |
| Q11 | **Store list source** for "Where do you shop?" (depends on D4). | Fixture list near the ZIP (Whole Foods Market, Safeway, H-E-B, Target in the demo). | Product |
| Q12 | **`GlassButton` size.** `00-foundations.md` says a 44 pt circle; the onboarding boards and `OnboardSimple.dc.html` draw the back button at 50 pt (`width: 50px; height: 50px`). | 44 pt, as the spec says (also the minimum tap target). | Design |
| Q13 | **`OptionTile` corner radius.** tokens.json `radius.tile` is 22 ("Tiles and leaf tiles"); board `onboarding/09-diet.png` and the prototype's `tileS` use 26. | 26, as on the board (`Theme.radius.optionCard`). Leaf tiles keep 22. | Design |
| Q14 | **Component type sizes missing from tokens.json.** The prototype uses 19/600 for option and group card titles, 18/700 for tile titles and 14/600 for kind badges; tokens.json has only `cardTitle` 17/600 and `caption` 14/400. Icon sizes also differ: option card icon 46 (token `iconInCard` 48), tile icon 58 (token and spec 64), leaf icon 34 (no token). | Text: the prototype sizes, defined in `DesignSystem/Components/ComponentTypeStyles.swift`. Icons: the tokens (48, 64), 34 for leaves. | Design |
| Q15 | **Group count pill color** `#eceeec` (prototype) is not a token. | Ink at 8% opacity on the white card (renders #edeeed). | Design |

## Where this handoff differs from older repo docs

This handoff (23 Oct) is newer than `docs/app-engineering/PRD/PRD_front_end.md` (19 Oct) and register rows D-11 and D-12. Build default: this handoff. Artem to confirm, then update the PRD and the register.

| Topic | Older doc | This handoff |
|---|---|---|
| Scope | Recipe and Basket screens | Recipe removed; lists, basket, Instacart parked |
| Verdict words | Good, Careful, Bad, Can’t confirm (D-11) | OK for Mia, Check first, Not for Mia, Can’t confirm (voice guide); flags only, as D-11 |
| Household in onboarding | one named profile, the rest in Profile (D-12) | every person asked one at a time |
| "May contain" for an allergy | Can’t confirm | Not for with the switch on (Q2) |
| Font | SF Pro | Outfit (the new onboarding style) |
| Store | optional | optional, "Set up later" (same) |
| Prices | Price shown first on the meta line and in totals (register D-13, `PRD_front_end.md` "Price") | prices across stores parked; the go-to row still shows a price (`specs/06-family.md`) |
| Instacart and cart | Instacart handoff and retailers (`PRD_front_end.md` Basket, backend PRD, `docs/app-engineering/architecture.md` endpoints, register D-07 reason, Q-05) | Instacart and ordering parked (D2) |
| Recipes | Weekly meal plan F3 is a "yes" (register D-06); recipe endpoints (backend PRD) | recipe shopping and swaps removed |
| What the model reads | The model writes text only and never sees the user's raw text; a rule router reads the intent (`docs/app-engineering/spikes/spike-foundation-models-ios27-prompts-tools-2026-10-23.md` answer 3, `PRD_front_end.md`) | Foundation Models reads the intent with guided generation; the keyword router is the fallback (`HANDOFF.md` §6, `logic/chat-agent.md`) |
| Favorites | A favorite shows a heart instead of the verdict (register D-12, `PRD_front_end.md`) | go-tos show the person line when not OK (`specs/06-family.md`) |
| Share | Share the list as text (`prd-mvp-week-1-2026-10-19.md`) | share cut (D5) |
| Voice input | Hold-to-talk mic in the composer, P0 (`PRD_front_end.md`, `prd-mvp-week-1-2026-10-19.md`) | composer has photo, text field and camera; no mic (`specs/02-chat-home.md`) |
| Analytics | Anonymous analytics events in week 1 (`prd-mvp-week-1-2026-10-19.md`) | none in the MVP (Q9) |
| Icons | SF Symbols (`PRD_front_end.md`) | Fluent Emoji 3D for content icons (D10); SF Symbols remain on some buttons (`specs/02-chat-home.md` composer) |
| Navigation | Tab bar with Chat, Basket and Profile (`PRD_front_end.md`) | no tab bar in the specs; Family opens from the chat header avatar (`specs/06-family.md`) |
| Product name | "AI Shopping Agent" in the repo docs | LabelSage (D16) |

Rows added on 2026-10-23 after the Store row compare the handoff with the older repo docs (paths without a folder are in
`docs/app-engineering/PRD/`). The team decides each one; the register lists the matching rows under "Conflicts with
the LabelSage handoff" in `docs/strategy/01-decision-register.md`.
