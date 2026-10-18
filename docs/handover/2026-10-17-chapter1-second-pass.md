# Handover: Chapter 1's maps, second pass (2026-10-17)

Stopped early (the owner's credits). **No chunk scene was changed**: `level-1-c4/d4/c5/d5.tscn` are
as committed in `48a7b514` (a copy is in the session scratchpad `chapter1b/backup/`). Nothing to
reload in the editor for this work. No commits.

## The owner's asks (2026-10-17, with his annotated map)

> "i want to make some adjustments to chapter 1, [in] red i want a level 1 cliff with stairs on north
> and south, [it] is fence[d] with [a] few spots to jump down, the border[s] colliding with the river
> and lake are fence. in blue you see the river that is move[d] east so crossing the river move[s] to
> [the] other chunk[,] a technique use[d] in zelda with chunk delimiters. also the lake now is bigger
> and ha[s] more things to do, with [the] small blue square is mark[ed] a new island and [in] yellow a
> falling bridge that connect[s it] with the land, in there put some enemies and a cracked wall to be
> open[ed] with a bomb, inside make a new cave room with some coffers [chests] and pot[s] to throw, we
> will place a secret there later ok, also put more thing[s] on the lake."

On D5's cave pocket: "the heart can't be visible here, in zelda only a few hearts are visible the
majority are hidden and in coffers what give more excitement at discovery time. we can't be that
obvious, player have to find things by be curious and some player will miss secrets".

Corrections (relayed by the coordinator):
1. The island's falling bridge is long and **crossed only by continuous rolling** (no
   `object.plank-landing` on it): a come-back secret; its card must name the lock.
2. "what happened to the river edge? it should show normally": the river's banks must show the normal
   water edge tiles everywhere, at chunk borders too, on both sides of the C4/D4 border; check today's
   edges as well.

## Done (in the repo, not yet tested)

- `godot/game/world/terrain_edges/terrain_edges.gd`: corners on the map's border are now drawn, with
  the cells past the border taken as the border cells carried on (`_inside`, `_same_level` takes the
  four cells). Before, every ground boundary that met a chunk border ended in a straight cut half a
  cell short of it (the "bare cut" the owner saw where the river meets C4/C5). `--check-only` clean.
  Doc updated: `docs/godot/TERRAIN_LAB.md` "How it works" step 3. **Run `test_terrain_edges`** (its
  header still says "the map border get nothing"; its patches lie inside the map, so counts should
  hold, but check) and look at a render of level-1's borders.
- For this to look right the two sides of every chunk border must have the same ground in their
  border cells. Today they differ in places (`scratchpad/chapter1b/work/borders.gd` prints them):
  C4 row 31 vs C5 row 0 (the old river: water at C4 cols 25-26, C5 cols 23-25), C5 col 31 vs D5 col 0
  (the pond at rows 12-16), D4 row 31 vs D5 row 0 (under trees, minor). The draft builder below copies
  one side onto the other.

## Draft, not applied: the builder's new C4/C5 and the cave rooms

`docs/handover/2026-10-17-chapter1-second-pass-builder-draft.gd.txt` holds the new sections for
`godot/tools/build_slimeshire_chunks.gd` (they replace its `# --- C4` and `# --- C5` sections; written,
never compiled or run). To finish:

1. Paste it over lines 478-591 of the builder (the old `_c4`/`_c5`), and add the constants it uses:
   `const STAIRS_NORTH := Vector2i(4, 1)` (elevation_tileset "stairs-n"), `const FENCE_WOOD :=
   Vector2i(1, 0)`, `const FENCE_TILESET := "res://game/world/elevation/fences/fence_tileset.tres"`,
   `const FENCE_LAYER := "res://game/world/elevation/fences/fence_layer.gd"`; `CLIFF_TILESET`,
   `CLIFF_LAYER`, `RED_ROCK`, `DECALS`, `ROCK_DECAL` exist already.
2. In `_initialize`: build order `["d5", "c5", "d4", "c4"]` (C5 copies D5's col 0, C4 copies C5's row
   0), then `_caves()`. Fix `_chunk_ground` cleanup (the draft's one-liner freeing the world is clumsy:
   keep the instantiated world and `free()` it).
3. `_d4()`: the river on D4 cols 0-1 (deep water rows 0-26, col 0 row 27; sand col 2 rows 0-27, the
   road row 9 forest floor; cols 0-1 rows 28-30 sand; (0,31) forest floor, (1,31) moss, D4 row 31 =
   D5 row 0); clear the ForestLayer at x -2..2 rows -2..30; remove `Nature/level-1-tree-035`, `-037`;
   move `old-camp-banner` to (3.6, 15.0) and the crates to (4.6, 15.9), (4.4, 16.8); the bridge's
   east half: `_river_bridge(Vector2(0, 9 * 64))` (the deck's middle on the border; its cells are D4
   cols 0-1, C4 cols 30-31, so the river must be exactly those four cells at row 9).
4. `_d5()`: the pocket closes (drop the `D5_POCKET` fills and level 1; maples at (15,5), (17,4),
   (16,7)); remove `Encounters/level-1-goo-heart-meadow-autumn-thicket` from D5 (it moves into the
   hill's cave); the crack becomes a door: `passage` Rect2(-32, -124, 64, 124), `passage_level` 1,
   `door_id` "hollow-hill-cave-mouth", `target_area_id` "hollow-hill-cave", `target_door_id`
   "hollow-hill-cave-door", `door_side` "north" (cracked_wall.gd "Door (once blown)"); the decals'
   `avoid` pocket rect goes.
5. Add `"world.lake-island-cave"` and `"world.hollow-hill-cave"` to `godot/game/scenes/scene_index.json`.
6. Run the builder, bake `level-1-c4, level-1-c5, level-1-d4, level-1-d5, lake-island-cave,
   hollow-hill-cave` (`tools/bake_elevation.gd -- --world=...`), render (below), iterate.
7. `godot/game/prologue/town_edge_meeting.gd`: Plop is put on the plateau (level 1) for the meeting
   and NPCs never use stairs, so he cannot walk home: in `_finish`, fade him out, put him back at the
   place he stood before `_meet` (store it), fade in. Update `docs/godot/PROLOGUE.md`.
8. The kit (wait for the coordinator's interface message): the planks on `C5_PLANKS` (cols 10-15,
   rows 5-6, 12 planks, `east_west` true, **no landing**) with a water hazard over the lane and
   Return markers at (9.4, 6.0) and (16.6, 6.0); the hearts into chests (`goo_heart_id`): D4's pen
   (`meadow-lakeside`, at the pen heart's spot (18.5, 4.9)), D4's plateau (`meadow-cliff-secret`, at
   (29.2, 22.6)), the hill cave (`meadow-autumn-thicket`, replacing the interim goo-heart node and its
   KitMarker). The draft leaves KitMarkers for each.
9. Tests, one file at a time with the lock: test_terrain_edges, test_water (C5's water tile and
   water-life counts change), test_enemy_ranged (its `OPEN` ground (528, 1640) in C5 becomes lake:
   suggested new home D4's old camp clearing, `MAP_ID` "level-1-d4", OPEN about (480, 1408) chunk
   units; check it is clear), test_world_puzzles, test_ceremony, test_camp, test_chapter_one_flow,
   test_quests, test_prologue (Plop), test_interaction, test_world_objects, test_fattys_lair; grep
   `godot/tests/` for C4/C5/D4 positions.
10. Docs: Chapter 1's "Slimeshire's places" (cards, secrets, checklist), DUNGEONS.md "Outside: Fatty's
    Hollow" (no pocket; the crack's cave), `docs/story/03-world.md` (text outside the generated
    block), WORLD_ATLAS's chunk notes, the builder's header, `docs/godot/specs/abilities.md` §14 (the
    hearts' places). World-map changes go to the coordinator (below).

## The layout (cells, chunk-local; C4 origin (0, 0), D4 x + 2048, C5 y + 2048)

**C4.** Plateau top (level 1): rows 18-26 cols 0-29, row 27 cols 0-28, rows 28-29 cols 0-26; its
south face is the wall in row 30, foot row 31 (inside C4). North stairs: a back flight at (10-11, 17)
where the plaza's road comes down (the lantern posts at (9.6/13.1, 18.5) flank its top). South
stairs: a front flight at (18-19, 30), road on the top (18-19, 27-29). The town's old south fence
nodes (`reinforced-fence*`, `palisade-gap*` at y 17.9) go: the plateau's back rim and its wood fence
are the town's edge. Wood fence on every rim cell but three jump-down gaps: (6-7, 18) into Lili's
yard by the woodpile (a shortcut from the forest path into the village), (23-24, 18) behind the forge
(camp to smithy), (23-24, 29) down to the river road past the stairs. River: cols 30-31 rows 0-26
(D4 cols 0-1), turning south-west: row 27 cols 29-31, rows 28-31 cols 27-30, col 31 sand rows 28-30,
(31, 31) forest floor; the old river (cols 27-28) and its banks become town ground (col 29 the new
sand bank, the road row 9 to the bridge). The old east bridge (by the starter camp) goes; the town
road's bridge spans the border at row 9 (half in each chunk, the scroll mid-bridge). The bell pond
moves to (7-9, 26-28), islet (8, 27) (its old place lies under the rim); watch post unchanged. The
arrival from the prologue (96, 1696) and Plop's spot (140, 1604) are on the top (the slime takes the
level where it appears). The river's top: North Wilds' C3 has water at cols 30-31 of its last rows and
D3 a lake along its bottom, so the river comes from the north (C4's level-3 cliff above the map
covers only cols 0-26).

**C5.** Lake: cols 0-15 rows 0-28 (sand row 29), the blossom island and the west islet kept. Island:
(2-9, 1-7), its rock (level 2) top (3-6, 1-2), wall rows 3-4, the crack at its foot (5.0, 5.0) into
`lake-island-cave`; worms: two swordsmen (wander (2.2-9.8, 5-7.8)) and an archer east of the rock.
Falling planks (10-15, 5-6) to the land by the south stairs: six cells, longer than any single Roll
(about 185 units), so only the held Roll crosses (the lock: the Roll held across; Beat 2's Roll,
come-back). River from C4 south-west: water per row 0..8 = (27-30), (27-30), (26-29: the road
bridge's row, exactly the deck's four cells, bridge middle x 28), (25-29), (23-28), (21-27), (19-25),
(16-23), (16-21). Road: stairs' foot (18-19, 0) east along rows 1-2 to the bridge, then down the east
bank (30, 2-3), (29-30, 4-7) to the lake road (rows 8-9, on into D5) and the camp path. Lake things:
an islet (3-6, 21-24) with a chest (15 coins, an energy potion) and pots, reached by a shallow ford
(5, 25-28) from the south shore; a fishing jetty (a footbridge, deck cols 12-15 row 20) with a crate;
shallows (10-13, 15-18) with a dark square (11-12, 16-17) and a glint over it (the Swim skin's secret,
later; a KitMarker); lily pads, reeds, fish, rocks (34 water-life nodes). Lookout rock unchanged; its
hidden chest moves to (20.3, 24.9), pots to (17.2, 25.7), (18.7, 26.3). C5 col 31 copies D5 col 0;
C5 row 0 is C4's row 31.

**Caves** (new worlds, 16 x 13 cells: rock at level 2, one room (1-14, 2-10) at level 0, a gap (7-8,
11-12) to a south door "opening" at (512, 808)): `lake-island-cave` (cave rock; chests 30 coins and
10 coins + a tonic, five pots, the KitMarker `cave-secret-spot` for the secret placed later) and
`hollow-hill-cave` (red rock; the grove's goo heart, a chest once the kit lands; pots). The doors are
the current `door.gd` "opening" pieces and the cracked walls' "Door (once blown)" exports: switch
them when the door rework lands.

## World-map changes for the coordinator (not applied; map x = 32 + level-1 x / 128, y = 48 + level-1 y / 128)

- New interiors for `slimeshire-meadow`: `lake-island-cave`, `hollow-hill-cave`.
- Island and its crack (C5 (5, 5) = level-1 (320, 2368)): map (34.5, 66.5). Island cave entrance.
- Town road bridge on the border (level-1 (2048, 608)): map (48, 52.75).
- North stairs (level-1 (704, 1120)): map (37.5, 56.75); south stairs (level-1 (1216, 1952)): map
  (41.5, 63.25).
- Moved: the first bell (C4 (8.5, 27.85) = level-1 (544, 1782)): map (36.25, 61.9); the lookout
  chest (C5 (20.3, 24.9) = level-1 (1299, 3642)): map (42.15, 76.45).
- New: the lake islet chest (C5 (4.9, 21.9) = level-1 (314, 3450)): map (34.45, 74.95); the dark
  square (C5 (12, 17) = (768, 3136)): map (38, 72.5); the jetty (C5 (14, 20.5)): map (39, 74.25).
- Removed: D5's cave pocket heart marker; the old C4 east bridge.

## Decisions taken (owner's marks were loose)

- The plateau's top starts at row 18, right under the town's old fence line; that fence goes.
- The river bends inside C4/C5 before the four-chunk corner so D5 stays untouched and every border
  cell matches its neighbour (the corner cells are forest floor in all four chunks).
- Jump-down gaps: two north, one south (above); the rims over the river and the lake are all fence.
- The main road crosses the new river in C5 row 2 on an east-west footbridge (the only bridge art is
  east-west, so the river runs north-south for its first rows).
- `test_enemy_ranged`'s open ground moves to D4 (C5's south meadow becomes lake, as drawn).

## Pictures

Before renders (whole chunks at 1/2): session scratchpad `chapter1b/before/level-1-*.png`, with grids
in `chapter1b/work/grid-*.png`; the border crop showing the cut: `chapter1b/work/border-river.png`.
Render a chunk: `"<console exe>" --path godot -s res://tools/render_weaver_hollow.gd --
--out=<dir> --scene=res://game/scenes/worlds/chunks/level-1-c4.tscn --zoom=0.5`.
