# Voice and strings

Every word in the app follows this. The full brand voice lives with the brand docs; this is the part an engineer needs.

## Who LabelSage is

The household's label hero. He reads every ingredient list, catches what someone at home avoids, and says it in one line. The enemy is **what hides in the ingredients** (other names, vague words, "may contain", quiet ingredient changes), never the food, the brand, the store or the person who chose it. A real hero doesn't bluff: when the label doesn't say, he says "Can’t confirm" and why.

## Hard rules

1. **Never "safe"** in any form: not "safe", "safer", "unsafe", "not safe", "100%", "guaranteed", "allergy-proof", "allergy-friendly", "protected" as a promise. If the person types "is this safe for my son?", answer "OK for Leo" or "Not for Leo" and never repeat their word.
2. **Verdicts name the person:** OK for Mia · Check first · Not for Mia · Can’t confirm. Several people: one segment each ("Not for Mia · OK for you").
3. **Certain about what was checked, never about the outcome:** "No milk in these ingredients", never "Mia will be fine".
4. **One idea per bubble**, at most 20 words and 2 lines; a verdict is 5 words or fewer; grade-6 words.
5. **Names, not roles:** Mia, Dad, Whole Foods. Never "the user", "household member", "little one".
6. **Every answer that changes something says what he'll do:** "On it. I’ll flag every ‘may contain’ peanut for Mia."
7. **Humour only at finds and light moments.** Never at verdicts, reactions, ingredient changes or errors. No puns near allergens.
8. **No guilt, no diet talk:** no "junk", "clean", "cheat", "guilt-free", "toxic", no streak pressure.
9. **At most one exclamation mark per screen**, only at a find. **No emoji** in his lines. **No em dashes** anywhere.
10. **"Check the package. Not medical advice."** under every verdict.

## Their words, not ours

| Say | Not |
|---|---|
| ingredients | label (except the brand name), fine print, ingredient analysis |
| check | scan, snap, analyze ("Barcode" is fine as a mode name) |
| OK for Mia | safe, good, approved, cleared |
| Not for Mia | bad, unsafe, warning |
| Check first | careful, caution |
| Can’t confirm | unknown, error, N/A |
| may contain | traces, PAL |
| cross-contamination | cross-contact (fine in help text) |
| hidden (as in whey, casein) | aliases, derivatives |
| allergies, family | rules, restrictions, household, profile |
| who you shop for | household members, users |
| Mia’s go-tos | safe list, favorites |
| other options, try instead | safer pick, dupe, swap |
| found | mission done, cleared |
| Skip | Not now, Later |

## Tone by moment

| Moment | Pose | Example |
|---|---|---|
| First open | wave | "Hi, I’m LabelSage. I check the ingredients for everyone you shop for." |
| Onboarding question | listen, point | "What does Mia avoid?" |
| Reaction to an answer | talk | "Got it. I’ll flag every ‘may contain’ milk for Mia." |
| Checking | reading | "Checking the ingredients…" |
| OK | (the flag leads) | "OK for Mia. Nothing Mia avoids is in it." |
| May contain | (the flag leads) | "Check first: says ‘may contain milk’." / "Not for Mia. May contain milk." |
| Contains an allergen | guard | "Not for Mia. Contains whey: that’s milk." |
| Can’t confirm | thinking | "Can’t confirm. ‘Natural flavors’ isn’t specific." |
| Other options | point, then done | "Try instead: 3 options OK for Mia." / "Found one for Mia." |
| Ingredients changed | talk (no hop) | "Heads up: Mia’s granola changed. It now contains egg." |
| A reaction story | listen | "That sounds hard. Want me to add sesame to Mia’s allergies?" |
| Venting | listen | "Every label, every time. I’ll take that part." |
| Profile change | talk | "Add sesame to Mia’s allergies? Nothing changes until you confirm." |
| Product not found | disguise | "This one’s new to me. Photo the ingredients and I’ll read them." |
| Offline | thinking | "No signal. Your go-tos still work." |

## Strings in code

- One **String Catalog** (`Localizable.xcstrings`), English (US) only for the MVP. Keys are descriptive (`verdict.notFor.contains`), values use the person's name as an argument, never "he/she".
- The app and mascot names are arguments from `Brand` (`"Hi, I’m %@."`).
- Typographic apostrophes and quotes (’ ‘ “ ”) in all copy; the engine's lines already use them.
- `LabelSageCore.Copy` holds the engine's deterministic lines. Move them to the catalog with the same wording when localizing.
- Localization notes for later: catchphrases ("on it", "heads up") are idioms, so translate the meaning; German runs about 30% longer, allow 3 lines in the bubble; "may contain" must use the wording printed on labels in that market.

## Copy checklist for every screen

- [ ] No word from the never-list (`grep -ri "safe"` returns nothing user-facing)
- [ ] Verdicts name people; the owner is "you"
- [ ] The disclaimer is under every verdict
- [ ] Bubble ≤ 20 words, verdict ≤ 5 words
- [ ] No em dashes, no emoji in his lines, at most one "!"
