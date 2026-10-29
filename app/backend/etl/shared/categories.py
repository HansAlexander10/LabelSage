"""Categories for Indonesian products that Open Food Facts left without one, from words in the product name.

Most Indonesian products (7,661 of 8,761 on 2026-10-26) have no category. A category only drives "Other options",
never a verdict, so a keyword guess is acceptable; the source is recorded as "name".
"""
import re

# Indonesian (and common English) name words -> Open Food Facts English category names
NAME_KEYWORDS = [
    (r"\b(mie|mi instan|indomie|ramen)\b", "Instant noodles"),
    (r"\bbihun|soun|kwetiau\b", "Noodles"),
    (r"\b(biskuit|biscuit|cookies|crackers?)\b", "Biscuits"),
    (r"\bwafer\b", "Wafers"),
    (r"\b(kerupuk|krupuk)\b", "Crackers"),
    (r"\b(keripik|kripik|chips)\b", "Chips and fries"),
    (r"\b(coklat|cokelat|chocolate)\b", "Chocolates"),
    (r"\b(permen|candy)\b", "Candies"),
    (r"\b(susu|milk)\b", "Milks"),
    (r"\b(yoghurt|yogurt)\b", "Yogurts"),
    (r"\bkeju\b", "Cheeses"),
    (r"\bes krim\b", "Ice creams"),
    (r"\b(kopi|coffee)\b", "Coffees"),
    (r"\b(teh|tea)\b", "Teas"),
    (r"\b(jus|juice)\b", "Juices"),
    (r"\bair mineral\b", "Waters"),
    (r"\b(minuman|drink)\b", "Beverages"),
    (r"\b(kecap|saus|sambal|sauce)\b", "Sauces"),
    (r"\b(bumbu|seasoning)\b", "Seasonings"),
    (r"\bminyak\b", "Vegetable oils"),
    (r"\bgula\b", "Sugars"),
    (r"\bgaram\b", "Salts"),
    (r"\btepung\b", "Flours"),
    (r"\bsirup\b", "Syrups"),
    (r"\bselai\b", "Spreads"),
    (r"\broti\b", "Breads"),
    (r"\bberas\b", "Rices"),
    (r"\bkacang\b", "Nuts"),
    (r"\bsereal|cereal\b", "Breakfast cereals"),
]
_COMPILED = [(re.compile(pattern, re.I), category) for pattern, category in NAME_KEYWORDS]


# ------ PHASE 1: ONE PRODUCT NAME --------

def from_name(name):
    """The first category whose keyword appears in the product name, or None."""

    # job 1: the first matching keyword wins (the list is ordered from specific to general)
    for pattern, category in _COMPILED:
        if pattern.search(name or ""):
            return category
    return None
