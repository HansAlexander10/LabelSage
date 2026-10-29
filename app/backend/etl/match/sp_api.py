"""Amazon SP-API Catalog Items 2022-04-01: search by barcode or by name and brand, and parse the items.

Needs a Selling Partner account and app. Credentials come from the environment, never from files in git:
  SP_API_CLIENT_ID, SP_API_CLIENT_SECRET, SP_API_REFRESH_TOKEN
Rate limits, which includedData our account receives, and whether we may show Amazon images in our app must be
checked against Amazon's current docs and terms before a full run; RATE_PER_SECOND is a placeholder.
Reference: https://developer-docs.amazon/sp-api/docs/catalog-items-api-v2022-04-01-reference
"""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

from shared.barcode import to_gtin14

ENDPOINT = "https://sellingpartnerapi-na.amazon.com"
TOKEN_URL = "https://api.amazon.com/auth/o2/token"
US_MARKETPLACE = "ATVPDKIKX0DER"
INCLUDED_DATA = "summaries,identifiers,images,productTypes,relationships"   # add "attributes" if our account gets it
BATCH_SIZE = 20                     # most identifiers searchCatalogItems takes per request
RATE_PER_SECOND = 1.0               # placeholder: set from the documented limit for our account


# ------ PHASE 1: CONNECTION --------

class Client:

    def __init__(self, marketplace_id=US_MARKETPLACE):
        self.marketplace_id = marketplace_id
        self._token, self._token_expires, self._last_call = None, 0.0, 0.0

    def _access_token(self):

        # job 1: reuse the token until a minute before it expires
        if self._token and time.time() < self._token_expires - 60:
            return self._token

        # job 2: exchange the refresh token for a new access token (Login with Amazon)
        body = urllib.parse.urlencode({
            "grant_type": "refresh_token", "refresh_token": os.environ["SP_API_REFRESH_TOKEN"],
            "client_id": os.environ["SP_API_CLIENT_ID"], "client_secret": os.environ["SP_API_CLIENT_SECRET"],
        }).encode()
        with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=body)) as response:
            data = json.load(response)
        self._token, self._token_expires = data["access_token"], time.time() + data["expires_in"]
        return self._token

    def _get(self, path, params, retries=5):
        """GET with pacing and backoff on 429/5xx. Returns (status, json body or None)."""
        url = f"{ENDPOINT}{path}?{urllib.parse.urlencode(params)}"
        for attempt in range(retries):

            # job 1: keep to RATE_PER_SECOND
            wait = 1.0 / RATE_PER_SECOND - (time.time() - self._last_call)
            if wait > 0:
                time.sleep(wait)
            self._last_call = time.time()

            # job 2: call; throttled or server errors wait 2, 4, 8 ... seconds and retry
            request = urllib.request.Request(url, headers={"x-amz-access-token": self._access_token()})
            try:
                with urllib.request.urlopen(request) as response:
                    return response.status, json.load(response)
            except urllib.error.HTTPError as error:
                if error.code == 429 or error.code >= 500:
                    time.sleep(2 ** (attempt + 1))
                    continue
                return error.code, None
        return 429, None


# ------ PHASE 2: SEARCHES --------

    def search_barcodes(self, gtins):
        """Search up to BATCH_SIZE GTIN-14s of one kind. Returns (status, items, query).

        12-digit UPCs (GTIN-14 starting "00") go as UPC, the rest as 13-digit EAN; do not mix kinds in one batch.
        """
        kind = "UPC" if all(g.startswith("00") for g in gtins) else "EAN"
        codes = [g[2:] if kind == "UPC" else g[1:] for g in gtins]
        query = ",".join(codes)
        status, body = self._get("/catalog/2022-04-01/items", {
            "identifiers": query, "identifiersType": kind, "marketplaceIds": self.marketplace_id,
            "includedData": INCLUDED_DATA, "pageSize": BATCH_SIZE})
        return status, (body or {}).get("items", []), query

    def search_name_brand(self, name, brand, page_size=5):
        """Keyword search for a product Amazon did not list under our barcode. Returns (status, items, query)."""
        params = {"keywords": name, "marketplaceIds": self.marketplace_id,
                  "includedData": INCLUDED_DATA, "pageSize": page_size}
        if brand:
            params["brandNames"] = brand
        status, body = self._get("/catalog/2022-04-01/items", params)
        return status, (body or {}).get("items", []), f"{name} | {brand or ''}"


# ------ PHASE 3: PARSE ONE ITEM --------

def _for_marketplace(blocks, marketplace_id):
    """Each top-level list holds one block per marketplace; keep ours only."""
    return next((b for b in blocks or [] if b.get("marketplaceId") == marketplace_id), {})


def parse_item(item, marketplace_id=US_MARKETPLACE):
    """One SP-API item -> rows for amazon_item, amazon_item_identifier and amazon_image, plus the matcher's view."""
    asin = item["asin"]

    # job 1: summary, product type and parent from our marketplace only
    summary = _for_marketplace(item.get("summaries"), marketplace_id)
    product_type = _for_marketplace(item.get("productTypes"), marketplace_id).get("productType")
    relations = _for_marketplace(item.get("relationships"), marketplace_id).get("relationships", [])
    parent = next((r["parentAsins"][0] for r in relations if r.get("parentAsins")), None)

    # job 2: attributes, when our account receives them
    attributes = item.get("attributes", {})
    ingredients = next((a.get("value") for a in attributes.get("ingredients", [])
                        if a.get("marketplace_id", marketplace_id) == marketplace_id), None)
    allergens = ",".join(a.get("value", "") for a in attributes.get("allergen_information", [])) or None

    # job 3: every barcode Amazon lists, also as GTIN-14
    identifiers = [{"asin": asin, "marketplace_id": marketplace_id, "identifier_type": i.get("identifierType"),
                    "identifier": i.get("identifier"), "gtin": to_gtin14(i.get("identifier"))}
                   for i in _for_marketplace(item.get("identifiers"), marketplace_id).get("identifiers", [])]

    # job 4: the largest image of each variant (Amazon returns several sizes per variant)
    best = {}
    for image in _for_marketplace(item.get("images"), marketplace_id).get("images", []):
        size = (image.get("width") or 0) * (image.get("height") or 0)
        if image.get("variant") not in best or size > best[image["variant"]]["size"]:
            best[image["variant"]] = {"url": image.get("link"), "width": image.get("width"),
                                      "height": image.get("height"), "size": size}
    images = [{"asin": asin, "marketplace_id": marketplace_id, "variant": v,
               "url": b["url"], "width": b["width"], "height": b["height"]} for v, b in sorted(best.items())]

    # job 5: the rows, and the fields matcher.score_pair reads
    row = {"asin": asin, "marketplace_id": marketplace_id, "item_name": summary.get("itemName"),
           "brand": summary.get("brandName"), "manufacturer": summary.get("manufacturer"),
           "product_type": product_type, "item_classification": summary.get("itemClassification"),
           "parent_asin": parent, "package_quantity": summary.get("packageQuantity"),
           "size_name": summary.get("sizeName"), "ingredients_text": ingredients, "allergen_info": allergens,
           "raw_json": json.dumps(item)}
    for_matcher = {"asin": asin, "item_name": row["item_name"], "brand": row["brand"],
                   "gtins": {i["gtin"] for i in identifiers if i["gtin"]}, "ingredients": ingredients,
                   "package_quantity": row["package_quantity"],
                   "main_image": best.get("MAIN", {}).get("url")}
    return row, identifiers, images, for_matcher
