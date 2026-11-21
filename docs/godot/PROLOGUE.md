# The prologue: the Wellspring and the glade

> **Status:** built 2026-10-16 (roadmap 5.18 to 5.24; the
> [prologue design](../design/2026-10-16-prologue.md)). A new game opens on it; nothing in it is
> saved. Tests: `godot/tests/test_prologue.gd` (the flow) and `test_barred_gate.gd` (the lock in the
> playground).

A few minutes from the slime's birth to its first shape, the Spear, and out into Slimeshire. Two
screens on **B4's south edge** (`west-village-b4`), sealed off by forest from the West village's
town in B4's north (question 112), then Slimeshire's south-west edge (`level-1-c4`).

## Where it is, and why there

| Place | World | Where (units) | What |
|---|---|---|---|
| The Wellspring | `west-village-b4` | camera room (0, 1152) 1024 x 896 | the glowing pool, the birth, the lone pot and the rock, the blocked path out (east) |
| The glade | `west-village-b4` | camera room (1024, 1152) 1024 x 896 | Yoi and the four worms, the light things to throw, the barred gate in its north side, the short forest path behind it (north, east, then down the chunk's east edge) |
| The town's edge | `level-1-c4` | arrival (96, 1696), Plop's spot (140, 1604) | Plop's meeting; Slimeshire begins |

The design put the glade on C4's south-west edge. It is in **B4's south-east** instead, right
against C4, so the barred gate still opens onto C4's west edge: C4's south-west holds the
starter worm camp's walled yard and the village's tree line (the open strip is ten tiles wide, too
narrow for a sealed one-screen arena), `level-1-c4` is hand-made and shared, and B4's south half was
free placeholder ground that question 112 gives to the prologue anyway. No underground cavern was
needed. C4 got only small additions: the arrival marker `arrive-from-west-village-1` (gone since
2026-10-31: the border is crossed at the same place on both sides), the exit back
`exit-to-west-village-1` (its west edge, y 1600-1792, the stretch with no trees), and the
`PrologueMeeting` node. B4's region exit to level-1 moved to the same stretch (y 1600-1792), so the
two line up. The world map (`world-map.json`) still has the old markers and the g-a opening at
y 1280-1536; it is redrawn with the world-map tool.

B4's placeholder town keeps rows 0-12; rows 13-31 were repainted (one-shot builder, then the chunk
is the scene to edit): ground (grass, forest moss under the trees, forest floor on the paths, the
pool's water by ellipse: shallow ring, deep middle, so the slime wades its edge and cannot walk into
it), the forest layer (the darker beech-and-pine mix round the Wellspring, the mixed one round the
glade), Scenery nodes from the palettes (flowers, ferns, glow mushrooms, stepping stones from the
pool to the gap, boulders), the pool picture, glows and fireflies, and a `homecoming-spot` marker on
the pool's south shore for the Pearls' homecoming scenes (5.17). No elevation is painted (nothing
to bake). The release "Web" export now keeps `west-village-b4` (it excludes the other West village
chunks only).

## Camera rooms

`game/world/camera_room.gd` (`CameraRoom`, group `camera_room`): a rect of a world. While the slime
stands in one the world camera keeps to it instead of the whole world, and walking into another
slides the view there over `WorldCamera.ROOM_SLIDE_MS` (a Zelda screen scroll inside one world).
B4 has three: `town` (0, 0, 2048 x 1024), `wellspring` and `glade`, so the Wellspring and the town
never see each other (5.18's done-when). A room smaller than the view (a window wider than 16
tiles) grows about its middle to the view and stays inside the world (`WorldCamera.fit_to_view`).
Rooms work in any world; a world without them keeps its whole rect. The camera also holds for a
scene: `pan_to(point, ms, false)` pans and stays, `set_zoom_level(z)` zooms in place, and
`release_room()` lets the scene's view leave its room (following back into the room slides back).

## The flow

`game/prologue/prologue_state.gd` keeps the prologue in the run's story flags:
`prologue.started` (New Game), one flag per beat (`born`, `path-cleared`, `fight-seen`, `rescued`,
`spear`, `gate-open`) and `prologue.done` (Plop's meeting). It **runs** from started to done. A run
that never started it (an old save, a launch option, the tests) sees both places as after it: the
path open, the gate open, no Yoi, no worms.

**New Game** (`game/shell/title.gd`) starts a new run and `PrologueState.begin`: the flag, no bag
(`inventory.max_slots` 0, roadmap 5.7), nothing discovered yet (the main quest and Slime Basics
wait for the prologue's end, `prologue-over`: [quests spec §14](specs/quests.md#14-the-main-quest-talks-and-tips-2026-11-19)), the old autosave removed (the player agreed to
replace it), and the first world build goes to `west-village-b4` at the marker `prologue-birth`.
`?prologue` (`-- --prologue`) does the same and skips the title.

**The director** (`game/prologue/prologue_director.gd`, the `Prologue` node in B4) plays the beats;
its timings are its properties. While a scene plays it holds the slime (`PrologueScene.hold`: no
walking, no input) and shows letterbox bars (`cinema_bars.gd`, layer 20, over the HUD console).

1. **The birth:** the HUD is hidden (the docked minimap too), the bars are in, the world has a cool
   dawn light (`dawn_tint`). A bubble (`birth_bubble.gd`, drawn in code) rises from the pool,
   wobbles, drifts to the shallow shore and pops; the slime is there with a squash; the light warms
   to day (`sunrise_ms`), the HUD fades in, the bars go.
2. **Moving, the Gulp, the blocked path:** a lone clay pot by the shore and a boulder to throw it at
   (teach); the gap east is choked with a crate, two clay pots, a wicker basket and a flour sack
   (`BlockedPath`; no log, which would read as the Heavy Roll's rotten trunk). An invisible
   `Barrier` holds until every one is gone; then the barrier goes and the secret jingle plays
   (`SecretFound`). Fireflies drift toward the gap and dawn light shines through it.
3. **The attack** (5.19): stepping into `glade_trigger` holds the slime; the camera pans and zooms
   (1.6, letting the view leave the room a little: `release_room`) on Yoi in front of the gate; he thrusts and the two worms on his line fall; a third bites
   him, he sinks; "You there! Kid! Throw something, anything!"; the camera comes back and the two
   worms left turn on the slime.
4. **The rescue** (5.21): prologue worms, 1 HP each (`character.prologue-worm`, placed as
   `PlacedEnemy` nodes under `Prologue/Worms` with no coins, frozen in their tableau until the
   attack); one throw kills one. The glade's light things come back `refill_ms` after each is gone.
   **No game over:** while the prologue runs the director is the player's respawn override
   (`player.gd` `RESPAWN_OVERRIDE_GROUP`), so a fainted slime wakes at the glade's edge
   (`glade-wake`) and the worms are spawned again at their spots.
5. **The veteran** (5.20): the slime lets go of what it holds; Yoi of the Thorn Guard tells his story
   and teaches the Spear (`shape-spear`, learned for good): the "New shape" ceremony
   (`AbilityCeremony.request_shape`; the banner when ceremonies are off); then the gate lesson.
6. **The first lock** (5.22): the barred gate (below). When it opens Yoi says goodbye and limps off
   into the trees.
7. **Out of the forest** (5.24): the path behind the gate leads to B4's east edge and into
   `level-1-c4`. There `game/prologue/town_edge_meeting.gd` (the `PrologueMeeting` node) moves Elder
   Plop to his spot, holds the slime, and Plop meets it (the "!" over him: the meeting's own, as his
   tips wait for `prologue.done`); he gives **his satchel**, the 10-slot bag (`max_slots` 10, the item
   ceremony "New bag"), and his first tips; then `PrologueState.finish` (`prologue.done`: the main
   quest "Win back the Pearls" starts, and Plop's tip of Burr's boy shows its "!"): saving works again, Slimeshire's banner
   shows, and Plop fades out, returns to his saved village position, then fades in; NPCs cannot use the plateau stairs. His elevation is refreshed at both positions, and completion/saving waits until control is released.

**The Spear in the story:** the Spear is a body shape, which only the body-shapes mode plays. Every
run plays in that mode in every world (main.gd `decide_rework_mode`, 2026-10-24) without the
playground's lent shapes and box abilities (`_rework_lending`: only the playground and `?shapes`
lend them), and a run that plays the prologue or has learned a shape keeps its autosave.

**First-time hints** (5.23, `game/hints/control_hints.gd` `PROLOGUE_HINT_IDS`): none during the
birth, then move, the mouth (suck and throw), `throw-move` (keep moving while you aim, worms near),
attack (once a shape is current) and `thrust-bars` (near a shut barred gate). The bag, the Roll
(young Burr teaches it in Slimeshire after the prologue, quests spec §14.3; until 2026-11-19 the
director turned `player.gd`'s `dodge_learned` off for the prologue), the menus and the charge wait
for Slimeshire.

## No saving (a no-save state)

While the prologue runs `RunState.saving_blocked_reason()` is `"prologue"`: `save_slot` (every
slot), the autosave and `write_recovery` (the window closing) all refuse, the pause menu greys Save
out with the hint "No saving yet: quitting starts again from the Wellspring", Quit to Title writes
nothing, and the area banners stay quiet (the Shell). So a quit, a closed window or a crash leaves
no save of it, and the next New Game plays it again from the birth (question 118's proposal, which the owner took; the
title has no Continue for it). Dungeons block saving the same way, with the reason "dungeon"
(there a quit resumes at the dungeon's entrance: [DUNGEONS.md](DUNGEONS.md#dungeon-state-no-saving-resume-at-the-entrance)).

## The barred gate

`object.barred-gate` (`game/scenes/objects/barred-gate.tscn`, scene script `game.barred-gate`,
`game/scripts/barred_gate.gd`; the lever `game/world_objects/barred_gate_lever.gd`). Its own look
(the level-design guide's open point 3): an old Thorn Guard grate of upright iron bars between two
thorn-carved stone posts, a beam with the bronze thorn emblem, and **the lever seen through the
bars**, one short step behind them, in line with a thrust from the open side. Fatty's drop gate (a
Roll lock) must not look like it: no bars to see through, no lever behind them.

- The node stands at the opening's foot; the slime comes from the south (+y) and thrusts north.
- The bars (`Bars`) block every body; their hurtbox lets the Spear's wall ray pass (a body that
  owns a hurtbox is a target, not a wall) and refuses the Spear quietly (`pass`). Anything else on
  them (a thrown pot breaking against them, a Roll, a sword) is refused as `immune`: the clink, the
  locked sound and the line "Barred. Only something long and thin fits between the bars."
- The lever takes only a hit tagged `spear` (the Spear shape's tags).
  It is tagged `resource`, so a throw's blast never reaches it.
- Pulled, the lever drops, the grate rises into the beam over `rise_ms` (its picture is cut from the
  bottom up), the bars stop blocking, and the gate is open for good: the map record's unlocked gate
  `gate_id` (`RunState.mark_gate_unlocked`), read when it is built. `open_now` opens it quietly
  without a record (the prologue's gate for a run that is not playing it).
- Tried in the playground first: the **Barred-gate corner** (`game/dev/corners/barred_gate_corner.tscn`,
  west of the Bestiary corner, a walled yard at x 2752-3264, y 4288-4600, its gate's foot at
  (2976, 4596), a chest inside to see through the bars, pots and a rock outside). Play it in the
  body-shapes mode (the playground's default).

## The homecoming (2026-11-20)

Each Pearl goes home to the Wellspring (questions 98, 110 and 159; plan step A7): the node
`WellspringHomecoming` under B4's `Wellspring` (`game/glimmerhill/wellspring_homecoming.gd`, its
`pool` and `glow` the `Pool` and `PoolGlow` beside it). It does nothing while the prologue runs.
When the slime's middle comes within `trigger_radius` (300) of the pool with a Pearl taken
(`pearl.<id>`) and not yet home (`pearl.<id>.home`), it plays, built on the prologue's scene helpers
(`prologue_scene.gd`: `hold`, `wait`, `ceremony_done`; the `CinemaBars`); several Pearls play one
after another, in the wake table's order (Fatty's, the Matron's, the Colossus's):

1. the bars come in, the slime holds still facing the pool; Bob says nothing and no NPC is there;
2. the Pearl (the picture and glow of `object.pearl`, its script left off) rises out of the slime,
   floats over the pool, hovers and sinks in with a splash; `PoolGlow` flares and settles one step
   brighter (`glow_step_alpha`, `glow_step_scale` for each Pearl home: the glow is set from the
   Pearls home whenever B4 is built, so it stays brighter on later visits);
3. `pearl.<id>.home` is set (the main quest, [quests spec 14.2](specs/quests.md)) and a card
   (`AbilityCeremony.request_entry`, its bubble over the slime) names the part of Glimmerhill that
   wakes: "Pearl of the Wellspring home (n of 8)", "Market Hill wakes" and so on (the texts are in
   game-constants.json `story.glimmerhill.pearls`);
4. the part wakes ([VILLAGERS.md](VILLAGERS.md#asleep-until-its-pearl-comes-home-2026-11-20)): its
   wake flag and the Pearl's `alsoFlags` (owner, 2026-11-20: Pearl 2 `workshop.restored`, which
   raises Slimeshire's Workshop, its card adding "Far off in Slimeshire, the old Workshop rises from
   its boards."; Pearl 3 `forge.restored`, which lights Slimeshire's Forge, "In Slimeshire, the old
   Forge glows again."). When the part's goo fountain stands in this world (Market Hill's, Pearl 1), the camera
   lets go of the room and pans to it (`pan_ms`) before the flag is set, so the fountain bursts into
   flow, the grey lifts and the villagers stretch awake on screen (`watch_ms`), then pans back to
   the slime and follows it again.

The run saves itself after the scene. Every timing is a property of the node. A **campfire**
(`decoration-world-solid--campfire.tscn`, `wellspring-campfire`) stands on the pool's west shore,
out of the scene's way. Filmed with `godot/tools/render_glimmerhill.gd -- --map=west-village-b4
--feet=520,1770 --then-flags=pearl.fatty-one-eye --film-ms=24000` (it closes the card with a key
press after `--close-cards-ms`).

Not built: the well's restoring and the Wellspring's or the fountains' energy refill.

## Art

Magnific GPT 2.5 (`gpt-2-mini`, transparent background), the Lili sheet as style reference,
2026-10-16; sources in `asset/Originals/prologue/generated/`, packed by
`python scripts/art/pack-prologue-art.py`:

| Runtime file | What |
|---|---|
| `godot/asset/MAPS/landmarks/wellspring-pool.webp` | the Wellspring's pool of glowing goo, 360 units wide |
| `godot/asset/MAPS/objects/barred-gate/frame.webp`, `grate.webp` | the gate cut in two: posts and beam, and the grate that rises |
| `godot/asset/MAPS/objects/barred-gate/lever-2x1.webp` | the lever, shut and pulled |
| `godot/asset/characters/authored/npcs/yoi.webp` | Yoi's three poses: standing, the thrust with his jelly spear, wounded |
| `godot/asset/UI/items/plops-satchel.webp` | Plop's satchel (the bag ceremony's icon) |

The pictures load through `game/runtime/sheet_sprite.gd` until the editor imports them. The glows,
mist, dawn light and fireflies are drawn in code (`soft_glow.gd`, `fireflies.gd`).

## Not built yet

- ~~Yoi's home under Lili's yard (5.12) and his tips there~~: built 2026-11-20 (step B4): the heap
  hatch in Lili's west yard leads down to his den `slimeshire-yoi-home`, where he stands as a talkable
  NPC (`game/scenes/characters/villagers/yoi.tscn`, his sheet's standing pose) with four war tips
  ([quests spec 14.3](specs/quests.md#143-talks-talks-in-npc-definitionsjson)), the fifth heart
  quarter and the Charged Roll in his chest (since the owner's change the same day a Roll Fragment,
  behind a Heavy statue maze: [quests spec 14.8](specs/quests.md#148-finds-the-war-journal-the-recipe-page-and-the-charged-roll-2026-11-20)).
- ~~The Wellspring's campfire and the Pearls' homecoming scenes (5.17)~~: built 2026-11-20
  ([The homecoming](#the-homecoming-2026-11-20)). A come-back secret in sight of the birth (the
  level-design guide's proposal: a heart quarter on a rooted ledge, after Feral).
- ~~The first bell, near the town's edge~~: built 2026-10-17 in `level-1-c4` (an islet in a little
  pond south of the road from the forest path, pots on its shore; it unlocks the keeper's
  storehouse, whose coffer is in a separate furnished interior:
  [Chapter 1](../story/chapters/chapter-1-the-clearing.md#slimeshires-places-built-2026-10-17)).
  The arrival and Plop's spot are unchanged; a road of forest soil now leads from them to the town.
- The 10-slot bag for runs that do not play the prologue (5.7): they keep `inventory.initialMaxSlots`.
