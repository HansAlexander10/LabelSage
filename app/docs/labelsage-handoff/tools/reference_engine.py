#!/usr/bin/env python3
"""LabelSage verdict engine, reference implementation.

This is the executable spec for LabelSageCore (Swift). It reads data/catalog.json
and runs data/verdict-cases.json. The Swift engine must give the same levels and
the same reason lines for every case.

Run:  python3 -I tools/reference_engine.py            (all cases)
      python3 -I tools/reference_engine.py --verbose  (print every line)
"""
import json, re, sys, unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS = ["ok", "checkFirst", "cantConfirm", "notFor"]  # worst last
RANK = {l: i for i, l in enumerate(LEVELS)}
NUTRIENT = {"sodiumMg": ("sodium", "mg"), "addedSugarsG": ("added sugar", "g"), "netCarbsG": ("net carbs", "g")}
SERVING_SHARE = 0.2  # a serving over 20% of a daily limit is "Check first" (FDA: 20% DV or more is high)


# ---------------------------------------------------------------- text
def fold(s):
    s = unicodedata.normalize("NFKD", s.lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    return s.replace("’", "'").replace("‘", "'").replace("&", " and ")


def norm(s):
    """Phrase form used for matching: lowercase words separated by one space, padded."""
    s = fold(s)
    s = re.sub(r"[^a-z0-9']+", " ", s)
    s = re.sub(r"'(?![a-z])|(?<![a-z])'", " ", s)   # keep brewer's, drop stray quotes
    return " " + " ".join(s.split()) + " "


def variants(term):
    t = norm(term).strip()
    out = [t]
    if not t.endswith("s"):
        out.append(t + "s")
    return out


# ---------------------------------------------------------------- label parsing
def split_depth0(s, seps=",;"):
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        if ch in seps and depth == 0:
            parts.append(cur); cur = ""
        else:
            cur += ch
    parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def sentences(s):
    """Split on '.' or newline at depth 0, but not inside numbers (2.5%)."""
    out, depth, cur = [], 0, ""
    for i, ch in enumerate(s):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        if depth == 0 and (ch == "\n" or (ch == "." and not (i > 0 and s[i - 1].isdigit() and i + 1 < len(s) and s[i + 1].isdigit()))):
            out.append(cur); cur = ""
        else:
            cur += ch
    out.append(cur)
    return [x.strip() for x in out if x.strip()]


LESS_THAN = re.compile(r"^(and |contains )?(\d+(\.\d+)?\s*% or less of|less than \d+(\.\d+)?\s*% of)\s*:?\s*")


def parse_items(s, index_start, parent=None):
    """Top-level items get an index (1-based); sub-ingredients share the parent's index."""
    items, idx = [], index_start
    for part in split_depth0(s):
        part = LESS_THAN.sub("", part.strip())
        m = re.match(r"^(.*?)[\(\[\{](.*)[\)\]\}]\s*\**$", part, re.S)
        head, inner = (m.group(1).strip(), m.group(2)) if m else (part, None)
        head = head.strip(" *:")
        if head:
            items.append({"index": idx, "text": head, "parent": parent})
        if inner:
            for sub in parse_items(inner, idx, parent=head or parent)[0]:
                sub["index"] = idx
                items.append(sub)
        idx += 1
    return items, idx


def statement_items(s):
    s = re.sub(r"\btraces? of\b|\bother\b|\bproducts?\b|\bingredients?\b", " ", s)
    out = []
    for p in split_depth0(s, ",;"):
        for q in re.split(r"\band\b|\bor\b|/", p):
            q = q.strip(" :.*")
            if q:
                out.append(q)
    return out


def parse_label(product, cat):
    text = product.get("ingredientsText") or ""
    label = {"ingredients": [], "contains": [], "mayContain": [], "hasContains": False}
    for extra, key in ((product.get("containsStatement"), "contains"), (product.get("mayContainStatement"), "mayContain")):
        if extra:
            label[key] += statement_items(fold(extra).replace("contains", "", 1) if key == "contains" else fold(extra))
            if key == "contains":
                label["hasContains"] = True
    may_markers = sorted((fold(m) for m in cat.d["mayContainMarkers"]), key=len, reverse=True)
    idx = 1
    for sent in sentences(fold(text)):
        s = re.sub(r"^ingredients?\s*:?\s*", "", sent.strip())
        low = s.lower()
        hit = next((m for m in may_markers if m in low), None)
        if hit:
            label["mayContain"] += statement_items(low.split(hit, 1)[1])
            continue
        if re.match(r"^contains\b(?!\s*\d)(?!\s+less)", low):
            label["contains"] += statement_items(re.sub(r"^contains\s*:?", "", low))
            label["hasContains"] = True
            continue
        items, idx = parse_items(s, idx)
        label["ingredients"] += items
    for it in label["ingredients"]:
        it["norm"] = norm(it["text"])
    label["containsNorm"] = [norm(x) for x in label["contains"]]
    label["mayNorm"] = [norm(x) for x in label["mayContain"]]
    return label


# ---------------------------------------------------------------- catalog helpers
class Catalog:
    def __init__(self, d):
        self.d = d
        self.fam = {f["id"]: f for f in d["families"]}
        self.majors = set(d["usMajorAllergens"])

    def expand(self, fid):
        """A family plus all its children (a group matches every child)."""
        f = self.fam[fid]
        out = [f]
        for c in f.get("children", []):
            out += self.expand(c)
        return out

    def ancestors(self, fid):
        out, f = [], self.fam.get(fid)
        while f and f.get("parent") in self.fam:
            out.append(f["parent"]); f = self.fam[f["parent"]]
        return out

    def match(self, fid, phrase):
        """First term of family fid (or its children) found in the normalized phrase.
        Returns (id of the family that owns the term, matched words) or None. Longest term wins."""
        fams = self.expand(fid) if fid in self.fam else []
        nots = set()
        for f in fams:
            nots.update(f.get("notTerms", []))
        q = phrase
        for nt in sorted(nots, key=lambda x: (-len(x), x)):
            for v in variants(nt):
                while " " + v + " " in q:
                    q = q.replace(" " + v + " ", " # ")
        # longest term first; ties by alphabet so every implementation picks the same one
        terms = sorted(((t, f["id"]) for f in fams for t in f["terms"]), key=lambda x: (-len(x[0]), x[0]))
        for t, owner in terms:
            for v in variants(t):
                for m in re.finditer(re.escape(" " + v + " "), q):
                    after = q[m.end():].split(" ", 1)[0]
                    if after in self.d["negationSuffixes"]:
                        continue
                    return owner, v
        return None


# ---------------------------------------------------------------- rules from a profile
def rules_for(profile, cat):
    rules, limits = [], []
    may = profile.get("mayContain", True)
    for a in profile.get("allergens", []):
        sev = a.get("severity", "allergy")
        ids = a.get("leaves") or [a["id"]]
        for fid in ids:
            rules.append({"family": fid, "strength": "avoid", "kind": sev, "mayContain": may and sev == "allergy"})
    for m in profile.get("medical", []):
        spec = cat.d["medical"].get(m)
        if not spec:
            continue
        for fid in spec.get("avoid", []):
            rules.append({"family": fid, "strength": "avoid", "kind": "medical", "mayContain": may})
        for l in spec.get("limits", []):
            limits.append(dict(l, kind="medical", source=m))
    for d in profile.get("diets", []):
        spec = cat.d["diets"].get(d)
        if not spec:
            continue
        kind = "religion" if d in ("halal", "kosher", "nobeef") else "diet"
        for fid in spec.get("avoid", []):
            rules.append({"family": fid, "strength": "avoid", "kind": kind, "mayContain": False, "diet": d})
        for l in spec.get("limits", []):
            limits.append(dict(l, kind="diet", source=d))
    for a in profile.get("avoid", []):
        rules.append({"family": a["id"], "strength": a.get("strength", "avoid"), "kind": "preference", "mayContain": False})
    for c in profile.get("custom", []):
        fid = "custom:" + c["label"].lower()
        cat.fam.setdefault(fid, {"id": fid, "name": c["label"], "terms": c["terms"], "isA": None})
        rules.append({"family": fid, "strength": c.get("strength", "avoid"), "kind": "preference", "mayContain": False})
    return rules, limits


# ---------------------------------------------------------------- evaluation
def evaluate_person(person, product, label, cat):
    rules, limits = rules_for(person["profile"], cat)
    findings = []
    has_list = bool(label["ingredients"]) or bool(label["contains"])
    for r in rules:
        fid = r["family"]
        if not has_list:
            continue
        hit = None
        for it in label["ingredients"]:
            v = cat.match(fid, it["norm"])
            if v:
                hit = {"source": "ingredients", "owner": v[0], "matched": v[1], "index": it["index"]}
                break
        if not hit:
            for p in label["containsNorm"]:
                v = cat.match(fid, p)
                if v:
                    hit = {"source": "contains", "owner": v[0], "matched": v[1], "index": None}
                    break
        if hit:
            lvl = "notFor" if r["strength"] == "avoid" else "checkFirst"
            findings.append(dict(hit, level=lvl, rule=r))
            continue
        if r["kind"] in ("allergy", "medical"):
            for p in label["mayNorm"]:
                v = cat.match(fid, p)
                if v:
                    findings.append({"source": "mayContain", "owner": v[0], "matched": v[1], "index": None, "rule": r,
                                     "level": "notFor" if r["mayContain"] else "checkFirst"})
                    hit = True
                    break
        if hit or r["strength"] != "avoid":
            continue
        # ambiguous terms: the label doesn't say the source
        targets = {fid, *cat.ancestors(fid)}
        for amb in cat.d["ambiguous"]:
            could = set(amb["couldBe"])
            if not (could & targets):
                continue
            if (could & targets) <= cat.majors and label["hasContains"]:
                continue  # a US major would be in the Contains statement
            fam = {"id": "amb", "terms": [amb["term"]] + amb["alt"], "notTerms": amb.get("resolvedBy", [])}
            cat.fam["__amb"] = fam
            found = None
            for it in label["ingredients"]:
                v = cat.match("__amb", it["norm"])
                if v:
                    found = (v[1], it["index"]); break
            if found:
                findings.append({"source": "ambiguous", "matched": found[0], "index": found[1], "rule": r,
                                 "level": "cantConfirm", "why": amb["why"]})
                break
    if not has_list and (rules or limits):
        findings.append({"source": "missingIngredients", "level": "cantConfirm", "rule": None, "matched": None, "index": None})
    nut = product.get("nutrition") or {}
    for l in limits:
        key = l["nutrient"]
        val = nut.get(key)
        if key == "netCarbsG" and val is None and nut.get("carbsG") is not None:
            val = nut["carbsG"] - (nut.get("fiberG") or 0)
        if val is None:
            findings.append({"source": "missingNutrient", "level": "cantConfirm", "nutrient": key, "rule": None, "matched": None, "index": None})
        elif val > l["perDay"] * SERVING_SHARE:
            findings.append({"source": "limit", "level": "checkFirst", "nutrient": key, "value": val, "perDay": l["perDay"],
                             "rule": None, "matched": None, "index": None})
    findings.sort(key=lambda f: (-RANK[f["level"]], f["index"] if f["index"] is not None else 999))
    level = findings[0]["level"] if findings else "ok"
    return {"id": person["id"], "name": display_name(person), "level": level, "findings": findings,
            "reason": reason_line(person, level, findings[0] if findings else None, cat)}


# ---------------------------------------------------------------- words (see docs/voice-and-strings.md)
def display_name(p):
    return "you" if p.get("isOwner") else p["name"]


def cap(s):
    return s[:1].upper() + s[1:]


def join_names(names):
    return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]


def family_name(cat, fid):
    f = cat.fam.get(fid, {})
    return (f.get("name") or fid).lower()


def reason_line(person, level, f, cat):
    who = display_name(person)
    if level == "ok":
        return "OK for you. Nothing you avoid is in it." if who == "you" else f"OK for {who}. Nothing {who} avoids is in it."
    src = f["source"]
    if src == "missingIngredients":
        return "Can’t confirm. No ingredient list for this one yet."
    if src == "missingNutrient":
        return f"Can’t confirm. No {NUTRIENT[f['nutrient']][0]} value on the label."
    if src == "limit":
        n, unit = NUTRIENT[f["nutrient"]]
        v = f["value"]; v = int(v) if float(v).is_integer() else v
        return f"Check first: {v} {unit} {n} per serving."
    if src == "ambiguous":
        return f"Can’t confirm. {f['why']}"
    r = f["rule"]; m = f["matched"]; fid = r["family"]
    fam = cat.fam.get(fid, {})
    if src == "mayContain":
        if level == "notFor":
            return f"Not for {who}. May contain {m}."
        return f"Check first: says ‘may contain {m}’."
    if r["kind"] in ("allergy", "intolerance", "medical"):
        # name the hidden form: "Contains whey: that’s milk." The family that owns the term names it.
        named = family_name(cat, f.get("owner") or fid)
        same = f" {named} " in f" {m} " or any(w.rstrip("s") == named.rstrip("s") for w in m.split())
        return f"Not for {who}. Contains {m}." if same else f"Not for {who}. Contains {m}: that’s {named}."
    if r["kind"] in ("diet", "religion"):
        tmpl = cat.d["diets"][r["diet"]].get("reason", "{ingredient} isn’t allowed")
        return f"Not for {who}: " + tmpl.replace("{ingredient}", m) + "."
    is_a = fam.get("isA")
    if level == "notFor":
        if not is_a or m == is_a:
            return f"Not for {who}. Contains {m}."
        return f"Not for {who}: {m} is {is_a}."
    if not is_a or m == is_a:
        return f"Check first: contains {m}."
    return f"Check first: {m} is {is_a}."


FLAG = {"ok": "OK for {names}", "checkFirst": "Check first", "cantConfirm": "Can’t confirm", "notFor": "Not for {names}"}


def household_check(product, household, cat):
    label = parse_label(product, cat)
    people = sorted(household["people"], key=lambda p: (not p.get("isOwner"), household["people"].index(p)))
    per = [evaluate_person(p, product, label, cat) for p in people]
    overall = max((x["level"] for x in per), key=lambda l: RANK[l]) if per else "ok"
    segs = []
    for lvl in ("notFor", "cantConfirm", "checkFirst", "ok"):
        names = [x["name"] for x in per if x["level"] == lvl]
        if not names:
            continue
        if lvl == "ok" and len(names) == len(per) and len(per) >= 3:
            segs.append("OK for everyone")
        elif lvl in ("ok", "notFor"):
            segs.append(FLAG[lvl].replace("{names}", join_names(names)))
        elif len(names) < len(per):
            segs.append(FLAG[lvl] + " for " + join_names(names))  # "Check first for you · OK for Mia"
        else:
            segs.append(FLAG[lvl])
    return {"overall": overall, "line": " · ".join(dict.fromkeys(segs)), "people": per, "label": label}


def ordinal(n):
    suf = "th" if 10 <= n % 100 <= 20 else {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suf}"


# ---------------------------------------------------------------- run the fixtures
def main():
    cat = Catalog(json.load(open(ROOT / "data/catalog.json")))
    cases = json.load(open(ROOT / "data/verdict-cases.json"))
    households = cases["households"]
    fails = 0
    for c in cases["cases"]:
        hh = households[c["household"]] if isinstance(c["household"], str) else c["household"]
        res = household_check(c["product"], hh, cat)
        got = {p["id"]: p["level"] for p in res["people"]}
        errs = []
        for pid, exp in c["expect"].get("levels", {}).items():
            if got.get(pid) != exp:
                errs.append(f"{pid}: level {got.get(pid)} != {exp}")
        for pid, exp in c["expect"].get("reasons", {}).items():
            r = next(p["reason"] for p in res["people"] if p["id"] == pid)
            if r != exp:
                errs.append(f"{pid}: reason «{r}» != «{exp}»")
        if "line" in c["expect"] and res["line"] != c["expect"]["line"]:
            errs.append(f"line «{res['line']}» != «{c['expect']['line']}»")
        if "index" in c["expect"]:
            for pid, exp in c["expect"]["index"].items():
                p = next(p for p in res["people"] if p["id"] == pid)
                gi = p["findings"][0]["index"] if p["findings"] else None
                if gi != exp:
                    errs.append(f"{pid}: index {gi} != {exp}")
        status = "ok  " if not errs else "FAIL"
        fails += bool(errs)
        if errs or "--verbose" in sys.argv:
            print(f"{status} {c['id']}: {res['line']}")
            for p in res["people"]:
                print(f"       {p['id']}: {p['level']} · {p['reason']}")
            for e in errs:
                print("       !", e)
    print(f"{len(cases['cases']) - fails}/{len(cases['cases'])} cases pass")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
