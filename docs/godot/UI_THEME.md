# UI theme

The Godot port has one UI Theme, `res://game/ui/theme/slime_theme.tres`, which redoes the
Phaser game's HTML/CSS look (`src/styles.css`, the field-kit theme resource
`content/scenes/authored/resources/ui/field-kit.theme.resource.json`) as Godot styleboxes,
colours, fonts and **type variations**. Every Control screen uses it: the shell (title, pause,
settings, controls, credits, game over, end card, area banner), the HUD, and the game windows
(inventory, chest, crafting, quests, dialogue, saves, map). The converted UI scenes under
`godot/generated/scenes/ui/` still point at the converter's minimal
`generated/resources/ui_theme.tres`; screens that Godot owns use this theme instead.

## Files and how to change the theme

| File | What it holds |
|---|---|
| `godot/game/ui/theme/ui_tokens.gd` (`UiTokens`) | The design tokens: colours, alphas, font sizes, the font paths. One place to change a colour |
| `godot/tools/build_ui_theme.gd` | Builds the theme from the tokens: every stylebox, colour, constant, font and variation, and the small icons (slider thumb, check boxes, switch, option arrow), which it draws and stores inside the `.tres` |
| `godot/game/ui/theme/slime_theme.tres` | The tool's output. Do not edit it in the editor: the next build would drop the edit |

To change the look, edit the tokens or the builder, then rebuild and commit both:

```bash
"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_ui_theme.gd
```

`pnpm test:godot` (`test_shell.gd::test_ui_theme_has_every_documented_variation`) fails when the
`.tres` is older than the builder, or when a variation listed below is missing.

**Applying it.** The theme becomes the project theme (`gui/theme/custom`), so every Control picks it
up. Until that is set, a screen's root Control sets `theme` to it explicitly (the shell scenes in
`res://game/shell/` and the HUD do; code can use `UiTokens.theme()`). Pick a role with the Control's
**Theme Type Variation** (`theme_type_variation`), not with per-node colour overrides; override
only what is really per node (a font size from the Phaser scene, a tone that changes at run time).

**Colours in code.** Scripts that draw by hand read the tokens from the theme's `Palette` type:
`get_theme_color(&"accent", &"Palette")` (names: `page`, `surface_base`, `surface_raised`,
`surface_inset`, `border`, `shadow`, `drop_shadow`, `text`, `text_secondary`, `text_tertiary`,
`muted`, `accent`, `accent_strong`, `info`, `warning`, `danger`, `special`; constants `spacing` 4 and
`focus_width` 2), or use the `UiTokens` constants directly.

## Font

Phaser asks for `"Trebuchet MS", "Segoe UI Variable", sans-serif`, which a web build cannot rely on
(Trebuchet is not licensed for redistribution). The theme uses **Godot's built-in default font**
(Open Sans SemiBold) for now: `UiTokens.FONT_PATH` is empty, so the theme's `default_font` is unset,
and the bold roles use a `FontVariation` with no base font (the default font emboldened by
`UiTokens.BOLD_EMBOLDEN`).

Recommendation: bundle an open-licence humanist sans close to Trebuchet's feel, such as **Fira
Sans** or **Source Sans 3** (both SIL OFL), regular and bold, under `res://game/ui/theme/fonts/`.
Then set `FONT_PATH` (and `BOLD_FONT_PATH` for the real bold face) in `ui_tokens.gd` and rebuild:
the theme's `default_font` and every bold variation follow it. The editor imports the font files
the first time it scans them.

**Symbols.** The default font has no arrows (↑ ↓ ← →), check mark (✓), triangles (▸ ▶), star (★)
or ◆ ○. Desktop builds borrow them from a system font; the **web build has no system fallback and
draws them as boxes**. Until a symbol fallback font is bundled (an OFL font with those glyphs added
as a fallback of the theme's fonts; it needs the owner's go-ahead), UI text uses words or glyphs
the default font has: `√ * ◊ » – · … − • ×` are present (checked with `Font.has_char`). The
look-alikes live in one place, `res://game/ui/glyphs.gd` (CHECK √, NEXT », CLOSE ×, ...): once a
symbol font is bundled, editing that file brings Phaser's ✓ ▸ ✕ back everywhere. The key names
spell out Up / Down / Left / Right (`ControlLabels`), and the world map draws its symbols as shapes.

## Tokens

| CSS (`styles.css` `:root`, field-kit resource) | `UiTokens` | `Palette` | Value |
|---|---|---|---|
| `--ui-bg` | `PAGE` | `page` | `#0b1020` |
| `--scene-surface-base` | `SURFACE_BASE` | `surface_base` | `#101a31` |
| `--scene-surface-raised` | `SURFACE_RAISED` | `surface_raised` | `#192642` |
| `--scene-surface-inset` | `SURFACE_INSET` | `surface_inset` | `#182b46` |
| `--scene-border-standard` | `BORDER` | `border` | `#3b5c78` |
| `--scene-shadow` | `SHADOW` | `shadow` | `#081022` |
| window `box-shadow` colour | `DROP_SHADOW` | `drop_shadow` | `#080e1abf` |
| `--scene-text-primary` | `TEXT` | `text` | `#f5f7ff` |
| `--scene-text-secondary` | `TEXT_SECONDARY` | `text_secondary` | `#c7e8d6` |
| `--scene-text-tertiary` | `TEXT_TERTIARY` | `text_tertiary` | `#a7bbd6` |
| `--scene-text-muted` (tone `muted`) | `TEXT_MUTED` | `muted` | `#8fbba3` |
| `--scene-accent` | `ACCENT` | `accent` | `#86f0c3` |
| `accentStrong` (`theme.ts`) | `ACCENT_STRONG` | `accent_strong` | `#73e2b1` |
| `--scene-info` | `INFO` | `info` | `#72d8ff` |
| `--scene-warning` | `WARNING` | `warning` | `#ffd277` |
| `--scene-danger` | `DANGER` | `danger` | `#ff6f88` |
| `--scene-special` | `SPECIAL` | `special` | `#a78bfa` |

`color-mix()` alphas: windows 94 % surface and 74 % border (`PANEL_ALPHA`, `PANEL_BORDER_ALPHA`),
buttons and lists 78 % border, bars 68 % border, `:disabled` 45 % opacity (`DISABLED_ALPHA`).

## What the base types look like

| Type | Look (CSS source) |
|---|---|
| `Label` | 14 px `text`, no shadow (`.scene-control--label`) |
| `Button`, `MenuButton`, `OptionButton` | Inset fill, 1 px border at 78 %, square; hover: accent text and border; pressed: base surface with accent border; focus: 2 px warning ring 2 px outside; disabled: 45 % (`.scene-control--button`, styles.css:3206-3232) |
| `Panel`, `PanelContainer` | The modal window: base surface 94 %, 1 px border 74 %, square, content margins 24 / 16 (`.scene-control--modalroot`, :3176-3185) |
| `ProgressBar` | Inset well, border 68 %, accent fill, 11 px text (`.scene-control--progressbar`, :3192-3204) |
| `HSlider`, `VSlider` | 8 px inset track (radius 4) filled with accent up to a 16 px warning thumb with an inset ring; focus ring 4 px out (`.scene-control--slider`, :3240-3312) |
| `CheckBox`, `CheckButton` | 16 px rounded box (accent with a dark tick when on), radio rings, a 32 × 16 switch |
| `ItemList` | Rows read like Phaser's list buttons: hover = inset with accent border, selected = raised surface with warning border and text (:3207-3238) |
| `TabContainer`, `TabBar` | Rounded tab buttons (radius 6) like the menu tab strip; the open tab in warning |
| `LineEdit`, `TextEdit` | Inset fill, border 78 %, warning caret and focus ring, accent selection |
| `ScrollBar`s | 8 px, inset track, border-coloured grabber, accent on hover |
| `PopupMenu`, `PopupPanel`, `TooltipPanel` / `TooltipLabel` | Raised surface with border and a soft drop shadow; tooltip text 12 px |
| `RichTextLabel` | `text` colour, bold = the bold font, 14 px |
| `HSeparator`, `VSeparator` | 1 px border line |
| `BoxContainer`s, `GridContainer`, flow containers | 8 px gaps (two spacing units, Phaser's menu gap) |

## Type variations

Set these names as a Control's **Theme Type Variation**. "Base" is the type the variation extends;
Panel variations work on both `Panel` and `PanelContainer`.

### Panels

| Variation | Base | Replaces (styles.css) | Use for |
|---|---|---|---|
| `ModalPanel` | PanelContainer | `.scene-control--modalroot` (:3176) | Shell windows: title, pause, settings, controls, credits, game over, end card, save slots. Square, as Phaser draws them |
| `WindowPanel` | PanelContainer | `.game-ui--inventory-ui`, `--chest-inventory-panel`, `--crafting-ui`, `--quest-journal`, `--quest-offer-modal`, `--world-map-ui` (:3429, 3529, 3566, 3613, 3678) | Game windows: radius 12 and the `0 18px 48px` drop shadow |
| `DialoguePanel` | PanelContainer | `.game-ui--npc-dialogue` (:3648) | The NPC conversation box: 2 px warning border at 55 %, radius 14 |
| `NamePlate` | PanelContainer | `.game-ui--npc-dialogue [/speaker]` (:3659) | The speaker pill on the dialogue's top edge |
| `TabStripPanel` | PanelContainer | `.game-ui--menu-tabs` (:3744) | The tab strip over bag / crafting / journal / map |
| `BannerPanel` | PanelContainer | `.game-ui--area-title-card` (:3368) | Area and "ability learned" banners |
| `HintPanel` | PanelContainer | `.game-ui--control-hint` (:3731) | First-time control hints (pill) |
| `TrackerPanel` | PanelContainer | `.game-ui--quest-tracker` (:3692) | The quest tracker card under the HUD (thick warning left edge) |
| `BossPanel` | PanelContainer | `.game-ui--boss-health-bar` (:3396) | The boss health card (red border) |
| `InsetPanel` | PanelContainer | inset wells (`--scene-surface-inset`) | Detail panes, empty slots, list backgrounds inside a window |
| `BarePanel` | PanelContainer | `.game-ui--hud` / `--weapon-hotbar` (`background: transparent`, :3786) | HUD groups and wrappers that must not draw |
| `DebugPanel` | PanelContainer | `dev/RenderingDiagnostics.ts` | Developer readouts (the FPS panel) |

### Labels

| Variation | Replaces | Use for |
|---|---|---|
| `PanelTitle` | window titles (Label `fontSize` 24, `fontWeight` 700, tone `warning`) | "Settings", "Controls", "Credits", "Paused" (26 px override), window headings |
| `MutedLabel`, `SecondaryLabel`, `TertiaryLabel`, `AccentLabel`, `InfoLabel`, `WarningLabel`, `DangerLabel`, `SpecialLabel` | Label `tone` muted / secondary / tertiary / accent / info / warning / danger / special | Any label whose Phaser scene sets that tone. `UiTokens.tone(name)` maps a tone name to its colour |
| `CaptionLabel` | 12 px muted status lines | "Esc resumes", "Changes apply immediately …", hints under a window |
| `KeyLabel` | bold accent key names (controls list) | Key names in lists and prompts |
| `HudLabel` | `.game-ui--hud` text with `text-shadow` (:3786) | Text over the world (coins, tracker lines): 12 px bold with a dark shadow |
| `AreaTitle` | `.game-ui--area-title-card .scene-control--label` (:3378) | The banner text (24 px bold, shadow; the colour is set per banner) |
| `BossName` | boss card name (16 px bold, danger) | The boss name over its bar |
| `DefeatTitle` | game-over "Defeated" (32 px, danger) | Defeat headings |
| `EndCardTitle` | `.game-ui--end-card [/title]` (:3728) | Chapter end titles (34 px special, shadow and violet glow) |
| `DebugLabel` | `RenderingDiagnostics` text | Developer readouts (11 px monospace) |
| `TrackerObjectiveLabel` | quest tracker objective lines | Objective lines in the HUD tracker: 12 px regular text with the soft HUD shadow |

### Buttons

| Variation | Replaces | Use for |
|---|---|---|
| `PrimaryButton` | Button `tone: accent` | The main action of a window: New Game, Resume, Wake, Return to title, Craft |
| `MutedButton` | Button `tone: muted` | Secondary / leaving actions: Close, Cancel, Defaults, Credits, Quit to Title |
| `DangerButton` | Button `tone: danger` | Destructive confirmations ("Start new game", delete a save) |
| `WarningButton` | Button `tone: warning` | Attention toggles ("Mute all") |
| `TabButton` | `.game-ui--menu-tabs .scene-control--button` (:3744-3781) | Menu tabs; the open tab is the disabled button (Phaser) or a pressed toggle button, drawn in warning |
| `SlotButton` | `.scene-control--itemlist > button` in the bag / chest / belt / crafting (:3434, 3234) | Item cells and selectable rows: radius 8, toggled = selected (warning border on the raised surface) |
| `GhostButton` | `.game-ui--quest-tracker [/track-]` (:3708) | Borderless clickable text blocks (tracker "show the way", inline links) |
| `BoldButton` | `.scene-control--modalroot .scene-control--button` weight 700 (:3620) | A button whose text should be bold |
| `HotbarSlot` | HUD weapon hotbar slots (artwork-first HUD) | Belt slots over the world: transparent, 1 px text-colour border at 38 %, radius 5; toggled = selected (warning border) |
| `BeltSlot`, `BeltSlotFilled` | belt slots in the bag window | `SlotButton` with a 60 % border while the slot is empty (`BeltSlot`) and a solid one once it holds a weapon (`BeltSlotFilled`) |
| `DialogueNextButton` | the dialogue box's Next button | Accent, bold, radius 8 |

### Bars

| Variation | Base | Replaces | Use for |
|---|---|---|---|
| `HudBar` | ProgressBar | `.game-ui--hud .scene-control--progressbar` (:3793) | The HUD pills (HP, energy): transparent, 42 % white border, dark ring, full radius. `game/ui/hud_bar.gd` draws its label text and tints the fill per bar |
| `BossBar` | ProgressBar | `.game-ui--boss-health-bar .scene-control--progressbar` (:3407) | The boss bar: inset well, radius 5, danger fill |
| `FloatingHealthBar` | ProgressBar | `.game-ui--health-bar .scene-control--progressbar` (:3390) | The 56 × 8 bar over the player (radius 4, no text) |

A plain `ProgressBar` (or one of these) takes its fill colour from the theme's `fill` stylebox;
for a per-bar tone, override `theme_override_styles/fill` with a copy whose `bg_color` is the tone,
as `hud_bar.gd` does in code.

## Differences from the Phaser look

- The font (above); Godot's default font is a little wider and heavier than Trebuchet MS.
- CSS gradients are drawn flat (the banner and boss card use their gradient's middle colour; the
  control hint and tracker use an average alpha); `text-shadow` blur becomes Godot's shadow outline.
- The area banner and the boss card follow their CSS rules (accent / red border). In the Phaser
  build a more specific `.scene-control--container.game-ui` rule overrides both, so they show the
  standard window border there.
- The controls list keeps each key on its description's row when the description wraps (Phaser's
  two-column text drifts out of line).
