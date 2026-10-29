"""Recipe-change check: do two ingredient lists (FDC and Open Food Facts) describe different recipes?

Additives, vitamins, minerals and wording do not change the recipe. Different allergen words, or fewer than
80% shared food words, do. A changed recipe keeps FDC's nutrients but is flagged and gets lower confidence,
because the nutrients may belong to the old recipe.
"""
import re

RECIPE_SIMILARITY = 0.8  # placeholder: share of food words both lists must have in common (team decision)

# additives, vitamins, minerals and preservative wording: not part of the recipe
NOT_FOOD = re.compile(r"vitamin|mineral|tocopherol|ascorb|phosphate|carbonate|niacin|thiamin|riboflavin|folic|"
                      r"pyridox|palmitate|mononitrate|\biron\b|\bzinc\b|preserve|freshness|\be\d{3}[a-z]?\b|"
                      r"citric acid|colou?r|flavou?r", re.I)
FILLER_WORDS = {"and", "or", "of", "contains", "less", "than", "ingredients", "added", "to", "the", "a", "from"}
# a first word list per US major allergen and gluten; LabelSageCore holds the reviewed lists on the phone
ALLERGEN_WORDS = {
    "milk": ("milk", "whey", "casein", "caseinate", "butter", "cream", "cheese", "lactose", "yogurt"),
    "egg": ("egg", "eggs", "albumin"),
    "fish": ("fish", "anchovy", "salmon", "tuna", "cod"),
    "shellfish": ("shrimp", "crab", "lobster", "prawn"),
    "tree_nuts": ("almond", "cashew", "walnut", "pecan", "hazelnut", "pistachio", "macadamia"),
    "peanut": ("peanut", "peanuts"),
    "wheat": ("wheat", "spelt", "semolina", "durum"),
    "soy": ("soy", "soya", "soybean", "soybeans"),
    "sesame": ("sesame", "tahini"),
    "gluten": ("wheat", "barley", "rye", "malt"),
}
NOT_MILK = re.compile(r"\b(cocoa|peanut|shea|nut) butter\b", re.I)


# ------ PHASE 1: WORDS OF ONE LIST --------

def food_words(ingredients_text):
    """The food words of an ingredient list, without additives, vitamins and minerals."""
    words = set()

    # job 1: split into items and skip the additive ones
    for item in re.split(r"[,;:.()\[\]]", ingredients_text or ""):
        if item.strip() and not NOT_FOOD.search(item):

            # job 2: keep the words of a food item
            words |= set(re.findall(r"[a-z]+", item.lower()))
    return words - FILLER_WORDS


def allergen_families(ingredients_text):
    """Which allergen families the list names, by a first word list."""
    text = NOT_MILK.sub(" ", (ingredients_text or "").lower())
    return {family for family, words in ALLERGEN_WORDS.items()
            if any(re.search(rf"\b{w}\b", text) for w in words)}


# ------ PHASE 2: COMPARE TWO LISTS --------

def recipe_changed(fdc_text, off_text):
    """True when the two lists describe different recipes; False when either is missing."""

    # job 1: nothing to compare without both lists
    a, b = food_words(fdc_text), food_words(off_text)
    if not a or not b:
        return False

    # job 2: different allergens always mean a different recipe
    if allergen_families(fdc_text) != allergen_families(off_text):
        return True

    # job 3: otherwise the share of shared food words decides
    return len(a & b) / len(a | b) < RECIPE_SIMILARITY
