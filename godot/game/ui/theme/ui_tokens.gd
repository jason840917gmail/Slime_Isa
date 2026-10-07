extends RefCounted
class_name UiTokens
## Design tokens of the game's UI ("field kit"): the colours, sizes and font of the Phaser UI
## (src/styles.css `:root` and content/scenes/authored/resources/ui/field-kit.theme.resource.json,
## src/game/presentation/theme.ts). res://tools/build_ui_theme.gd builds
## res://game/ui/theme/slime_theme.tres from these values, and scripts that draw by hand
## (HUD bars) read the same values through the theme's `Palette` type. docs/godot/UI_THEME.md
## lists every theme type variation and the CSS role it replaces.
##
## Change a value here, then rebuild the theme:
##   "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_ui_theme.gd
##
## Owner: shell / UI theme.

## The theme every UI scene uses (will become the project theme, gui/theme/custom).
const THEME_PATH := "res://game/ui/theme/slime_theme.tres"

## The UI font: Source Sans 3 (SIL OFL, variable `wght`; owner pick 2026-10-05). Phaser asks for
## Trebuchet MS, which the web build cannot rely on. Empty = Godot's built-in default font. To
## change it, put the .ttf/.otf/.woff2 under res://game/ui/theme/fonts/, set its path here (and
## BOLD_FONT_PATH for a static bold face) and rebuild the theme: the theme's `default_font` and
## every bold variation follow it. A variable font (a `wght` axis) is drawn at REGULAR_WEIGHT, and
## its bold at BOLD_WEIGHT.
const FONT_PATH := "res://game/ui/theme/fonts/source-sans-3/SourceSans3[wght].ttf"
## A static bold face; empty = the variable font at BOLD_WEIGHT, else the regular font emboldened
## by BOLD_EMBOLDEN.
const BOLD_FONT_PATH := ""
const BOLD_EMBOLDEN := 0.55
const REGULAR_WEIGHT := 400
const BOLD_WEIGHT := 700
## A fallback font for the symbols the UI font lacks (✓ ▸ ✕ ★ ◆ ▶ ○; docs/godot/UI_THEME.md
## "Symbols"): Noto Sans Symbols 2 (SIL OFL). Empty = none.
const SYMBOL_FONT_PATH := "res://game/ui/theme/fonts/noto-sans-symbols-2/NotoSansSymbols2-Regular.ttf"
## Fonts for the developer readouts (FPS panel); system fonts, never bundled.
const MONOSPACE_FONTS: PackedStringArray = ["Consolas", "Menlo", "DejaVu Sans Mono", "Courier New", "monospace"]

# --- colours (styles.css :root, field-kit theme resource) ---------------------------------------
## --ui-bg: the page behind the game, fades.
const PAGE := Color("#0b1020")
## --scene-surface-base: modal windows.
const SURFACE_BASE := Color("#101a31")
## --scene-surface-raised: hovered / selected list rows, raised cards.
const SURFACE_RAISED := Color("#192642")
## --scene-surface-inset: buttons, bars, slider tracks, inputs.
const SURFACE_INSET := Color("#182b46")
## --scene-border-standard.
const BORDER := Color("#3b5c78")
## --scene-shadow / --ui-shadow: text shadows.
const SHADOW := Color("#081022")
## Window drop shadow (`box-shadow: 0 18px 48px #080e1abf`).
const DROP_SHADOW := Color("#080e1abf")
const TEXT := Color("#f5f7ff")
const TEXT_SECONDARY := Color("#c7e8d6")
const TEXT_TERTIARY := Color("#a7bbd6")
const TEXT_MUTED := Color("#8fbba3")
const ACCENT := Color("#86f0c3")
## UiTheme.colors.accentStrong (theme.ts), the old area banner border.
const ACCENT_STRONG := Color("#73e2b1")
const INFO := Color("#72d8ff")
const WARNING := Color("#ffd277")
const DANGER := Color("#ff6f88")
const SPECIAL := Color("#a78bfa")
## Boss card border and gradient top (styles.css `.game-ui--boss-health-bar`).
const BOSS_BORDER := Color("#8b2f2f")
const BOSS_SURFACE_TOP := Color("#261727")
## FPS readout text (dev/RenderingDiagnostics.ts).
const DEBUG_TEXT := Color("#d7e7f8")

# --- alphas of color-mix() in styles.css --------------------------------------------------------
## `.scene-control--modalroot` background: surface-base 94 %.
const PANEL_ALPHA := 0.94
## `.scene-control--modalroot` border: border-standard 74 %.
const PANEL_BORDER_ALPHA := 0.74
## Button / list border: border-standard 78 %.
const BUTTON_BORDER_ALPHA := 0.78
## Progress bar border: border-standard 68 %.
const BAR_BORDER_ALPHA := 0.68
## `:disabled { opacity: 0.45 }`.
const DISABLED_ALPHA := 0.45

# --- sizes ---------------------------------------------------------------------------------------
## field-kit `spacing-unit`; gaps are multiples of it.
const SPACING := 4
## field-kit `focus-width`: the 2 px warning focus outline.
const FOCUS_WIDTH := 2
## Default text size (Label/Button `fontSize` default in ControlNodes.ts).
const FONT_SIZE := 14
const FONT_SIZE_SMALL := 12
const FONT_SIZE_TITLE := 24
## HUD bar text (`.scene-control--progressbar { font-size: 11px }`).
const FONT_SIZE_BAR := 11


## The game theme (null when the file is missing, e.g. before the first build).
static func theme() -> Theme:
	return load(THEME_PATH) as Theme if ResourceLoader.exists(THEME_PATH) else null


## The colour of a Phaser `tone` ("default", "muted", "accent", "info", "warning", "danger",
## "special"); TEXT for anything else (HtmlControlPresentationAdapter.ts TONE_VARIABLE).
static func tone(tone_name: String) -> Color:
	match tone_name:
		"muted":
			return TEXT_MUTED
		"accent":
			return ACCENT
		"info":
			return INFO
		"warning":
			return WARNING
		"danger":
			return DANGER
		"special":
			return SPECIAL
	return TEXT
