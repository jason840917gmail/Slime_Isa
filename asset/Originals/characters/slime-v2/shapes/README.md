# Body shapes art (2026-10-12)

Art for the body-shapes prototype (branch `exp/body-shapes`, docs/godot/BODY_SHAPES.md): the
slime's attack key poses for the Spear, the War Axe and the Hammer, the jelly weapons that grow out
of its body, and the shapes' impact effects. Generated with Magnific GPT 2.5 (`gpt-2-mini`,
1:1 or 2:1, 1k, `transparentBackground: true`), the owner's choice ("use GPT-2.5 with transparent
background"), after he asked to start on the art on 2026-10-12. Video takes were not used: the
three attack videos of 2026-10-05 failed (slime-v2 README), and still key poses keep the slime on
model.

## Files

| File | What it is | References |
|---|---|---|
| `poses-<shape>-<direction>.png` | A 2 x 2 sheet of four key poses, no weapon: Spear ready, jab, load (the pull-back), thrust; War Axe swing-down, swing-up, load (the crouch), chop (the jump chop); Hammer lift, smash, load (the big lift), rebound. Directions `down` (front), `up` (back), `side` (facing right; left is mirrored) | the direction's `start-<direction>.png`, `turnaround-e.png`, Lili |
| `weapon-spear.png`, `weapon-axe.png`, `weapon-hammer.png` | The jelly weapons lying horizontal, root on the left | `turnaround-e.png`, Lili |
| `vfx-goo-splat.png` | A 2 x 2 sheet of a goo splat in four frames | `turnaround-e.png`, Lili |
| `vfx-axe-swoosh.png`, `vfx-spear-glint.png` | The Axe's swing trail, the Spear's pierce glint | `turnaround-e.png` |
| `energy-shard.png` | The energy shard pickup | Lili |
| `strikes/spear-<jab\|finisher>-<side\|down\|up>.png` | The Spear's six-frame body-only strike strips, 3 x 2 (packed into the strike sheet, "Strike sheet" below) | |
| `strikes/axe-<sweep\|chop>-<side\|down\|up>.png`, `strikes/axe-backswing-side.png`, `strikes/hammer-<thud\|boom>-<side\|down\|up>.png` | The War Axe's and the Hammer's six-frame body-only strips with the jelly knob (packed into their strike sheets, "War Axe and Hammer strike sheets" below) | |
| `prototypes/strikes-preview/` | What the game draws from the Axe's and the Hammer's strike manifest, simulated (GIFs, contact sheets, knob and neck sheets; "War Axe and Hammer strike sheets" below) | |
| `prototypes/` | The Spear's body-morph prototypes, the animation tests and the synced-spear compositor (`prototypes/synced/`); the War Axe and Hammer body strips and the synced-axe compositor; in-game captures (`prototypes/in-game/`); sections below | |

Two variants were made of each; the kept one is noted in the table below. Rejected: the first
War Axe pose sheets (GPT drew real stone-and-wood axes held by a goo tendril, against the owner's
"the weapon is part of the body"; the second round said "ALONE, holding NOTHING: absolutely no
axe, no blade, no handle"), and the first front Spear sheet (refused by the content filter; the
reworded prompt said "poke" and "a small round jelly knob" instead of "thrust" and "bulging").

| Set | Kept |
|---|---|
| Spear side / front / back | a / a (second round) / b |
| War Axe side / front / back | a / a / a (second round) |
| Hammer side / front / back | a / a / a |
| Weapons spear / axe / hammer | b / a / b |
| Splat / shard / swoosh / glint | a / a / a / a |

Cost: 3,800 credits (38 images at 100), including the rejected rounds; the two filtered images
were not charged.

## Prompts

Every prompt starts with the style block of docs/assets/visual-style-guide.md and the slime line
("Glossy translucent jelly slime body with rim light, cute big glossy eyes"). The pose sheets
then say: "A SPRITE SHEET of ONLY the EXACT same little green jelly slime as the reference (same
leaf-green jelly, same two-leaf sprout, same big glossy eyes, same size and proportions), ALONE,
holding NOTHING ... [the view: strict SIDE VIEW FACING RIGHT (one eye visible, profile) / FROM THE
FRONT, facing the viewer / FROM BEHIND, facing away] ... A 2 by 2 grid of four key poses, each
centred in its own quarter, all four the same size on the same baseline: TOP LEFT ... TOP RIGHT
... BOTTOM LEFT ... BOTTOM RIGHT ... Isolated on a transparent background, no ground shadow
plate, no scenery, no grid lines, no borders." The weapons say "A single game sprite of a SPEAR /
WAR AXE / big HAMMER MADE OF THE SAME GREEN SLIME JELLY as the reference slime, lying horizontal:
on the left a soft rounded jelly root blob (where it grows out of the slime's body) ..." with the
shaft and head described (the Spear: "a long, very THIN glossy goo shaft, ending on the right in a
sharp ARROWHEAD tip with two small swept-back barbs", after the owner's sketch).

## Packing

`python scripts/characters/pack-slime-shape-poses.py` packs the poses into
`godot/asset/characters/256x256-tile_8x8-slime-v2-page-6.webp` (page 1's cells and baseline;
each sheet scaled so its poses cover the same area as page 1's first idle frame of that direction,
because jelly keeps its volume; each pose stood on y 251 at the centre of its ground contact) and
writes `../page-6.json` (where every pose landed), and crops the weapons into
`godot/asset/characters/shapes/<shape>.webp` with `shapes.json` (root, neck, Spear shaft, root end
and head start, which the game's StrikeRig reads; the axe's and the hammer's head start, where the head
leaves the haft or stalk, are measured constants, `HEAD_STARTS`: 200 and 184). Then
`tools/build_player_clips.gd -- --only=shape-` (docs/TOOLING.md) builds the pose clips the game
shows, `shape-axe-<load|swing-down|swing-up>-<down|up|side>` (9 clips: the War Axe's Spin and its
charge ring; every other strike plays its strike frames, below), into the player scene.

The same script packs the effects into `godot/asset/MAPS/effects/`, each used by the prototype
(docs/godot/BODY_SHAPES.md "Art"): the goo splat's four frames in a 4 x 1 strip of 256 px
(`256x256-tile_4x1-goo-splat.webp`, the `goo-splat-sheet` flipbook of `game/feel/particle_fx.gd`:
the goo enemies' hit debris), the Axe swoosh (`shape-axe-swoosh.webp`, 384 px on its long side; drawn by
`game/shapes/strike_rig.gd` on the strikes and by `game/shapes/shape_visuals.gd` on the Spin) and the
Spear glint (`shape-spear-glint.webp`, 256 px, drawn by `shape_visuals.gd`),
and the energy shard (`energy-shard.webp`, 128 px, `game/combat/reactions/energy_shard_look.gd`).
It also writes the shape icons, `godot/asset/UI/shapes/<shape>-icon.webp` (128 x 128, the packed
weapon turned 45 degrees to point up and to the right, `pack_icons`), which the HUD Shape slot, its
carousel and the bag's Shapes row show (`game/ui/body_cards.gd` `SHAPE_ICONS`). The seven weapon
and effect textures import with mipmaps (`mipmaps/generate=true`; they are drawn small).

| Page 6 row | Columns 0-3 | Columns 4-7 |
|---|---|---|
| 0 | spear-down | spear-up |
| 1 | spear-side | axe-down |
| 2 | axe-up | axe-side |
| 3 | hammer-down | hammer-up |
| 4 | hammer-side | free |
| 5-7 | free | free |

## Spear prototypes: the body becomes the weapon (2026-10-12)

The owner judged the overlays above as "separate assets": his idea is the slime's body itself
turning into the weapon, like a shape-shifting symbiote, so the weapon must be painted into
full-body frames. `prototypes/` holds three directions for the Spear, side view facing right, each
a strip of three stages from the first change to the full spear (GPT 2.5, 21:9, transparent,
two takes each; 600 credits):

| Prototype | Files | The idea |
|---|---|---|
| Pour | `spear-proto-pour-a.png`, `-b.png` | The front swells into a nose, pours out into a cone, and the body shrinks to a teardrop as its jelly flows into one long needle with a jelly arrowhead |
| Tendrils | `spear-proto-tendril-a.png`, `-b.png` | Three tendrils sprout from the front, braid as they shoot out, and fuse into a twisted spear with a barbed head |
| Harden | `spear-proto-harden-a.png`, `-b.png` | The front ripples, a soft spike grows from below the eye and hardens along its length into a dark glassy crystal point, goo dripping at the base |

The prompts follow the pose sheets' pattern with "Its OWN JELLY BODY TURNS INTO A SPEAR: the spear
is not an object, it is the slime's body itself, one continuous piece of the same glossy jelly with
no seam, no handle, no separate part" and the three stages described left to right.

## Spear animation tests, side view (2026-10-12)

The owner chose Pour for the jabs and Tendrils for the finisher (Pour alone if that is too hard).

- **Seedance 1.5 Pro videos** (`prototypes/videos/`, 5 s, 1:1, start = the side still small on
  #FF00FF, end = the prototype's last stage placed at the same scale and back edge; 550 credits
  each): `spear-pour-side.mp4` zoomed in and turned the slime to the camera halfway (unusable
  middle); `spear-pour2-side.mp4` (the end frame with less shrink, "the camera is locked ... only
  ONE eye is ever visible") holds the side view, but the sprout turns into a bubble and the spear
  comes out thick before it thins; `spear-tendril-side.mp4` holds the side view but the tendrils
  loop between frames 50 and 70 (usable by skipping them), and Seedance paints a pale pink haze
  over the chroma (keyed by hue: red and blue above green); `spear-tendril2-side.mp4` grew two
  tendrils and looped worse.
- **GPT 2.5 six-frame strips** (`spear-jab-pour-side-6.png`, `spear-finisher-tendril-side-6.png`,
  3 x 2 frames, 3:2, transparent; 100 credits each) stay on model and in profile through every
  stage and are the better source. GPT paints a faint ground stroke under some frames; the preview
  script keeps each figure's tallest block of rows.
- Previews: `prototypes/jab-pour-gpt.gif`, `finisher-tendril-gpt.gif`, `jab-pour-video.gif`,
  `finisher-tendril-video.gif`.

Cost of the prototypes and tests: 3,200 credits (6 prototype images, 4 videos, 4 strips).

## Separate spear synced to body frames (2026-10-12)

The owner rejected the full-body morphs ("I don't like the feel"; the sprite changing size during
the animation is "not good") and asked for separate weapons with better body animation, the weapon
reading as part of the body at all times. Six-frame GPT 2.5 body-only strips keep the slime's size
(`prototypes/spear-body-jab-side-6.png`, `spear-body-finisher-side-6.png`: rest, lean or wind-up,
lunge with a painted bump where the spear leaves, full lean, spring back, rest; 400 credits).
Three attachment treatments were prototyped (sheathed behind the body, grown from the bump, a code
tendril bridge) and judged; the kept one, in `prototypes/synced/` (`compose.py`, `jab.gif`,
`finisher.gif` and their game-size versions):

- every body frame at one scale (the rest frame is 72 game px tall), the back and the baseline on
  the same pixel in every frame;
- the socket is the tip of the painted bump, found per frame (`godot/*-sockets.json`); only the
  lunge and full-lean frames hold the spear;
- the rigid spear is drawn behind the body, its hidden end inside the jelly, and slides out; a jelly
  neck grown from the bump (`godot/*-neck-b<frame>.png`) joins it with no seam;
- the hit: a hit-stop on the contact frame, the target flashes white then pink, the glint and the
  goo splat at the tip, the target rocks.

## Strike sheet (2026-10-12)

The owner approved that look ("much better, I think this is the way to go"). `strikes/` holds its
six-frame body-only strips for every direction, `spear-<jab|finisher>-<side|down|up>.png` (GPT 2.5,
3 x 2, transparent; the figures are not on exact thirds): jab rest, lean back, lunge with the bump,
full lean, spring back, rest; finisher rest, big wind-up squash, launch with the bump, strongest (the
cry), bounce back, rest. Side views face right (left is mirrored); in the front views the bump sits
at the bottom of the front below the mouth and the spear goes down the screen; in the back views the
bump rises at the top in front of the sprout and the spear goes up the screen.

`python scripts/characters/pack-slime-strikes.py [--preview <dir>]` packs them, following
`prototypes/synced/compose.py`, into `godot/asset/characters/512x416-tile_8x8-slime-v2-strikes.webp`
(8 x 8 cells of 512 x 416, the other pages' grid; rows 0-2 spear-jab side / down / up, rows 3-5
spear-finisher side / down / up, columns 0-5 = frames 1-6) and writes
`godot/game/data/shape-strikes.json` (merged: the War Axe's and the Hammer's entries stay):

- each figure is cut from its row at the empty columns, keeping its largest connected component and
  the ones touching it; one scale per strip, set by the rest frame (6), as tall as page 1's first
  idle frame of that direction (jab 0.486 / 0.503 / 0.507 cell px per source px side / down / up,
  finisher 0.529 / 0.488 / 0.546);
- the rest frame stands on the idle frame's ground and middle (page 1's cell centre is the strike
  cell's centre, so a sprite drawn about its cell centre at the same scale puts both in the same
  place); every frame keeps the back (side: the left-most solid px of the lower body) or the middle
  (down / up) and the ground (the bottom of the solid px on the side, the two feet in the front and
  back views, so the front view's bump hangs below toward the camera instead of lifting the body);
- frames 3 and 4 have the jelly neck baked in, grown from the tip of the painted bump along the aim
  (the compositor's neck: a smooth union of the body's painted interior and a band tapering to the
  spear's shaft, 5 game px on the jab and 6 on the finisher, in the bump's colours and grain, no
  outline at the join, fading into the shaft past its end); in the back views the sprout stays in
  front of the neck, so the spear rises from behind the leaves; the game draws only the rigid spear;
- the manifest gives per strike and direction the row, the aim and, per frame, the socket (the neck's
  end, where the spear's visible part starts), the bump tip and the spear's state (`hidden`, `part` on
  frame 3, `full` on frame 4), plus the cell's origin and scale, each strip's rest centre and ground,
  and the spear's tint (40 percent toward the body's jelly colour; the neck fades into the tinted
  shaft);
- the cells are 512 x 416, not 256: the finisher's side lunge with its neck reaches 247 px right of
  the cell centre and its front-view neck 205 px below it. The packer stops if a frame no longer fits
  and prints the cell size the art needs. `--preview` writes the sheet on grass with the sockets, the
  joins with the spear drawn behind the body, and the rest frames beside page 1's idle frames.

The game builds no clips from the sheet: at run time its strike animations
(`game/characters/strikes/`, StrikeLibrary) key the sheet, the frame and `Visual:offset` (-256, -208),
the sheet's -origin. In the game (docs/godot/BODY_SHAPES.md "The Spear's strike frames"; rework mode
only) the jabs play the spear-jab strip and the lunging jab and the Lunge the spear-finisher strip on
the step's own timeline, and the StrikeRig (`game/shapes/strike_rig.gd`) draws only the rigid spear
(spear.webp with its root blob cut off, tinted by the manifest's `tint_gain`) behind the body from the
shown frame's socket; the hit line starts at the full-lean frame's socket.

## War Axe and Hammer body strips, synced prototype (2026-10-12)

The same method for the other two shapes, side view first (GPT 2.5, 3 x 2, transparent, the side
Spear strips' references and wording; "ALONE, holding NOTHING" and "NO weapon is drawn"). Each
strip paints a rounded jelly knob that moves round the body with the swing, where the weapon's
handle leaves it:

- `prototypes/axe-body-swing-down-side-<a|b>.png`, the sweep (kept: a): rest, rears up tall with
  the knob on the top of its front, pitches forward (knob mid-front), low follow-through (knob at
  the bottom of the front), springs back, rest;
- `prototypes/axe-body-swing-up-side-b.png`, the backswing: the reverse (crouch with the knob low,
  straighten, stretched tall with the knob on top); its variant a came back on an opaque hazy
  background and was dropped;
- `prototypes/axe-body-chop-side-<a|b|c|d>.png`, the chop: rest, big wind-up squash with the knob on
  top, springs up tall (the game adds the hop), the chop, bounce back, rest. a and b put the knob at
  the bottom front on the chop, so the handle lay almost flat; c and d (second round) tip the whole
  body forward with the knob on the upper front pointing down at the ground (kept: c);
- `prototypes/hammer-body-thud-side-<a|b>.png` (kept: b) and `hammer-body-boom-side-<a|b>.png`
  (kept: b): the lift with the knob on top of the head (the sprout sits on it), the pitch forward,
  the smash flattened with the knob on the upper front, the rebound; the BOOM winds up low, leaps
  tall (the game adds the hop), lands flattened very wide with a shout. The Quake charge would reuse
  the BOOM strip.

`prototypes/synced/compose_axe.py` (it imports `compose.py`) composes the Axe strips with the rigid
axe.webp drawn behind the body from each frame's knob tip at a per-frame angle on the swing, a jelly
neck baked from the knob, the swoosh bent onto the swept arc between frames, the chop's hop and
landing (dust, shock ring, shake) and the training dummy's hit; it writes `axe-<sweep|backswing|
chop>.gif`, `axe-chain.gif`, `axe-chain-game.gif`, `axe-frames.png` and `axe/` (the knob detection
sheet and `axe-sockets.json`: per frame the socket, the angle and the axe's state). The knobs sit 34
to 48 game px from the slime's centre, so a head that reads as a war axe rides well past the game's
radius of 60: the arc's radius has to grow to match before the Axe goes in game. The second round
(kept; the first round's chains are `axe-chain-v1.gif` and `axe-chain-game-v1.gif`) draws the axe
1.2x the game's radius-60 size with its handle stretched 1.45x (the head 64 % of the slime's height)
and uses chop strip c: the blade tip reaches about 107 / 93 / 90 game px from the centre at contact
(sweep / backswing / chop, up to 113 in the swing), so the arc wants a radius of about 110, and the
chop reaches its target only with a forward leap of about 50 px (the game steps 12).

`prototypes/synced/compose_hammer.py` (it imports `compose_axe.py`) does the same for the Hammer
with the thud and BOOM strips (b): the mallet's handle bent and stretched into a jelly stalk from the
knob on the head, the head rigid at its end and flat on its face on the smash; the dust and pebbles
of the thud, the BOOM's hop, cracks and shock ring; `hammer-<thud|boom>.gif`, `hammer-chain.gif`,
`hammer-chain-game.gif`, `hammer-frames.png` and `hammer/` (knobs, `hammer-sockets.json`). The head
is 54 game px face to face (75 % of the slime); it lands 82 / 87 px in front of the centre (the
body's front is at 49), so the impact's `offset` wants about 85 against the game's 48.

Cost: 1,200 credits (12 images at 100).

## War Axe and Hammer strike sheets (2026-10-12)

The owner said "go" on the synced Axe and Hammer (docs/design/2026-10-12-weapon-strike-frames.md, the
build contract). `strikes/` holds their strips for every direction (GPT 2.5, 3 x 2, transparent; the
side ones are the kept prototypes): `axe-sweep-<side|down|up>`, `axe-backswing-side` (its front and
back views are the sweep's, mirrored), `axe-chop-<side|down|up>`, `hammer-thud-` and
`hammer-boom-<side|down|up>`. In the front sweep the knob moves from the picture's right to the bottom
to the left, in the back sweep from the left over the top to the right; the chops and smashes carry
it on top.

`python scripts/characters/pack-slime-weapon-strikes.py [--preview [<dir>]] [--knobs-only]` packs them
the Spear's way (pack-slime-strikes.py's helpers: one scale per strip from its rest frame against page
1's idle frame, the back or middle and the ground fixed) into
`godot/asset/characters/512x416-tile_8x8-slime-v2-strikes-axe.webp` (rows 0-2 axe-sweep side / down / up,
3 axe-backswing side, 4-6 axe-chop) and `...-strikes-hammer.webp` (rows 0-2 hammer-thud, 3-5
hammer-boom), the Spear's grid, cell and scale, lossless, with no neck baked in. It writes the code neck
`godot/asset/characters/shapes/neck.webp` and merges its five strikes, `weapons` and `neck` into
`godot/game/data/shape-strikes.json` (the Spear's packer merges the same way, so either can run first).
Since round 3 (2026-10-12) the strikes' motion is real Godot animations, and since round 4
(2026-10-13) each is a strike file you edit in the Inspector (`godot/game/characters/strikes/`;
docs/godot/BODY_SHAPES.md "Editing the strike animations"; the Round 3 library was converted once and removed):
the manifest lost its `keys`, and the packer's timelines, its key checks and
reach solving and its previews of them below are legacy (a re-run writes keys back; the game ignores
them). Since round 5 (2026-10-14) the Inspector plays a strike file above its fields (the plugin
`godot/addons/strike_preview/`), the chain steps' hit reach lives only in those files (`hit_reach`, measured
from the direction's `hit_center`; the packer's `REACH_TARGETS` are the numbers they were first set from), each
direction's `arm_px` is its drawn reach (negative pulls the weapon in; the packer's contact-length slides became
negative arms), and its `socket_nudge` moves the packer's socket of a frame by a few game px. The up chop, Thud and
BOOM were since redone by hand in their files (the weapon brought back over the head toward the camera first, a
shorter reach). The art (the sheets, the sockets and knob widths, the weapon blocks and views, the neck) is still
the packer's:

- **The knob** (compose_axe.py's search): the silhouette, the sprout's leaves masked (outlined
  interiors apart from the body's once the stem is cut, elongated, above the middle; in the front and
  back views a round one on the middle line is a knob), its radius round the body's core in polar form
  minus that radius's opening, the highest bump near the frame's expected direction. The socket is the
  knob's tip, or where the contact angle leaves it (the side chop), or the body's lowest middle point
  (`bottom`: the front views' chop and smash contact frames, so the weapon lands below the body and the
  face stays clear); frames without a knob take the silhouette along a set direction. Seven knobs the
  search mistakes for a leaf are read off the knob sheet by hand (`manual`: axe-sweep up f3, axe-chop
  down f3, hammer-thud side f4, hammer-boom side f2 and f4, hammer-boom down f2) plus the front sweep's
  bottom knob on a lower bar. `knob_w`: the knob's chord 2.5 game px inside its tip (6.5-12).
- **The weapons** keep the proportions to the body the owner approved: the prototypes drew the slime
  72 px tall, the game draws it 48.7, so their sizes are taken x 0.676 (axe head 30.9 px, 64 % of the
  slime; hammer head 36.5 px face to face, 75 %); the axe's handle 1.45x stretched as there, the
  hammer's stalk 0.8x the texture handle's thickness (`handle_across`).
- **The keys** (the contract's timeline) per strike and direction, in the packer's `KEYS`: the side
  views follow the prototypes' tables, the sweeps run the hit arc itself through the active window
  (aim -/+ 70, linear: "arc"), the side chop lands its blade 4 px into the ground line ("bite"), the
  smashes stand the head on its face on the ground ("smash", head_angle 0); the front views swing round
  in front at ground level (sweeps) or over the head and out below the body (chop, smashes, `front`);
  the back views raise to one side and come down beyond (`behind`); the side chop and smashes go
  `front` on the contact, so a target in reach that sorts in front of the slime does not hide the head. The game slides the weapon out
  without scaling it, so the shown lengths stay at 0.65 or more and jump to 0.
- **The neck**: a horizontal jelly cone (compose.py's look: the body's jelly between its deep and lit
  colours, its grain, a soft gloss, the body's line on the flanks, none on the root), its wide root
  fading into the knob, then a short straight tube (the arm span), then the taper fading into the
  handle; the game lays its root on the socket at the knob's width.
- **The arms**: one hit number per step must fit every direction, and the back views' knobs sit near
  the top of the head, so each strip has an `arm_px`: the neck's cone stretched that far,
  solved so the reach at contact meets the game's number (the sweeps' blade tip 76 px from the centre,
  the chop's 70, the smashes' head centre 68 along the aim). The back views get 22-35 px, the side
  views 0-12, the front views 0 (they reach past: 74-78).
- **contact** (in the manifest, every direction in `by_direction` with its arm and target): at the hit
  (the sweeps' a0.5, the others' w1) the Axe's blade tip is 76.0 (sweep, backswing) and 70.0 (chop)
  from the slime's centre in the side and back views, the Hammer's head centre 68.0 along the aim
  (thud side 68.5, no arm).

`--preview` (default `prototypes/strikes-preview/`) draws from the manifest alone what the game draws
(shape_visuals.gd's weapon and neck drawing, ported): per strike and direction a GIF at 3 px per game
px over the step's real timeline (game-constants' wind-up, active window and recovery, the hit-stop, the
step forward, the chop's hop), left for the side strips, down-right (the side strip turned +45) for the
sweep, the chop and the thud, the training dummy at the contact (white then pink; drawn faint where it
stands in front of the slime), and `-right-close` for the chop and the smashes (the dummy inside the hit,
its feet 4 px lower, sorted in front); `<strike>-sheet.png` (every second tick), `axe-chain.gif` and
`hammer-chain.gif` (the chain at real speed, the next tap at `cancelAtMs`; `-game` at game size x 2),
`knobs-<axe|hammer>.png` (the search per frame: sprout magenta, knob orange, socket red, knob_w cyan)
and `neck-joins.png` (the neck, arm and weapon on every knob at the knob's angle and 40 degrees either side).
The game reads the sheets and the manifest at run time (no clips to build; docs/TOOLING.md).

### Turning weapons on the front and back views (Round 2, 2026-10-12)

The owner saw the front and back chop and smashes flip from above the head to the front: the weapon
must turn toward or away from the viewer. `weapon-<axe|hammer>-<toward|away>.png` (GPT 2.5, 2 x 2)
draw one vertical swing as the camera sees it (1 raised, 2 tipping, 3 pointing at / away, 4 planted in
front / beyond). The packer cuts them into `godot/asset/characters/shapes/<axe|hammer>-views.webp`
(row 0 toward, row 1 away; the round end ball cut off where the handle narrows, the jelly matched to the
side weapon's, one scale per view so view 1's head is the side drawing's size), finds per view the
pivot (the cut, where the code neck's tip meets the handle; `views-<axe|hammer>.png` in the previews
shows the cut in red, the pivot, head and dir) and writes `weapons.<shape>.views`. The down and up keys
of axe-chop, hammer-thud and hammer-boom swing through the views (toward: the axe 1, 3, 2, 4, the hammer
1, 2, 3, 4; away 1-4), switching at once between keys at the same `at`; the down strips' toward views 3
and 2 pass over the face (`front`) and view 4 lands below the body.

Every direction draws the same reach at contact as the side view (the owner: "they all should be
equal reach"): the packer gives a strip that falls short an arm (the up strips: 30-49 px) and slides one
that reaches past into the jelly from `w1` on (`contact_length` 0.73-0.99 on the down strips and the
thud's side), and stops, writing nothing, if any direction ends more than 2 px from its side view.
