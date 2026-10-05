extends RefCounted
## Symbols the game UI draws in text. Phaser used ✓ ▸ ✕ ★ ◆ ▶ ○, which the theme's font (Godot's
## default Open Sans SemiBold) does not have: the desktop build borrows them from a system font,
## the web build has no system fonts and draws boxes (checked 2026-10-05 in the web export). Until a
## symbol fallback font is bundled with the theme (an owner decision, UI_THEME.md "Symbols"), these
## look-alikes from the font stand in. Bundle the font, then set each back to Phaser's glyph here.
##
## Owner: UI (game windows).

## Phaser ✓: done (tracker objectives, crafting materials, the dialogue's last page, the journal).
const CHECK := "√"
## Phaser ▸: go on (dialogue and conversation buttons).
const NEXT := "»"
## Phaser ✕: close (the dialogue box's corner button).
const CLOSE := "×"
## Phaser ★: a main-story quest (journal).
const MAIN := "*"
## Phaser ◆: a side quest (journal).
const SIDE := "◊"
## Phaser ▶: the current step (journal).
const CURRENT := "»"
## Phaser ○: a step not reached (journal).
const PENDING := "–"
