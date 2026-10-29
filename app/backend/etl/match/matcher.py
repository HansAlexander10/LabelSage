"""Decide whether an Amazon catalog item is the same product as one of ours.

Three ways a candidate reaches us:
  same_barcode  the Open Food Facts record with the same barcode as an FDC product. The barcode already links them;
                this catches volunteer errors (another product's name or photo under the barcode) before we show
                the OFF photo next to FDC's ingredients. A missing OFF brand is allowed.
  barcode       Amazon lists our barcode on the item (searchCatalogItems by UPC/EAN). Still checked, because sellers
                reuse barcodes and put single flavors on variety packs.
  name_brand    our barcode found nothing, so we searched by name and brand. Stricter thresholds.

Score = 0.30 brand + 0.70 title - penalty, then hard vetoes for allergen-claim conflicts.
A wrong match is worse than a missed one: a missed match only means no Amazon photo.
Weights and thresholds are placeholders until a hand-labelled sample of real pairs exists (team decision).
"""
import re

from shared.barcode import to_gtin14

MATCHER_VERSION = "2026-10-28.5"

WEIGHT_BRAND, WEIGHT_TITLE = 0.30, 0.70
THRESHOLDS = {                       # (accept at or above, review at or above); below review = reject
    "same_barcode": (0.75, 0.60),    # from the tune half of 300 labelled FDC-OFF pairs (2026-10-28)
    "barcode": (0.85, 0.65),
    "name_brand": (0.92, 0.80),
}
MIN_BRAND_NAME_BRAND = 0.90          # name_brand matches also need a near-identical brand


# ------ PHASE 1: WORDS --------

COMPOUND_WORDS = {
    "oatmilk": "oat milk", "almondmilk": "almond milk", "soymilk": "soy milk", "coconutmilk": "coconut milk",
    "peanutbutter": "peanut butter", "glutenfree": "gluten free", "dairyfree": "dairy free", "nonfat": "non fat",
    "lowfat": "low fat", "wholewheat": "whole wheat", "sugarfree": "sugar free",
}

# allergen groups: a claim "X free" names the group, an ingredient word puts the product in it
ALLERGEN_GROUPS = {
    "gluten": {"gluten", "wheat", "barley", "rye", "malt", "spelt", "semolina"},
    "dairy": {"dairy", "lactose", "whey", "casein", "butter", "cream", "cheese", "yogurt", "milkfat"},
    "peanut": {"peanut", "peanuts"},
    "nut": {"nut", "nuts", "almond", "almonds", "cashew", "cashews", "walnut", "walnuts", "pecan", "pecans",
            "hazelnut", "hazelnuts", "pistachio", "pistachios", "macadamia"},
    "soy": {"soy", "soya", "soybean", "soybeans"},
    "egg": {"egg", "eggs"},
    "sesame": {"sesame"},
    "fish": {"fish", "anchovy", "salmon", "tuna"},
    "shellfish": {"shellfish", "shrimp", "crab", "lobster"},
    "sugar": {"sugar"},
}
# "lactose free" is not a claim: lactose-free products still contain milk, so it stays a content word
CLAIM_WORDS = {"gluten": "gluten", "dairy": "dairy", "milk": "dairy", "peanut": "peanut",
               "nut": "nut", "soy": "soy", "egg": "egg", "sesame": "sesame", "sugar": "sugar", "grain": "gluten"}

# words that make two otherwise similar titles different products (allergens, flavors, formulations)
CRITICAL_WORDS = set().union(*ALLERGEN_GROUPS.values()) - {"sugar"} | {
    "milk", "oat", "oats", "mustard", "celery", "lupin", "sulfite",
    "chocolate", "vanilla", "strawberry", "blueberry", "raspberry", "apple", "cinnamon", "honey", "lime", "lemon",
    "natural", "unsweetened", "sweetened", "decaf", "variety", "assorted",
    "reduced", "light", "lite", "diet", "zero",
    # fruit, sweet and savory flavors, and heat levels (a Cherry strudel under a Strawberry strudel's barcode)
    "cherry", "orange", "grape", "peach", "mango", "pineapple", "banana", "coconut", "watermelon", "cranberry",
    "pomegranate", "kiwi", "pear", "apricot", "plum", "berry", "caramel", "butterscotch", "toffee", "mint",
    "peppermint", "spearmint", "coffee", "mocha", "espresso", "maple", "pumpkin", "ginger", "cola",
    "bbq", "barbecue", "ranch", "cheddar", "jalapeno", "buffalo", "garlic", "onion", "teriyaki", "chipotle",
    "original", "hot", "mild", "spicy",
}

# product variants: a word on one side only means another product of the same brand (organic vs plain oats,
# colby vs colby jack, cream cheese vs whipped). From the false accepts on the golden set (match/benchmark.py,
# 2026-10-28). Kept apart from CRITICAL_WORDS so golden_set.py's flavor flag, and so its sample, stays the same.
VARIANT_WORDS = {"organic", "jack", "whipped", "shaved", "string", "powder", "popcorn", "soup", "sandwich",
                 "skinless", "layered", "fat", "herb", "healthy", "citrus"}
# the only brand words that name a variant ("Diet Sierra Mist" vs "Sierra Mist"); other brand words are company
# names ("Simple Truth Organic", "Cedarlane Natural Foods") and say nothing about the product
BRAND_VARIANT_WORDS = {"diet", "zero", "light", "lite", "decaf"}

# label claims that say nothing about which product it is; left out of the title score
MARKETING_WORDS = {"vegan", "kosher", "non", "gmo", "certified"}

# plant words before a dairy word make it not dairy: "almond milk", "cocoa butter", "coconut cream"
PLANT_DAIRY = re.compile(r"\b(almond|oat|soy|rice|coconut|cashew|hemp|pea|flax|macadamia|cocoa|peanut|nut|apple|shea|"
                         r"seed|sunflower|cookie|body) (milk|cream|cheese|butter|yogurt)\b")
# a title with one of these describes a dairy alternative: its "cheese" or "cream" is not dairy
PLANT_MARKERS = {"plant", "vegan", "alternative", "nondairy"}

LEGAL_SUFFIXES = re.compile(r"\b(the|inc|llc|ltd|co|corp|corporation|company)\b")
CLAIM = re.compile(r"\b(\w+) free\b|\bno (\w+)(?: added)?\b|\bwithout (\w+)\b")


def words(text):
    """Lowercase words with food compounds split ("Oatmilk" -> "oat", "milk") and hyphens as spaces."""

    # job 1: lowercase, drop apostrophes ("bob's" -> "bobs"), everything else not a letter or digit is a space
    t = re.sub(r"['’]", "", (text or "").lower())
    t = re.sub(r"[^a-z0-9]+", " ", t)

    # job 2: split the compounds
    for compound, split in COMPOUND_WORDS.items():
        t = re.sub(r"\b" + compound + r"\b", split, t)
    return t.split()


def claims_and_contents(text):
    """Split a title into its free-from claims ({"gluten"}) and the words left once claims are removed."""
    joined = " ".join(words(text))
    claims = set()

    # job 1: "gluten free", "no sugar added", "without dairy" become claims; their words leave the text
    for match in CLAIM.finditer(joined):
        word = next(w for w in match.groups() if w)
        if word in CLAIM_WORDS:
            claims.add(CLAIM_WORDS[word])
    rest = CLAIM.sub(lambda m: " " if next(w for w in m.groups() if w) in CLAIM_WORDS else m.group(0), joined)

    # job 2: what is left counts as content ("contains gluten" keeps "gluten")
    return claims, rest.split()


def singular(word):
    """Plural to singular for comparing critical words: "oats" -> "oat", "peanuts" -> "peanut"."""
    return word[:-1] if len(word) > 3 and word.endswith("s") and not word.endswith("ss") else word


def groups_in(tokens, title=False):
    """Allergen groups named by a list of words. Plant dairy words ("almond milk") do not count; in a title,
    no dairy word counts when the title describes a dairy alternative ("cream cheese alternative")."""

    # job 1: drop the dairy word of plant phrases
    text = PLANT_DAIRY.sub(lambda m: m.group(1), " ".join(tokens))
    words_ = set(text.split())

    # job 2: groups whose words appear
    groups = {group for group, members in ALLERGEN_GROUPS.items() if members & words_}
    if title and (words_ & PLANT_MARKERS or "non dairy" in text):
        groups.discard("dairy")
    return groups


def clean_brand(brand):
    """Lowercase brand without legal suffixes and punctuation: "Bob's Red Mill, Inc." -> "bobs red mill"."""
    return " ".join(LEGAL_SUFFIXES.sub(" ", " ".join(words(brand))).split())


# ------ PHASE 2: SIMILARITY --------

def levenshtein(a, b):
    """Edit distance between two strings."""
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def ratio(a, b):
    """1.0 for equal strings, 0.0 for nothing in common."""
    if not a or not b:
        return 0.0
    return 1.0 - levenshtein(a, b) / max(len(a), len(b))


def jaro_winkler(a, b, prefix_scale=0.1):
    """Jaro-Winkler similarity: rewards a shared start, good for brand names."""

    # job 1: matching characters within the window, then half the transpositions
    if a == b:
        return 1.0
    if not a or not b:
        return 0.0
    window = max(len(a), len(b)) // 2 - 1
    a_hit, b_hit = [False] * len(a), [False] * len(b)
    matches = 0
    for i, ca in enumerate(a):
        for j in range(max(0, i - window), min(i + window + 1, len(b))):
            if not b_hit[j] and b[j] == ca:
                a_hit[i] = b_hit[j] = True
                matches += 1
                break
    if matches == 0:
        return 0.0
    a_chars = [c for c, hit in zip(a, a_hit) if hit]
    b_chars = [c for c, hit in zip(b, b_hit) if hit]
    transpositions = sum(x != y for x, y in zip(a_chars, b_chars)) / 2
    jaro = (matches / len(a) + matches / len(b) + (matches - transpositions) / matches) / 3

    # job 2: up to four shared leading characters raise the score
    prefix = 0
    for x, y in zip(a[:4], b[:4]):
        if x != y:
            break
        prefix += 1
    return jaro + prefix * prefix_scale * (1 - jaro)


def brand_score(our_brand, amazon_brand, amazon_title):
    """Brand similarity, or None when either side has no brand."""
    ours, theirs = clean_brand(our_brand), clean_brand(amazon_brand)
    if not ours:
        return None

    # job 1: Amazon left the brand empty: the brand written inside the title counts
    title = " " + " ".join(words(amazon_title)) + " "
    if not theirs:
        return 0.92 if f" {ours} " in title else None

    # job 2: same brand, or one is the other plus words ("califia" / "califia farms"), whole words only
    score = jaro_winkler(ours, theirs)
    if ours == theirs or f" {ours} " in f" {theirs} " or f" {theirs} " in f" {ours} ":
        score = max(score, 0.98)
    elif f" {ours} " in title:
        score = max(score, 0.92)
    return score


def title_score(our_name, amazon_title):
    """75 % token-set ratio (extra Amazon words cost little) + 25 % token-sort ratio.

    Free-from claims and marketing words are left out here; conflicts() judges the claims.
    """

    # job 1: the words that name the product
    ours = [w for w in claims_and_contents(our_name)[1] if w not in MARKETING_WORDS]
    theirs = [w for w in claims_and_contents(amazon_title)[1] if w not in MARKETING_WORDS]
    a, b = set(ours), set(theirs)
    if not a or not b:
        return 0.0

    # job 2: token set: the shared words compared with each side's full word list
    shared = " ".join(sorted(a & b))
    a_full = " ".join(sorted(a & b) + sorted(a - b))
    b_full = " ".join(sorted(a & b) + sorted(b - a))
    token_set = max(ratio(x, y) for x, y in ((shared, a_full), (shared, b_full), (a_full, b_full)) if x and y)

    # job 3: token sort: all words, sorted
    token_sort = ratio(" ".join(sorted(ours)), " ".join(sorted(theirs)))
    return 0.75 * token_set + 0.25 * token_sort


# ------ PHASE 3: CONFLICTS --------

def conflicts(our_name, amazon_title, our_ingredients=None, amazon_ingredients=None, method="barcode", brands=(None, None)):
    """Penalty, veto flag and reasons from allergen claims and critical words.

    same_barcode: a critical or allergen word on one side only is a shorter name, not a different product
    ("ORGANIC ALMONDMILK, VANILLA" vs "Organic Almondmilk"; "PIZZA, 5 CHEESE" vs "Pizza"); only critical words
    on both sides that differ (vanilla vs chocolate) cost points. Amazon methods keep the stricter rule
    (Jif vs Jif Natural).
    """
    reasons, veto = [], False
    our_claims, our_words = claims_and_contents(our_name)
    amz_claims, amz_words = claims_and_contents(amazon_title)

    # job 1: what each product contains: its title words outside claims, plus its ingredient list when we have one
    #        (a title's own "dairy free" makes its "cream cheese" not dairy)
    our_title, amz_title = groups_in(our_words, title=True) - our_claims, groups_in(amz_words, title=True) - amz_claims
    our_groups = our_title | groups_in(claims_and_contents(our_ingredients)[1] if our_ingredients else [])
    amz_groups = amz_title | groups_in(claims_and_contents(amazon_ingredients)[1] if amazon_ingredients else [])

    # job 2: veto: one side says "X free", the other contains X ("gluten free oats" vs "contains gluten")
    for group in sorted((our_claims & amz_groups) | (amz_claims & our_groups)):
        reasons.append(f"claim_conflict:{group}")
        veto = True

    # job 3: a claim on one side only: allowed (Amazon titles add "Dairy-Free, Vegan"), but without our
    #        ingredient list to check it against, it stays in review
    one_sided = sorted(our_claims ^ amz_claims)
    for group in one_sided:
        reasons.append(f"claim_one_side:{group}")
    needs_review = bool(one_sided) and not our_ingredients

    # job 4: critical and variant words (singular form) that differ ("blueberry" vs "raspberry"). Title words in
    #        a brand do not count ("ranch" in "California Olive Ranch"); a diet word in one brand only does count
    #        for that side ("Diet Sierra Mist" vs "Sierra Mist")
    our_brand, amz_brand = set(words(brands[0])), set(words(brands[1]))
    brand_words = our_brand | amz_brand
    watched = CRITICAL_WORDS | VARIANT_WORDS
    ours = {singular(w) for w in our_words if w in watched and w not in brand_words}
    theirs = {singular(w) for w in amz_words if w in watched and w not in brand_words}
    if our_brand and amz_brand:
        ours |= (our_brand - amz_brand) & BRAND_VARIANT_WORDS
        theirs |= (amz_brand - our_brand) & BRAND_VARIANT_WORDS
    if method == "same_barcode":
        diff = (ours - theirs) | (theirs - ours) if ours - theirs and theirs - ours else set()
        one_sided = (our_title ^ amz_title) - {"sugar"}
        if one_sided and not diff:
            reasons.append("allergen_one_side:" + ",".join(sorted(one_sided)))   # logged, no points
    else:
        diff = ours ^ theirs

        # job 5: "sugar free" on one side only may be another product (chocolate syrup vs sugar free chocolate
        #        syrup) or a title that leaves it out (Trident gum): a person decides
        if "sugar" in our_claims ^ amz_claims:
            needs_review = True
    penalty = 0.35 if len(diff) >= 2 else 0.20 if diff else 0.0
    if diff:
        reasons.append("critical_words:" + ",".join(sorted(diff)))
    return penalty, veto, needs_review, reasons


# ------ PHASE 4: DECIDE --------

def score_pair(ours, amazon, method):
    """Score one (our product, Amazon item) pair.

    ours:   a match_input row: {"gtin", "name", "brand", "brand_owner"(optional), "ingredients"(optional)}
    amazon: {"asin", "item_name", "brand", "gtins"(set of GTIN-14), "ingredients"(optional)}
    method: "same_barcode", "barcode" or "name_brand"
    """
    reasons = []

    # job 1: a barcode match must really list our barcode (GTIN-14 on both sides)
    gtin = to_gtin14(ours.get("gtin"))
    if method in ("same_barcode", "barcode") and (gtin is None or gtin not in amazon.get("gtins", set())):
        return {"brand_score": None, "title_score": 0.0, "penalty": 0.0, "confidence": 0.0,
                "tier": "reject", "reasons": ["barcode_not_listed"]}

    # job 2: brand (ours, or FDC's brand owner when that fits better: "Kellanova" for Pringles) and title similarity
    brands = [brand_score(ours.get(key), amazon.get("brand"), amazon.get("item_name")) for key in ("brand", "brand_owner")]
    b = max((x for x in brands if x is not None), default=None)
    t = title_score(ours.get("name"), amazon.get("item_name"))
    if b is None:
        reasons.append("brand_missing")

    # job 3: conflicts
    penalty, veto, needs_review, conflict_reasons = conflicts(
        ours.get("name"), amazon.get("item_name"), ours.get("ingredients"), amazon.get("ingredients"), method,
        (ours.get("brand"), amazon.get("brand")))
    reasons += conflict_reasons

    # job 4: confidence; a missing brand counts as half a match, except on the same barcode, where the
    #        title alone decides (Open Food Facts often has no brand)
    if b is None and method == "same_barcode":
        base = t
    else:
        base = WEIGHT_BRAND * (b if b is not None else 0.5) + WEIGHT_TITLE * t
    confidence = 0.0 if veto else max(0.0, min(1.0, base - penalty))

    # job 5: tier by method; a one-sided claim, a missing brand (except on the same barcode), a weak
    #        name_brand brand, or an allergen on one side with no brand to confirm it caps it at review
    #        (trail mix with nuts vs a "dried cranberries" record)
    accept_at, review_at = THRESHOLDS[method]
    tier = "accept" if confidence >= accept_at else "review" if confidence >= review_at else "reject"
    allergen_unconfirmed = b is None and any(r.startswith("allergen_one_side:") for r in reasons)
    capped = (needs_review or allergen_unconfirmed or (b is None and method != "same_barcode")
              or (method == "name_brand" and (b is None or b < MIN_BRAND_NAME_BRAND)))
    if tier == "accept" and capped:
        tier = "review"
    if veto:
        tier = "reject"
    return {"brand_score": None if b is None else round(b, 4), "title_score": round(t, 4),
            "penalty": round(penalty, 4), "confidence": round(confidence, 4), "tier": tier, "reasons": reasons}


def pick_best(scored):
    """Choose one ASIN for a barcode from its scored candidates, or None.

    scored: list of (amazon item dict, score dict). Accepted candidates only; when two accepted candidates differ
    in critical words (a single flavor and a variety pack under one barcode), nobody wins and all go to review.
    """

    # job 1: accepted candidates, best first; ties go to single packs (package_quantity 1 or unknown)
    accepted = sorted((pair for pair in scored if pair[1]["tier"] == "accept"),
                      key=lambda p: (-p[1]["confidence"], (p[0].get("package_quantity") or 1) != 1))
    if not accepted:
        return None

    # job 2: disagreeing winners: no pick
    first_words = set(words(accepted[0][0].get("item_name"))) & (CRITICAL_WORDS | VARIANT_WORDS)
    for item, score in accepted[1:]:
        if set(words(item.get("item_name"))) & (CRITICAL_WORDS | VARIANT_WORDS) != first_words:
            for _, s in accepted:
                s["tier"] = "review"
                s["reasons"].append("ambiguous_candidates")
            return None
    return accepted[0]
