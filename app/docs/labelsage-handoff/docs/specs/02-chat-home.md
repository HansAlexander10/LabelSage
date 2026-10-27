## Handoff Spec: Chat home and thread

### Overview
Home (D1). People check a product, ask about one, look for other options, compare, or change someone's allergies. Every answer names the person and the ingredient. The camera is one tap away, and its result comes back here (in the thread and as a product sheet). LabelSage stands in a fixed dock above the composer and says the latest answer. Older messages stay as plain text (D9).

Boards: `design/screens/10-chat-home.png`, `70-flows-ai-first.png` (7 stories), `71-chat-intents.png`, `63-explainer-and-coach-marks.png`. Source: `design/prototype/Chat.dc.html`, `Flows.dc.html`, `ChatIntents.dc.html`. Logic: `docs/logic/chat-agent.md`.

### Layout
Background `screenTint.chat` (#eef8f1).

**Header** (top, 16 pt gutter): avatar circle (owner's initials, green) → Family. Title button "New chat ⌄" (opens chat history as a menu or sheet: past chats by title, "Peanut butter check", "Mia’s allergies"). Under it the **people line** in caption size: "Mia: peanut, tree nuts · You: seed oils" (each person's top items, truncated). Right: glass circle "New chat" (`square.and.pencil`).

**Start screen** (empty chat):
- Large title "What do you need today?" (34/700), line "I check the ingredients for you and Mia." (names from the household).
- **Hero card** "Check a product": magnifier icon, title, "Scan the barcode or photo the ingredients", primary "Open the camera" (with `barcode.viewfinder`). On first run a coach mark points here (`63-…`).
- **Three tiles** (3 columns, 3D icons): "Ask about a product" (label), "Find other options" (sparkles), "Change allergies" (busts in silhouette). Tapping fills the composer with a starter and focuses it, or (Change allergies) opens the person picker inline.

**Thread:** user messages right-aligned in white bubbles. Answers are **content cards** in the thread (a product row with its verdict, up to three option cards, a change card) plus LabelSage's line in the dock. Section "Today" separators.

**Dock** (bottom, above the composer): LabelSage 64 pt at the left with his bubble to the right (max 2 lines, 20 words). Pose follows the latest answer (see `mascot.md`): talk while a bubble is shown, reading while checking, guard on Not for an allergy, done at a find, listen while the person types. When a sheet opens, he leaves the dock and appears in the sheet; the dock is empty.

**Composer:** photo button (left, glass) → upload a photo (the ingredients) into the Scan flow; text field "Ask LabelSage…" (capsule, white); right button is the camera (`barcode.viewfinder`) when the field is empty, and Send (`arrow.up`, ink circle) when it has text.

### Design Tokens Used
| Token | Value | Usage |
|-------|-------|-------|
| `screenTint.chat` | #eef8f1 | Background |
| `type.screenTitle` | 34/700 | "What do you need today?" |
| `radius.card` | 26 | Hero card, tiles, content cards |
| `color.amber` | #eb9d15 | "Open the camera" |
| `size.mascotChatDock` | 64 | Dock mascot |
| `verdict.*` | | Flags in product rows |

### Components
| Component | Variant | Props | Notes |
|-----------|---------|-------|-------|
| `ChatHeader` | | people line, title, onHistory, onNew, onAvatar | |
| `StartHero` | default, highlighted (coach mark) | onOpenCamera | |
| `StartTile` | 3 | icon, title, action | |
| `UserBubble` | | text | |
| `ProductResultCard` | compact | product, `HouseholdVerdict` | Image, name, price, brand · size, key ingredient chips colored by finding ("Sunflower oil" red, "Cane sugar" amber); tap opens the product sheet |
| `OptionsResult` | 1 to 3 cards | products, verdicts | "Compare both", "More options", "Check another" buttons under it |
| `ChangeCard` | proposed, saved, cancelled | person, change, severity | "Mia · 1 change to confirm · Open"; chips of the new item; "Mia avoids: peanut, tree nuts, sesame"; segmented Allergy / Intolerance; helper "Flags “may contain sesame” too." / "Flags sesame in the ingredients only."; "After you confirm, I re-check Mia’s go-tos."; Cancel and **Confirm change** |
| `MascotDock` | pose, bubble text | | Single instance per screen |
| `Composer` | empty, typing, sending | text, onPhoto, onCamera, onSend | |
| `ThinkingRow` | | "Checking the ingredients…" with "For you and Mia" | Shown while the engine or model works; mascot reading |

### States and Interactions
| Element | State | Behavior |
|---------|-------|----------|
| Start screen | First open after onboarding | Camera opens immediately (D1); after it closes, the coach mark on the hero: "Start here. Point the camera at a barcode and I’ll check it for Mia." with "Got it" |
| Start screen | Returning | Dock bubble "Check a product, or ask me about one." |
| Open the camera / camera button | Tap | Presents Check a product full screen; the result returns here as a product sheet and as a `ProductResultCard` in the thread |
| Photo button | Tap | Photo picker → OCR → same flow as the ingredients mode |
| Send | Tap | Runs the intent pipeline (`logic/chat-agent.md`); shows `ThinkingRow`; then the answer card and the dock line |
| Product card | Tap | Product page sheet (medium, then large); mascot moves into the sheet |
| "Compare both" | Tap | Compare sheet (large) |
| Change card | Confirm | Saves, toast "Saved: Mia avoids sesame, allergy (“may contain” too)." with Undo, then dock "Done. I re-checked Mia’s go-tos: none contains sesame." |
| Change card | Cancel | "No changes made." |
| New chat | Tap | Clears the thread (kept in history); start screen |
| History | Tap a chat | Restores the thread and its context |
| Header avatar | Tap | Family |

### The seven stories (acceptance tests)
From `70-flows-ai-first.png`. Each must work end to end with the sample household and products.
1. **First open:** launch → onboarding → camera → product sheet with a verdict per person.
2. **Snack aisle:** camera → Crunchwell Popped Corn Chips → "Not for you: sunflower oil is a seed oil." → Try instead → Compare → Save to go-tos ("Saved Canyon Kettle to your go-tos. I check it again every time.").
3. **Peanut butter, chat to camera and back:** camera → Northfield Creamy Peanut Butter → back in the thread: "Not for Mia. Contains peanuts." (guard) → "Show me other options".
4. **At home: is my go-to still OK?** "Are the popped corn chips OK for me?" → product card with ingredient chips → "Not for you: sunflower oil is a seed oil. Canyon Kettle is OK for you." → Compare both.
5. **No barcode or a new product:** camera → unknown barcode → "This one’s new to me. Photo the ingredients and I’ll read them." (disguise) → ingredients photo → verdict.
6. **Mia reacted to hummus:** "Mia reacted to hummus. Add sesame to her allergies" → change card → Confirm → re-check go-tos.
7. **Chips without seed oils:** "kettle chips without seed oils" → reading → "Found 3. All OK for you and Mia." (done). Needs D4 for real data; fixtures until then.

### Responsive Behavior
| Breakpoint | Changes |
|------------|---------|
| AX sizes | Tiles stack to one column; dock bubble may grow to 4 lines and pushes the thread up |
| Keyboard up | Dock collapses to the mascot only (bubble hidden) so the thread stays visible; bubble returns when the keyboard hides |

### Edge Cases
- **Model unavailable** (no Apple Intelligence, or disabled): keyword router + deterministic lines; the composer still works.
- **No match for "Other options":** "Nothing here fits Mia yet. Want me to check something else?" (Q1).
- **Ambiguous product name** ("pesto"): LabelSage thinking, asks "Which one?" with up to 3 product rows.
- **Message about safety** ("is this safe for my son?"): answer in the person form, never repeat "safe".
- **Venting** ("every label, every time"): listen pose, acknowledge in one line, no sales: "Every label, every time. I’ll take that part."
- **Offline:** checks of products seen before work; new lookups: "You’re offline. Products you checked before still work."

### Animation / Motion
| Element | Trigger | Animation | Duration | Easing |
|---------|---------|-----------|----------|--------|
| New message | Send | bubble rises 12 pt + fades in | 220 ms | easeOut |
| Answer card | Ready | fades up, cards stagger 40 ms | 260 ms | easeOut |
| Dock bubble | New line | old bubble fades out, new one in; mouth talks while the line is new | 180 ms | ease |
| Mascot to sheet | Sheet opens | dock mascot fades out as the sheet's mascot fades in (no flying across) | 200 ms | ease |

### Accessibility Notes
- Focus order: header, start content or thread (oldest to newest), dock line, composer.
- New answers post an accessibility announcement with the dock line ("Not for Mia. Contains peanuts.").
- Product cards read: name, price, then the person line ("Not for you, OK for Mia").
- The mascot is hidden from VoiceOver; his bubble is a live region.

### Decisions made in build
(The coding agent lists here anything the spec didn't cover.)
- 27 Oct: chat home's always-visible elements follow board 10 where it differs from this spec (Q-CHAT-1 to Q-CHAT-3): left header with the history menu, 32 pt title, board tile and hero sizes, 84 pt dock mascot with a full-width bubble, "Start here" and the tip in the dock (no popovers), working and guard states in the dock bubble, green user bubbles, a glass field, Stop while checking; greetings like "Hi" are small talk.
- T11: the intent router is keyword-based (`Features/Chat/ChatIntent.swift`); the Foundation Models reader is not built (optional in the brief).
- T11: "Ask about a product" prefills "Is it OK for Mia: "; "Find other options" prefills "Find other options for "; "Change allergies" shows the people as option cards and prefills "Mia is allergic to ".
- T11: other options keep only OK and Check first products, OK first, up to three; "without seed oils" also drops products whose list names a seed oil term.
- T11: chat history is in memory for the session; a product title is "<product name> check", a change is "Mia’s allergies".
- T11: the dock bubble shows the inline tip once, after the coach marks, with a "Got it" link under it.
