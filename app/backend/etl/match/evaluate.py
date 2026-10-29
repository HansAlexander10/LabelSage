"""Score a labelled pair file and report accuracy, precision, recall and F1.

Usage (from backend/etl):
  python3 match/evaluate.py match/eval-pairs-synthetic-2026-10-28.json

"Predicted match" = tier accept. Review counts as not matched: it only gets a photo after a person approves it.
Prints one table per method and the cases the matcher got wrong; returns rows shaped like the match_eval table.
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from match import matcher  # noqa: E402

TEST_GTIN = "00047495012057"      # any valid GTIN-14; the label does not depend on it


# ------ PHASE 1: SCORE THE PAIRS --------

def score_file(path):

    # job 1: read the pairs
    pairs = json.loads(pathlib.Path(path).read_text())["pairs"]

    # job 2: Amazon lists our barcode unless the case says otherwise
    results = []
    for pair in pairs:
        ours = dict(pair["ours"], gtin=TEST_GTIN)
        amazon = dict(pair["amazon"], gtins={TEST_GTIN} if pair.get("lists_our_barcode", True) else set())
        results.append((pair, matcher.score_pair(ours, amazon, pair["method"])))
    return results


# ------ PHASE 2: METRICS --------

def metrics(results, threshold=None):
    """Counts and rates. With a threshold, accept = confidence >= threshold and not capped by the rules."""
    tp = fp = tn = fn = 0
    for pair, score in results:

        # job 1: predicted match: the matcher's own tier, or a sweep threshold on top of its caps and vetoes
        if threshold is None:
            predicted = score["tier"] == "accept"
        else:
            capped = score["tier"] != "accept" and score["confidence"] >= matcher.THRESHOLDS[pair["method"]][0]
            predicted = score["confidence"] >= threshold and not capped and score["confidence"] > 0

        # job 2: count
        actual = pair["label"] == 1
        tp += predicted and actual
        fp += predicted and not actual
        tn += not predicted and not actual
        fn += not predicted and actual

    # job 3: rates
    total = tp + fp + tn + fn
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"tp": tp, "fp": fp, "tn": tn, "fn": fn, "accuracy": round((tp + tn) / total, 3) if total else 0.0,
            "precision": round(precision, 3), "recall": round(recall, 3), "f1": round(f1, 3)}


# ------ PHASE 3: REPORT --------

def report(path):
    results = score_file(path)
    rows = []

    # job 1: per method at the matcher's own thresholds, then a threshold sweep
    for method in ("barcode", "name_brand", "all"):
        subset = [r for r in results if method == "all" or r[0]["method"] == method]
        default = metrics(subset)
        print(f"\n{method} ({len(subset)} pairs) at matcher thresholds: {default}")
        rows.append(dict(default, method=method, threshold=None))
        if method != "all":
            for threshold in (0.60, 0.70, 0.75, 0.80, 0.85, 0.90, 0.92, 0.95):
                m = metrics(subset, threshold)
                print(f"  t={threshold:.2f}  P={m['precision']:.3f} R={m['recall']:.3f} "
                      f"F1={m['f1']:.3f} acc={m['accuracy']:.3f}  tp={m['tp']} fp={m['fp']} tn={m['tn']} fn={m['fn']}")
                rows.append(dict(m, method=method, threshold=threshold))

    # job 2: every pair, wrong ones marked
    print("\ncase | method | label | brand | title | penalty | confidence | tier | reasons")
    for pair, s in results:
        wrong = (s["tier"] == "accept") != (pair["label"] == 1)
        print(f"{'WRONG ' if wrong else ''}{pair['case']} | {pair['method']} | {pair['label']} | {s['brand_score']} | "
              f"{s['title_score']} | {s['penalty']} | {s['confidence']} | {s['tier']} | {','.join(s['reasons'])}")
    return rows


if __name__ == "__main__":
    report(sys.argv[1])
