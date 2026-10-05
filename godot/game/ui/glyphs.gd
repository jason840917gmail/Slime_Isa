extends RefCounted
## Symbols the game UI draws in text: Phaser's ✓ ▸ ✕ ★ ◆ ▶ ○, all in one place. The theme's Source
## Sans 3 has most of them and its fallback, Noto Sans Symbols 2, the rest (UI_THEME.md "Symbols").
## The web build has no system fonts, so a new symbol must be in one of the two
## (`Font.has_char`), or it draws as a box.
##
## Owner: UI (game windows).

## Done (tracker objectives, crafting materials, the dialogue's last page, the journal).
const CHECK := "✓"
## Go on (dialogue and conversation buttons).
const NEXT := "▸"
## Close (the dialogue box's corner button).
const CLOSE := "✕"
## A main-story quest (journal).
const MAIN := "★"
## A side quest (journal).
const SIDE := "◆"
## The current step (journal).
const CURRENT := "▶"
## A step not reached (journal).
const PENDING := "○"
