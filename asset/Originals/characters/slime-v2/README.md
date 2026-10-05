# Player slime v2: three-quarter top-down sources

The owner asked on 2026-10-05 for a new player sheet: the old `slime_normalized` sheet is
side-view, has no real walk up or down, and snaps back to one facing when idle. The new slime
faces down, up and side (left mirrors side), seen from a higher camera like classic top-down
adventure games, and is built page by page.

## Files

| File | What it is |
|---|---|
| `turnaround-e.png` | The approved reference (candidate E of the second round, about a 55° camera): down, side (facing right), up. Magnific GPT 2.5 with the current slime, Lili and the directional beds sheet as references |
| `start-down.png`, `start-side.png`, `start-up.png` | Each view of E, scaled to 440 px tall and placed on a flat #FF00FF 1024 px square: the start AND end frame of every clip |
| `videos/<row>.mp4` | One Seedance 1.5 Pro clip per video row (4 s, 1:1, 1080p, no audio): `idle-down`, `idle-up`, `idle-side`, `walk-down`, `walk-up`, `walk-side`, `roll-down`, `roll-up` |
| `page-<n>.json` | The packer's choice per row: loop (or one-shot) start and length in source frames, the 8 sampled frames, the playback fps the Godot clips use, and whether the clip loops |

Rebuild a runtime sheet `asset/characters/256x256-tile_8x8-slime-v2-page-<n>.webp` with
`python scripts/characters/pack-slime-v2-page.py --page <n>` (see that file for the keying and
loop rules), then its clips with `godot/tools/build_player_clips.gd` (docs/TOOLING.md).

## Page 1 layout

8 x 8 cells of 256 px; the slime is 186 px wide in its first idle-down frame (the old sheet's
width), centred at x 128 and standing on y 251, like the old sheet, so it keeps its on-screen
size and fits the same 30 x 26 body.

| Row | Clip | Playback |
|---|---|---|
| 0 | idle-down | 2.7 fps |
| 1 | idle-up | 2.7 fps |
| 2 | idle-side | 5.05 fps |
| 3 | walk-down | 14.77 fps |
| 4 | walk-up | 16 fps |
| 5 | walk-side | 13.71 fps |
| 6, 7 | free | |

`idle-down` was retimed in the Godot editor on 2026-10-05 (8 fps, ping-pong, without column 2);
rebuild other clips with `build_player_clips.gd --only=<prefix>` so that tuning stays.

## Page 2 layout

Same cells, scale and baseline as page 1 (one scale for every page, from page 1's first frame).

| Row | Clip | Playback |
|---|---|---|
| 0 | roll-down | 16 fps, once (the 500 ms dodge roll) |
| 1 | roll-up | 16 fps, once |
| 2 | roll-side | 16 fps, once |
| 3-7 | free | |

- **roll-down and roll-up** are cut from their videos' tumbling stretch (source frames 25-46
  and 30-66). The clips drift sideways and bob, so every frame is centred and stood on the
  baseline on its own (in play the body moves during a dodge anyway).
- **roll-side is baked, not filmed.** Its video turned the slime toward the camera mid-roll, so
  the packer spins `start-side.png` clockwise in 45° steps (tucked to 88 % so the turned shape
  fits the cell): a right-facing slime rolling right; mirrored, it rolls left. The rejected take
  was not kept.
- **The sword swing has no sheet rows.** Three attack takes failed (the slime inflated like a
  balloon and grew fists; sparkles and a tall stretch; a stretch far beyond the cell), so the
  Godot `attack-1-<direction>` clips reuse page 1's idle art and carry the swing in keys: a
  wind-up on the row's most squashed frame, then a lunge toward the slash on its most stretched
  frame (`build_player_clips.gd`, `ATTACKS`).

## What worked (2026-10-05)

- **Same start and end frame.** Clips with only a start frame drifted: the background became a
  lit pink gradient with light rays, shadows and ripple rings, the idle slime melted into a puddle
  or grew, and the side walk turned to face the camera. Using the same image as start and end
  frame keeps the slime in place and closes the loop.
- **A plain prompt with no lighting words.** The style block's "warm golden light" lit the
  backdrop. The working prompt names the action, the facing ("never turns toward the viewer"),
  "keeps its exact painted look, size and position", and a "flat, unlit, solid #FF00FF
  chroma-key" background with an explicit list of what not to add.
- **Keying per frame.** The background still drifts from #FF00FF to a duller pink, so each frame
  is keyed against its own border colour; painted contact shadows (the background darkened) are
  removed by hue, not brightness.
- **Side walks are the hardest.** Seedance kept turning the slime toward the camera when it
  stretched upward; the third take ("glides like a slug, does not jump") still turned before
  frame 58, so the packer only uses its frames 58-96.

Cost: 7,080 Magnific credits for page 1, including both turnaround rounds and the discarded
first batch; 2,640 for page 2's six videos (three rolls, three rejected attacks).
