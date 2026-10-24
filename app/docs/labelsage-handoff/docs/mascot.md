# LabelSage, the mascot

A label tag with a cape, rubber-hose arms and legs, and a magnifier. He reads the ingredients so you don't have to. Board: `design/screens/80-mascot-states.png`. Source: `design/prototype/Mascot.dc.html` (all poses and keyframes as CSS), `MascotStates.dc.html`.

## Hard rules

- **One LabelSage per screen** (D9). In the chat he stands in the dock above the composer; when a sheet, tip or another screen needs him, he moves there and the dock is empty. Two at once is a bug. Write a UI test that counts `MascotView` instances on every screen.
- **His name comes from `Brand.mascot`** (D11).
- **On an allergy or Not for result he stands guard:** still, serious, no joke, no celebration. The flag stays the main thing on screen.
- **Decorative for VoiceOver** (`accessibilityHidden(true)`); his bubble is real text.
- **Reduce Motion** freezes him on the pose's key frame. No meaning lives only in his animation.

## The 13 states

| State | When | What he does | Loop |
|---|---|---|---|
| `idle` | Home, empty states | Feet planted, breathes, shifts weight, glances, blinks; arms, cape and string follow a beat later. After 15 s with no tap → `hum` | 4.8 s |
| `hum` | 15 s of nothing | Strolls in place, whistles, music notes float up; any tap → `idle` | 1.6 s |
| `reading` | Reading ingredients, checking | Magnifier moves from one eye to the other, the eye under the lens is big; label lines turn green as items are found | 3.2 s |
| `done` | A find, end of onboarding | Once: squash, jump, land. Then happy hops from leg to leg, sparkles | 2 s |
| `thinking` | A choice is needed, Check first, Can’t confirm | One arm folded, hand tapping the chin, eyes up, "?" bobs | 3.2 s |
| `talk` | A bubble is on screen | Mouth opens and closes, one hand gestures, a brow lifts | 1.8 s |
| `wave` | Hello, welcome back, end of the tour | Waves, mouth open | 0.6 s |
| `point` | Directs to options or a button below | Two pokes, then holds; eyes follow the hand | 2.4 s |
| `listen` | While the person chooses or types | Looks down at the options, nods gently | 2.4 s |
| `compare` | Compare works out which fits | A product in each hand, raises one, then the other | 3.6 s |
| `sit` | Learning someone's allergies, building a profile | Sits on a stack of books, reads, turns a page | 3.6 s |
| `disguise` | Product not found | Glasses, red nose, mustache; glances around. Never on Not for | 4.8 s |
| `guard` | Not for (an ingredient someone avoids) | Still and serious: no bob, brows down, flat mouth, eyes ahead | none |

Verdict → pose: `notFor` → `guard`, `checkFirst` → `thinking`, `cantConfirm` → `thinking`, `ok` → `done` (first show) then `idle`.

## Assets

- `assets/Mascot/parts-full/`: 21 transparent PNG parts at full resolution (tag, cape, arms, legs, eyes, brows, mouths, magnifier, question mark, sparks, string, dots).
- `assets/Mascot/parts-prototype/`: the same parts at the prototype's size, plus `eye_l_base` and `eye_r_base` (closed-eye bases for blinking). Positions in `Mascot.dc.html` CSS match these sizes.
- `assets/Mascot/rig.json`: every part's anchor, stage position, scale, rotation and pivot on a 960 × 1210 artboard, plus the draw order back to front.
- `assets/Mascot/mascot-hero.png`: the flattened hero pose for the welcome and the App Store.

## Building it in SwiftUI (MVP)

1. `MascotView(state: MascotState, size: CGFloat)`: a `ZStack` of the parts placed from `rig.json` in draw order, scaled to `size` (the artboard height maps to `size × 1.26`).
2. Each part is an `Image` with `.rotationEffect(_, anchor:)` and `.offset` around its pivot. Drive loops with `TimelineView(.animation)` or `PhaseAnimator`/`KeyframeAnimator`, taking the keyframes from the CSS in `Mascot.dc.html` (`@keyframes tg-*`). Transform and opacity only.
3. Curves: loops `easeInOut` (0.77, 0, 0.175, 1); entrances and the jump `easeOut` (0.23, 1, 0.32, 1).
4. Pose changes crossfade 150 ms; never fly the mascot across the screen between dock and sheet.
5. Reduce Motion: render the pose's first key frame, no `TimelineView`.
6. Sizes in use: 74 (onboarding), 64 (chat dock), 56 (Family), 40 (camera), 30 (section headings).

Later: the rig is Rive-ready (state machine "Mascot" with a `state` number input). Swap `MascotView`'s body for `RiveViewModel` without changing call sites.
