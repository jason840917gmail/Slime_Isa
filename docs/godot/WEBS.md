# Webs: floor webs, web walls and silk parcels

> **Status:** built 2026-10-17 for the Weaver Hollow (Chapter 2's dungeon,
> [its design](../design/2026-10-16-dungeon-weaver-hollow.md)); tried in the playground's Webs corner.
> Tests in `godot/tests/test_weaver_webs.gd` (not run yet). The Silk skin is built (roadmap 7.8,
> [SKINS.md](SKINS.md#silk)): its hook is `player.crosses_webs()` (`game/scripts/player.gd`), true
> once the skin is won (or lent); the Silk Gulp form no longer counts.

The webs' rules (owner, 2026-10-16, question 131; roadmap 7.9):

| | Floor web | Web wall | Silk parcel |
|---|---|---|---|
| **Without the Silk skin** | a walk is halved; **a Roll sticks** (it ends there and the slime is rooted) | solid: a walk and a Roll stop against it | every hit clinks: "Wrapped tight in silk. You need something to free it." |
| **With the Silk skin** | full speed, a Roll crosses | passed at half speed; a shape's hit cuts it open for good | a shape's hit frees it: it tears open and spills what it holds, for good |

Every hit on a web wall without the skin clinks with "Thick silk. It will not give." With the skin,
only a weapon or shape hit (request tags `weapon` or `spear`: the Spear in Release 1, and the old
weapons) cuts or frees; throws and blasts clink without a line. **A blast never clears a web.**
Enemies are never slowed by floor webs (only the slime's walk asks), and web walls block them.

The numbers are in `game-constants.json` `webs`: `floorSlowMultiplier` 0.5, `rollStickMs` 900,
`wallPassMultiplier` 0.5, `enterCueIntervalMs` 1200 (the first step into a floor web plays a soft
`WebStruggle`, at most this often), `glintEveryMs` [2600, 5200] and `glintMs` 520 (the parcel's
glint).

## Floor webs: the `webs` WebLayer

1. In a world scene, **Add Node > WebLayer**, name it `webs`, beside the ground layer (same grid,
   position (0, 0)). It takes `game/world/webs/web_tileset.tres` by itself and draws at z -1 (with
   the ground's details, under every body).
2. Paint cells from its palette (TileMap panel): **row 0, the auto tile** (light frame, three dots):
   each cell picks one of six webs and one of eight turns from its cell (`variation` rerolls them),
   so a field never repeats; **row 1** (dark frame, dots count the web): one web exactly, turned by
   the TileMap panel's flip and rotate buttons. Erase a cell to clear its web.
3. Each web is a flat picture 1.5 cells wide centred on its cell, so painted neighbours overlap
   into one web; the slow and the stick hold exactly on the painted cells (the slime's feet).
   `paint_opacity` (0.3) shows the palette squares in the editor only; `web_opacity` fades the webs.

A web that must move or vanish with what it lies on (B6's falling slabs) is an **`object.floor-web`**
node instead: the same rule over `size` (64 x 64, centred on its root), one of the six webs
(`variant`, `turn`); hidden, it holds nothing. As a child of a slab, raise its `z_index` above the
slab's picture.

**The Matron's volley patches** (`effect.matron-web-patch`, `web_patch.gd`) follow the same rule
over their circle (r 50, the slime's centre): half a walk, a Roll sticks (`caught`), nothing sets
the slime back; the Silk slime tears them quietly ([specs/matron.md](specs/matron.md) §5.5).

## Web walls: `object.web-wall`

Thick silk filling a door slot or a nook's mouth. Place it as an instance in the world scene:

- **A north or south door:** `orientation` "across" (the web faces the camera). Put the root on the
  doorway's floor line (where the wall's foot is), in the middle of the opening. `span` 128 (a
  two-tile door), `thickness` 24 (the solid band across it; drawn as a red box in the editor, the
  hurtbox as an orange one). Set `height` to the wall's height (the corner's fieldstone wall: 92) so
  the web does not stand over the wall; 0 keeps the picture's own proportion (about 138 high).
- **An east or west door:** `orientation` "side" (a narrow band of silk seen from above). Put the root
  in the middle of the opening; `span` is the opening's length north to south (128).
- `hides_secret` on: cutting it plays the secret jingle (`SecretFound`), else the web tear cue; both
  say "The web tears open!". `flag_id` names its story flag (default
  `web-wall.<world scene>:<node path>`; name it when anything else reads it, e.g. a story variant
  that shows a nook's prize). `preview_cut` shows the cut look in the editor; `art_scale` resizes the
  picture.

The solid is a StaticBody2D on the `world` layer; the Silk slime gets a collision exception with it
(kept until it has left the passage), and walks at half speed while its feet are within the solid
grown by 16 units. It stops enemies, their shots and a throw too (a throw ends at its hurtbox, so a
thrown Goo Bomb stops in the silk).

- `remembered` off: silk that is spun again (the Matron's cage, specs/matron.md 8.2): a cut sets
  and reads no flag.
- While the slime stands behind an "across" web (its feet just north of the root, inside the
  picture) the silk fades to 0.45 so the slime shows through (`BEHIND_ALPHA`; presentation only),
  as in the Weaver Hollow's C4, whose rows of web walls stand across an open floor.

## Silk parcels: `object.silk-parcel`

Something small wrapped in silk, lying flat on the floor; it glints now and then and never breathes
or stands up (the Cocoon Mimic does both; `object.cocoon-prize` is the Mimic's look). Put its root
where the parcel's front edge meets the floor; `coins` are paid at once ("+30c"), `contents`
({item_id: count}, as a chest's) spill around it as loot piles (saved until picked up), with "Freed
from the silk!". It stays torn open: its story flag (`flag_id`, default
`silk-parcel.<world scene>:<node path>`). Behind a web wall, put it far enough in that the web's
picture does not hide it. A dungeon item in `contents` ("dungeon-small-key": a key wrapped in silk,
the Weaver Hollow's C4) drops in front of it as the kit's floor key (`DungeonKeyPickup`, recorded
under the parcel's flag), and lies there again after the world is built again until it is taken.

## Critters in silk (2026-11-21)

`game/world/webs/silk_critter.gd` (on a silk parcel; placed by `tools/build_gloop_river_roads.gd` in
Gloop Forest): a forest critter wrapped in silk.
- **Look:** the silk parcel, wriggling now and then (its shiver, every `wriggle_every_ms`), so it
  reads as alive before the Silk skin. A hit without the skin clinks: "Something wriggles inside
  the silk...".
- **Freed** (the Silk skin and the Spear, as any parcel; its flag `gloop-forest.critter-<animal>`):
  the animal (`critter`, a town animal's scene) pops out and runs off along `run_toward` (toward the
  camp), fading; only its picture runs (presentation, real time).
- **Home:** `game/world/webs/freed_critter.gd` in Mossy's camp holds nothing until that flag is set,
  then puts the animal there to wander (as the town's animals).
- **The five:** squirrel, hedgehog, snail, robin, bluebird. All five home: Sunny's talk
  `critters-prize` (npc-definitions.json) gives her prize once (`sunny.critters-prize`).

## Tripwires (2026-11-21)

`game/world/webs/tripwire.gd` (a Node2D, placed by `tools/build_gloop_river_roads.gd` in Gloop Forest):
- **Look:** a silk thread `length` units along the node's x axis. Turn the node for a thread across a
  north-south road.
- **Snap:** when the slime's feet come within `touch_px` of it, it snaps with the `WebTear` cue.
- **The drop:** every Silk Lurker within `reach` (260) of its middle drops at once
  (`silk_lurker.gd` `trip()`: its tell, then its drop, even with the slime out of its usual range).
- **Use:** a trap to step round, or to spring on purpose.
- **Again:** it is spun again when its chunk is built again.
- **Where:** at the foot of E3's spider column and on F4's road up to the Oak.

## Art

Generated on Magnific (GPT 2.5, transparent, the Lili sheet as style reference) and packed by
`scripts/art/pack-web-art.py` into `godot/asset/MAPS/webs/` (2 px per unit; sources and prompts in
`asset/Originals/weaver-hollow/webs/`): `floor-webs-6x1.webp`, the palette `palette.png`,
`web-wall-across-2x1.webp` and `web-wall-side-2x1.webp` (intact, cut), `silk-parcel-3x1.webp`
(closed, torn open, the glint star). The sheets import with mipmaps.

## Files

| Path | What |
|---|---|
| `godot/game/world/webs/floor_webs.gd` | FloorWebs: the rule (the walk's scale, the Roll's stick, the enter cue); player.gd's `_move` asks it |
| `godot/game/world/webs/web_layer.gd`, `web_tileset.tres` | The `webs` WebLayer and its palette |
| `godot/game/scripts/floor_web.gd`, `scenes/objects/floor-web.tscn` | `object.floor-web`: one web as a node |
| `godot/game/scripts/web_wall.gd`, `scenes/objects/web-wall.tscn` | `object.web-wall` |
| `godot/game/scripts/silk_parcel.gd`, `scenes/objects/silk-parcel.tscn` | `object.silk-parcel` |
| `godot/game/scripts/web_patch.gd` | The Matron's volley patch, on the floor webs' rule |
| `godot/game/dev/corners/webs_corner.tscn` | The playground's Webs corner (east, below the bestiary pens, around (3456-4480, 4790-5570)): a painted band, a lone `object.floor-web`, two nooks behind web walls (across, side) with parcels, a skin pedestal that lends the Silk skin ([SKINS.md](SKINS.md#the-skins-corner)) |
| `godot/tests/test_weaver_webs.gd` | Floor webs, web walls, parcels |

## Limits

- The Silk skin is the Silk Gulp form until roadmap 7.8 builds it.
- A web layer has no elevation levels: a web cell slows whoever's feet are in it, on any level.
- The parcel's glint place (`GLINT_AT_PX` in `silk_parcel.gd`) is the packer's printout; repack and
  update it together.
