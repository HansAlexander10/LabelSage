---
type: reference
entity: LabelSage known issues — device walkthrough 2026-10-28
owner: Alex
status: open
updated: 2026-10-28
---

# Known issues: real-device walkthrough (2026-10-28)

Found walking through onboarding, Family and chat on a real iPhone. Three of these are not new: they are
already flagged in `open-questions.md` as unwired build defaults, cross-referenced below instead of
duplicated. The other three (ZIP → city/state, city save, chat placeholder context) are new.

| # | Issue | Screen | Expected | Actual | Related |
|---|---|---|---|---|---|
| 1 | No height/weight/age input for "Help me set them" | Onboarding, goals/targets step | Choosing "Help me set them" asks for height, weight and age (or reads Apple Health) to compute targets | No input screen appears; the app just prefills the default targets | `open-questions.md` Q-T7-7: "'Help me set them' only prefills the default targets", no real field yet |
| 2 | "Use my location" does nothing | Onboarding, region step | Tapping it requests location permission and fills in the ZIP | Button has no effect | `open-questions.md` Q-T7-3: a custom card calling a `locate` closure that defaults to `nil`; CoreLocation and the `NSLocationWhenInUseUsageDescription` plist key are not wired yet |
| 3 | Store picker only shows Whole Foods | Onboarding, store step | A short list of nearby stores (the fixture set names Whole Foods, Safeway, H-E-B, Target) | Only Whole Foods appears | `open-questions.md` Q11 and Q-T7-4: `FixtureProductSource.stores(near:)` currently returns one store, not the four-store demo list |
| 4 | Entering a ZIP doesn't show city/state | Onboarding, region step | Typing a valid ZIP reverse-fills the city and state so the person can confirm it | Nothing shown after the ZIP | New — no matching open question found; needs a ZIP → city/state lookup (local table or reverse-geocoding) |
| 5 | Entering a city doesn't save | Onboarding, region step | Typing a city and continuing saves it as the region, same as a ZIP | Save appears to no-op; the city doesn't persist | New — likely the same underlying region-save path as #4, but confirm separately since the symptom is "doesn't save" not "doesn't look up" |
| 6 | No "5-digit ZIP expected" validation message | Onboarding, region step | An invalid ZIP shows a message telling the person a 5-digit number is expected | No feedback; invalid input is silently accepted or ignored | `open-questions.md` Q10 sets "ZIP must be 5 digits" as the build default, but the user-facing validation message that enforces it isn't implemented |
| 7 | Chat composer placeholder never changes context | Chat home / thread | The placeholder reflects what's happening (e.g. something allergy-change-specific right after "Change allergies") | Always reads "Point the camera at a barcode, or ask me about any products," even mid-flow | New — no matching open question found |

Facts:
- Issues 1, 2 and 3 → are already tracked as → unwired build defaults in `open-questions.md` (Q-T7-7, Q-T7-3, Q11/Q-T7-4), not new bugs
- Issues 4, 5, 6 and 7 → are new → found during this 2026-10-28 walkthrough, no existing open-question row
- The region step (ZIP, city, "Use my location", validation) → accounts for → four of the seven issues (2, 4, 5, 6), the single most-broken screen in this walkthrough
