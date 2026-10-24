# Verdict engine

The heart of the app. Pure, deterministic, offline, tested. Implemented twice so they check each other:

- `tools/reference_engine.py`: the runnable spec (45/45 cases pass).
- `LabelSageCore/Sources/LabelSageCore/`: the Swift port the app uses (`VerdictEngine`, `LabelParser`, `Catalog`, `Copy`).

The cases are in `data/verdict-cases.json`. Every behavior below has at least one case.

## Inputs

- **Product:** `ingredientsText` as printed (nil = no list yet), optional `containsStatement` and `mayContainStatement` when the source keeps them apart, `nutrition` per serving.
- **Household:** people, each with a `Profile` (allergens with severity and leaves, the "may contain" switch, medical, diets, avoid groups with Avoid or Prefer not, custom terms, goals).
- **Catalog** (`data/catalog.json`): families of ingredients and the names they hide under.

## 1. Parse the label (`LabelParser`)

1. Fold the text: lowercase, strip accents, unify quotes, `&` → "and".
2. Split into sentences on `.` or a newline at bracket depth 0 (not inside "2.5%").
3. A sentence with a **may contain marker** ("may contain", "made in a facility that also processes", "made on shared equipment with"…) → its items go to `mayContain`.
4. A sentence starting with **"contains"** (but not "contains 2% or less of") → its items go to `contains`.
5. Every other sentence is the ingredient list: split on `,` and `;` at depth 0. Each item gets a 1-based **index**. "contains 2% or less of:" in front of an item is dropped. **Sub-ingredients** in brackets ("chocolate chips (sugar, cocoa butter, milkfat)") are parsed too and **share the parent's index**.
6. Every item is normalized for matching: words of `[a-z0-9']`, single spaces, padded with a space on each side (" whey protein concentrate ").

## 2. Expand the profile into rules

| Profile | Rules |
|---|---|
| Allergen (or chosen leaves of a group), severity Allergy | Avoid, kind `allergy`, `mayContain` = the person's switch |
| Allergen, severity Intolerance | Avoid, kind `intolerance`, never "may contain" |
| Medical celiac | Avoid gluten, kind `medical`, `mayContain` = the switch |
| Medical heart / blood sugar | daily limits: sodium 1,500 mg, added sugar 25 g |
| Diet (vegan, vegetarian, pescatarian, keto, paleo) | Avoid the diet's families (`catalog.diets`), kind `diet`; keto also net carbs 20 g a day |
| Religion (halal, kosher, no beef) | Avoid the families, kind `religion` |
| "Anything else" group | its strength (Avoid or Prefer not), kind `preference` |
| Custom ("cilantro") | its confirmed terms and strength |

A group rule (tree nuts, fish and shellfish) matches every child's terms. A leaf rule (only almond) matches only that leaf.

## 3. Match a family in a phrase (`Catalog.match`)

1. Collect the family's terms and look-alikes (`notTerms`) from the family and all its children.
2. **Blank out look-alikes first**, longest first: "cocoa butter", "peanut butter" for milk; "eggplant" for egg; "nutmeg", "coconut", "water chestnut" for tree nuts; "buckwheat" and other flours for wheat.
3. Find terms with word boundaries, **longest first, ties alphabetical** (so both engines pick the same term). Each term also matches its simple plural (+s).
4. Skip a match followed by "free" ("gluten free", "dairy free").
5. Return the **owner family** of the matched term and the matched words. The owner names the hidden form: "praline" is owned by almond, "whey" by milk.

## 4. Evaluate one person

For each rule, stop at the first hit:

1. **Ingredients, then the Contains line** → Avoid: **Not for**; Prefer not: **Check first**. Record the index.
2. **May contain** (only kinds `allergy` and `medical`) → switch on: **Not for**; switch off: **Check first**. (Open question Q2.)
3. **Ambiguous terms** (only Avoid rules): if an ingredient is a term whose source the label doesn't say, and it could be one of this rule's families (or a parent), the result is **Can’t confirm** with the term's reason. Examples: "natural flavors" (could hide gluten, celery, mustard, lupin, corn), "spices" (celery, mustard), "lecithin" (soy, egg), "modified food starch" (wheat, gluten, corn), "oats" (gluten, unless "gluten-free oats"), "gelatin" (pork, unless "fish gelatin" or "beef gelatin"), "mono and diglycerides" (meat, pork), "enzymes" or "rennet" (meat). **US major allergens are resolved by a Contains statement**: if the label has one and the ambiguity is only about US majors, it isn't flagged, because the law requires them to be declared there.

Then for the whole person:

4. **No ingredient list** (and any rule or limit) → **Can’t confirm**: "No ingredient list for this one yet."
5. **Daily limits** per serving: missing value → **Can’t confirm** ("No sodium value on the label."); value over `perDay × servingShare` (0.2) → **Check first** ("690 mg sodium per serving."). (Q4.)

The person's level is the worst finding (`notFor` > `cantConfirm` > `checkFirst` > `ok`). Findings are sorted worst first, then by ingredient position, then in the order found.

## 5. Words (`Copy`)

| Finding | Line |
|---|---|
| OK | "OK for Mia. Nothing Mia avoids is in it." · "OK for you. Nothing you avoid is in it." |
| Allergy / intolerance / medical, term is the family name | "Not for Mia. Contains peanuts." |
| Allergy / medical, hidden form | "Not for Mia. Contains whey: that’s milk." · "Not for you. Contains malt extract: that’s gluten." |
| May contain, switch on | "Not for Mia. May contain peanuts." |
| May contain, switch off | "Check first: says ‘may contain peanuts’." |
| Diet or religion | "Not for you: whey isn’t vegan." · "Not for Sam: pork gelatin isn’t halal." · "Not for you: shrimp isn’t kosher." |
| Preference, Avoid | "Not for you: sunflower oil is a seed oil." · "Not for you. Contains palm oil." |
| Preference, Prefer not | "Check first: cane sugar is an added sugar." |
| Ambiguous | "Can’t confirm. ‘Natural flavors’ isn’t specific." |
| No list | "Can’t confirm. No ingredient list for this one yet." |
| Limit | "Check first: 690 mg sodium per serving." |

**Household line**, worst first: "Not for Mia · OK for you", "Check first for you · OK for Mia", "OK for you and Mia", "OK for everyone" (3+ people all OK), "Can’t confirm" (everyone). The owner is "you".

**Position:** `Copy.position(2)` → "the 2nd ingredient", used by the writer ("Sunflower oil is the 2nd ingredient, so it’s not for you.").

## 6. What the engine never does

- Never says "safe", never promises an outcome.
- Never guesses: a missing fact is Can’t confirm, never OK.
- Never uses the network or the model.
- Never changes a profile. Per-check rule switches on the product page are passed in as a modified copy of the household.

## Extending it

1. Add a case to `data/verdict-cases.json` with the expected level and line.
2. Update `data/catalog.json` (terms, notTerms, ambiguous) or the engine.
3. `sh tools/sync-data.sh`: both engines must pass.
4. Clinical changes need the review in Q7.
