# Kickoff: running this with Claude Code

## 1. Put the repo where you build

```sh
unzip labelsage-ios-handoff.zip -d ~/Developer
cd ~/Developer/labelsage-ios
git init && git add -A && git commit -m "Handoff from design: LabelSage iOS MVP"
```

If you already have the app repo, copy this folder into it as a subfolder (`handoff/`) or merge it at the root. `CLAUDE.md` must sit at the root Claude Code starts in, so move it up if you nest the rest.

Check you have Xcode 26 (`xcodebuild -version`) and that `swift --version` shows 6.2 or later.

## 2. Start Claude Code in plan mode

```sh
cd ~/Developer/labelsage-ios
claude --permission-mode plan
```

Claude Code reads `CLAUDE.md` on its own. Plan mode makes it propose before it edits, which suits the first milestone.

## 3. First prompt (paste as is)

```
Read HANDOFF.md, CLAUDE.md and docs/milestones.md. Then do milestone M0 only:
1. Create the Xcode project as described in CLAUDE.md (iOS 26, SwiftUI, Swift 6.2, main actor by default for the app target) and add LabelSageCore as a local package.
2. Build LabelSageCore. It has never been compiled: fix compile errors without changing behavior.
3. Run `python3 -I tools/reference_engine.py` and `cd LabelSageCore && swift test`. Both must pass all 45 cases.
Show me the plan first. Don't start M1 until I say so. Don't commit until I ask.
```

## 4. Then one milestone per session

```
Do milestone M1 (design system) from docs/milestones.md. Read docs/specs/00-foundations.md, design/tokens.json, docs/icons.md and docs/mascot.md first. Every component gets SwiftUI previews for every state in the spec. Compare each preview with its PNG in design/screens/ and list any differences you couldn't resolve.
```

Swap the milestone and the spec names for M2 to M7. Run `/clear` between milestones so each one starts from the docs, not from a long history.

## 5. Useful habits

- **Screens:** ask it to open the PNG it is matching ("Look at design/screens/onboarding/12-region.png before you build the region step").
- **Exact values:** "Check design/prototype/Main.dc.html for the exact spacing of the For you section."
- **Logic bugs:** "Add a case to data/verdict-cases.json that reproduces it, run tools/sync-data.sh, then fix."
- **Open questions:** if it hits one, it should add it to docs/open-questions.md with a build default and keep going. Review that file after each milestone.
- **Decisions made in build:** each spec ends with that list; read it after each milestone and move anything you agree with into the spec.
- **Subagents for review:** after a milestone, "Use a subagent to review this milestone against its spec and the hard rules in CLAUDE.md, without reading our conversation."

## 6. Checking the result yourself

- Run on a device; walk the seven stories in `docs/specs/02-chat-home.md`.
- Turn on VoiceOver and the largest text size for one pass per milestone.
- Search the app's strings for "safe": nothing user-facing may contain it.
