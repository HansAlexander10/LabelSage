"""Barcode rules shared by the weekly build and the scan-time lookup.

Every barcode becomes a GTIN-14: digits only, padded to 14, with a valid check digit.
The same rules exist as DuckDB macros in transform/transform.py (BARCODE_MACROS).
"""
import re


# ------ PHASE 1: ONE BARCODE --------

def gtin_check_ok(gtin14):
    """True when the last digit of a 14-digit GTIN matches its check digit."""

    # job 1: weight the first 13 digits 3, 1, 3, 1, ... from the left
    digits = [int(c) for c in gtin14]
    total = sum(d * (3 if i % 2 == 0 else 1) for i, d in enumerate(digits[:-1]))

    # job 2: the check digit brings the total up to a multiple of 10
    return (10 - total % 10) % 10 == digits[-1]


def to_gtin14(code):
    """Return the GTIN-14 for a barcode, or None when it is not a valid barcode."""

    # job 1: keep the digits only ("6 66186 27762 1" -> "666186277621")
    digits = re.sub(r"\D", "", str(code or ""))

    # job 2: EAN-8, UPC-A (11 or 12 digits), EAN-13 and GTIN-14 all pad to 14 digits
    if not 8 <= len(digits) <= 14:
        return None
    gtin = digits.zfill(14)
    return gtin if gtin_check_ok(gtin) else None


# ------ PHASE 2: BARCODES INSIDE RECALL TEXT --------

UPC_TEXT = re.compile(r"UPC[^0-9]{0,12}((?:\d[\d\s-]{9,20}\d)(?:\s*(?:,|and|&)\s*\d[\d\s-]{9,20}\d)*)", re.I)


def recall_gtins(text):
    """Find valid barcodes written after "UPC" in recall text, e.g. "UPC: 6 66186 27762 1"."""
    found = []

    # job 1: find each "UPC ..." mention and split lists such as "UPC 123, 456 and 789"
    for match in UPC_TEXT.finditer(text or ""):
        for chunk in re.split(r",|and|&", match.group(1)):

            # job 2: keep only valid barcodes, once each
            gtin = to_gtin14(chunk.strip())
            if gtin and gtin not in found:
                found.append(gtin)
    return found
