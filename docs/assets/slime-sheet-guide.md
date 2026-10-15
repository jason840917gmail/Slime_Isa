# Slime Sheet Guide

The format of the player slime sheets, the reference layout for slime-style
animated characters. The player draws the three-quarter top-down pages ([below](#three-quarter-top-down-sheet-v2-godot));
the side-view sheet described first is retired (no player clip uses it; the Gulp form skins were built from it).

## Sheet format

- Asset ID: `character.player.slime`; texture key `slime`
- File: `godot/asset/characters/slime_normalized.webp`
- Sheet: `2048 x 2048 px`, `8 columns x 8 rows` of `256 x 256 px` frames
- Index rule: `frame = row * 8 + column`
- Default art facing: left (flipped at runtime when moving right)

## Runtime measurements

Set in `godot/game/characters/player_slime.tscn`:

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
scene's AnimationPlayer (Godot editor).

## Authoring tips

- Keep a shared baseline guide visible while animating.
- Test idle, walk, and special frames together before exporting the sheet.
- Avoid frame-to-frame anchor drift in the lower body.

## Three-quarter top-down sheet (v2, Godot)

Since 2026-10-05 the player is being redrawn for the three-quarter top-down camera, page by
page, for the Godot port (the Phaser game used the sheet above). Sources, prompts and lessons
are in `asset/Originals/characters/slime-v2/README.md`.

- Pages: `godot/asset/characters/256x256-tile_8x8-slime-v2-page-<n>.webp` (`character.player.slime.v2.page-<n>`),
  8 x 8 cells of 256 px, same placement as the old sheet (186 px wide, centred at x 128,
  standing on y 251) so the slime keeps its size and body.
- One row per clip and direction, 8 frames, named `<clip>-down`, `<clip>-up`, `<clip>-side`;
  side art faces right and is mirrored for left. Rows never move once filled, so adding a
  page or a row never renumbers existing frames.
- Page 1: rows 0-5 = idle down/up/side, walk down/up/side; row 6 = doze-down (one-shot, 1 s);
  row 7 = sleep-down (loop).
- Page 2: rows 0-2 = roll down/up/side (one-shot, timed to the 500 ms dodge; down and up are
  true front and back rolls, the side roll is spun in the picture); rows 3-5 = stretch
  (the lash) down/up/side (one-shot, 270 ms; hand-picked frames, the down and side rows drawn
  shifted in their cells, see the slime-v2 README); row 6 = die-down (one-shot, 1 s, drawn at
  0.9 scale so the puddle fits); row 7 free. Since 2026-10-09 the roll rows are no longer played
  (the Dodge became the Roll, which spins page 4's ball).
- Page 3: rows 0-2 = swim down/up/side (loops, 6-7.4 fps): the slime treading water, squashing as it
  sinks and stretching as it rises, every frame stood on the baseline. The whole body is drawn: the
  swimmer (the Frog Gulp form, `game/player/gulp/player_swimming.gd`) hides its lower part under a
  waterline 30 px above the baseline (keep it below about 40 px of the cell so the eyes of the
  flattest down frames show). Rows 3-7 free.
- Page 4 (2026-10-09): rows 0-2 = suck down/up/side (loops while Q sucks); rows 3-5 = spit
  down/up/side (one-shot, 300 ms: the take starts full and pops empty); row 6 = ball-side (the
  Roll's ball, spun in the picture from `start-ball.png`); row 7 free.
- Page 5 (2026-10-09): rows 0-2 = full down/up/side, the full slime's waddle (loops, 8 fps), drawn
  at page 1's scale and so bigger than the slime; `full-idle-<direction>` play the same rows at
  2.67 fps, a slow sway at rest; rows 3-4 = ball-down and ball-up (the Roll's ball rolled on a
  sphere toward and away from the camera, 2026-10-09). Rows 5-7 free.
- Page 6 (2026-10-12): the body shapes' attack key poses, four per shape and direction
  (asset/Originals/characters/slime-v2/shapes/README.md: rows 0-4, groups of four columns; row 4
  columns 4-7 and rows 5-7 free). Not row clips: each cell the game shows is its own one-frame clip
  `shape-<shape>-<pose>-<down|up|side>` (side faces right, mirrored for left), held by
  game/shapes/shape_poses.gd as long as the pose lasts; only the War Axe's `load`, `swing-down` and
  `swing-up` are built (its Spin; every other strike plays its strike frames). Packed by
  `python scripts/characters/pack-slime-shape-poses.py` (not the page packer), at page 1's cells and
  baseline.
- Strike sheet (2026-10-12): `godot/asset/characters/512x416-tile_8x8-slime-v2-strikes.webp`, the
  Spear's body-only strike frames (asset/Originals/characters/slime-v2/shapes/README.md "Strike
  sheet"). 8 x 8 cells of 512 x 416, larger than the pages' so the lunges and the necks fit, centred
  like page 1 (page 1's x 128 is x 256, its centre y 128 is y 208; the rest frames stand on page 1's
  idle ground and middle at its scale). Rows 0-2 = spear-jab side/down/up, rows 3-5 = spear-finisher
  side/down/up, columns 0-5 = frames 1-6 (rest, lean or wind-up, lunge with the bump, full lean,
  spring back, rest); rows 6-7 and columns 6-7 free. Each strip is drawn at one scale with its back
  (side) or middle (down/up) and its ground on the same pixel in every frame; frames 3 and 4 carry the
  jelly neck the code-drawn spear joins. The sockets, bumps and spear states are in
  `godot/game/data/shape-strikes.json`. No clips in the player scene: the game builds the strike
  animations at run time from `godot/game/characters/strikes/` (StrikeLibrary: each keys the sheet, the
  frame and `Visual:offset` (-256, -208), the sheet's -origin; side faces right, mirrored for left),
  sought by game/shapes/shape_poses.gd. Packed by `python scripts/characters/pack-slime-strikes.py`
  (the War Axe's and the Hammer's sheets, `...-strikes-axe.webp` and `...-strikes-hammer.webp`, laid
  out the same way, by `pack-slime-weapon-strikes.py`).
- The sword swing (`attack-1-down/-up/-side/-left`) has no rows: it reuses page 1's idle art
  and carries a wind-up and a lunge toward the slash in animation keys (`Visual:offset`, plus
  `Visual:skew` for the side). A `-left` clip exists only when keyed motion or a shifted row
  has a direction, because flip_h mirrors the art but not an offset.
- The other abilities, eating and knockback (`hop`, `squash`, `teleport`, `eat`, `knockback`) have
  no rows either: keyed clips pick page 1's cells by pose (`build_player_clips.gd`, `ACTIONS`).
- Build a page with `python scripts/characters/pack-slime-v2-page.py --page <n>`, then add its
  clips to the Godot player scene with `tools/build_player_clips.gd` (see docs/TOOLING.md). The
  player script plays every clip in the version for its facing (`<clip>-down/-up/-side`, or
  `-left`) and keeps that facing when idle. Doze, sleep and the defeat exist facing down only,
  and the player turns to the camera before them. The old sheet is no longer used by the player
  (every clip of `player_slime.tscn` draws a v2 page).
