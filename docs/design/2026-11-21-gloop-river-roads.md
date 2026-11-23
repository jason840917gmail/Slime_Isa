# Gloop Forest: River Roads (2026-11-21)

Chapter 2's forest, redone as a whole. The owner's brief: "i dont like the actual design, it can
take part of E3 and F3; the idea is of a forest with narrow roads and bridges over rivers, few hills
if any; the player have to overcome the webs in his way to kill the enemies and get to places." Three
sketches were drawn (`output/gloop-sketches/`, git-ignored, with a README). The owner picked **A,
River Roads**, then asked for more ("we need more spaces in the chunk ... make some under the trees
walks giving the idea of a really dense forest; imagine cool things to do in a forest, take ideas of
other successful games"). That became **A2**:
[the map](gloop-river-roads/sketch-a2-river-roads-developed.png) and
[the ideas board](gloop-river-roads/forest-ideas.png).

**Webs (owner, 2026-11-21):** "there are webs that stop and others that slow down; the ones that stop
only to be passed with the Silk skin, so don't put them in the main way to the Pearl."
- On the way to the Weaver Hollow there are only floor webs, which slow a walk and stick a Roll.
- Web walls close side ways and Silk shortcuts the slime sees early.
- The sketches' "spinner webs" (web walls an orb-weaver held, dropped by killing it) were rejected.

## The layout

Gloop Forest is now six chunks: E3 F3 / E4 F4 / E5 F5. E3 and F3 were the North Wilds'; their
neighbours D3 and G3 are closed against them by woods.
- **Rivers.** The Gloop flows from the Mere (E3/F3) down the E|F line. A creek runs along E3|E4 and
  another along F4|F5. Every other chunk line is a canopy wall (forest tile 18).
- **Crossings.** Two touching chunks meet at exactly one crossing:
  - footbridges over the Gloop: X2 (E3|F3, rows 18-19) and X3 (E4|F4, rows 20-21);
  - north-south footbridges over the creeks (phase 2): X1 (E3|E4, columns 24-25) and X5 (F4|F5,
    columns 5-6); a ford: X4 (E5|F5, rows 25-26);
  - trail gaps between lantern posts: X6 (F3|F4, columns 6-7, a path under the canopy) and X7
    (E4|E5, columns 14-15).

  `check_chunk_lines.gd` passes every Gloop line. It flags only Volcano Ridge's F2, which is open on
  its own side against F3's border wood (a placeholder region).
- **The ways out of the region.** The way in from Slimeshire stays on E4's west edge (rows 7-9, three
  rows to match D4's gate road). The way out to the Crystal Caverns stays on F4's east edge (rows
  26-27, into the Spiral's G4).
- **Clearings.** Every chunk has four or five clearings, joined by two-cell roads:
  - **E4:** the gate glade, Mossy's walled camp and its yard on the Gloop (the raft jetty), the
    bridge-head, the fairy ring glade.
  - **E3:** the landing glade (the first floor webs, nothing around), the Web Glade, the Firefly
    Tangle, the spider's column, the weavers' road, and Tom's hollow under a rock ledge.
  - **F3:** the east bank, the Clod Stompers' clearing, the beach, the Mere's lily-pad islet (a heart
    quarter), the stump glade.
  - **F4:** the bridge-head, the Watch Oak's glade (the forecourt stays where it was), the silk nook
    (behind a web wall; its heart quarter in a cave under a cracked ground since round 3), the
    web-wall maze.
  - **E5:** the crossroads, the sinkhole (the Gloop Cavern's cracked ground), the glow grove behind
    deadthorn, the beaver pond, and the knoll (the forest's one hill, level 2, with living roots on
    its face for the Feral skin).
  - **F5:** the lookout glade, the long webbed bridge over the pool, the iron hollow (moved; a heart
    quarter in its chest), the east shore, and the secret glade behind a fallen tree (Heavy Roll).

## The main path

1. Through the Verdant Gate to Mossy's camp.
2. North over X1 into E3. The Web Glade, then the Tangle, then the spider's column: a Slime Spider at
   the top of a webbed column.
3. The weavers' road, and a fallen tree (Heavy Roll) into Tom's hollow.
4. Tom: three Spear hits, then the Goo Bomb lesson.
5. The cracked rock in the ledge beside him: blown, it is the old raft landing, and a ride back to the
   camp's jetty (Tom's way back, question 132).
6. East over X3 into F4: floor webs on the road and in the Oak's glade.
7. The root gate: the Weaver Hollow, Pearl 2 (the Silk skin), the Matron.
8. With the Silk skin: the web-wall maze south of the glade, then east to the Caverns.

## Built (phase 1, 2026-11-21)

`godot/tools/build_gloop_river_roads.gd` holds the layout (64 x 96 cells, E3's corner at 0, 0) and
writes one chunk a run:

```bash
"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_gloop_river_roads.gd -- --chunk=e3|f3|e4|f4|e5|f5|wilds [--dry]
```

What it does:
- It paints the chunk's ground: forest floor under the canopy, moss in the clearings, sand on the
  roads, deep water, and shallow water for the fords.
- It paints the canopy walls, `elevation` (Tom's ledge and the knoll), a `webs` WebLayer and `vines`.
- It places its nodes under `RiverRoads`: footbridges, lantern posts, web walls, chests, silk
  parcels, placed enemies, Tom's web and crack, the fallen trees, the jetty's arrival, and the glow
  grove's deadthorn.
- It moves the story places that stay in their chunk once (root meta `river_roads_moved`): the camp
  with its walls, hut and safe zone (cells -11, -20), the iron hollow with its pen (+7, -1), and the
  Gloop Cavern's cracked ground.
- It takes out the old props, the wander areas, the placed enemies, the web lane, the old silk nook
  and the old webs.
- E3 and F3 are made from F5's scene the first time. `--chunk=wilds` closes D3 and G3.

The data changed with it:
- `world-map.json`: regionCells, and the sketch's terrain in E3/F3.
- `world-chunks.json`: Gloop's six chunks, and the doors `tom-raft-landing` and `raft-jetty`.
- `scene_index.json`: the new chunks are listed, and North Wilds E3/F3 are deleted.

The elevation caches were baked for the six chunks, D3, G3, E2 and F2.

**Rendered in the running game** (`render_glimmerhill.gd`, laid out by
`output/gloop-sketches/compose_renders.py`). Not playtested. The tests were not run.

These tests name the old places and need updating:
- `test_tom.gd`: Tom is now in E3, not E5.
- `test_matron.gd`: the nook is now in F4, and F5's wander areas are gone.
- `test_chapter_two_gloop.gd`: the web lane is gone.
- `test_quests_gloop.gd`: the camp has moved.

## Phase 2, built (2026-11-21)

- **Paths under the canopy:** ForestLayer's canopy-path tile ([FORESTS.md](../godot/FORESTS.md),
  palette row 1, column 18). They carry:
  - the Firefly Tangle and its wrong turns (E3), with lantern posts at its mouth by the Web Glade;
  - X6 (F3 to F4), with lantern posts at both mouths. Since round 3 it runs down columns 38-39
    (region) from the stump glade to the Oak road, a canopy column west of the Oak's glade;
  - the secret ways (one cell or two wide, a firefly at the mouth as the only tell) to the fairy ring
    (E4), the glow grove (E5), and a hidden way from F4's bridge-head into the Oak's glade.
- **Fireflies:** `soft_glow` nodes over the Tangle's four right turns and at the secret mouths, drawn
  over the treetops.
- **The glow grove** (E5) is dim, not black (`dark_room.gd` `darkness_override` 0.72). Glow-moss
  (`glow_moss.gd`) lights the way to its chest, and deadthorn still shuts its way in.
- **The fairy ring** (E4's secret glade): `game/world/fairy_ring.gd` heals 2 HP every 0.7 s of the
  gameplay clock while the slime stands in it (scene properties). The mushroom decor's fairy-ring-glow
  art, scaled 1.7, is its picture.
- **Tripwires** (`game/world/webs/tripwire.gd`, [WEBS.md](../godot/WEBS.md)): one at the foot of E3's
  spider column and one on F4's road to the Oak, each with Silk Lurkers over it. Touched, a thread
  snaps and they drop.
- **New art** (Magnific GPT 2.5; sources in `asset/Originals/props/gloop-river-roads/`, packed by
  `scripts/art/pack-gloop-river-roads.py` into `godot/asset/MAPS/props/gloop-river-roads/`; scenes in
  `game/scenes/objects/gloop/`; the pictures load through `sheet_sprite.gd`, so they show before
  the editor imports them):
  - **North-south footbridges** at X1 and X5 (`footbridge-north-south.tscn`: `bridge_deck.gd` with
    a deck 80 x 192 that opens the three creek rows). They replace the fords there.
  - **The raft** moored at the camp's jetty, where Tom's crack brings the slime.
  - **The hollow log** lying along F5's north road (`hollow-log.tscn`, `game/world/walk_through.gd`):
    the slime walks through it, and it fades to 0.45 while the slime is inside.
  - **The beaver dam** on E5's pond (`beaver-dam.tscn`, `game/world/beaver_dam.gd`). A Goo Bomb
    blast (group `blast_targets`) sets `gloop-forest.beaver-dam`; the pond's cells turn to forest
    floor (no water collision, the ground's surfaces refreshed), the dam goes, and the sunk chest
    on the bed shows. With the flag set, the pond is dry when the chunk is built. The pond's south
    bank (row 74) is open ground, so the bed can be reached.
- **A fix on the way:** the Oak's glade had touched F4's bridge-head at row 49 and was cut back. That
  gap had let the slime skip the webbed road.

Rendered in the game (`output/gloop-sketches/canopy-paths.png`). Not playtested.

## Phase 2, round 3 (2026-11-21)

- **Lily pads** to the Mere's islet (F3, row 5, from the beach at column 44 to the islet at 36):
  `game/world/water/sinking_lily_pad.gd` (the falling plank with the water-life sheet's round pad,
  bobbing on its idle loop; touched it dips with `WaterEnter` and sinks 300 ms later, back 10 s
  after) and `lily_pad_landing.gd` (the white-lily pad, a HazardDeck that never sinks). Two pads, a
  landing, two pads, a landing, one pad: a quick Roll crosses two pads to a landing; a walk sinks
  them. A water hazard lies over the lane, with return points on the beach and the islet. Scenes
  `game/scenes/objects/gloop/sinking-lily-pad.tscn` and `lily-pad-landing.tscn`.
- **Critters wrapped in silk** for Sunny ([WEBS.md](../godot/WEBS.md#critters-in-silk-2026-11-21)):
  the squirrel (E3's Web Glade), the hedgehog (F3's Clod clearing), the snail (F4's maze), the robin
  (E5's knoll glade) and the bluebird (F5's secret glade). They wriggle in their silk; the Silk
  skin's Spear frees each, it runs off toward the camp and from then on wanders the camp's yard by
  Sunny. All five: Sunny gives three berry baskets (`sunny.critters-prize`; a placeholder prize).
  Her basket talk now also tells of the five.
- **The Bow's secret, the ravine** (owner, 2026-11-21: a secret reached only by an arrow, with a
  falling bridge and a hole): east of the Mere's beach in F3, a ravine (`elevation` level -2, a void
  hazard over it whose abyss fades in under the far wall, `top_fade_px` 104) cuts off a glade with a
  chest (60 coins, an energy potion). The dungeon kit's drawbridge stands up on the glade's rim; a
  crystal lens on the glade, struck by an arrow from the bank across the ravine, lowers it for good
  (`gloop-ravine-lens`, `gloop-ravine-bridge`). The Bow comes in Chapter 3, so it is a come-back.
- **The Watch Oak moved up two rows** (owner, 2026-11-21: the picture's faded top showed over the
  glade): the builder first moved them up to F4 (960, 512); the owner then placed them by hand in
  the editor, the oak at (964, 265) and its root gate at (964, 271), its fade under the canopy wall.
  X6 moved west (above), so the path's
  fading treetops never uncover the trunk; the Silk Lurker over the Oak road hangs at (40.4, 46.6).
- **The silk nook's cave** (owner, 2026-11-21: the nook's heart quarter in a chest in a cave room
  reached by bombing a cracked ground in its clearing): F4's loose `silk-nook-heart` is gone; a
  cracked ground (`RiverRoads/silk-nook-crack`, (1726, 270), flag `cracked.gloop-silk-nook`) takes its
  place (its own scene since round 4, below), a Goo Bomb opens it, and its door `silk-nook-crack`
  leads down to `world.silk-nook-cave`
  (`game/scenes/worlds/rooms/gloop-forest-f4/silk-nook-cave.tscn`, made once from the Gloop Cavern's
  room by `tools/build_silk_nook_cave.gd`: 18 x 16 cells, no smaller than the game's 1024-unit view, the heart quarter `gloop-silk-nook` in the
  chest, spider silk dressing, a ladder back up). The door is in world-chunks.json and the room is
  on the world map. F4 was changed by a small text edit, after the owner had saved it.
- **The owner's hand edits are kept:** the owner reworked F4 in the editor (2026-11-21: a plateau
  and terrace painted on `elevation`, the forest repainted, Scenery and Animals, the Oak at (964, 265)).
  `build_gloop_river_roads.gd` now refuses to lay a chunk whose scene changed since it last wrote it
  (hashes in `godot/tools/gloop_river_roads_written.json`; `--force` overrides and loses the edits),
  so F4 is edited by hand from here on.
- `--chunk=ascii` prints the layout as text, a character a cell, to plan by.
- `render_glimmerhill.gd` has `--then-call=<node>:<method>` (a lens struck, a critter freed on film).

Rendered in the game (`output/gloop-sketches/round-3.png`). Not playtested.

## Phase 2, round 4 (2026-11-21)

- **The lookout tree** (F5, the lookout glade's south-west, region (36.9, 87.0)):
  `game/scenes/objects/gloop/lookout-tree.tscn` with `game/world/forest/lookout_tree.gd` and new art
  (Magnific GPT 2.5: a giant trunk with plank stairs winding up to a railed deck under the crown;
  the packer now clears the specks the generator scatters round a piece).
  - The interact key at the stairs' foot offers "Climb the lookout". A fade, and the slime stands on
    the deck (its body waits, hidden, at the foot).
  - The camera pulls back over the forest, never past the chunk's bounds, and every unopened chest
    in sight twinkles. Any key climbs back down.
  - The crown fades while the slime walks behind the trunk (`walk_through.gd`). F5's floor webs
    and their orb-weaver moved north of it.
- **The bell on the Mere's islet** (E3), as level-1 C5's lookout bell:
  - The `lash-bell-post` stands on the islet. Two clay pots lie in a notch of shore off the weavers'
    road below it.
  - A thrown pot (about 200 px across the water) or an arrow rings it. Then a hidden chest rises in
    the notch (`mere-bell-chest`, 40 coins and a health potion).
  - The builder marks the bell, pots and chest editable, so the editor keeps their settings.
- **The silk nook's crack, fixed:** its flag and door were settings on nodes inside the
  cracked-ground scene. Without an `[editable path]` line, the editor's save-on-run dropped them, so
  the hole led nowhere. The crack now has a scene of its own,
  `game/scenes/objects/gloop/silk-nook-crack.tscn`, which holds them.

## Phase 2, not built yet

- Dressing: the chunks have no painted props yet.
