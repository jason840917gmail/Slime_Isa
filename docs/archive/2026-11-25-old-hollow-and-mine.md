# The Weaver Hollow on four floors and the Crystal Mine as one world (2026-10-17 to 2026-11-25)

Retired at step 5 of [the dungeons rework](../design/2026-11-23-dungeons-2-3-rework.md) on
2026-11-25, once both dungeons were rebuilt one world per room and the game entered the rebuilt
ones ("step 5 this is the way to go so get rid of the old", the owner). These are the sections of
[DUNGEONS.md](../godot/DUNGEONS.md) that described the worlds before, kept for the decisions they
explain: the Pearl inside the dungeon, the main paths both rebuilds follow, the Colossus's first
fight. They describe files that are gone: the four floor worlds `weaver-hollow-trunk`, `-roots`,
`-boughs`, `-crown` with their room copies `rooms/weaver-hollow-{trunk,roots,boughs,crown}/`, the
one-scene `crystal-mine` with its copies `rooms/crystal-mine/`, their elevation caches, their
builders (`tools/build_weaver_hollow.gd` with `tools/weaver_hollow/`, `tools/build_crystal_mine.gd`,
the room splitter `tools/lib/dungeon_room_splitter.gd` and `tools/split_dungeon_rooms.gd`), their
render and film tools (`render_weaver_hollow.gd`, `film_weaver_hollow.gd`, `render_matron.gd`,
`render_dungeon_room_views.gd`), the doorway frames they drew (`game/dungeon/doorway_art.gd`),
`room_arenas.gd`, `latched_hatch.gd` and the cocoon fight's copied encounter
`weaver-hollow-matron-old.tscn`. All of them are in commit `09d5ebae`. A save standing in one of the
retired worlds wakes in the rebuilt dungeon's entrance (RunState `RETIRED_WORLDS`). Links into
DUNGEONS.md below may point at sections since cut.

## The Crystal Mine as one world (2026-10-17 to 2026-11-25)

Chapter 3's dungeon, built 2026-10-17 from [its design](../design/2026-10-16-dungeon-crystal-caverns.md)
and reworked the same day for the Pearl inside it, before the Colossus
([the plan](../design/2026-10-17-pearl-mid-dungeon.md#the-crystal-mine-chapter-3-the-feral-skin); as
built, below; the design's [status](../design/2026-10-16-dungeon-crystal-caverns.md) lists what moved).
One world, `world.crystal-mine` (`game/scenes/worlds/crystal-mine.tscn`), 80 x 70 tiles: a 5 x 5 grid
of screens, 14 camera rooms, 7 of them dark. **Built by a tool:**
`"<Godot console exe>" --headless --path godot -s res://tools/build_crystal_mine.gd [-- --dry]`
rebuilds the whole world (hand edits are lost), then bake its elevation
(`tools/bake_elevation.gd -- --world=crystal-mine`). Its code is `godot/game/crystal_mine/` and the
Colossus's `game/scripts/crystal_colossus.gd`; its art `scripts/art/pack-mine-art.py` (sources and
prompts in `asset/Originals/mine/`). Tests: `godot/tests/test_crystal_mine.gd` and
`test_mine_camp.gd`. *As built (2026-11-22): the game plays this one scene. Its root carries the
room shell's script (`room_scene_shell.gd`) but holds no `RoomScenes`, and no door, no
`scene_index.json` entry and no script loads the 14 `rooms/crystal-mine/M*.tscn` files: they are
leftovers of the 2026-10-17 split, and an edit to them does not reach the game (F6 on one opens
`crystal-mine` at that room). A run of the builder splits the world into them again
(`tools/lib/dungeon_room_splitter.gd`).* *Since 2026-11-25 the Mine is rebuilt as room worlds
([The Crystal Mine rebuilt](../godot/DUNGEONS.md#the-crystal-mine-rebuilt-wing-1-the-mouth-and-the-high-line-step-4-2026-11-25))
and the game enters those ([the switch-over](../godot/DUNGEONS.md#the-switch-over-the-mine-2026-11-25)): this scene stays
on disk and in `scene_index.json`, unreached, until step 5; a save standing in it loads into the
rebuilt M1.*

**Its shape** (the plan's dungeon template): the first half uses what the slime brings and is the
Lantern's (six dark rooms, the maze), the Heavy Roll's and the Bow's (the Chasm, its last lock); the
Shardback guards **Pearl 3** in his Den; its take seals the mine; the second half teaches the
**Feral skin** (teach, test, twist, then the known way down); the Colossus is its exam. About 40
minutes with the camp, 13 rooms on the main path.

- **The paint:** every cell is rock at level 2 (its top crystal floor, so its walls are crystal rock
  and it never reads as a room's floor; masonry and cobble round the old fort's hall); each room is
  carved out to level 0 with cavern floor and a one-cell rock border, the Den to level -1; doorways
  are two-cell gaps (an east or west one also clears the two rows its lintel hangs over). Holes: M2's
  two void pits (-2), the Dark Maze's void (-2), the Chasm (-3), the Great Shaft's floor with the
  boss door's way (-2), M11's rift (-2) and the Colossus's arena (-2). Raised: the S5 shelf in M1
  (1), the maze's inner walls (1), the shaft's spire (0), the Den's ledge (0, one level over its
  floor), M12's balcony (2) with the hall's north band and corner blocks at 3 (so the balcony never
  joins the mine's rock top). A front flight of stairs (the `elevation` layer's stairs row) leads from
  the Chasm's far rim down into the Den. The gallery's rim is fenced (`fences` layer) but for the
  spire plank's foot.
- **Kit pieces used:** the Dungeon (`crystal-mine`, "The Crystal Mine", resume at
  `dungeon-entrance` in M1; the seal's `boss_id` `crystal-colossus`, `boss_name` "The Crystal
  Colossus", `seal_color` smoky violet `#8a68c0`, his roar `fatty-roar.ogg` at pitch 0.6, crystal dust
  `#c8d4f0`), a floor key (K1), six chests (K2, the map, S1, S4, S5, M10's) and the big chest (on
  M12's balcony), the Foreman's Gate (`key-door`, two keyholes), the boss door, four shutters (M1's
  iron shutter `starts_shut`, the Den's north fight shutter, its two south rim shutters
  `starts_shut`), two seals (`object.dungeon-seal`: M1's mouth, `glimpse`; the climb-out's foot), the
  Den's room fight (`once`, `boss_id` `crystal-mine-shardback`), the crank (`winch` in M7, M1's
  shutter), two drawbridges (the Chasm's, the spire plank), four void hazards (`draw_look` off,
  `Return...` points), the shadow path, six pots that grow back, an energy flower and five prize
  glints (Pearl 3's goes once it is taken: `crystal_mine.gd`). `KitMarkers` keeps a marker for what
  nothing builds yet: S5's war journal page and S1's heart quarter (S1 and S5 hold coins until then;
  S1's also holds one of the potion belt's slots since 2026-11-20, crafting spec 12.4). M10's chest
  holds the war journal's third page since 2026-11-20 (its marker went;
  [quests spec 14.8](../godot/specs/quests.md#148-finds-the-war-journal-the-recipe-page-and-the-charged-roll-2026-11-20)).

### The rooms

Screens by column (0 to 4, west to east) and row (0 to 4, north to south); the main path in order.

| Room | Screen | What is there |
|---|---|---|
| M1 Mine Mouth | (1, 4) | the entrance from the camp (south doorway; **the seal** stands in it from Pearl 3's take until the Colossus falls, and the take's glimpse shows it slam up), the resume marker, the empty cart station ("The cart is at the far end of the line."), the iron shutter in the east wall (lifted by M7's crank), the root wall up to the S5 shelf (Feral, a come-back after the Pearl) and its chest, pots |
| M2 Lamp Tunnel | (1, 3), dark 1 | rails north, two void pits west of them (a fall: back at the south door), three sconces (60 s) that light it for good, a pot that grows back |
| M5 Tally Room | (0, 3), dark 2 | west of M2: the desk, four crystal pillars, a Gloomling on K1 (a floor key); the cracked wall in its north wall (the Goo Bomb, S2) opens the way to M3 |
| M3 Survey Office | (0, 2), lit | optional: the map chest on the surveyor's table, a Crystal Crawler round its pillar |
| M4 The Great Shaft | (1-2, 2), lit | the hub: the gallery (two braziers burning for good) round the shaft (-2), the ore lift's two landings, the spire with its lens (the Bow) and the S1 chest; north the Foreman's Gate (two keyholes); the shaft's north wall: the roots down from the Den's broken rim (seen from the gallery on the first visit); M14, the shaft floor: pots (two hearts), an energy flower, the boss door east |
| M6 Bat Gallery | (2-3, 3), dark 3 | three Glint Bats over the rails, two sconces, the rotten timbers in the south-east doorway (a Heavy Roll), the S3 nook in the east wall behind a web wall (the Silk skin) with a silk parcel |
| M7 Ore Store | (2-3, 4), lit | east half: the Pick Mole behind its crates, K2 in the chest behind it; west half, past the divider: the Bone Leaper alone, and the crank that lifts M1's shutter |
| M8 The Dark Maze | (0-1, 0-1), dark 4 | four corner candles (60 s, group `dark-maze`): all four at once open the exit gate (the mine's lantern gate) for good; the goal brazier burning beyond it; the void across the middle with the shadow path over it; two Gloomlings (one smothering the north-west candle, one on S4's chest), three Glint Bats, a pot |
| M9 The Chasm | (2, 0), dim | the first half's last lock: the cart station (the cart starts here), the chasm (-3) with the raised drawbridge on the far rim and the lens beside it (an arrow lowers it, rows 8 and 9), the Bone Thrower on the far ledge, crystal vein glows; the far rim's way on is the stair down into the Den (x 44, 45); its old door east to M10 is bricked |
| M13 Shardback's Den | (2, 1), dark 6, level -1 | **the Pearl room.** The Shardback (two braziers, 20 s, `stomp_puts_out`: fire light makes his shell brittle); the room fight (`once`, `boss_id` `crystal-mine-shardback`) shuts the north shutter at the stair's foot; won, it opens and the two shutters of the broken south rim sink for good. Pearl 3 (`pearl-three.tscn`, `boss_id` the Shardback's) on its crystal cradle among four crystal clusters, its glint seen from the stair through the fight: it rises when he falls. **Teach:** the ledge (level 0) in the north-east holds the east door; its root wall (one level) is the Feral skin's first lock, a climb back down beside it |
| M11 Crystal Veil | (3, 1), dark 5 | **Test:** the rift (-2) between the west landing (the Den's door) and the east landing (M12's door): climb down the west landing's face, cross the rift's floor, climb up the east landing's (each face two levels, each with a climb down from its lip); a pot. The optional Lantern wing: the veil across the mouth of the doorway north to M10, its brazier on the east landing (20 s) and one on M10's side, two Glint Bats roosting over it |
| M10 Prism Gallery | (3, 0), lit | optional (the Lantern wing): the Prism Eye, the iron-banded ore crate (a heavy block), the chest of the war journal page that lay on M12's stand (its third page since 2026-11-20; 30 coins before), the veil's far brazier |
| M12 The Fort Hall | (4, 1), lit | **Twist:** cobble and masonry; the balcony (level 2) along the north wall with the big chest (the big key), two root walls up its face (x 68 and 75); the Watcher Eye's beam finds a climber, the Bone Marcher's loop passes the walls' feet; five armour statues (heavy blocks, cover, three cells or more from the roots), two watch-fires; a drop off the balcony's west end lands by the west door |
| M15 The Colossus's Arena | (3, 2), dark | **the exam:** four braziers (until put out), the Colossus, four root walls on the north wall beside his three climb spots (they end on the face, `holds_at_top`), the climb out to the Lookout (its seal at its foot until he falls), his full heart |

**The second half's way:** from the Den up its ledge, through M11 (down, across, up), M12's balcony
and the big key, back through M11 and the Den, then down the roots of the shaft's north wall from
the Den's broken rim to the shaft floor (or let go: no cost), the boss door. The roots are also the
short way up from the shaft floor to the Den. **The way back after a resume** (the mouth sealed
behind): M1, the cart to the Chasm (it runs both ways, both stations inside the seal), the stair to
the Den; or M1, M2, the hub, the lift (once raised from the floor), the shaft floor and the boss door.
Nothing before the Chasm needs the Bow; a slime without it rides the cart to M1, walks out, and comes
back with it (all before the Pearl). The big key cannot be had without the Pearl: M11 and M12 are
reached only up the Den's ledge.

### The Colossus's first fight

His fight in the one-scene Mine (crystal_colossus.gd with `plate_fight` off: the code is still there,
placed nowhere since the world was retired; the rebuilt Mine's M15 and his lab play the plate fight,
[DUNGEONS.md](../godot/DUNGEONS.md#the-plate-fight-step-2-of-the-rework)). What differs from the plate
fight:

- **On the floor, the Lantern's exam (as built):** the braziers (candle.gd, `burn_ms` -1: they burn
  until put out, `stomp_puts_out`): while all four burn his weak spot is open (`set_exposed`): a plate
  of his armour cracks open on a side picked at random (front, back, left or right), glowing; he
  reels for `reelMs` (1800) when it opens. Every hit clinks off his crystal except the Spear's (tag
  `spear`) on the open weak spot from its side (the hit's source within `weakSideDot` 0.45 of that
  side's direction). **His stomp** (the tell: a foot raised for `raiseMs` 650 over a darkening ring
  `stompRx` x `stompRy` 116 x 78; within `stompRangePx` 120 of the slime or every `stompEveryMs`
  2600): 40 damage in the ring, and it puts out the lit `stomp_puts_out` brazier nearest to him
  (`stompPutsOut` 1; `CandleScript.put_out_near` nearest only), so the weak spot shuts.
- **On the wall, the Feral skin's exam (2026-10-17):** after `stompsPerClimb` (3) stomps he leaps
  onto the north wall at the climb spot nearest the slime (`climb_spots`: x 51.5, 54.5, 57.5) and
  clings for `climbMs` (5200), throwing a Crystal Mite down every `throwEveryMs` (1300;
  `mitesPerClimb` 2, at most `maxMites` 4 alive; at a climbing slime the mite drops straight down the
  face onto it, `climberHitPx` 30, and its hit knocks the slime off: no cost but the hit). Roots run
  up the wall beside each spot (x 50, 53, 56, 59). The slime climbs them to his height and strikes
  his gripping claws with the Spear from the face (the strike while clinging: an attack press aims
  the Spear left or right along the face, player.gd `_climb_strike`, at the Feral tempo); while he
  clings his hurtbox rides up the face with his pose and only a Spear hit from a climbing slime
  counts (no damage). **`clawHits` (3)** and he loses his grip: he crashes down `fallDropPx` (70) from
  the wall over `fallMs` (450) with no landing stomp (no brazier goes out), a hard shake, and lies
  stunned **`fallStunMs` (2500)**, sprawled, his back cracked open: any Spear hit lands, from any
  side. Then he gets up and fights on. If the slime does not reach him, he leaps down at it as built
  (kept on his floor: a landing ring, `landPutsOut` 1 brazier).

### Dev

- **F6** on `crystal-mine.tscn` lends `dungeon.devPowers.crystal-mine` (the Spear, the Roll, the
  Heavy and Silk skins, the Goo Bomb, the Lantern): the first half. The Feral skin is won in the Den.
- **The second half without playing the first** (today's one-scene world, still opened on request
  until step 5; in the rebuilt Mine `?map=crystal-mine-m14-shaft-floor&sealed`, any room, does the
  same: [the switch-over](../godot/DUNGEONS.md#the-switch-over-the-mine-2026-11-25)): `?map=crystal-mine&sealed` (desktop
  `-- --map=crystal-mine --sealed`) takes Pearl 3 quietly (the Shardback's fight finished, Feral won)
  and seals the mine; add `&room=M11-crystal-veil` (any camera room's name) to start there. To lend
  Feral alone (unsealed): `?skins=feral` (`-- --skins=feral`, also in the editor's Main Run Args for
  F6).

### The mine's limits

- The **Bow** is built (2026-11-20, [BODY_SHAPES.md](../godot/BODY_SHAPES.md#the-bow-2026-11-20)): the two
  lenses take its arrow's hook (`on_arrow_hit`) and nothing else strikes them, so the Chasm is
  crossed with it (it is in the Mine's F6 powers). In the story Pip carves its rune in Slimeshire
  once the Matron's Pearl is home (its homecoming raises his Workshop) and the slime brings him 5
  wood, the Matron's thread and the smith's crystal; the mine cart is the Bow-less slime's quick way
  out to him and back in. Not playtested.
- **Heart quarters** and S5's **war journal page** are not built: S1 and S5 hold coins until then
  (their `KitMarkers` say what goes there; M10's chest holds the journal's third page since
  2026-11-20). S1's chest also holds a belt slot
  (2026-11-20, [crafting spec 12.4](../godot/specs/crafting.md#124-the-potion-belt-step-b3-2026-11-20)).
  *As built (2026-11-22): heart quarters exist since 2026-10-26 (a chest holds one through its
  `goo_heart_id`), but S1's chest has none: 50 coins and the belt slot. *Since 2026-11-23 (owner) it gets none: no heart quarter inside a dungeon; the Caverns' four lie outside.* The war journal has its
  three pages, none in S5 (quests spec 14.8), whose chest holds 40 coins and an energy potion; its
  marker still asks for a page.*
- The spire plank (S1) lands across the spire's own wall face; its walk across is untested.
- The strike while clinging runs in the body-shapes mode only (the shapes strike there); in the
  classic game an attack press on a wall does nothing.
- Tests: `test_crystal_mine.gd` (20) and `test_mine_camp.gd` (6), all passing on 2026-10-17 (run one
  file at a time with `pnpm test:godot -- --filter=<file>`). Since 2026-11-21 `test_mine_camp.gd`
  holds 9 for the Spiral (the yard's gate and cart end, the first talk's Lantern and crystal, the lamp
  freeing the one-way cart, the gate, the mine's way in and out, the seal, the later talks, the Bow
  first, his stay after the Colossus): all passing on 2026-11-21. The seal test closes Release 1's
  end card, which opens over the game (and pauses it) when the Colossus is marked beaten. The strike while clinging is tested in
  the body-shapes mode turned on for the test (`test_the_spear_strikes_his_claws_from_the_face`).

## The Weaver Hollow on four floors (2026-10-17 to 2026-11-25)

**No longer entered since [the switch-over](../godot/DUNGEONS.md#the-switch-over-2026-11-25) (2026-11-25):** the game plays
the Hollow rebuilt one world per room ([below](../godot/DUNGEONS.md#the-weaver-hollow-rebuilt-the-trunk-and-the-roots-step-3-2026-11-25)).
The four worlds this section describes stay on disk and in `scene_index.json`, unreached, until step 5
of the rework retires them with their tests; their Crown keeps its cocoon fight through a copy of the
encounter (`weaver-hollow-matron-old.tscn`).

Chapter 2's dungeon, built 2026-10-17 from [its design](../design/2026-10-16-dungeon-weaver-hollow.md)
(its status lists what moved in the build): the Thorn Guard's old watch fort inside the Watch Oak,
climbed from its roots to the Matron's web at its top. Four worlds are one dungeon (`weaver-hollow`,
"Weaver Hollow"); its forecourt is the open world's `gloop-forest-f4`. **Reworked the same day for
the Pearl inside the dungeon** ([the plan](../design/2026-10-17-pearl-mid-dungeon.md#the-weaver-hollow-chapter-2-the-silk-skin),
the owner's decision of 2026-10-17): the first half is the Goo Bomb's, up to the Brood Warden, who
guards Pearl 2 in the Hoard; its take grants the Silk skin and seals the way out; the second half
teaches the Silk skin (the Hoard's stair, C1, the new C4 the Spinning Loft), and the Matron's fight
is its exam.

| World | Floor | Camera rooms |
|---|---|---|
| `weaver-hollow-trunk` | the ground floor, the entrance | T1 Root Door, T2 the Hollow Heart (the hub, 2 x 2, its gallery along the north), T3 the Larder, T4 the Well Room (the map nook T3a sealed in its west), S3's nook |
| `weaver-hollow-roots` | below ground | R1 Root Fall, R2 the Bone Cellar (2 x 1), R3 the Drop Gate, D1 the Old Cellar (dark) |
| `weaver-hollow-boughs` | the upper floor | B1 the Bough Stair, B2 the Drawbridge (2 x 1), B3 the Mimic's Pantry, B4 the Nursery, B5 the Warden's Den, the Hoard (the Pearl room), B6 the Pillar, D2 the Dark Bough (dark) |
| `weaver-hollow-crown` | the top | C1 the Crown Stair, C2 the Crown (the Matron), C3 the Outer Bough, C4 the Spinning Loft |

**Built by a tool, not by hand.** `godot/tools/build_weaver_hollow.gd` writes the four scenes from
`godot/tools/weaver_hollow/hollow_floors.gd` (every room, door, object and enemy, by cell), with
`hollow_canvas.gd` (the painting) and `hollow_scene.gd` (the layers and nodes). Rebuilding
overwrites edits made in the editor: change `hollow_floors.gd`, build again
(`"<Godot console exe>" --headless --path godot -s res://tools/build_weaver_hollow.gd [-- --only=<floor>]`),
then bake (`tools/bake_elevation.gd -- --world=weaver-hollow-trunk,weaver-hollow-roots,weaver-hollow-boughs,weaver-hollow-crown`).
`tools/render_weaver_hollow.gd` renders the floors (`--rooms`, `--collision`, `--scene=<world>`) and
`tools/film_weaver_hollow.gd` films the main path in the game, shot by shot (`--only=<prefix>`;
`--only=check` walks over the lowered drawbridges and down the gallery's stair and prints where the
slime ends; `python scripts/maps/weaver-hollow-contact-sheet.py <film dir> <out.png>` lays the shots
out). Its
pieces: the webs ([WEBS.md](../godot/WEBS.md)), the bomb's cracked floor, cracked winch post and blast kegs
([BODY_SHAPES.md](../godot/BODY_SHAPES.md) "Goo Bomb") and the Matron ([specs/matron.md](../godot/specs/matron.md)
section 8). Tests: `godot/tests/test_weaver_hollow.gd`, `test_weaver_webs.gd`,
`test_weaver_bombs.gd`, `test_matron.gd`.

- **The paint:** each floor is a mass of rock at elevation level 2 (its top the oak's dark soil, its
  walls root rock on the `cliffs` layer) with the rooms carved out at level 0: every camera room
  (16 x 14 cells) keeps a one-cell rim of rock, so two rooms are parted by a two-cell band whose
  face is a wall of two courses. Doorways are two-cell gaps through the bands (an east or west one
  also clears the two rows its lintel hangs over). The hub's gallery is level 1 under two rows of
  rock (so the Crown Door's arch fits, as the kit's doors stand three rows down) and four rows deep
  (so the door shows from the top of the hub's floor), with a front flight of stairs at its east
  end; R1's ledge is level 1 with its own flight. The voids (B2, B6) are
  holes at level -2 floored with dark cavern stone. Rooms vary their floors (cobble, dry leaves,
  moss; C4 the interiors' wooden boards, `HollowCanvas.WOOD_FLOOR`, one tile) so they read apart from
  the rock's top. C1 has a one-row band of rock across it (row 21, its face over rows 22-23) whose
  one gap is the stair's straight way; the Hoard's stair is a well between two blocks of rock at the
  vault's south end. Floor webs are never painted under a wall's face (they would draw over it);
  `paint_webs(rect, 1)` webs a level-1 ledge (the gallery's west end).
- **Kit pieces used:** the Dungeon in each floor (resume at `dungeon-entrance` in T1; the other
  floors' `entrance_map_id` is the Trunk; the seal: `boss_id` `orb-weaver-matron`, `boss_name` "The
  Orb-Weaver Matron", `seal_color` violet `#9a5ad8`, `roar_sound` the spider hiss at 0.4,
  `dust_color` silk `#efe6d6`); two seals (`object.dungeon-seal`: `entrance-seal` in T1's south
  doorway, `wall` south, `glimpse`; `crown-east-seal` in C2's east doorway, `wall` east); three key
  doors of one keyhole (the hub's east door; the Warden's door in B2, `den-door`; C1's K3 door,
  `crown-k3-door`) and the boss door (the Crown Door on the gallery); dungeon chests for the map
  (T3a), small key 1 (R2's pocket), the Nursery's coins and potion (B4, `hidden`: the ambush's
  reward) and the dark rooms' prizes (D1, D2); the big chest with the big key (the Hoard); small key
  2 is the Cocoon Mimic's swallowed drop (`object.dungeon-key`, spat out when she is beaten), small
  key 3 lies in C4's silk parcel (its `contents` `dungeon-small-key`: freed, it drops as the kit's
  floor key); six shutters (the gallery stair's block, `starts_shut`, lowered by the gallery's winch;
  the Nursery's two; the Warden's; the Hoard's, `starts_shut`, the Warden fight's reward; the
  Crown's, shut and opened by the Matron's camp, `boss_engaged` / `boss_defeated`); two room fights
  (the Nursery, `once`; the Warden's Den, `boss_id` `weaver-hollow-brood-warden`, Pearl 2's guard);
  two drawbridges (B2's and B6's, each lowered by a cracked winch post's `trigger`); three void
  hazards (`draw_look` off); twelve pots that hide a refill and grow back (four on the gallery and
  four at C1's top, heart or energy; four in the den, random) and an energy flower (the gallery);
  prize glints in D1 and, for Pearl 2's glow, over its altar and at the Hoard's shutter in the den.
  Three small keys for three keyholes, so no key can be spent wrong. No falling slabs, no shadow
  path, no compass.
- **Pearl 2** (`object.pearl-two`, `boss_id` `weaver-hollow-brood-warden`, `take_radius` 90) on the
  brood's altar (`game/scenes/objects/weaver-hollow/brood-altar.tscn`: a mossy stone pillar bound in
  old silk, solid at its base) in the Hoard beside the big chest. It rises when the Warden's fight is
  won; its take grants the Silk skin and seals the Hollow (the kit's take, [The seal](../godot/DUNGEONS.md#the-seal));
  T1's seal is on another floor, so the take plays the roar and the line, no camera cut. Its glow
  (two pale violet `object.prize-glint`s under a StoryVariant on `pearl.orb-weaver-matron`) twinkles
  until it is taken.

### The main path

1. **The forecourt** (`gloop-forest-f4`): the Watch Oak's bricked root gate, a cracked wall: a bomb
   blows it, and the hole is a door into T1.
2. **T1 Root Door:** floor webs (a walk slows, a Roll sticks); S3's web wall east (the Silk skin,
   on a later visit).
3. **T2 the Hollow Heart:** the hub. The Crown Door is seen on the gallery from the floor; the
   hatch in the floor is latched from below; the east door is locked.
4. **T3 the Larder:** two orb-weavers; two cracked walls in its north face: the west one into the
   map nook (T3a, the map), the east one into T4.
5. **T4 the Well Room:** the cracked floor; blown, it drops the slime one way into the Roots.
6. **R1 Root Fall:** the slime lands on a ledge (`roots-landing`) above the first egg sac.
7. **R2 the Bone Cellar:** the Watcher Eye among stone pillars (cover from its beam and the bones),
   two Bone Throwers at their posts; a cracked face in a block of rock hides small key 1's pocket.
8. **R3 the Drop Gate:** Fatty's Lair's old Thorn Guard drop gate (`object.drop-gate`) in a band
   of rock: pull its worm lever and Roll the web-free row before it drops; the gate winch
   (`object.gate-winch`) beyond holds it up for good; the cave ladder climbs to the hub's hatch,
   which opens for good (the loop back).
9. **T2's east door** (key 1) leads to **B1 the Bough Stair** (a Silk Lurker; D2's doorway north).
10. **B2 the Drawbridge:** the void across the room; a bomb thrown over it breaks the cracked winch
    post on the far rim, and the bridge drops west across the gap.
11. **B3 the Mimic's Pantry:** the Cocoon Mimic swallowed small key 2; S2's parcels behind the
    alcove's web wall.
12. **The Warden's door** (key 2, one keyhole) opens **B5 the Warden's Den:** the Brood Warden (the
    first half's last test: a blast plants it), the den's shutter shut behind the slime; Pearl 2's
    glow twinkles at the Hoard's shutter through the fight. Beaten, the Hoard's shutter sinks:
    *since 2026-11-21* once nothing lives in the den (the Warden, the egg sac by the back wall and
    its Broodlings: the room fight's live rule; before, the fight named the Warden alone).
13. **The Hoard, the Pearl room:** the big chest with the big key and, on the brood's altar, Pearl 2,
    risen with the Warden's fall. **The take:** the Silk skin, worn; the Matron's roar from the
    Crown, silk dust, "The Orb-Weaver Matron roars! The way out slams shut."; the seals shut (T1's
    way out, C2's east doorway).
14. **The Hoard's stair** (the Silk skin's first lock, safe, right at the Pearl): a web wall across
    the well's mouth, passed at half speed or cut for good with the Spear. Down it, **T2's gallery**,
    the calm room (the pots, the flower; silk spills over its west end, seen from the hub's floor on
    the first visit); its winch lowers the block at the foot of the gallery's stair, the short way
    down to the hub's floor and the entrance after a faint.
15. **The Crown Door** (the big key) leads up to **C1 the Crown Stair** (the test): floor webs from
    wall to wall, which the Silk slime walks and Rolls at full speed; a band of rock across the stair
    whose one gap, the straight way up, a web wall chokes (wade it, or cut it for good and every climb
    after a faint is quick); at the top the K3 door and four pots, the calm spot before her. C1's
    south part leads east into **C4 the Spinning Loft** (the twist): two rows of web walls from wall
    to wall (seven each, `loft-web-<row>-<i>`, 104 tall) part the old store loft into three
    corridors; a Slime Spider in each corridor ahead lines up and shoots while the slime wades a row
    at half speed (its body shows above the silk, which fades while the slime stands behind it), or
    the Spear cuts a lane for good; small key 3 lies wrapped in a silk parcel at the north corridor's
    east end. Silk-hung rafters, a peg rail of silk hanks, a spool and a spinning wheel dress it.
16. **The K3 door** (key 3) opens **C2 the Crown:** the Matron (the boss shutter shut while she
    fights), enraged while sealed, the Silk skin's exam ([specs/matron.md](../godot/specs/matron.md) 8.2):
    round 1 as built (a blast on her shadow, then the Spear); round 2 a cage of web walls round her
    shadow (a thrown bomb stops in its silk and blows out of reach: cut in or wade in, then cast
    inside); round 3 her webbed floor and her brood (the Silk slime Rolls through). Her fall breaks
    the seals; her full heart and her thread.
17. **C3 the Outer Bough:** past the sunk seal, her web wall (pass or cut) and the drop back to the
    forecourt by S1.

**After a faint or a quit** (resumed at T1, inside the seal): T1, the hub, the stair block (once the
gallery's winch is turned), the gallery, the Crown Door, C1 (its web wall cut), the K3 door: four
rooms. Before the winch: T1, the hub, the east door, B1, B2, B5, the Hoard and its stair. S3 (T1's
web wall) and S2 (B3's parcels) open on any walk after the Pearl; S1 (the forecourt) after the seal
lifts, on the way out.

**Off the path:** B4 the Nursery and B6 the Pillar, an optional bomb wing (from B2's east doorway).
The Nursery's ambush (once: shutters close both doorways; three egg sacs in rings of webs and an
orb-weaver; won once nothing lives in the room, the Broodlings the sacs hatched too) brings a chest
with 30 coins and a health potion. B6 (from B4): a bomb on the first
blast keg sets off the line along the broken parapet, and the last breaks the pillar's cracked post:
its bridge drops across the void to the rim, and the far shore's Goo Heart is the heart quarter's stand-in. *Since 2026-11-23 no heart quarter belongs in a dungeon (owner): this Goo Heart (`weaver-hollow-pillar-heart`) is still placed and goes with the Hollow's rework ([the plan](../design/2026-11-23-dungeons-2-3-rework.md)).* D1 the Old Cellar and D2 the
Dark Bough are dark (the Lantern): D1's chest (its glint seen from the doorway) is for a page of the
war journal; D2's three candles, all lit, light the room for good and bring its chest, for the
Silkspun Stew recipe. D1's holds the war journal's second page since 2026-11-20 (40 coins before;
[quests spec 14.8](../godot/specs/quests.md#148-finds-the-war-journal-the-recipe-page-and-the-charged-roll-2026-11-20));
the stew recipe is not an item yet: D2 holds a health potion and 20 coins.
Secrets behind web walls (the Silk skin): S1 in the forecourt
(50 coins and an energy potion), S2 in the pantry (a health potion, an energy potion, 40 coins), S3
off T1 (30 coins).

### Doors between the floors

`door.gd` doors (a north door pairs with a south one, east with west):

- `trunk-entrance` (T1, south) and the forecourt's blown root gate (`weaver-hollow-root-gate`);
- `trunk-east-stair` (T2, east, behind the key door) and `boughs-from-trunk` (B1, west);
- `trunk-gallery-stair` (the gallery, north) and `boughs-hoard-stair` (the Hoard, south);
- `trunk-crown-door` (the gallery, north, behind the Crown Door) and `crown-from-trunk` (C1, south);
- `trunk-hatch` (T2's floor, a ladder down in a `LatchedHatch`: a south door, pushed down onto) and
  `roots-ladder` (R3's cave ladder, a north door);
- one way: the Well Room's blown floor (`trunk-well-floor`, a fall) to the marker `roots-landing`
  in R1, and `crown-bough-drop` (C3, a fall) to the marker `weaver-hollow-silk-drop` in the
  forecourt.

While sealed, `trunk-entrance` and `crown-bough-drop` (to the forecourt) refuse with the seal's line;
the doors between the floors go on.

### The Hollow's own pieces

- `game/scripts/latched_hatch.gd` (`LatchedHatch`): the hub's hatch, latched from below ("Latched
  from below.") until the slime climbs up through it from R3 (its door's `arrived` signal); then
  open for good (`weaver-hollow.hatch-open`).
- `game/scripts/room_arenas.gd` (`RoomArenas`, a node in every floor): each placed enemy's arena is
  its camera room, so egg sacs hatch, the Watcher Eye drifts and enemies chase only in their room,
  also when the room is entered again.
- `RoomEntry` markers in B2 and B6, whose middles are void: `?room=B2-drawbridge` starts there.
- C4's dressing and the brood's altar (`game/scenes/objects/weaver-hollow/`: `loft-rafter`,
  `loft-peg-rail` hang on the north wall's face, `loft-spool`, `loft-spinning-wheel` stand solid in
  the corridors' corners, `brood-altar`): Magnific GPT 2.5 (`gpt-2-mini`, transparent, the Lili
  creation as style reference), 2026-10-17, two generations (200 credits), sources and prompts in
  `asset/Originals/weaver-hollow/loft/`, packed by `python scripts/art/pack-loft-art.py` into
  `godot/asset/MAPS/props/weaver-hollow/` (loaded through `sheet_sprite.gd` until the editor imports
  them).
- **F6 on the second half with the Silk skin:** F6 on a floor gives the Hollow's dev powers (the
  Spear, the Roll, the Heavy skin, the Goo Bomb: Silk is won mid-dungeon, from Pearl 2; one line,
  `dungeon.devPowers.weaver-hollow`, read for every world of the dungeon). F6 on
  `game/dev/weaver-hollow-second-half.tscn` (`game/dev/second_half_run.gd`; dev only) runs the
  rebuilt Hollow's Hoard (`weaver-hollow-hoard`, since the switch-over; today's Crown before) the same
  way and lends the Silk skin for the session, worn; on the web or a desktop launch
  `?map=weaver-hollow-hoard&skins=silk` does the same, and `?sealed` takes Pearl 2 quietly and seals.

### Limits

- B6's prize is a heart quarter (roadmap 5.3, built 2026-10-26), against the owner's rule of 2026-11-23 (none inside a dungeon): it goes with the rework.
- Side doors now sit in the Hollow's root-rock wall pieces; the room outline hides the world beyond.
- The Hoard is a small vault in the east of a full-size camera room; the rest of its screen is rock.
- C4's rows of web walls hide the slime behind them only partly: an "across" web fades to 0.45 while
  the slime stands behind it (`web_wall.gd`); the corridors are three rows deep.
- A Slime Spider's web shot (`spider-web`, 5 since 2026-11-24) is the Gloop Forest's, untuned for C4;
  web walls stop shots (they are solid on the world layer), so the spiders hit the slime while its
  body shows above a row it wades, or through a cut lane. Cut lanes let the spiders roam between the
  corridors.
- Not built: Mossy's tip at the ring's south gap, the Matron's three-way lash (8.7; if built it
  pulls but never traps a silk-skinned slime). Her defeat in the Crown counts for the main quest's
  second stage and sets `chapter-2-complete` (the old quest "The Matron's Nest" is retired since
  2026-11-19: [quests spec §14](../godot/specs/quests.md#14-the-main-quest-talks-and-tips-2026-11-19)).
- Filmed (`tools/film_weaver_hollow.gd`, 41 shots, the forecourt to her fall and out) but not played
  through by the owner.
