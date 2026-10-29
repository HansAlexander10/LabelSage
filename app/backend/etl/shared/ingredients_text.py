"""Ingredient-text checks shared by the build and the scan-time lookup: language and quality.

A list that is unreadable (scanned text broken into fragments, a code such as "RH-30") is as risky as a missing
one, so a list that fails the quality gate is treated as missing: the app shows "Can't confirm".
"""
import re

# common function and ingredient words per language; a list's language is the one with more hits
LANGUAGE_MARKERS = {
    "id": {"dan", "garam", "gula", "air", "minyak", "tepung", "mengandung", "pengemulsi", "penstabil", "perisa",
           "pewarna", "bahan", "susu", "telur", "kedelai", "terigu", "bawang", "rempah", "penguat", "rasa",
           "pengawet", "pengental", "sayur", "nabati", "bubuk", "ekstrak", "alami", "identik", "kacang"},
    "en": {"and", "salt", "sugar", "water", "oil", "flour", "contains", "emulsifier", "stabilizer", "flavor",
           "flavour", "color", "colour", "ingredients", "milk", "egg", "soy", "wheat", "onion", "spices", "natural",
           "vegetable", "powder", "extract", "acid", "corn", "starch", "syrup", "less", "than", "of"},
    # other label languages: the app's engine cannot read them yet, so their lists stay off the phone
    "fr": {"et", "sucre", "sel", "lait", "farine", "huile", "eau", "beurre", "oeufs", "blé", "arôme", "arômes",
           "sirop", "poudre", "végétale", "végétales", "graisse", "levure", "crème", "fromage", "contient", "peut"},
    "es": {"azúcar", "sal", "leche", "harina", "aceite", "agua", "trigo", "huevo", "contiene", "puede", "aceites",
           "vegetal", "jarabe", "almidón", "saborizante", "colorante", "conservador", "soya", "polvo", "manteca"},
    "it": {"zucchero", "latte", "farina", "olio", "acqua", "frumento", "uova", "aromi", "oliva", "vergine",
           "extra", "burro", "contiene", "tracce", "grano", "semi", "lievito", "amido"},
    "de": {"und", "zucker", "salz", "milch", "mehl", "wasser", "weizen", "eier", "enthält", "spuren", "pflanzliche",
           "pflanzliches", "butter", "sahne", "hefe", "aroma", "kann"},
}
UNREADABLE_LANGUAGES = ("fr", "es", "it", "de")   # lists in these languages are hidden on the phone
MIN_KNOWN_SHARE = 0.7   # placeholder: share of words that must be known ingredient words (team decision)


# ------ PHASE 1: LANGUAGE --------

def words(text):
    """Lowercase words of two letters or more, accents kept."""
    return re.findall(r"[a-zà-ÿ]{2,}", (text or "").lower())


def language(text):
    """'id', 'en' or 'other', by counting marker words of each language."""

    # job 1: count marker hits per language
    tokens = words(text)
    hits = {lang: sum(t in markers for t in tokens) for lang, markers in LANGUAGE_MARKERS.items()}

    # job 2: the language with more hits wins; no hits at all is 'other'
    best = max(hits, key=hits.get)
    return best if hits[best] > 0 else "other"


# ------ PHASE 2: QUALITY GATE --------

def looks_ok(text, vocabulary):
    """True when the text reads like an ingredient list: mostly words seen across many other lists.

    `vocabulary` is the set of words that appear in many ingredient lists of the whole catalog (built by the
    transform), so broken scanned text ("olycerdes", "rižino", "c tain") falls below MIN_KNOWN_SHARE.
    """

    # job 1: no real word, no list ("RH-30" has only "rh", "100g" only "g")
    tokens = words(text)
    if not any(len(t) >= 3 for t in tokens):
        return False

    # job 2: short lists ("Water", "Susu sapi segar") must be all known words; longer ones mostly known
    known = sum(t in vocabulary for t in tokens) / len(tokens)
    return known == 1.0 if len(tokens) < 3 else known >= MIN_KNOWN_SHARE


# ------ PHASE 3: THE KNOWN-WORD VOCABULARY --------

def draft_terms():
    """Every word of the Indonesian allergen draft, so Indonesian lists are judged with Indonesian words too."""
    import json
    import pathlib
    data = json.loads((pathlib.Path(__file__).parent / "allergen-terms-id.draft.json").read_text())
    terms = []
    for family in data["families"]:
        terms += family.get("regulation", []) + family.get("proposed", []) + family.get("notTerms", [])
    for group in ("containsMarkers", "mayContainMarkers"):
        terms += data[group]["regulation"] + data[group]["proposed"]
    return {w for term in terms for w in words(term)} | LANGUAGE_MARKERS["id"]
