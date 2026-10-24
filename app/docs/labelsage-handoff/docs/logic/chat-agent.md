# The chat agent

Board: `design/screens/71-chat-intents.png`. Principle: **code decides, LabelSage explains** (D8).

## Pipeline

```
user text ──► IntentReader ──► Intent + slots ──► Action (deterministic) ──► Result ──► Writer ──► dock line + cards
               (on-device model,                  (ProductSource,             (findings)   (on-device model
                guided generation;                 VerdictEngine,                           or templates)
                keyword fallback)                  Household edits)
```

- **IntentReader** turns text into a typed `Intent` with Foundation Models guided generation (`@Generable`). It sees the household (names, what each avoids), the last product and the last result. It never sees anything it doesn't need.
- **Actions are plain Swift.** They call `ProductSource`, `VerdictEngine` and the household store. The model never returns a verdict.
- **Writer** turns the action's result into LabelSage's line. It receives the findings and the deterministic reason, writes at most 20 words in the voice (`voice-and-strings.md`), and is validated: the line must contain the person's name and the flag word of the engine's level, must not contain any word from the never-list, and falls back to the deterministic reason when it fails or the model is unavailable.

## Intents (MVP)

| Intent | Example | Slots | Action | Answer |
|---|---|---|---|---|
| `check` | (camera) / "check this" | barcode or photo | open the camera; look up; engine | product card + sheet; "Not for Mia. Contains peanuts." |
| `ask` | "Are the popped corn chips OK for me?" | product name, people? | search `ProductSource` by name; engine | one flag per person with the deciding ingredient; "Can’t confirm" with the reason when the ingredients don't say |
| `otherOptions` | "kettle chips without seed oils" / "find one that is" | category or last product, constraints | search same category in the household store (D6), engine on each, keep OK for everyone first, then Check first | up to 3 cards, "Found 3. All OK for you and Mia." (done); nothing: say so and offer the closest (Q1) |
| `compare` | "compare these two" | two products (last two by default) | engine on both | Compare sheet, differences first |
| `changeAllergies` | "Mia reacted to hummus. Add sesame to her allergies" | person, item, severity? | build a `ProfileChange`; **never save without Confirm** (D14) | change card; after Confirm re-check that person's go-tos |
| `pivot` | "make it nut-free", "what about Leo?", "undo" | change to the last request | apply to the last result in place; never start from scratch | the updated card |
| `smallTalk` / `vent` | "every label, every time" | | none | one line, listen pose, no sales |

Also from the start screen tiles: "Ask about a product" and "Find other options" prefill the composer; "Change allergies" opens the person picker.

## Typed output (sketch)

```swift
import FoundationModels

@Generable
struct ReadIntent {
    @Guide(description: "What the person wants", .anyOf(["check", "ask", "otherOptions", "compare", "changeAllergies", "pivot", "smallTalk"]))
    var intent: String
    @Guide(description: "Product name or category as written, if any")
    var product: String?
    @Guide(description: "Names of people from the household this is about; empty means everyone")
    var people: [String]
    @Guide(description: "Ingredient or allergen to add or avoid, as written")
    var item: String?
    @Guide(description: "allergy or intolerance if the person said so")
    var severity: String?
}
```

Map `item` to a catalog family with the same search the onboarding uses (`searchSynonyms`, family terms). If nothing matches, propose a custom rule with terms and show them in the change card for the person to confirm.

## Context the agent keeps per chat

`lastProducts` (up to 3), `lastResult` (`HouseholdVerdict`), `focusPeople` (when the person said "for Leo"), `pendingChange`. A new chat clears it. History keeps a title (the first product or the topic: "Peanut butter check").

## Guardrails

- Never says "safe" (or "safer", "unsafe"), never promises an outcome, never gives dosing or medical advice. "Check the package. Not medical advice." under every verdict card.
- When the person asks "is this safe for my son?": answer "OK for Leo" or "Not for Leo", never repeat "safe".
- Profile changes only through the change card and Confirm. An inferred change ("Mia reacted to hummus") is a proposal, never a save.
- If the model output fails validation twice, use the deterministic line.
- No network calls from the model. The only network is `ProductSource`.
