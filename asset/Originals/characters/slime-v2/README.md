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
| `start-ball.png` | The Roll's ball (2026-10-09): the slime curled into a ball, its sprout lying flat on it (`asset/Originals/gulp/generated/ball-b.png`, GPT 2.5), on a flat #FF00FF 1024 px square; the packer spins it into page 4's `ball-side` |
| `videos/<row>.mp4` | One Seedance 1.5 Pro clip per video row (4 s, 1:1, 1080p, no audio): `idle-down`, `idle-up`, `idle-side`, `walk-down`, `walk-up`, `walk-side`, `roll-down`, `roll-up`, `stretch-down`, `stretch-up`, `stretch-side`, `doze-down`, `sleep-down`, `die-down`, `swim-down`, `swim-up`, `swim-side`, and since 2026-10-09 `suck-down`, `suck-up`, `suck-side`, `spit-down`, `spit-up`, `spit-side`, `full-down`, `full-up`, `full-side`. The full slime's start stills are `asset/Originals/gulp/generated/start-full-<direction>.png` (1.15 times the start slime's width, on the same baseline); the spit takes start full and pop empty |
| `page-<n>.json` | The packer's choice per row: loop (or one-shot) start and length in source frames, the 8 sampled frames, the playback fps the Godot clips use, and whether the clip loops (page 6: where each pose landed, see "Page 6 layout") |
| `shapes/` | The body shapes' art (2026-10-12): the attack pose sheets packed into page 6, the Spear's strike strips packed into the strike sheet, the jelly weapons, their effects and icons ([shapes/README.md](shapes/README.md)) |

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

- **The roll rows are no longer played** (2026-10-09): the Dodge became the Roll, which spins
  page 4's ball. Rows 0-2 are still packed and built into clips.
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

## Page 4 layout

The Gulp (2026-10-09, roadmap 7.5) and the Roll's ball (roadmap 7.7); the video prompts are in
[asset/Originals/gulp/README.md](../../gulp/README.md#prompts). Same cells and baseline as page 1; its takes do not start on a standard start frame, so it takes page 1's scale from its
manifest (`PAGE_1_SCALE`).

| Row | Clip | Playback |
|---|---|---|
| 0 | suck-down | 19.2 fps, loops while Q sucks |
| 1 | suck-up | 8.73 fps |
| 2 | suck-side | 24 fps |
| 3 | spit-down | 26.67 fps, once (the 300 ms throw): starts full, pops empty |
| 4 | spit-up | 26.67 fps, once |
| 5 | spit-side | 26.67 fps, once |
| 6 | ball-side | 24 fps, loops (the Roll's ball; in play its speed follows the roll's, three times faster during the spin-up) |
| 7 | free | |

- **The sucks hold their open mouth.** The loop is 8-36 source frames long (`LOOP_RANGE`) and
  taken from where the mouth stays open (`WINDOWS`): down 14-54, up 6-30 (the up take leans
  sideways after frame 30), side 20-50. The packer chose down 39-48, up 6-27 and side 34-41.
- **The spits are picked by hand** (`PICKS`) and timed to 300 ms (`ONE_SHOT_MS`). Down (62, 65,
  68, 72, 81, 83, 86, 90): the cheeks puff, the slime stretches up, bursts wide and stands empty.
  Up (40, 52, 60, 64, 66, 68, 72, 78): squashed flat, it springs up tall and empty. Side (16, 22,
  26, 28, 29, 30, 76, 84): the cheeks bulge and the mouth opens on a short puff; the long blast of
  air is left out (it runs past the cell), then the empty slime.
- **ball-side is baked, not filmed** (owner, 2026-10-09: the old sheet's ball roll). The packer
  spins `start-ball.png` clockwise in 45° steps like `roll-side` (`SPINS`), not tucked
  (`SPIN_TUCKS` 1.0: a ball keeps its size when it turns). Rolling down and up have their own
  rows on page 5 since the owner found this spin wrong for them (2026-10-09).
- suck-side, spit-down and spit-side touch the cell edge (`touches_cell_edge` in page-4.json).

## Page 5 layout

The full slime (2026-10-09): what idle and walk become while the mouth holds something. Page 1's
scale (`PAGE_1_SCALE`), so the full slime is drawn bigger than the slime, because it is.

| Row | Clip | Playback |
|---|---|---|
| 0 | full-down | 8 fps (the waddle while it walks) |
| 1 | full-up | 8 fps |
| 2 | full-side | 8 fps |
| 3 | ball-down | 24 fps (the Roll toward the camera) |
| 4 | ball-up | 24 fps (the Roll away from the camera) |
| 5-7 | free | |

- **Played faster than filmed** (`LOOP_FPS` full 8.0): the takes rock left and right over three
  seconds, too slow for a walk; at 8 fps the slime waddles once a second. Loops of 24-72 source
  frames (`LOOP_RANGE`): down 9-81, up 7-79, and side 63-87 from its frames 52-97 (`WINDOWS`; the
  side take turns to the camera around frame 44).
- **Stood on the spot** (`RECENTRED`): the takes waddle across the frame; with every frame stood
  on the baseline the sway is a rocking tilt.
- **ball-down and ball-up are rolled, not filmed** (owner, 2026-10-09: the side spin looked good,
  the down and up views did not). The packer wraps the inner 80% of `start-ball.png` round the
  ball like a band about the horizontal axis (the back half mirrors the front) and turns it 45
  degrees a frame (`ROLLS`, `roll_cells`; the band scrolls by angle, so the picture never smears
  into streaks at the sides mid-roll): the swirl rolls down the screen for ball-down and up for ball-up, while
  the still's own soft shading, outline ring and shine spots stay put in every frame.
- **At rest** the same rows sway slowly: `build_player_clips.gd` adds `full-idle-down`, `-up`
  and `-side` on them at 2.67 fps (`ALIASES`). The held thing is drawn inside, on the belly
  (`game/player/gulp/mouth.gd`).

## Page 6 layout

The body shapes' attack key poses (2026-10-12, for the body-shapes prototype): still GPT 2.5
pose sheets, not videos, so their sources, prompts and layout are in
[shapes/README.md](shapes/README.md). Rows 0-4 hold four poses per shape and direction in groups of
four columns (row 4 columns 4-7 and rows 5-7 are free), on page 1's cells and baseline. They are
packed by `python scripts/characters/pack-slime-shape-poses.py`, not `pack-slime-v2-page.py`, and
`page-6.json` lists where each pose landed instead of rows; `tools/build_player_clips.gd` makes each
cell the game shows a one-frame clip `shape-<shape>-<pose>-<down|up|side>` (only the War Axe's `load`,
`swing-down` and `swing-up`, for its Spin: every other strike plays its strike frames;
docs/assets/slime-sheet-guide.md).

The Spear's strike frames (2026-10-12) are on a sheet of their own,
`godot/asset/characters/512x416-tile_8x8-slime-v2-strikes.webp` (larger cells centred like page
1's), packed by `python scripts/characters/pack-slime-strikes.py` from `shapes/strikes/` with its
manifest `godot/game/data/shape-strikes.json` ([shapes/README.md](shapes/README.md) "Strike sheet").

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
three videos); 1,760 for the re-filmed down and up rolls (two takes each). Page 3: 1,760 for the four swim videos (one rejected side take). Pages 4 and 5
(2026-10-09): 3,960 for the nine suck, spit and full videos (440 each).
