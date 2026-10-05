# Slime Sheet Guide

The format of the player slime sheet, the reference layout for slime-style
animated characters.

## Sheet format

- Asset ID: `character.player.slime`; texture key `slime`
- File: `asset/characters/slime_normalized.webp`
- Sheet: `2048 x 2048 px`, `8 columns x 8 rows` of `256 x 256 px` frames
- Index rule: `frame = row * 8 + column`
- Default art facing: left (flipped at runtime when moving right)

## Runtime measurements

Set in `src/game/content/scenes/authored/characters/player-slime.scene.json`:

- `Visual` sprite: origin `[0.5, 0.5]`, scale `0.28125` (72 px on screen)
- Movement body: `30 x 26` rectangle on the `CharacterBody2D`

The slime should sit in the lower middle of each cell and stay there across
frames; if it drifts, the art no longer matches the body.

## Frame placement rules

- Uniform grid only; keep every pose inside its own `256 x 256` cell,
  including the widest squash and tallest stretch.
- Keep the slime bottom-aligned and horizontally centred.
- Use transparent padding instead of changing the frame size.

## Row layout

Clip frame indices live in the scene's `AnimationPlayer` library. Current use:

| Row | Frames | Clips |
| --- | --- | --- |
| 0 | 0-7 | idle (and doze pose) |
| 1 | 8-15 | walk |
| 2 | 16-23 | hop (moving down) |
| 3 | 24-31 | squash: hurt, knockback, die |
| 4 | 32-39 | stretch (moving up) |
| 5 | 40-47 | roll/boost, eat, doze, sleep |
| 6 | 48-55 | trick, attacks, charge |
| 7 | 56-63 | teleport, cast |

If you change the layout, update the frame keys of the affected clips in the
Scene Studio animation dock.

## Authoring tips

- Keep a shared baseline guide visible while animating.
- Test idle, walk, and special frames together before exporting the sheet.
- Avoid frame-to-frame anchor drift in the lower body.

## Three-quarter top-down sheet (v2, Godot)

Since 2026-10-05 the player is being redrawn for the three-quarter top-down camera, page by
page, for the Godot port (the Phaser game keeps the sheet above). Sources, prompts and lessons
are in `asset/Originals/characters/slime-v2/README.md`.

- Pages: `asset/characters/256x256-tile_8x8-slime-v2-page-<n>.webp` (`character.player.slime.v2.page-<n>`),
  8 x 8 cells of 256 px, same placement as the old sheet (186 px wide, centred at x 128,
  standing on y 251) so the slime keeps its size and body.
- One row per clip and direction, 8 frames, named `<clip>-down`, `<clip>-up`, `<clip>-side`;
  side art faces right and is mirrored for left. Rows never move once filled, so adding a
  page or a row never renumbers existing frames.
- Page 1: rows 0-5 = idle down/up/side, walk down/up/side; rows 6-7 free.
- Build a page with `python scripts/characters/pack-slime-v2-page.py`, then add its clips to
  the Godot player scene with `tools/build_player_clips.gd` (see docs/TOOLING.md). The player
  script picks the directional clip for its facing and keeps that facing when idle; clips
  without a directional version still draw the old sheet.
