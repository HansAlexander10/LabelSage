## Handoff Spec: Check a product (camera)

### Overview
The main action. The person points the camera at a barcode, or switches to Ingredients and photographs the ingredient list. LabelSage reads it and the result opens as the **product page sheet over the camera** (with the photo hidden, since the product is in their hand). The same result also lands in the chat thread. "Check", never "scan", in copy (the word "Barcode" is fine as a mode label).

Boards: `design/screens/20-check-a-product-camera.png`, `60-states-scan.png` (idle, checking, product, no barcode), `61-states-scan-edge-cases.png` (not found, no ingredients yet, camera off, offline). Source: `design/prototype/Scan.dc.html`, `ScanStates.dc.html`, `MvpStates.dc.html`.

### Layout
Full screen, black, the camera feed under a dim layer (#232323 at 55%) with a clear cutout.
- **Top bar** (glass circles on dark): Close (✕) left, title "Check a product" center (17/600, white), torch right.
- **Hint** above the frame: "Point at the barcode" (barcode mode) or "No barcode? Photo the ingredients" with "The ingredient list on the pack, or upload a photo of it" (ingredients mode).
- **Frame:** rounded corner brackets (white, 4 pt), about 280 × 200 for barcodes, taller (280 × 360) for ingredients.
- **LabelSage** small (40 pt) at the frame's bottom-left corner, pose `point`; line under the frame "Hold steady inside the frame · tap to try".
- **Bottom:** segmented control on glass: **Barcode | Ingredients**. Under it two glass pills: "Enter code" (barcode) or "Upload a photo" (ingredients), and "Type a name" (→ chat with the composer focused).

### Design Tokens Used
| Token | Value | Usage |
|-------|-------|-------|
| `screenTint.scan` | #000000 | Background |
| dim layer | #232323 at 55% | Around the frame |
| `materials.glass` (dark) | white 14% + blur | Top buttons, segmented control, pills |
| `verdict.*` | | Product sheet flag |

### Components
| Component | Variant | Props | Notes |
|-----------|---------|-------|-------|
| `ScannerView` | barcode, text | mode, onBarcode, onText | `DataScannerViewController` (`.barcode(symbologies: [.ean13, .ean8, .upce, .code128])` and `.text()`), wrapped in `UIViewControllerRepresentable`; highlight off |
| `ScanFrame` | barcode, ingredients | | Corner brackets, the cutout |
| `ScanStateCard` | checking, notFound, noIngredients, cameraOff, offline | | White sheet card over the dim camera, radius 28 |
| `ProductSheet` | | product, verdict | The product page with `as: .sheet, photo: .hidden` (`04-product-page.md`) |

### States and Interactions
| # | State | What shows | Mascot | Actions |
|---|---|---|---|---|
| 1 | **Idle** | Hint, frame, "Hold steady inside the frame · tap to try" | point | Tap frame → focus; Barcode/Ingredients; Enter code; Type a name |
| 2 | **Barcode found, checking** | Card: "Barcode found" · "Looking up 0 28400 59031 8…" | reading | none; timeout 8 s → offline or not found |
| 3 | **Product** | Product sheet over the camera; medium detent; flag, person line, reason | moves into the sheet (guard / thinking / done by verdict) | Check another (closes the sheet, back to idle), Ask LabelSage (→ chat with this product), Try instead, Compare |
| 4 | **Ingredients mode** | "No barcode? Photo the ingredients" | point | Shutter (tap the frame) or Upload a photo → Vision OCR → "Reading the ingredients…" → product sheet named "Your photo" |
| 5 | **Not found** | Card: "Barcode read", line "This one’s new to me. Photo the ingredients and I’ll read them.", "Barcode 0 12345 67890 5" | disguise | **Photo the ingredients** (primary, switches to ingredients mode), Report it, Check another |
| 6 | **Found, no ingredients yet** | Product row (name, size), flag "Can’t confirm", "No ingredient list for this one yet. Check the package, or photo the ingredients and I’ll read them.", "Data updated Oct 2026 · not medical advice" | thinking | Photo the ingredients, Report it, Check another |
| 7 | **Camera access off** | "Allow the camera to check products" · "The barcode is read on your iPhone. No photos are saved or sent." | listen | Open Settings (primary), Type a name instead |
| 8 | **Offline** | "You’re offline" · "Products you checked before still work. A new product needs a connection." · "Checked before" list (rows with the reason under each) · "Saved checks use what you avoid today. Check the package. Not medical advice." | thinking | Try again |

- One barcode read is enough: debounce repeated reads of the same code for 2 s; `success` haptic when found.
- "Report it" opens a short sheet (what's wrong: not found, wrong product, ingredients changed) and stores the report locally for now (no backend in the MVP; D4).
- An ingredients photo makes a `Product(name: "Your photo", ingredientsText: recognized)`; split the "Contains" and "May contain" lines with the parser. Keep the photo only in memory.
- "Checked before" is the local history (SwiftData), re-evaluated with today's profiles.

### Responsive Behavior
| Breakpoint | Changes |
|------------|---------|
| Small phones | Frame 260 wide; pills wrap to two rows if needed |
| AX sizes | Hint and pills grow; the frame keeps its size; the pills go under each other |

### Edge Cases
- **Two barcodes in view:** take the one closest to the frame center.
- **Barcode mode on an ingredient list:** after 4 s with text but no barcode, hint "No barcode? Switch to Ingredients."
- **OCR finds no list:** "I couldn’t read the ingredients. Try closer, with more light." with Retake.
- **Product in the data but in another region:** show it; options come from the household store (D6).
- **Torch** only when the device has one.

### Animation / Motion
| Element | Trigger | Animation | Duration | Easing |
|---------|---------|-----------|----------|--------|
| Frame brackets | Barcode found | brackets tighten 6 pt and turn green, then the card slides up | 200 ms + 260 ms | easeOut |
| State card | Appear | slides up 24 pt + fade | 260 ms | easeOut |
| Product sheet | Result | native sheet, medium detent | system | system |
| Mascot | State change | pose crossfade | 150 ms | ease |

### Accessibility Notes
- VoiceOver: on appear "Check a product. Point the camera at a barcode." Found: announce the person line ("Not for Mia").
- The frame is not focusable; the segmented control, Enter code and Type a name are.
- "Enter code" opens a numeric field (12 or 13 digits) as the accessible path without the camera.
- No meaning in the bracket color alone; the card text says "Barcode found".

### Decisions made in build
(The coding agent lists here anything the spec didn't cover.)
- Built in T8 (`Features/Scan/`). Defaults for the conflicts are Q-T8-1 to Q-T8-4 in `open-questions.md`.
- "Report it" is a confirmation dialog ("What’s wrong?") with the three reasons; the screen hands a `ScanReport` (reason, barcode, product name, nothing about a person) to the caller, which stores it.
- "Enter code" is an alert with a number-pad field; Check is enabled at 12 or 13 digits.
- An ingredients photo keeps the text from the word "Ingredients" on, so a nutrition panel above it is dropped; when the parser finds no list, the "couldn’t read" card shows with Retake.
- While a photo is read, the hint says "Ingredients photo" and the card says "Reading the ingredients…".
- Offline: the back button returns to the camera; each "Checked before" row shows the household line ("Not for you · OK for Mia") as its note, re-checked with today's household.
- The "No barcode? Switch to Ingredients" hint after 4 s is not built: the barcode scanner reads barcodes only, so it cannot see text.
- The simulator has no camera: tapping the frame opens a picker of the fixture products (and an unknown barcode, and a photo with no list).
