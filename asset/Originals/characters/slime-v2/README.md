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
| `end-sleep-down.png`, `end-defeated.png` | The end frames of the doze and the defeat (GPT 2.5 from `start-down.png` and Lili, transparent, placed like the start frames: centred, standing on the start's baseline, at 0.883 of the generated size); the sleep row loops on `end-sleep-down.png` |
| `videos/<row>.mp4` | One Seedance 1.5 Pro clip per video row (4 s, 1:1, 1080p, no audio): `idle-down`, `idle-up`, `idle-side`, `walk-down`, `walk-up`, `walk-side`, `roll-down`, `roll-up`, `stretch-down`, `stretch-up`, `stretch-side`, `doze-down`, `sleep-down`, `die-down`, `swim-down`, `swim-up`, `swim-side` |
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
| 6 | doze-down | 8 fps, once (Phaser's 1 s doze): a blink, heavy eyes, a yawn, asleep |
| 7 | sleep-down | 4.09 fps (one slow breath, 1.96 s), eyes closed, the sprout drooping |

`idle-down` was retimed in the Godot editor on 2026-10-05 (8 fps, ping-pong, without column 2);
rebuild other clips with `build_player_clips.gd --only=<prefix>` so that tuning stays.

## Page 2 layout

Same cells, scale and baseline as page 1 (one scale for every page, from page 1's first frame).

| Row | Clip | Playback |
|---|---|---|
| 0 | roll-down | 16 fps, once (the 500 ms dodge roll) |
| 1 | roll-up | 16 fps, once |
| 2 | roll-side | 16 fps, once |
| 3 | stretch-down | 29.63 fps, once (the lash's 270 ms reach); drawn 37 px higher in its cells |
| 4 | stretch-up | 29.63 fps, once |
| 5 | stretch-side | 29.63 fps, once; drawn 26 px left and 3 px higher in its cells |
| 6 | die-down | 8 fps, once (Phaser's 1 s defeat): a flinch, squeezed > < eyes, the melt into a puddle; drawn at 0.9 of the page scale so the puddle fits a cell |
| 7 | free | |

- **roll-down and roll-up are true front and back rolls** (re-filmed 2026-10-05: the first takes
  spun the slime sideways like a wheel, its sprout swinging round to the side). A ball rolling
  toward the camera moves everything on it DOWN the screen: the sprout folds over the face, the
  face slides under, the back rolls over, the face comes back from the top. Rolling away moves
  everything UP. The prompts said so in screen terms ("everything on the ball moves straight down
  the screen ... never a sideways spin"); of two takes each, the down take rolled the right way
  only backwards (its features slide up), so `PICKS` plays its frames in reverse
  (36, 33, 30, 27, 22, 15, 10, 4); the up take's first roll is used as filmed (8-34). The other
  takes (a sprout that came off, sparkles) were not kept. Every frame is centred and stood on the
  baseline on its own (`RECENTRED`): the takes bob and hop, and in play the body moves anyway.
- **roll-side is baked, not filmed.** Its video turned the slime toward the camera mid-roll, so
  the packer spins `start-side.png` clockwise in 45° steps (tucked to 88 % so the turned shape
  fits the cell): a right-facing slime rolling right; mirrored, it rolls left. The rejected take
  was not kept.
- **The sword swing has no sheet rows.** Three attack takes failed (the slime inflated like a
  balloon and grew fists; sparkles and a tall stretch; a stretch far beyond the cell), so the
  Godot `attack-1-<direction>` clips reuse page 1's idle art and carry the swing in keys: a
  wind-up on the row's most squashed frame, then a lunge toward the slash on its most stretched
  frame (`build_player_clips.gd`, `ATTACKS`).
- **The stretch lash is filmed** (rows 3-5). Each take reaches twice and wobbles in between, so
  the packer uses hand-picked source frames (`PICKS`): neutral, reach, hold, back to neutral (the
  side pulls back through its reach frames reversed). The down arm hangs below the baseline and
  the side arm reaches past the cell, so those rows are drawn shifted in their cells (`SHIFTS`,
  recorded as `shift` in page-2.json) and `build_player_clips.gd` keys `Visual:offset` back by
  the shift; the shifted side row also gets a mirrored `stretch-left` clip. Down frames whose
  stretched body and hanging arm span more than a cell (about 270 px) are left out. The up take
  stretches the sprout itself into the lash. The first side take slid the whole slime off-frame
  along a long arm; the second ("a short, stubby, rounded jelly arm ... the body itself stays
  exactly where it is") was kept and the first was not.
- **Rest and defeat face the viewer only** (owner decision 2026-10-05: replace all the old player
  art). Doze, sleep and defeat are filmed facing down, from `start-down.png` to an end still
  (`end-sleep-down.png`, `end-defeated.png`); the player turns to the camera before it dozes or
  falls (`face(Vector2.DOWN)`), so no turning take is needed. The sleep loop is cut from frames
  0-72 (the take perks its sprout up after that). The defeat take opens with a hand poking the
  slime, so its picks start at frame 56.
- **No old clip is left.** `build_player_clips.gd` removes every clip it does not build, so the
  player scene no longer uses the old `slime_normalized` sheet (Phaser's `attack-2`, `attack-3`,
  `cast`, `charge`, `hurt` and `trick` were never played by the port).
- **The other abilities have no sheet rows** (owner decision 2026-10-05: keys from the new art,
  only the stretch lash filmed). `hop`, `squash`, `teleport`, `eat` and `knockback`, each `-down`, `-up` and `-side`, pick page 1's idle and walk cells by pose (`POSES`: rest; low,
  the widest cell; tall, the narrowest; an open mouth and a chew for eating) at keyed times
  (`ACTIONS`). The ability sequences' tweens carry the squash, stretch, arc and fade. Measured
  width / height per cell: down low `walk-down` 1 (1.18), tall `idle-down` 3 (0.71); up low
  `walk-up` 0 (1.27), tall `walk-up` 4 (0.71); side low `walk-side` 0 (0.99), tall `walk-side` 2
  (0.70).

## Page 3 layout

Same cells, scale and baseline as pages 1 and 2.

| Row | Clip | Playback |
|---|---|---|
| 0 | swim-down | 7.38 fps |
| 1 | swim-up | 6.19 fps |
| 2 | swim-side | 6.0 fps |
| 3-7 | free | |

- **Swimming is treading water** (owner, 2026-10-06: the classic top-down games show the swimmer's
  head and a ripple). The takes start and end on `start-<direction>.png` with "treads water in
  place ... bobs gently down and up twice ... no water is shown"; the game draws the water (the
  wake ripple, `game/world/water_wake.gd`) and will hide the lower body under a waterline.
- **Every swim frame is stood on the baseline** (`RECENTRED`): the takes hop up to 60 px out of
  the "water"; on the baseline their squash and stretch reads as sinking and rising under the
  waterline. The down take squashes very flat (240 px wide), so its eyes sit about 50 px above the
  baseline: the waterline must stay below that.
- **swim-side is the second take.** The first turned the slime toward the camera halfway (like the
  side walk); the second said "strict side view ... we see one eye and its profile, and it never
  turns its face or body toward the viewer, not even for a moment ... does not jump" and held the
  profile. The first was not kept.

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
first batch; 2,640 for page 2's six videos (three rolls, three rejected attacks); 1,760 for the
four lash videos (one rejected side take); 1,720 for the rest and the defeat (four stills at 100,
three videos); 1,760 for the re-filmed down and up rolls (two takes each). Page 3: 1,760 for the four swim videos (one rejected side take).
