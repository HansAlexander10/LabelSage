# LabelSage iOS: design handoff

Everything a coding agent needs to build the LabelSage MVP as a native SwiftUI app.

**Start here:** `HANDOFF.md` (what, why, key decisions, logic) → `CLAUDE.md` (how to work in this repo) → `docs/milestones.md` (the build order) → `docs/KICKOFF.md` (prompts for Claude Code).

## Map

| Folder | What | Use it for |
|---|---|---|
| `docs/specs/` | One handoff spec per screen: layout, tokens, components, states, edge cases, motion, accessibility | Building each screen |
| `docs/logic/` | Verdict engine, onboarding decision tree, chat agent, data and privacy | Behavior |
| `docs/` | Decisions, open questions, milestones, voice and strings, mascot, icons, kickoff | Rules and planning |
| `design/tokens.json` | Colors, type, radius, shadow, spacing, sizes, motion | `Theme` in code |
| `design/screens/` | 2x PNGs of every MVP board; `onboarding/` has the 14 key steps | Matching the look |
| `design/prototype/` | The design canvas sources (`.dc.html`, HTML + inline styles + JS logic) | Exact values and copy (reference only, don't port) |
| `assets/` | `LabelSageIcons.xcassets` (116 Fluent 3D icons, 256 px) + `icons.json`, mascot parts and rig, app icon, Outfit font, licenses | Drop into the app target |
| `data/` | `catalog.json` (hidden names), `verdict-cases.json` (the spec, 45 cases), sample household and products | Engine and fixtures |
| `LabelSageCore/` | Swift package: models, parser, matcher, verdict engine, reason lines, Swift Testing tests | Add as a local package |
| `tools/` | `reference_engine.py` (runnable spec), `sync-data.sh` | Keeping both engines in step |

## First commands

```sh
python3 -I tools/reference_engine.py          # 45/45 cases pass
cd LabelSageCore && swift test                # must pass the same 45 (not compiled yet: see CLAUDE.md)
```

## Licences

- Icons: Microsoft Fluent Emoji 3D, MIT (`assets/LICENSES/FluentEmoji-MIT.txt`).
- Font: Outfit, SIL Open Font License 1.1 (`assets/LICENSES/Outfit-OFL.txt`).
- Mascot, app icon, designs and copy: LabelSage, all rights reserved.

## Not in this folder

Research material, transcripts and client work are private and stay out of this repo. The demo household (Mia, Leo, Sam, Dad) and all demo products are made up.
