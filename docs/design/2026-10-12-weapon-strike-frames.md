# War Axe and Hammer strike frames: build contract (2026-10-12)

The owner approved the synced-weapon look for the Spear (in game) and saw the side-view prototypes
of the War Axe and the Hammer (`asset/Originals/characters/slime-v2/shapes/prototypes/synced/`,
`compose_axe.py`, `compose_hammer.py`), then said "go": put both in the game, every direction, the
same way as the Spear. This note is the contract between the two halves of that build — the packer
(art to sheets and manifest) and the game (drawing and timing) — until docs/godot/BODY_SHAPES.md
describes the result. Rework mode only; the classic game and the Spear stay as they are.

## Sources

`asset/Originals/characters/slime-v2/shapes/strikes/` (GPT 2.5, 3 x 2 six-frame strips,
transparent; side views face right):

| Strike | side | down (front) | up (back) |
|---|---|---|---|
| `axe-sweep` (chain step 1, cw) | `axe-sweep-side.png` | `axe-sweep-down.png` | `axe-sweep-up.png` |
| `axe-backswing` (step 2, ccw) | `axe-backswing-side.png` | the sweep's down strip MIRRORED | the sweep's up strip MIRRORED |
| `axe-chop` (step 3, finisher) | `axe-chop-side.png` | `axe-chop-down.png` | `axe-chop-up.png` |
| `hammer-thud` (step 1) | `hammer-thud-side.png` | `hammer-thud-down.png` | `hammer-thud-up.png` |
| `hammer-boom` (step 2, finisher; the Quake charge plays it too) | `hammer-boom-side.png` | `hammer-boom-down.png` | `hammer-boom-up.png` |

Frames: 1 rest (never shown), 2 wind-up / lift, 3 swing / spring up / pitch, 4 follow-through /
chop / smash, 5 spring back, 6 rest. Each frame paints a round jelly knob where the weapon leaves
the body; it moves round the body with the swing. Front sweep: knob on the picture's right, bottom
front, left; back sweep: left, top, right (the hit arc's cw order seen from the front and the back).
The Axe's Spin keeps its old drawing (page-6 poses and the overlay axe) for now.

## Sheets

One sheet per shape beside the Spear's, the same grid and cell so a strike clip differs only by
its texture: `godot/asset/characters/512x416-tile_8x8-slime-v2-strikes-axe.webp` and
`...-strikes-hammer.webp` (8 x 8 cells of 512 x 416, cell origin (256, 208), 0.28125 game px per
cell px). Every frame at one scale per strip set by its rest frame (as tall as page 1's idle frame of
that direction), back (side) or middle (down / up) and ground fixed, as pack-slime-strikes.py does.
No neck is baked into these frames (the game draws it, below). A mirrored strip has no rows of its
own: it shows its source's row with the sprite flipped.

## Manifest (`godot/game/data/shape-strikes.json`)

The Spear's entries stay exactly as they are. New per-strike keys (the Spear's entries may gain
them with their current values: texture = the Spear sheet):

```jsonc
"strikes": {
  "axe-sweep": {
    "texture": "res://asset/characters/512x416-tile_8x8-slime-v2-strikes-axe.webp",
    "weapon": "axe",              // the weapon block below
    "rest_frame": 6,
    "side": {
      "row": 0, "flip": false,     // flip: true for a mirrored strip (it shows `row` flipped)
      "aim": [1, 0], "source_scale": ..., "rest_centre": ..., "ground": ..., "anchor": ...,
      "frames": [                  // 1..6
        {"socket": [x, y], "socket_game": [x, y], "knob_w": 9.5}   // socket = knob tip, cell px;
      ],                                                          // knob_w: its chord, game px
      "keys": [                    // the timeline, in order (below)
        {"at": "w0", "frame": 2, "angle": -82, "length": 0.3, "layer": "behind"},
        {"at": "w0.4", "frame": 2, "angle": -95, "length": 1.0},
        {"at": "w1", "frame": 3, "angle": -70, "layer": "front"},
        {"at": "a0.5", "frame": 4, "angle": 0},
        {"at": "a1", "frame": 4, "angle": 70},
        {"at": "r0.3", "frame": 5, "angle": 45, "length": 0.4},
        {"at": "r0.6", "frame": 6, "length": 0.0}
      ]
    }, "down": {...}, "up": {...}
  }
}
```

- `at`: a point on the step's own timeline: `w<share>` of the wind-up (`windupMs`), `a<share>` of
  the active window, `r<share>` of the recovery (shares 0..1; `w1` = `a0`, `a1` = `r0`).
- Each key sets the frame shown from that point (until the next key that names a frame) and the
  weapon's values at that point; the game eases linearly between consecutive keys and holds the
  last values after the last key. A key that leaves a value out keeps the previous key's.
- `angle`: degrees, screen, in the strip's own frame (0 = right, +90 = down): the direction from the
  frame's socket along the handle. The game mirrors it for a left strike and for a `flip` strip
  (a -> 180 - a, the socket's x negated) and rotates it by the aim's offset from the strip's aim on
  the diagonals (the side strip covers them; the body frame stays).
- `length`: the share of the weapon out (0 = hidden inside the jelly, 1 = full): the grow-out and
  the pull-in (a slide along the axis, "Agreed drawing" below). `head_angle` (Hammer): the head's
  own angle when it differs from the stalk's (degrees, same frame; the smash stands the head flat on
  its face); a key that leaves it out has its own stalk angle (it is not carried on).
- `layer`: `behind` (the whole weapon under the body, as the Spear) or `front` (the part past the
  neck's tip over the body and the world; the root still behind). A key that leaves it out keeps it.
- Sync with the hit: a sweep's active window (`w1` .. `a1`) must run the hit arc itself: from the aim
  minus half `arcDeg` to the aim plus half, in the sweep's turning sense (cw on screen for the sweep,
  ccw for the backswing), linear in time — the game's arc grows linearly over the active window.
  A chop or a smash shows its contact angle from `w1` (the contact frame), the hit-stop freezing it.
- Per strike, `contact` reports the art's reach for the game numbers: `{"head_centre_game",
  "blade_tip_game"}` (Axe: px from the slime's centre at contact) or `{"head_centre_game",
  "head_centre_along_aim_game"}` (Hammer: the second is px in front of the centre where the head
  lands); the side view's at the top, every direction's in `by_direction` (with its `arm_px` and the
  `target` it was solved for).

Weapon blocks, top level (the game draws them; "Agreed drawing" below has the exact rules):

```jsonc
"weapons": {
  "axe": {"texture": "res://asset/characters/shapes/axe.webp", "scale": <game px per texture px>,
          "head_start": <texture x>, "axis_row": <texture row of the handle's centre line>,
          "handle_px": <game px of handle from the neck's tip to the head>,
          "hidden_px": <game px of handle behind the socket, inside the jelly>, "tint_gain": [r, g, b]},
  "hammer": {... the same, the stalk being the handle stretched ...}
},
"neck": {"texture": "res://asset/characters/shapes/neck.webp", "root_x": <texture x set on the
         socket>, "tip_x": <texture x where the handle starts>, "axis_row": <its centre row>,
         "width_px": <texture px across at the root>}
```

Agreed drawing (2026-10-12: the game half's code, shape_visuals.gd `_strike_weapon_at`, and the
packer's previews, which port it). The weapon blocks also carry `axis_row` (the texture row of the
handle's centre line, on the line through the socket; the neck block too) and, for reference,
`head_centre`, `face_row` (Hammer), `socket_to_head_px`, `handle_width_game`, `head_depth_game`,
`head_height_game`:

- Everything in the strip's frame, game px from the Visual's origin (the slime's centre, +y down),
  then mirrored (a left strike, a `flip` strip: x negated, every angle a -> 180 - a, the textures
  reflected across their axis) and, on a diagonal, the stalk's angle turned by the aim's offset from
  the strip's aim (the sockets stay); a `head_angle` a key names is the head's own (flat on its face
  on the ground) and does not turn, while a head that follows its stalk turns with it (the game eases
  that share between keys). Angles ease linearly as numbers (no wrapping); two keys a hair apart make
  a jump.
- The neck: neck.webp with (`root_x`, `axis_row`) on the socket, along the angle, scaled uniformly by
  `knob_w` / `width_px`; its tip is neck_len = (`tip_x` - `root_x`) x that scale from the socket. It
  grows over the first quarter of `length` and draws over the body in the weapon's colour without
  its tint.
- The jelly arm (the lead, 2026-10-12: one hit radius per step must fit every direction): each
  direction block has `arm_px` (game px, >= 0; a `flip` strip has its own, else its source's). The
  game stretches only the neck's tube (texture x `arm_from_x` to `arm_to_x`, a straight jelly tube) by
  arm = `arm_px` x `length`, so it reaches out and pulls back in with the weapon; the root's cap, the
  fillet, the taper into the handle and the run past `tip_x` keep the knob's uniform scale
  (stretching the whole cone read as a stick). The neck's tip, where the handle shows and a `front`
  weapon goes over the world, is neck_len + arm from the socket.
- The weapon, rigid at `scale`: the handle (texture x 0 to `head_start`, `handle_across` x `scale`
  thick: 1 for the axe, 0.8 for the hammer's stalk) stretched from `hidden_px` behind the socket to
  `handle_px` past the neck's tip (the joint), the head from the joint along `head_angle` (its collar
  overlapping the stalk where it turns); the whole slid back along the axis by (1 - `length`) x
  (`hidden_px` + neck_len + `handle_px` + the head's depth) and cut at the hidden end: the slide
  leaves the arm out (the arm pulls in by itself), so the head never ends up inside the arm. Below
  about 0.6 the head straddles the socket, so the packer's keys show lengths of 0.65 or more and jump
  to 0.
- `behind`: all of it under the body; `front`: the part past the neck's tip over the world (over
  the neck). A `behind` weapon whose axis points down (y > 0.5) on a downward aim draws that part over
  the world too (as the Spear). The side chop and smashes turn `front` at `w1` (a target in reach with
  its feet a little lower sorts in front of the slime and would hide the head), the smashes back to
  `behind` when the hammer springs up in the recovery. The weapon's colour is multiplied by `tint_gain` (a modulate, as the Spear's).
- A `flip` strip's `frames` and `keys` are its source row's, unmirrored (the game mirrors both).
- The swoosh (the game's own): the painted crescent along the head's path, sampled from the same
  timeline every 8 ms back over 120 ms while the weapon turns at least 0.6 deg a ms one way, from 5 px
  inside the head to 3 px past it, fading over 110 ms once the head slows; a sample step that turns 90
  deg or more is a cut (the front and back views' chop and smash) and ends it.

What the packer found (scripts/characters/pack-slime-weapon-strikes.py, 2026-10-12):

- Size. Page 1's idle slime is 48.7 game px tall in the game (the Visual's 0.28125), but the side
  prototypes drew it 72 px tall, so their weapon sizes were 1.48x too big for the body in game px. The
  weapons keep the approved proportions (every prototype size x 0.676): the axe head 30.9 px across
  (64 % of the slime), the hammer head 36.5 px face to face (75 %). The prototypes' reach numbers
  (blade tip about 107, hammer head 82 / 87) shrink the same way; `contact` holds the new ones.
- Front views of the chop and the smashes: the contact frame's socket is the body's lowest middle
  point (`bottom`), not the painted knob on top, so the weapon lands below the body and the face
  stays clear; the swing over the head hides behind the body for a few ms and comes out below.
- Back views reached less (the knobs sit near the top of the head: 33 to 48 px against 65 to 78), so
  the lead set one number per step and the packer solves each strip's `arm_px` to meet it at contact:
  the sweeps' blade tip 76 px from the centre, the chop's 70, the smashes' head centre 68 along the aim
  (the Quake shares the BOOM's art). Arms: sweep side 0.4 / up 30.3, backswing side 11.8 / up 30.3,
  chop side 5.2 / up 22.2, thud up 31.6, boom side 1.2 / up 35.1; the front views already reach past
  (sweeps 78.5, chop 77.5, thud 74.2, boom 74.8) and the thud's side 68.5, so their arms are 0.
- Diagonals of the chop and the smashes: their angles are a vertical swing seen from the side, and
  the turn tilts the landing (the side chop already lands down and in front); the stalk turns as the
  rule says, but the game keeps a named `head_angle` unturned (the smash's head stays flat on its
  face; turned 45 deg it balanced on an edge in game).

## The code neck

The Axe and the Hammer turn while one body frame shows, so their neck cannot be baked. A neck
sprite (`godot/asset/characters/shapes/neck.webp`, made by the packer from compose.py's
`neck_layer`: a horizontal jelly cone in the body's colours and grain, its wide root fading out so it
melts into the knob, tapering to the handle's width, no outline at the root) is drawn by the game
OVER the body at the frame's socket along the current angle, its root width scaled to the frame's
`knob_w`. It covers the knob's outline where the handle leaves, so the handle reads as grown from
the body at any angle.

## The game

- `ShapeStrikes` (game/shapes/shape_strikes.gd) reads every strike's texture, row, flip, frames and
  keys; `STRIKES` maps the Axe's `sweep`, `backswing`, `chop` and the Hammer's `thud`, `boom`,
  `quake` to their strikes (the Spear's stay). The frame shown is the timeline's, pinned by its
  single-frame clip (`strike-<strike>-<direction>-f<n>`, tools/build_player_clips.gd: every strike in
  the manifest, keyed with its own texture; a flip strip keys its source's frames). A shown frame is
  identified by the running strike (texture + row + flip), not by the row alone (two strikes share
  the mirrored rows).
- `ShapeVisuals` draws on the strike frames: the rigid weapon from the socket (hidden end
  `hidden_px` behind it) along the current angle at `length`, tinted, in the Gulp form's skin;
  `behind` under the Visual, `front` past the neck's tip over the world; the neck over the body; the
  swoosh along the head's recent path (sampled from the same timeline at earlier times, so a
  hit-stop freezes it); the existing hit feel (hit-stop, flash, splat, dust, cracks, shock rings,
  shake) unchanged.
- The charge ring holds a charge's strike wind-up frame (the Hammer's Quake: hammer-boom f2), as the
  Spear's Lunge already does.
- Hit numbers (`game-constants.json` shapes.axe / shapes.hammer reach: radius, offset, stepPx) are set
  from the packer's `contact` report once both halves exist; neither half changes them alone.

Built 2026-10-12 as above (docs/godot/BODY_SHAPES.md "The War Axe's and the Hammer's strike frames"
describes it); the reach numbers were then set from the `contact` report: the Axe's sweep and
backswing `radius` 76, its chop 70, the Hammer's Thud, BOOM and Quake `offset` 68.

## Round 2: turning weapons on the front and back chop and smashes, 4-way attacks (2026-10-12)

The owner, after playing it: on the down and up attacks the Axe's chop and the Hammer's smashes show
the side drawing turned upright, and they jump from above the head to the front without turning
("the weapon should rotate to represent the right direction"); the diagonals look off on every
weapon ("we can just disable diagonal attacks"). The sweeps stay as they are.

**4-way attacks** (done in game): `aim` "snap4" for all three shapes (game-constants.json;
ShapeDefs.snap4: the nearest of right, down, left, up; an exact diagonal goes to the side, as the
strike art shows it). The facing follows the snapped aim. Movement stays 8-way. The diagonal
rotation rules above no longer trigger in play.

**Weapon views.** New sources in `asset/Originals/characters/slime-v2/shapes/`:
`weapon-axe-toward.png`, `weapon-axe-away.png`, `weapon-hammer-toward.png`,
`weapon-hammer-away.png` (GPT 2.5, 2 x 2, transparent; the variants in `prototypes/weapon-views/`).
Each holds four views of one vertical swing as the game's camera sees it: 1 raised straight up
(handle vertical, its free end at the bottom), 2 tipping toward the viewer (toward) or away (away),
3 pointing at the viewer / away, 4 planted on the ground in front (toward: the handle's free end at
the top, the head below) or beyond (away: the free end at the bottom, the head above). The packer
cuts them, scales them to the weapon's game size (the head as big as the side drawing's), and writes
per weapon a `views` block:

```jsonc
"weapons": {"axe": {..., "views": {
  "toward": {"texture": "res://asset/characters/shapes/axe-views.webp", "scale": <game px per tx px>,
             "frames": [{"rect": [x, y, w, h], "pivot": [x, y], "dir": <deg>, "head": [x, y]}, ...4]},
  "away": {...}}}}
```

`rect`: the view's region in the texture; `pivot`: the handle's free end (texture px), set on the
neck's tip; `dir`: the screen direction from the pivot toward the head in that view (degrees, 0 =
right, +90 = down); `head`: the head's centre. Keys gain `"view": "toward" | "away"` and
`"view_frame": 1..4` (steps, like `frame`; a key without `view` draws the side weapon as before). While
a view shows, the game draws that view's frame with its pivot on the neck's tip, turned by
`angle - dir` (the packer writes `angle` = the view's `dir` for no turn; a few degrees of turn are
allowed for in-betweens), and the neck along `angle`; `length` slides it as before; `head_angle` and
`handle_across` do not apply. The down and up strips of axe-chop, hammer-thud and hammer-boom use the
views through their swing: view 1 through the wind-up, 2 and 3 in the last part of the wind-up (the
swing over the head, the swoosh along the head's path), 4 from `w1` (contact, hit-stop) through the
hold, then the pull-in; no instant 180-degree flip. Contact reach stays at the targets (chop blade
tip 70, smash head centre 68 along the aim), with `arm_px` as needed.


As built (game, 2026-10-12): `view` is read per key (a key without it draws the side weapon) and
`view_frame` is kept from the previous key in the same view (else 1); the view's frame is drawn as
a quad whose rect is cut at the same hidden end and `front` split as the side weapon (along the
weapon's axis from the socket), slid back by (1 - `length`) x (`hidden_px` + the neck + the frame's
reach along its `dir`), the arm left out; where a view shows, the swoosh follows the frame's `head`
and is gated by the head's speed (0.35 px a ms; a 40 px jump between 8 ms samples is a cut).

What the packer wrote (2026-10-12, Round 2):

- `godot/asset/characters/shapes/axe-views.webp` (1716 x 984) and `hammer-views.webp` (1476 x 974):
  row 0 toward, row 1 away, views 1-4 left to right, each figure cut clean, its round end ball cut off
  where the handle has narrowed (the pointing-at views keep the handle's end that peeks above the head;
  their pivot is 14 source px in from it), the jelly matched to the side weapon's so the block's
  `tint_gain` modulate gives the same colour. One scale per view, set so view 1's head is as big as the
  side drawing's (axe blade span 30.9 px, hammer 36.5 face to face).
- Per frame also `extent` (texture px: the farthest opaque px from the pivot). The previews draw a view
  as: pivot at socket + axis x (neck_len - slide), slide = (1 - `length`) x (neck_len + extent x
  scale); turned by `angle - dir`; whole (not cut); `behind` under the body, `front` over the body and
  the world; the neck over it in either layer (its tail covers the cut end).
- The order through the swing reads as one turning motion: toward (down strips) axe 1, 3, 2, 4 (its
  view 2 already has the head below the pivot), hammer 1, 2, 3, 4; away (up strips) 1, 2, 3, 4. Every
  key of those six strips names its `view`; the switches are two keys at the same `at` (a jump, no
  rotation between); `angle` is each view's `dir` but for two keys of a few degrees' lean in the
  wind-up. View 1 from the top knob through the wind-up (`behind`), the toward views 3 and 2 over the
  face (`front`) in its last part, view 4 from `w1` (the down strips from the body's bottom middle, as
  before, so the planted weapon lands below the body); the up strips stay `behind`. The hammer's
  rebound (frame 5) shows view 1 again.
- Reach (the owner: "they all should be equal reach"): every direction's drawn reach at contact
  equals the side view's, within 2 px (the packer stops otherwise, writing nothing): sweeps and
  backswing blade tip 76, chop 70, smashes head centre 68 along the aim; the head's far edge along the
  aim within 3 px of the side's. A strip that falls short gets an arm (the up strips: sweeps 30.3, chop
  30.6, thud 45.3, boom 48.8); one that reaches past is slid into the jelly from `w1` on: every key from
  `w1` holds `length` at most the strip's `contact_length` (reported in `contact.by_direction`; sweeps
  down 0.945, chop down 0.733, thud down 0.894, boom down 0.883, thud side 0.992). The neck flips from
  up to down at the pointing-at view (a 6 px neck, under the big head).
- The previews follow the game's placement: the arm is `arm_px` x `length` stretching the neck's tube,
  the slide leaves it out; a view's slide is (1 - `length`) x (`hidden_px` + the neck's own length + the
  view rect's reach along its `dir`), and a view is split at the neck's tip like the side weapon.

## Round 3: the strikes become real animations (2026-10-12)

The owner marked the contact frames: attacking up, the weapon sits on a long jelly arm and reaches
far past the body (the round-2 reach was measured from the slime's centre, he judges from the
body), and asked to check and adjust the animations himself, in the editor; asked whether they are
part of player_slime, he chose real animations over a custom tuner scene. With 4-way attacks each
strike has exactly three drawings (side, mirrored for left; down; up), so they can be ordinary
Godot animations.

- **The library:** `res://game/characters/player-strikes.tres`, an AnimationLibrary added to the
  player's AnimationPlayer as `strikes`; one animation per strike and direction:
  `strikes/<spear-jab|spear-finisher|axe-sweep|axe-backswing|axe-chop|hammer-thud|hammer-boom>-<side|down|up>`
  (the Lunge plays spear-finisher, the Quake hammer-boom, on their own timing). Its length is the
  step's windup + active + recovery; markers `contact` (the end of the wind-up) and `active_end`.
- **Tracks:** the Visual's body frame (texture, hframes, vframes, frame, offset; discrete), and the
  properties of the `StrikeRig` node (below): `weapon`, `socket`, `angle`, `length`, `arm_px`,
  `knob_w`, `head_angle`, `layer`, `view`, `view_frame`, and once at 0 `hit_reach` (the hit's radius
  for the Axe, offset for the Hammer, reach for the Spear, in this direction; the game uses it, so
  the hit follows the drawing per direction).
- **StrikeRig** (`game/shapes/strike_rig.gd`, @tool, a Node2D under the player's Visual in
  player_slime.tscn): draws the weapon, the neck and the views from those properties with the one
  drawing code the game had in ShapeVisuals (moved into the rig or a static helper it calls), behind
  the body or over the world by `layer`, mirrored when the Visual is flipped. In the editor it also
  draws the step's real hit area at the animation's current time (read from game-constants.json and
  the animation's `hit_reach`, no autoloads) and the reach from the body's edge, so scrubbing in the
  Animation panel shows the weapon and what it hits.
- **The game:** while a strike runs, the step's elapsed gameplay time is mapped onto the animation
  by its markers (wind-up onto 0..`contact`, the active window onto `contact`..`active_end`, the
  recovery onto the rest) and the animation is sought there every tick (a hit-stop freezes it); the
  rig draws; the swoosh samples the rig's head along the animation at earlier times; the Spear's hit
  line starts at the socket the animation has at `contact`. Gameplay timing stays in
  game-constants.json.
- **The converter:** `tools/build_strike_animations.gd` (headless) writes the library from today's
  look (the manifest's keys, the Spear's stages) once; it never overwrites an animation that exists
  unless asked by name. After it runs, the animations are the source of the motion: the manifest
  keeps the art (sheets, cells, weapon textures and sizes, the neck) and loses its keys.


As built (game, 2026-10-12): `game/characters/player-strikes.tres` holds the 21 animations (step 5 ms,
the Visual's texture, hframes, vframes, offset and flip keyed once at 0, its frame per key; the rig's
discrete tracks `weapon`, `socket`, `knob_w`, `layer`, `view`, `view_frame`, `arm_px`, `hit_reach` and the
Spear's `spear_inside`, `spear_fade`, `spear_shaft`, its linear tracks `angle`, `length`, `head_angle`;
two keys at one time became a key 0.5 ms before the second). The rig is three nodes under the Visual,
`StrikeRig` (behind the body), `StrikeRigFront` (z 1) and `StrikeRigNeck` (over the body), drawing what
ShapeVisuals drew before; a flipped Visual mirrors the sockets and angles (a -> 180 - a). Details the
engine needed: the game assigns the animation paused and seeks it every physics step
(`PlayerScript.seek_strike_animation`), so the AnimationPlayer never plays it on its own clock; the
old downward-aim rule (a `behind` weapon pointing down on a down aim draws over the world) became
`front` layer keys; `hit_reach` applies to chain steps only (the Lunge and the Quake play another
step's animation with their own numbers); the charge ring's held frame is the animation's first
frame, still shown through its `strike-...-f<n>` clip; the Spear's line starts at the animation's
socket at `contact`. The editor overlay draws the hit at the animation's own marker timing and
measures the body's edge as the far end of the frame's opaque run nearest the centre along the aim.

## Round 4: simple, editable strikes (2026-10-13)

The owner could not edit the Round 3 animations: each strike was 17 generated tracks, and the arm and
reach were hidden single keys. Decision: every strike is a small Godot resource that you edit in the
Inspector. Nothing is generated by hand, and there is no AnimationPlayer library in the scene.

**Files** (`godot/game/characters/strikes/`, one per strike, seven in all):
`spear-jab.tres`, `spear-finisher.tres`, `axe-sweep.tres`, `axe-backswing.tres`, `axe-chop.tres`,
`hammer-thud.tres`, `hammer-boom.tres`. The Quake charge uses `hammer-boom`.

**Fields of a strike** (`StrikeAnimation`): `shape` (axe, hammer, spear) and `step` (the chain step or
charge id in game-constants.json, for its timing), and three directions `side`, `down`, `up`.

**Fields of a direction** (`StrikeDirection`):
- `arm_px`: how far the jelly arm reaches out (game px).
- `hit_reach`: the hit's radius (Axe), circle offset (Hammer) or line reach (Spear), game px. The game
  hits with this number, so it is the hit range in this direction.
- `flip_h`: the strip is shown mirrored (the backswing's down and up).
- `spear_inside`, `spear_fade`, `spear_shaft`: the Spear only.
- `keys`: the timeline (below).

**Keys** (`StrikeKey`): `phase` (windup, active or recovery), `share` (0 to 1 through that phase),
then the values from that moment on:
- `frame` (1 to 6, the strip frame of the body),
- `angle` (degrees on screen, 0 right, +90 down; linear to the next key),
- `length` (0 to 1, the weapon out; linear),
- `layer` (behind or front), `view` (side, toward, away), `view_frame` (1 to 4), `head_angle` (the
  Hammer's head; linear). Layer, view, view_frame and frame hold until the next key.

**Time.** A strike's time runs 0 to 3: windup is 0 to 1, active 1 to 2, recovery 2 to 3, each phase's
share spread linearly. The game maps its elapsed milliseconds onto that with the step's own windup,
active and recovery (game-constants.json), so the timing numbers stay where they are. The editor
preview takes milliseconds from the start of the windup and does the same mapping.

**The rig** (`StrikeRig`, @tool, under the Visual in the player scene) computes its state from the
resource: no tracks. It has `animation` (the resource), `direction`, `preview_ms` and the overlay. In
the editor it also sets the Visual's body frame and texture, so the body and the weapon are shown
together; the rig restores the Visual's idle frame before saving (NOTIFICATION_EDITOR_PRE_SAVE), so
the scene file is never saved with a preview frame.

**The game** builds its AnimationPlayer library in code from the resources (`StrikeLibrary`), at run
time, so the scene references no library file. The names stay `strikes/<strike>-<direction>`, and the
body frame still comes from the animation, so the locomotion clip cannot override it. The hit uses
the direction's `hit_reach`.

**Migration.** A one-off headless tool reads the Round 3 library, reduces each strike to keys (it
keeps a key only where a value changes or where the angle or length departs from a straight line by
more than 0.5 degrees or 0.01), writes the seven resources, and is then deleted. The Round 3 library
(`player-strikes.tres`) is copied to the scratchpad before it goes. The scene's library reference
goes too. The arm and reach values carry over exactly: axe-chop up 30.55 and 70, and so on.

**Checks before the migration is accepted:** for all 21 Round 3 animations, the new state at every
millisecond matches the old tracks (angle and length within 0.5 degrees and 0.01, frame, layer, view
and view_frame exactly); films of the axe, hammer, spear and the Quake charge match the round 5 films
on every tick, apart from the dummy's reactions and the damage numbers; zero runtime errors; every
script compiles.

**Owner steps** (in BODY_SHAPES.md, "Editing the strike animations"): open
`game/characters/strikes/axe-chop.tres` in the FileSystem dock, change `up.arm_px` or
`up.hit_reach`, edit the keys in the list, select `Visual/StrikeRig` in the player scene, set its
`animation` to that file, pick the direction and drag `preview_ms`, then save.

**As built (2026-10-13).** Seven resources in `godot/game/characters/strikes/`; the classes are
`StrikeAnimation`, `StrikeDirection` and `StrikeKey` (`game/shapes/strike_*.gd`, with `class_name` for the
Inspector). `game/shapes/strike_library.gd` (static, preloaded) reads them: `state_at` and `state_at_unit`
(what a strike shows), `unit_at` (elapsed ms to the 0-3 time), `build_library` (the player's `strikes` library,
built at run time and installed by the shape controller, so the scene holds no library), `contact_socket`,
`hit_reach`, `flip_h`, `step_data` and `timing_of` (game-constants.json read directly for the editor). The rig
keeps its drawing and reads the state from the library. Deviations from the spec, and why:
- `StrikeKey` has a `jump` flag: the angle, length and head angle snap to the key instead of sliding to it.
  The Round 3 Spear's length (and its other stepped values) was nearest-interpolated, and the approved look needs
  the steps; a straight line would have changed the look.
- `shape` and `step` are plain strings (an enum cannot have the empty default the spec asks for).
- `spear_inside` and `spear_fade` are one value per direction, taken at the longest stage (they varied by a few
  hundredths of a px across the shown stages, and the hidden stages drew nothing).
- The axe chop's up strip was saved with a length of 0.1 s (its keys run to 0.575 s; the step takes 0.65 s, and
  the other twenty strips match their steps). Godot samples a track by the animation's own length, so the
  migration first set it to the step's length; the Round 5 films have that look.
- The migration reduced the keys with the spec's tolerances, checked at the old key times (a straight line
  between kept keys and the held values; the stepped values as steps). Checked at every millisecond of each
  strike's step timings (17,580 checks): angle and head within 0.37 degrees, length within 0.0005; frame, layer,
  view, view_frame, arm_px, hit_reach, flip_h, socket and knob width exact. The migration tool was deleted after
  it ran (copy in the scratchpad). The Round 3 library was never committed, so its only copy is the scratchpad
  backup until the owner's editor closes.
- Films (the axe, the hammer, the spear, the Quake and the Lunge, on the round 5 aims): the body frame, texture,
  flip, layer, strike and weapon angle, length and head match on every tick; the pixel differences are the
  dummy's reaction and numbers, the impact effects and the camera shake, and a 1 to 2 px render jitter (two runs
  of the same code differ by the same amount).
- Not done: the scene edit (`player_slime.tscn`: the `libraries/strikes` reference and the StrikeRig's old track
  properties) and the deletion of `game/characters/player-strikes.tres`, both held while the owner's Godot editor
  is open. The owner's editor preview was not run here (the rig's @tool preview needs the editor); a windowed
  capture of the player scene with `axe-chop.tres`, `up`, the overlay on, at 330 ms was made instead. (Both done
  by the lead before round 5, once the editor was closed.)

## Round 5: the preview in the Inspector, fewer keys, one home for the reach (2026-10-14)

The owner asked whether Round 4 was the best design. Agreed changes: a live preview where the strike is edited
(not on a rig node in the player scene), fewer keys, the chain steps' reach in one place, editable attachment
points.

**Spec.**
- A plugin `godot/addons/strike_preview/` (plugin.cfg, plugin.gd, an EditorInspectorPlugin, a @tool preview
  Control), enabled next to godot_ai. Above a StrikeAnimation's fields: the slime large (body at least about 120 px
  on screen) and centred in side, down and up, drawn exactly as the game draws it (the body frame from the strike
  sheet, the StrikeRig's weapon, neck and views, the hit-area overlay and the "past the body" readouts); a
  play/pause button looping in real time; a time slider over the whole strike with the windup, active and recovery
  bands and a marker for every key of each direction; live updates while fields are edited. Built like the game: a
  Visual Sprite2D and the three rig nodes, the state from StrikeLibrary.state_at, the timing read from
  game-constants.json. No AnimationPlayer; player_slime.tscn is not touched.
- The rig's own editor preview goes (`preview_ms`, driving the Visual, the pre- and post-save handling); its
  drawing, overlay and the clock, timing and tint stay.
- Fewer keys: always a key where frame, layer, view, view_frame or jump change; angle and length keys only where a
  straight line would be off by more than 3 degrees or 0.05; target 4 to 8 a direction. The sweeps' active window
  still runs the hit arc exactly (its two ends). A before-and-after image (axe-chop, hammer-boom; side, down, up; the
  contact and two other moments), looked at, with extra keys kept where the look changes.
- One home for the reach: game-constants.json loses the chain steps' `radius` (the Axe), `offset` (the Hammer's
  Thud and BOOM; `radius` 48 stays) and `reach` (the Spear's jabs and lunging jab); every reader goes through
  StrikeLibrary.hit_reach for the step's direction, a missing strike file being a push_error, never a silent 0.
  The charges (the Spin, the Quake, the Lunge) keep their numbers.
- Attachment points: `StrikeDirection.socket_nudge` (six Vector2, game px, default zero) added to the manifest's
  socket of frames 1 to 6, mirrored with a left strike and a flip strip; the preview draws the socket as a dot.
- Short resource doc comments; `class_name` on the three resources only.

**As built (2026-10-14).**
- **The preview** (`addons/strike_preview/`: `plugin.cfg`, `plugin.gd`, `strike_inspector.gd`, `strike_preview.gd`).
  Three views, each a SubViewport with a Sprite2D Visual at the player scene's scale (0.28125) and the rig's
  StrikeRig (behind the Visual), StrikeRigFront (z 1) and StrikeRigNeck under it; the body frame, the sheet and the
  mirror from StrikeLibrary.state_at on the step's game-constants.json timing; zoom 130 / 48, so the body is 130
  screen px tall (the side view 382 x 312 px, down and up 382 x 421, in a 420 px Inspector). The slime sits at the
  middle of the side view, a little above (down) or below (up) the middle of the others, where their weapons reach
  further. Play / Pause loops in real time (a 300 ms rest at the end); the time bar draws the three bands and a
  tick per key and direction (pink for a jump), and a click or a drag sets the time and pauses. The readouts are
  the rig's `overlay_numbers()` (the tip and the hit's far edge, each also past the body's edge, and the body's
  edge), as two lines under each view. It checks the file every frame and redraws only while it plays or when
  the time, a size or a value changed (the rig no longer redraws itself every frame in the editor), so a paused
  preview lets the editor idle. It writes nothing and keeps its time and play state across the Inspector's
  rebuilds.
- **The rig.** `preview_ms`, the Visual handling and the save notifications are gone. `animation`, `direction`,
  `show_overlay`, `overlay_text`, `clock_ms`, `timing` and `tint` are plain properties (no exports, so a scene
  saves none) whose setters redraw; `is_active()` is a strike set and `clock_ms` >= 0; its every-frame redraw
  while active is the game's only. New: the socket's dot on the overlay, `overlay_numbers()` and `overlay_lines()`.
- **Keys**, side / down / up: spear-jab 6 / 6 / 6, spear-finisher 6 / 6 / 6, axe-sweep 11 / 13 / 12, axe-backswing
  12 / 13 / 12, axe-chop 12 / 13 / 13, hammer-thud 11 / 12 / 11, hammer-boom 11 / 12 / 12: 231 to 216. That is the
  fewest the rules allow (an exhaustive fewest-keys search over the round 4 keys gives the same 216): an Axe or Hammer
  direction has 5 to 7 keys forced by frame, layer and view changes and 4 to 7 more where its motion bends beyond 3
  degrees or 0.05, so the 4 to 8 target is out of reach without changing the motion. The snap pairs (a key that
  only holds the one before it, less than one 60 fps frame before the next) became one `jump` key each
  (axe-sweep side, axe-chop down, the Thud and the BOOM). The largest difference from round 4, sampled every 0.0005 units: 2.85 degrees
  (hammer-thud side, angle and head), length 0; frame, layer, view and view_frame exact. The sweeps' active window
  runs the hit arc to 0.0000 degrees (its frame and layer keys inside lie on the straight line). The
  before-and-after image showed no visible change in its 18 pairs, so no extra key was kept.
- **Reach.** Removed from game-constants.json: `reach` 110 (jab, jab-2) and 132 (lunging-jab), `radius` 76 (sweep,
  backswing) and 70 (chop), `offset` 68 (Thud, BOOM). The strike files held the same numbers, so the game hits
  the same. The readers: ShapeController `_with_strike` (now `StrikeLibrary.chain_hit` for every chain step: the hit,
  the Spear's wall-cut line and the drawing's numbers, which ShapeVisuals and the rig's `reach_override` read) and
  `reaches()` (the click and moba attack orders), and the rig's overlay (`StrikeLibrary.hit_reach`). With no `reach`
  in the Spear's chain steps, `ShapeDefs.area_kind` tells a line by `minReach` too. A missing file or reach is a
  push_error once per strike and direction. No test reads these keys (the suite has no shapes tests).
- **Sockets.** `socket_nudge` (Array[Vector2], six zeros) on every direction; `StrikeLibrary.socket` adds it to the
  manifest's socket, `contact_socket` and the rig use it, and a left strike or a flip strip mirrors it with the
  socket.
- Also removed: `ShapeStrike.strike` (unused).
- **Checks.** Every touched script compiles (`--check-only`). Films of the axe, the hammer and the spear (right,
  down, up) and the Quake charge (down, left) against round 4's films (and round 3's): the body frame, texture,
  flip, strike, layer and clock match on every tick; the weapon's angle within 2.4 degrees on the hammer (the
  thinning), 0 on the others; no runtime errors. Against the lead's films after round 4, in the same aim order, the
  frames before the first hit are identical or differ by a 1 px jitter, and the rest differ in the dummy's
  reaction, the numbers (a random crit) and that jitter; the weapons look the same. The real editor (the console exe with `--editor` and a temporary @tool probe scene, godot_ai off for the
  run, no other editor on the worktree): `axe-chop.tres` opened in the Inspector shows the preview playing in real
  time; raising `up.arm_px` by 30 in memory lengthens the up weapon at once (not saved: the file is byte-identical
  afterwards). In the editor's default low processor mode the editor drew 61 frames in a second while the preview
  played, none in a second while it was paused, and one after the edit made while paused. The only console errors are the engine's `texture_set_size_override` messages, which every windowed
  run here prints. The probe files were deleted. The suite was not run.

## Round 5b: the owner's review of round 5 (2026-10-14)

The owner tried the preview. The up chop did not bring the axe from behind the head as the side and front ones do;
changing `arm_px` seemed to do nothing until 0 (the up and down weapons are mostly the painted view's own handle, the
arm only the jelly tube, and the picture lagged one edit behind); and in this steep top-down view a strike away from
the camera leaves from the top of the head, so measured from the body's centre it looks twice as long as the one
toward the camera. Decisions: redesign the up chop (and the up smashes, which had the same fault); one knob for the
drawn reach (`arm_px`, negative pulls the weapon in); a hit centre per direction that the owner drags in the preview,
with a handle for the reach; the preview must show an edit on the edit itself.

**As built.**
- **The up motion** (axe-chop, hammer-thud, hammer-boom `up`; the body frames unchanged): the weapon raised (toward 1,
  in front of the body), then back over the head toward the camera (toward 2, and the chop's toward 3, turned head
  up, larger: closer to the camera), back up through the vertical, then over the head and away (away 1 to 3, behind
  the body, smaller) to land beyond (away 4). The tilts toward the camera snap (`jump`), so they draw no swoosh, and
  a step where a painted view's frame changes no longer starts a swoosh anywhere.
- **The perspective values** for those three (every other strike's reach values are unchanged, the owner tunes
  them): `arm_px` -6 (chop), 2 (Thud, was 45.27), -2 (BOOM, was 48.78), so the up weapon lands a little shorter on
  screen than the down one (the tip 26 / 40 / 39 px past the body against the down's 33 / 49 / 48); the hit covering
  where it lands: the chop's sector from `hit_center` (0, -7.5), the top of the head, with `hit_reach` 25.5 (to the
  blade's tip); the Thud's and the BOOM's 48 px circle on the head (`hit_reach` 25 and 17 from the centre). This
  replaces the owner's trial values on the chop's up.
- **`hit_center`** (StrikeDirection, a Vector2, zero by default, in the side view's right-facing frame, mirrored with
  a left strike and a mirrored strip like the sockets): StrikeLibrary.chain_hit puts it in the chain step's numbers
  (`ShapeStrikes.HIT_CENTER_KEY`); ShapeStrike.area_shapes measures every area from it (the Axe's arc round it, the
  Hammer's circle `offset` ahead of it, the Spear's line), `impact_centre` and the knock start there, and the Spear's
  wall ray is cast from the feet moved by it (`wall_reach(..., shift)`); the drawn spear runs to the hit line's end.
  The charges are unchanged. The rig's overlay draws the hit from it, with a yellow cross on it and a blue handle on
  the ring along the aim.
- **The handles** (the preview): a press near the cross or the handle starts a drag (the strike pauses); the cross
  sets `hit_center` under the pointer, the handle `hit_reach` (the Hammer's: the far edge less its circle), live,
  snapped to 0.5 px; the release is one action in the editor's undo history (`create_action`, `add_do_property`,
  `add_undo_property` on the StrikeDirection, `commit_action`), so Ctrl+Z undoes it and Ctrl+S saves the file.
- **`arm_px`, one knob:** positive stretches the neck's tube as before; negative slides the weapon back into the jelly
  by that many px (the tube at its own length, the hidden end cut as with a shorter length); both grow with the
  length. The six directions whose keys slid the length below 1 from the contact on now hold it at 1 with a negative
  arm (axe-sweep and axe-backswing down -2.54, axe-chop down -13.29, hammer-thud side -0.47 and down -6.35,
  hammer-boom down -7.01; their later keys' lengths solved so every key draws the same tip). Checked every 5 ms: the
  same tip from the contact on (within 0.006 px), the wind-up weapon that many px further in, body frames, layers,
  views and angles unchanged everywhere else.
- **The refresh:** the preview redraws the rig's three nodes and renders its views (`UPDATE_ALWAYS`) for six frames
  after any change (its time, its sizes, any value of the file, a handle's state), then lets the editor idle.
- **The readout:** past the body first and larger (the weapon's tip and the hit's edge), then the hit centre and the
  numbers from the slime's centre, in words.
- **One scale:** the three views are equally tall and share one zoom (the largest that fits each), so the slime and its
  reach have the same size on screen in all of them; only the slime's anchor differs per view.
- **Checks.** Every touched script compiles. Films of the axe and the hammer (right, down, up): the body frame,
  texture, flip and clock the same as round 5's on every tick; the angle and the layer changed only on the three up
  strikes, the length only on the six folded directions; no runtime errors. The real editor in its default
  low-processor mode, a temporary probe (godot_ai off for the run, no other editor on the worktree): `up.arm_px`
  set 30, 10 and -10 through the undo history, each followed by a one-second real-time wait, drew six frames each and
  a changed up view (the tip 68.8, 48.8, 28.8 from the centre); `up.hit_center` (0, -20) and `hit_reach` 35 through
  the history changed the picture; a synthetic drag of the cross 40 screen px up set `hit_center` (0, -22.5) and one
  undo put back (0, -7.5); the file was byte-identical afterwards and the probe was deleted. The suite was not run.
