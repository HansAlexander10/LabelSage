"""Benchmark matching algorithms on the golden set: same product or not, with no shared ID (barcodes hidden).

Reads golden-pairs.csv (match/golden_set.py, labelled), leaves out label 2 (can't tell), scores every pair with
each algorithm, picks each algorithm's threshold on the dev split (best F1) and reports on the test split:
precision, recall, F1, recall at precision >= 0.99, hit@1 (the best-scored candidate of a query is a match),
and recall per edge-case flag and per category. Writes benchmark-results.md and benchmark-scores.csv to OUT_DIR.

Usage (from backend/etl):
  python3 match/benchmark.py              # all algorithms
  python3 match/benchmark.py --no-embed   # skip the two embedding models (no sentence-transformers needed)
"""
import csv
import os
import pathlib
import sys

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from match import golden_set, matcher  # noqa: E402

OUT_DIR = golden_set.OUT_DIR
EMBED_MODELS = {"bge-small": ("BAAI/bge-small-en-v1.5", ""), "e5-small": ("intfloat/e5-small-v2", "query: ")}
HIGH_PRECISION = 0.99                 # the matcher's goal: no false positives
MIN_FLAG_POSITIVES = 5                # per-flag recall is shown only with at least this many test positives


# ------ PHASE 1: READ THE LABELLED PAIRS --------

def read_pairs():
    """Labelled pairs (0 or 1); label 2 and unlabelled pairs are left out."""
    with open(OUT_DIR / "golden-pairs.csv", newline="") as f:
        rows = [r for r in csv.DictReader(f) if r["label"] in ("0", "1")]
    for r in rows:
        r["y"] = int(r["label"])
        r["flags"] = set(filter(None, r["query_flags"].split(",")))
        r["fdc_text"] = " ".join(matcher.words(f"{r['fdc_brand'] or ''} {r['fdc_name']}"))
        r["off_text"] = " ".join(matcher.words(f"{r['off_brand'] or ''} {r['off_name']}"))
    return rows


# ------ PHASE 2: THE ALGORITHMS (one score per pair, higher = more alike) --------

def exact(r):
    return float(r["fdc_text"] == r["off_text"])


def jaccard(a, b):
    a, b = set(a.split()), set(b.split())
    return len(a & b) / len(a | b) if a | b else 0.0


def brand_title(r):
    """The matcher's brand + title score with no rules: no penalty, no veto, no caps."""
    b = max((x for x in (matcher.brand_score(r[k], r["off_brand"], r["off_name"]) for k in ("fdc_brand", "fdc_brand_owner"))
             if x is not None), default=0.5)
    return matcher.WEIGHT_BRAND * b + matcher.WEIGHT_TITLE * matcher.title_score(r["fdc_name"], r["off_name"])


def current_matcher(r):
    """matcher.score_pair as the name_brand method uses it; returns (confidence, tier)."""
    ours = {"gtin": None, "name": r["fdc_name"], "brand": r["fdc_brand"], "brand_owner": r["fdc_brand_owner"],
            "ingredients": r["fdc_ingredients"]}
    off = {"item_name": r["off_name"], "brand": r["off_brand"], "ingredients": r["off_ingredients"], "gtins": set()}
    s = matcher.score_pair(ours, off, "name_brand")
    return s["confidence"], s["tier"], s["penalty"], s["brand_score"]


def tfidf_cosine(rows):
    """Cosine of char 3-4 gram TF-IDF vectors (the same kind golden_set.py used to find hard negatives)."""
    vectorizer = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 4), sublinear_tf=True)
    vectorizer.fit([r["fdc_text"] for r in rows] + [r["off_text"] for r in rows])
    a = vectorizer.transform([r["fdc_text"] for r in rows])
    b = vectorizer.transform([r["off_text"] for r in rows])
    return np.asarray(a.multiply(b).sum(axis=1)).ravel()


def embed_cosine(rows, name):
    """Cosine of sentence embeddings from a cached model (no download)."""
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    from sentence_transformers import SentenceTransformer
    model_id, prefix = EMBED_MODELS[name]
    model = SentenceTransformer(model_id, device="cpu")
    texts = sorted({r["fdc_text"] for r in rows} | {r["off_text"] for r in rows})
    vectors = dict(zip(texts, model.encode([prefix + t for t in texts], batch_size=64, normalize_embeddings=True)))
    return np.array([float(vectors[r["fdc_text"]] @ vectors[r["off_text"]]) for r in rows])


def score_all(rows, embed):
    """Every algorithm's score per pair, as {algorithm: array}; plus features for the learned model."""
    s = {"exact text": np.array([exact(r) for r in rows]),
         "jaccard words": np.array([jaccard(r["fdc_text"], r["off_text"]) for r in rows]),
         "levenshtein ratio": np.array([matcher.ratio(r["fdc_text"], r["off_text"]) for r in rows]),
         "brand + title (no rules)": np.array([brand_title(r) for r in rows]),
         "tf-idf char 3-4": tfidf_cosine(rows)}
    current = [current_matcher(r) for r in rows]
    s["current matcher (confidence)"] = np.array([c[0] for c in current])
    tiers = np.array([c[1] for c in current])
    if embed:
        for name in EMBED_MODELS:
            s[f"embedding {name}"] = embed_cosine(rows, name)

    # job 1: features for logistic regression: the scores above plus brand, penalty and ingredient overlap
    ingredient_overlap = np.array([jaccard(" ".join(matcher.words(r["fdc_ingredients"])),
                                           " ".join(matcher.words(r["off_ingredients"]))) for r in rows])
    features = np.column_stack([s[k] for k in s] + [
        [c[2] for c in current],                                        # penalty
        [c[3] if c[3] is not None else 0.5 for c in current],           # brand score
        [c[3] is None for c in current],                                # brand missing
        ingredient_overlap,
        [bool(r["fdc_ingredients"]) and bool(r["off_ingredients"]) for r in rows]])
    return s, tiers, features


# ------ PHASE 3: THRESHOLDS AND METRICS --------

def counts(y, predicted):
    tp = int(((predicted == 1) & (y == 1)).sum())
    fp = int(((predicted == 1) & (y == 0)).sum())
    fn = int(((predicted == 0) & (y == 1)).sum())
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"tp": tp, "fp": fp, "fn": fn, "precision": precision, "recall": recall, "f1": f1}


def best_threshold(y, score, min_precision=None):
    """Threshold with the best F1 on these pairs; with min_precision, the lowest one that keeps precision."""
    best, best_value = None, -1.0
    for t in np.unique(score):
        c = counts(y, (score >= t).astype(int))
        if min_precision is not None:
            if c["precision"] >= min_precision and c["tp"] and c["recall"] > best_value:
                best, best_value = t, c["recall"]
        elif c["f1"] > best_value:
            best, best_value = t, c["f1"]
    return best


def hit_at_1(rows, score, mask):
    """Share of queries (with at least one match) whose best-scored candidate is a match."""
    by_query = {}
    for i in np.flatnonzero(mask):
        by_query.setdefault(rows[i]["query_id"], []).append(i)
    hits = [rows[max(ix, key=lambda i: score[i])]["y"] for ix in by_query.values() if any(rows[i]["y"] for i in ix)]
    return sum(hits) / len(hits) if hits else 0.0


def evaluate(rows, name, score, dev, test, fixed=None):
    """Threshold on dev, metrics on test. `fixed` = a ready-made 0/1 prediction (the matcher's accept tier)."""
    y = np.array([r["y"] for r in rows])
    if fixed is not None:
        predicted, threshold, p99 = fixed, None, None
    else:
        threshold = best_threshold(y[dev], score[dev])
        predicted = (score >= threshold).astype(int)
        t99 = best_threshold(y[dev], score[dev], HIGH_PRECISION)
        p99 = counts(y[test], (score[test] >= t99).astype(int)) if t99 is not None else None
    result = dict(counts(y[test], predicted[test]), algorithm=name, threshold=threshold,
                  hit1=hit_at_1(rows, score, test), p99=p99)

    # job 1: recall per flag and per category stratum, test positives only
    result["by_flag"], result["by_category"] = {}, {}
    for key, groups in (("by_flag", lambda r: r["flags"]),
                        ("by_category", lambda r: {r["stratum"]} if not r["stratum"].startswith("edge:") else set())):
        for g in sorted({g for i in np.flatnonzero(test) for g in groups(rows[i])}):
            ix = [i for i in np.flatnonzero(test) if g in groups(rows[i]) and rows[i]["y"] == 1]
            result[key][g] = (sum(predicted[i] for i in ix), len(ix))
    return result, predicted


def learned(rows, features, dev, test):
    """Logistic regression trained on dev, scored on test (and on dev by cross-fitting, for the threshold)."""
    y = np.array([r["y"] for r in rows])
    x = (features - features[dev].mean(axis=0)) / (features[dev].std(axis=0) + 1e-9)
    score = np.zeros(len(rows))
    model = LogisticRegression(max_iter=2000, C=1.0).fit(x[dev], y[dev])
    score[test] = model.predict_proba(x[test])[:, 1]

    # job 1: dev scores from 5 folds grouped by query, so the dev threshold is not tuned on training data
    queries = np.array([r["query_id"] for r in rows])
    dev_queries = np.unique(queries[dev])
    fold_of = {q: i % 5 for i, q in enumerate(np.random.default_rng(golden_set.SEED).permutation(dev_queries))}
    folds = np.array([fold_of.get(q, -1) for q in queries])
    for k in range(5):
        train, held = dev & (folds != k), dev & (folds == k)
        score[held] = LogisticRegression(max_iter=2000, C=1.0).fit(x[train], y[train]).predict_proba(x[held])[:, 1]
    return score


# ------ PHASE 4: REPORT --------

def pct(x):
    return f"{100 * x:.1f}"


def report(results, rows, dev, test):
    y = np.array([r["y"] for r in rows])
    lines = ["# Matching benchmark on the golden set", "",
             f"{int(dev.sum())} dev pairs ({int(y[dev].sum())} matches), {int(test.sum())} test pairs "
             f"({int(y[test].sum())} matches); label 2 (can't tell) left out. Threshold = best F1 on dev; "
             f"numbers are test. P99 = threshold for precision >= {HIGH_PRECISION} on dev, applied to test "
             f"(- = no threshold reaches it on dev). Fixed = a yes/no rule with no threshold.", "",
             "| Algorithm | Threshold | Precision | Recall | F1 | FP | Recall @ P99 (test P) | Hit@1 |",
             "|---|---|---|---|---|---|---|---|"]
    for r in sorted(results, key=lambda r: -r["f1"]):
        p99 = f"{pct(r['p99']['recall'])} ({pct(r['p99']['precision'])})" if r["p99"] else "-"
        threshold = "fixed" if r["threshold"] is None else f"{r['threshold']:.3f}"
        lines.append(f"| {r['algorithm']} | {threshold} | {pct(r['precision'])} | {pct(r['recall'])} | "
                     f"{pct(r['f1'])} | {r['fp']} | {p99} | {pct(r['hit1'])} |")

    # job 1: recall per flag and per category, one column per algorithm
    for key, title in (("by_flag", "Recall per edge case (test matches)"),
                       ("by_category", "Recall per category (test matches, random part of the sample)")):
        names = [r["algorithm"] for r in sorted(results, key=lambda r: -r["f1"])]
        groups = [g for g, (_, n) in results[0][key].items() if n >= (MIN_FLAG_POSITIVES if key == "by_flag" else 1)]
        lines += ["", f"## {title}", "", "| Group | n | " + " | ".join(names) + " |",
                  "|---|---|" + "---|" * len(names)]
        by_name = {r["algorithm"]: r for r in results}
        for g in groups:
            n = results[0][key][g][1]
            lines.append(f"| {g} | {n} | " + " | ".join(
                pct(by_name[a][key][g][0] / n) if n else "-" for a in names) + " |")
    (OUT_DIR / "benchmark-results.md").write_text("\n".join(lines) + "\n")
    return "\n".join(lines)


if __name__ == "__main__":
    rows = read_pairs()
    dev = np.array([r["split"] == "dev" for r in rows])
    test = ~dev
    scores, tiers, features = score_all(rows, embed="--no-embed" not in sys.argv)
    results, predictions = [], {}
    for name, score in scores.items():
        fixed = score.astype(int) if name == "exact text" else None      # a yes/no score has no threshold to tune
        result, predictions[name] = evaluate(rows, name, score, dev, test, fixed=fixed)
        results.append(result)
    accept = (tiers == "accept").astype(int)
    result, predictions["current matcher (accept tier)"] = evaluate(
        rows, "current matcher (accept tier)", scores["current matcher (confidence)"], dev, test, fixed=accept)
    results.append(result)
    score = learned(rows, features, dev, test)
    result, predictions["logistic regression (all features)"] = evaluate(
        rows, "logistic regression (all features)", score, dev, test)
    results.append(result)

    # job 1: per-pair scores and predictions for looking at the errors
    with open(OUT_DIR / "benchmark-scores.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["pair_id", "split", "label", "query_flags", "fdc_text", "off_text"]
                        + [f"score: {k}" for k in scores] + [f"pred: {k}" for k in predictions])
        for i, r in enumerate(rows):
            writer.writerow([r["pair_id"], r["split"], r["y"], r["query_flags"], r["fdc_text"], r["off_text"]]
                            + [round(float(scores[k][i]), 4) for k in scores]
                            + [int(predictions[k][i]) for k in predictions])
    print(report(results, rows, dev, test))
