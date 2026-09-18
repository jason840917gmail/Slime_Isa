# Slime Isa interface system

## Direction

Slime Isa UI is an adventurer's field kit: compact, readable instruments laid over a playful authored world. Gameplay state leads; ornament supports it. Preserve the existing responsive layouts and illustrated skin assets during the universal-scene migration.

Domain cues: slime combat, forest and stone exploration, crafted gear, campfire progression, authored maps, and playful creature silhouettes.

Color world: dusk navy surfaces, moss green structure, slime lime success, parchment cream text, ember orange warnings, sky cyan information, and berry red danger.

The signature is a family of compact field instruments: meters, slots, journals, and map frames feel collected from the world rather than arranged as generic dashboard cards.

## System rules

- Depth: surface color shifts plus restrained, low-contrast borders. Illustrated frame assets may replace the code-drawn surface, but do not combine heavy shadows with heavy borders.
- Spacing: 4 px base unit. Prefer 8, 12, 16, 24, and 32 px for component and section spacing.
- Typography: `Trebuchet MS, Segoe UI Variable, sans-serif` for gameplay UI. Use weight, color, and tracking for hierarchy before adding new typefaces.
- Surfaces: `#101a31` base panel, `#192642` raised panel, `#182b46` inset/control field, `#3b5c78` quiet boundary, `#081022` deep shadow.
- Text: `#f5f7ff` primary, `#c7e8d6` secondary, `#a7bbd6` tertiary, `#8fbba3` muted.
- Semantic color: `#86f0c3` action/success, `#72d8ff` information, `#ffd277` reward/warning, `#ff6f88` danger, `#a78bfa` special ability.
- Focus: visible amber or mint outline with at least 2 px separation; modal surfaces always consume gameplay input.
- Motion: short cubic ease-out entrances and ease-in exits. No bounce.

## Reusable patterns

- Status instrument: label/value above or beside a quiet track; semantic color belongs in the fill, not the surrounding panel.
- Modal field panel: centered responsive surface, one clear close path, stack-owned Escape handling, restored focus on close, and explicit pause ownership.
- Slot grid: selected state uses an amber boundary; hover/focus use mint; unavailable state reduces contrast without removing the label.
- Scene Studio UI authoring: the common scene tree and inspector remain primary. UI layout handles are a viewport context, never a separate editor or duplicated property owner.
