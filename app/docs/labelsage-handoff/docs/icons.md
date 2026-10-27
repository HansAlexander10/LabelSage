---
type: reference
entity: LabelSage icon library
owner: Artem
status: current
updated: 2026-10-27
---

# Icons

Board: `design/screens/81-icon-library.png`. Source: `design/prototype/IconLibrary.dc.html`, `Icon.dc.html`.

## Library

- **Microsoft Fluent Emoji 3D**, MIT licence (`assets/LICENSES/FluentEmoji-MIT.txt`). One library, one 3D style and point of view (D10). No generated icons.
- `assets/LabelSageIcons.xcassets`: 117 image sets, 256 px PNG each. Draw at 24 to 72 pt.
- `assets/icons.json`: 130 keys in 11 categories (allergens, tree nuts, seafood, other allergens, ingredients, diets, religion, medical, goals, people, app), 126 **aliases** (prawn → shrimp, all tree nuts → treenuts, added sugars → sugar) and an `asset` name per key.
- **Nearest stand-ins** (`standIn: true`, 17 keys): no exact Fluent icon exists, so the nearest one is used: every tree nut uses the chestnut, sesame the bagel, mustard the hot dog, celery a leafy green, lupin beans, mussels the oyster, wheat and grains a sheaf of rice, insect-derived a lady beetle. If the team wants exact art later, replace the PNG in the image set and keep the key.

### Added 2026-10-27 (onboarding and Family audit)

Every key the app asks for (`IconView(key:)`, option and summary keys, catalog family ids, names and icons) now resolves. These were letter tiles before:

- New keys: `honey` (honey pot), `meat` (cut of meat), `legumes` (beans), `grains` (sheaf of rice, stand-in), `insect` (lady beetle, stand-in; the only new image set, `lady_beetle`, from `assets/Lady beetle/3D/lady_beetle_3d.png` in the Fluent repo).
- New aliases: `insect-derived`, `carmine`, `cochineal`, `shellac` → `insect`; `shellfish_only` → `shellfish`.
- Family asked for `bar_chart` and `red_heart`, which are asset names, not keys. It now asks for `macros` and `gotos`.

A custom filter the person types ("cilantro" with no catalog match) still shows the letter tile: that is the Missing state.

## SF Symbols vs 3D icons

- **3D icons** for things: allergens, ingredients, diets, people, the start tiles, summary chips, Family rows.
- **SF Symbols** for controls and verdicts: back, close, chevrons, checkmarks, the four verdict symbols, camera, send, torch, heart.

## `IconView(key:size:)`

Resolves `key` (or an alias) in `icons.json` → image set. States:

| State | When | Shows |
|---|---|---|
| Loaded | The image is in the bundle | The 3D icon |
| Loading | Only if an image is ever fetched remotely (not in the MVP) | A sand tile (#f3ead8) with a slow shimmer, at most 600 ms |
| Missing | Unknown key (typed or rare items like "quinoa") | Letter tile: sand #f3ead8, the first letter in #8a6a3a, 46% of the size, radius 28% |
| Failed | The image fails to load | The same letter tile; never an error |

The verdict never depends on an image. Product pack photos follow the same rule: a pack-shaped placeholder with the brand initial.

VoiceOver: icons next to a text label are hidden; a standalone icon reads its `label` from `icons.json`.
