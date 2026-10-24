# Onboarding decision tree

Source: `design/prototype/OnboardSimple.dc.html` (`renderVals`, the `path` array) and `design/screens/72-onboarding-decision-tree.png`. The path is **computed from the answers so far**, so a step only appears when an earlier answer needs it. Nothing is asked twice.

## The path

```
welcome
household                         "Who do you shop for?"  Just me | My family
[firstprofile]                    if My family: the first person's name + everyone else at home
── per person (pi = whose turn) ─────────────────────────────────────────────
goal                              checklist: Allergies and ingredients (avoid) | Macros and calories (numbers)
if avoid:
  why                             checklist: medical | allergy | diet | religion | dislike
  [diet]                          if why ∋ diet         (asked first: a diet already rules some allergens out)
  [religion]                      if why ∋ religion
  [medical]                       if why ∋ medical
  [allergens, severity]           if why ∋ allergy
  avoid                           everyone on this branch: groups + search + custom
  [strict]                        unless the only reason is "dislike"
if numbers:
  source, phase, targets
[nextperson]                      if My family and more people are left → loop back to goal for them
── once for the household (D6) ──────────────────────────────────────────────
region                            required
store                             optional ("Set up later")
[depth]                           if a goal was set: Start now | Fine-tune more
[prefs]                           if Fine-tune more
summary
```

```swift
func path(for s: OnboardingState) -> [Step] {
    var p: [Step] = [.welcome, .household]
    if s.household == .family { p.append(.firstProfile) }
    p.append(.goal)
    if s.goals.contains(.avoid) {
        p.append(.why)
        if s.why.contains(.diet) { p.append(.diet) }
        if s.why.contains(.religion) { p.append(.religion) }
        if s.why.contains(.medical) { p.append(.medical) }
        if s.why.contains(.allergy) { p += [.allergens, .severity] }
        p.append(.avoid)
        if s.why != [.dislike] { p.append(.strict) }
    }
    if s.goals.contains(.numbers) { p += [.source, .phase, .targets] }
    if s.household == .family && s.personIndex < s.team.count { p.append(.nextPerson) }
    else { p += [.region, .store] }
    if !s.goals.isEmpty { p.append(.depth) }
    if s.depth == .more { p.append(.prefs) }
    p.append(.summary)
    return p
}
```

## Validation (Continue is enabled when)

| Step | Valid when |
|---|---|
| household | a choice is made |
| firstprofile | the first name is not empty |
| goal | at least one ticked |
| why | at least one ticked |
| allergens | at least one allergen (after removing the ones a diet covers) |
| medical | at least one ticked |
| source | a choice |
| phase | at least one |
| region | a 5-digit US ZIP is set (from location or search) |
| store | a store is picked, or "Set up later" (the store is optional) |
| depth | a choice |
| everything else | always |

**Skip** is shown on optional steps. It jumps toward the summary, but **never past the region**: if the ZIP is missing, Skip lands on the region step. Skip is hidden on region, goal and summary. On the store step it reads **"Set up later"**.

## The per-person loop (My family)

- `team` holds the other names entered on `firstprofile`. `pi` is whose turn it is (0 = the first person).
- On `nextperson`, Continue snapshots this person's answers (`goals, why, allergens, sev, medical, diet, avoid, custom, may, source, phases, protein, kcal, notes`) into `doneP`, clears them, increments `pi` and goes back to `goal` with titles that name the next person ("What should I check for Leo?").
- `others` (from the strict step: "Same allergies for anyone else?") get a copy of this person's allergies without answering again. The summary shows "Same for Dad".
- Region and store come after the last person.

## Rules that shape the answers

- **Diet covers allergens** (`catalog.onboarding.dietCovers`): vegan hides milk, egg and fish from the allergen list; vegetarian hides fish. The footnote says so: "Already covered by your vegan diet: milk, egg, fish and shellfish." See open question Q3.
- **Peanut suggests related allergens:** picking Peanut shows a sheet suggesting Tree nuts and Lupin. **Never pre-ticked.**
- **Groups open in place:** Tree nuts and Fish and shellfish open into leaves; "All tree nuts" selects the group; any subset becomes `leaves`.
- **Search knows other names:** `catalog.onboarding.searchSynonyms` maps "prawns" → Fish and shellfish, "whey" → Milk, "tahini" → Sesame. Matching groups open automatically.
- **Severity per allergen** (D3): Allergy (default) or Intolerance. Allergy reads "Avoid it, and “may contain” too", Intolerance "Only when it’s in the ingredients".
- **"May contain" switch** (strict step): on by default when any allergen is Allergy or celiac is picked. Shows "On because of your answers."
- **Avoid or Prefer not** (D12): groups from the "Anything else" step are Avoid, unless the only reason is "dislike", then Prefer not. The summary badge flips each one.
- **Medical "Something else" and religion "Other"** take free text. The chat agent turns it into a custom rule later, with a confirm.
- **Targets** are prefilled from the goals: lose fat 160 g / 1,900 kcal, maintain 140 / 2,300, build muscle 170 / 2,800, both lose and build 170 / 2,200. Steppers move ±5 g and ±100 kcal.

## Progress

Three dots (sections): 0 Who you shop for (household, firstprofile, nextperson), 1 Their allergies (everything per person), 2 Where you shop (region, store, depth, prefs, summary). The progress value never moves backwards.

## Output

`Household { people: [Person { name, isOwner, profile }], region, store }` saved to SwiftData. `Profile` maps 1:1 to `LabelSageCore.Profile`:

| Answer | Profile field |
|---|---|
| allergens + severity + leaves | `allergens: [AllergenChoice]` |
| strict switch | `mayContain` |
| medical (celiac, heart, sugar) | `medical` |
| diet + religion | `diets` |
| "Anything else" groups and Avoid/Prefer not | `avoid: [AvoidChoice]` |
| catalog picks and custom filters | `custom: [CustomChoice]` (terms confirmed) |
| targets | `goals` |
