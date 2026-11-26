# Painted pits: sources

Pictures of a hole's inside, seen from above, that `PitDepth`'s `picture` draws inside a room's faces
(from `picture_margins`, cropped about its middle to fill the hole, the dark over it only to
`picture_dark`): [DUNGEONS.md](../../../../docs/godot/DUNGEONS.md#the-crystal-mine-rebuilt-wing-1-the-mouth-and-the-high-line-step-4-2026-11-25).
`godot/tools/pack_pit_picture.gd` packs one into a texture resource under `godot/asset/MAPS/interiors/`.
Every file is one Magnific GPT 2.5 still (`gpt-2-mini`, 1k), stripped of its credentials block
(`scripts/art/strip-credentials.py`). The pictures stay on this disk only (git-ignored); this README is
tracked.

| File | Size | What | Used by |
|---|---|---|---|
| `mine-shaft-a.png` (2026-11-25) | 1344 x 752 (16:9) | M4's shaft: timber cribbing, a ladder and two lift ropes, crystal veins in the slate, into the dark | `godot/asset/MAPS/interiors/mine-shaft.res`, M4 |
| `mine-chasm-a.png` (2026-11-25) | 752 x 1344 (9:16) | a natural rock rift: dark blue-grey slate ledges stepping down both long sides, icy-blue and violet crystal veins, black along the middle | `godot/asset/MAPS/interiors/mine-chasm.res`, M9 |
| `mine-pit-a.png` (2026-11-25) | 1024 x 1024 | a natural square pit: slate ledges stepping down on all four sides to a black middle, crystal veins, loose pebbles | `godot/asset/MAPS/interiors/mine-pit.res`, M8's void and M2's two pits (cropped by `PitDepth`) |
| `rejected/mine-chasm-a-warm.png`, `rejected/mine-pit-a-warm.png` | as above | the first takes of the chasm and the pit: their rims came out sandy gold and read as yellow frames against the Mine's blue rooms | nothing |

**Crop boxes** (about the middle, for each hole's drawn part: its size less the default
`picture_margins` 24, 60, 24, 24; source pixels, x0, y0, x1, y1):

| Hole | Size (units) | Drawn | Source | Crop | Source px per unit |
|---|---|---|---|---|---|
| M9's chasm | 384 x 768 | 336 x 684 | `mine-chasm-a.png` | 46, 0, 706, 1344 | 1.96 |
| M8's void | 512 x 576 | 464 x 492 | `mine-pit-a.png` | 29, 0, 995, 1024 | 2.08 |
| M2's west pit | 320 x 256 | 272 x 172 | `mine-pit-a.png` | 0, 188, 1024, 836 | 3.76 |
| M2's south pit | 384 x 192 | 336 x 108 | `mine-pit-a.png` | 0, 347, 1024, 676 | 3.05 |

`PitDepth` crops about the middle by itself, so packing with `--aspect=<hole width>x<hole height>`
(as M4's `--aspect=832x448`) gives the same picture; the game's art density is 2 px per unit, so M9
and M8 draw at about full size and M2's pits at about half.

Cost: 200 Magnific credits for the chasm and the pit (five generations at 40: the first takes of
the chasm, the pit and the props sheet `../../mine/mine-props-e.png`, then a second take of the chasm
and the pit). The shaft's 40 came before.

## Prompts

**The shaft** (one still, 16:9, the first kept; the style reference a crop of M4's render). Its exact
prompt was not kept; the wording planned for it was "top-down view straight down a deep square mine
shaft, dark blue slate walls with glowing icy-blue and violet crystal veins and old timber cribbing
receding into black darkness, faint dust in the air, hand-painted game art matching the reference ...".

**The chasm and the pit, second takes (kept).** References: the shaft above (downscaled to 1024 px
wide) and a crop of M14's room as the game draws it (`output/dungeon-rework/mine/rooms/game/look-m14-shaft-floor.png`,
the room only). The chasm (9:16):

> Hand-painted 2D game art. Take the camera, brush work and darkness falloff from the first reference
> picture (looking straight down a deep mine shaft into black) and the rock colours from the second
> reference picture (a dark blue-grey slate cave floor with icy-blue and violet crystals). Paint:
> looking straight down into a deep natural rock chasm inside a crystal mine, a tall narrow rift whose
> long side runs from the top of the picture to the bottom. All the rock, from the rim at the
> picture's edges down to the depths, is the same dark blue-grey slate as the second reference's
> floor, cool and dim, with only a soft faint warm glint on the highest ledge tops; no yellow, golden,
> orange or sandy rock anywhere. The walls break into jagged ledges and outcrops that step down and
> down on both long sides and narrow toward the middle; veins and clusters of glowing icy-blue and
> violet crystal run through the rock and glint on the ledges; the walls fall away in perspective
> toward a pitch black bottomless darkness along the middle of the rift; faint dust in the air. No
> timber, no ladder, no ropes, no bridge, no figures, no creatures, no sky. The rock fills the picture
> to every edge, no border, no frame, no text.

The pit (1:1): the same opening, then "Paint: looking straight down into a deep natural pit in the
rock floor of a crystal mine, roughly square, seen from directly above its middle." and the same
rock sentence, then "Its four walls break into jagged ledges that step down on every side and
converge in perspective toward a pitch black bottomless darkness in the middle; small veins and
clusters of glowing icy-blue and violet crystal run through the rock; faint dust in the air; a few
loose slate pebbles on the ledges." and the same closing ("No timber, no ladder, no ropes, ...").

**The first takes (rejected).** The shaft alone as the reference; "Hand-painted 2D game art matching
the reference picture exactly in camera, light, colours, brush work and darkness falloff: looking
straight down into ...", the walls "rough natural dark blue-grey slate rock", and "warm golden light
catches the top ledges at the picture's edges and fades to black with depth". That light painted the
rims sandy gold.
