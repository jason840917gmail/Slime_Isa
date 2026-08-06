# Weapon Spritesheet Prompt Design

## Status

Approved by the user on 2026-08-06.

## Goal

Add a reusable prompt system for generating weapon animation spritesheets that
fits Slime Isa's existing modernized pixel-stylized top-down art direction and
current 64×64 weapon-cell convention. Add a concrete prompt for a sword attack
sheet with three directional rows and ten frames per row.

## Scope

Create two Markdown files under a new root-level `prompts/` directory:

1. `weapon-spritesheet-prompt-template.md`
   - Generic, model-neutral template for future melee and ranged weapon sheets.
   - Captures reference-image handling, sheet geometry, row/column semantics,
     pivot/anchor stability, art direction, solid-background/no-alpha export
     rules, negative constraints, and an artist QA checklist.
2. `sword-attack-3x10.md`
   - Copy/paste-ready sword prompt using the generic rules.
   - Includes an explicit `[ATTACH REFERENCE IMAGE HERE]` placeholder because
     the user will supply the sword reference image separately.

No bitmap is generated and no runtime manifest or gameplay code is changed.

## Approved sheet contract

- Grid: 10 columns × 3 rows.
- Cell size: 64×64 px, matching the current authored weapon convention.
- Full image: 640×192 px.
- Background: one flat solid chroma purple, exactly `#8000FF`, filling the
  entire canvas and every cell; no gradients, checkerboard, texture, or
  background scenery.
- Every cell is a separate uniform frame with no gutters, labels, borders, or
  frame lines.
- The weapon's logical attachment pivot stays in a consistent location in every
  frame; the purple field absorbs motion and size changes.
- No blade, glow, slash trail, or impact effect may be cropped by its cell.

## Approved row mapping

- Row 1: side attack, authored facing right and safe to mirror for left-facing
  playback.
- Row 2: downward attack, weapon moves toward the bottom of the frame.
- Row 3: upward attack, weapon moves toward the top of the frame.

## Approved frame progression

Each row must read left-to-right as one complete attack:

| Columns | Phase | Requirement |
| --- | --- | --- |
| 1–3 | Preparation / wind-up | Neutral start, raise or draw back, then a clear loaded pose. |
| 4–6 | Attack / active contact | Acceleration, strongest swing, and readable contact or maximum reach. |
| 7–10 | Follow-through / recovery | Overshoot, deceleration, return toward neutral, and a clean endpoint. |

The progression must not jump directly from idle to impact. The contact moment
must be visually distinct without permanently baking gameplay hitboxes into the
art.

## Art direction

The prompts must use the project's existing direction: modernized pixel-stylized
top-down 2D game art, chunky readable silhouettes, deliberate pixel clusters,
deep cool outlines, cool shadows, selective highlights, and controlled material
gradients only when useful. Use the existing palette language as a guide:
deep-night outline/shadow, cyan or mint energy accents, and restrained warm
contact highlights. The supplied reference image remains authoritative for the
sword's silhouette, proportions, materials, and distinctive design details.

## Reusable rules added

The generic template will also enforce these useful rules:

- Treat the sheet as a grid, never as a collage or a sequence of separate
  illustrations.
- Keep camera angle, scale, lighting direction, palette, outline thickness, and
  pivot consistent across all frames and rows.
- Preserve the weapon's identity while changing pose; do not redesign it from
  frame to frame.
- Use one clear dominant action per frame and avoid unreadable motion blur.
- Keep trails, sparks, glints, and impact flashes subordinate to the weapon's
  silhouette and use them only where the phase calls for them.
- Keep the weapon visually centered around its pivot, while allowing the blade
  and effects to travel within the cell.
- Do not put a character, UI, text, damage numbers, enemies, or scenery into the
  sheet unless explicitly requested.
- Avoid duplicate frames, frozen poses, missing recovery frames, accidental
  extra rows/columns, and inconsistent facing.
- Export at exact integer dimensions with nearest-neighbor-friendly hard edges;
  preserve the solid `#8000FF` background as a clean flat chroma field and do
  not add anti-aliased resampling.

## Verification

The prompt documents are complete when:

- The reusable template can be adapted by replacing bracketed inputs.
- The sword prompt is directly usable after attaching a reference image.
- Both files agree on the 10×3 grid, 64×64 cells, row directions, pivot rules,
  and frame phases.
- The prompt explicitly requests a solid `#8000FF` background and exact 640×192
  output.
- The prompt includes positive art direction and a negative prompt/checklist that
  addresses common spritesheet-generation failures.
