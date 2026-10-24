# Icons

Board: `design/screens/81-icon-library.png`. Source: `design/prototype/IconLibrary.dc.html`, `Icon.dc.html`.

## Library

- **Microsoft Fluent Emoji 3D**, MIT licence (`assets/LICENSES/FluentEmoji-MIT.txt`). One library, one 3D style and point of view (D10). No generated icons.
- `assets/LabelSageIcons.xcassets`: 116 image sets, 256 px PNG each. Draw at 24 to 72 pt.
- `assets/icons.json`: 125 keys in 11 categories (allergens, tree nuts, seafood, other allergens, ingredients, diets, religion, medical, goals, people, app), about 120 **aliases** (prawn → shrimp, all tree nuts → treenuts, added sugars → sugar) and an `asset` name per key.
- **Nearest stand-ins** (`standIn: true`, 15 keys): no exact Fluent icon exists, so the nearest one is used: every tree nut uses the chestnut, sesame the bagel, mustard the hot dog, celery a leafy green, lupin beans, mussels the oyster, wheat a sheaf of rice. If the team wants exact art later, replace the PNG in the image set and keep the key.

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
