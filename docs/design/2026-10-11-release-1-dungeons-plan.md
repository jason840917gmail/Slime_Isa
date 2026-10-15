# Release 1 Progression and Dungeons

*Status: a plan to discuss, on branch `exp/body-shapes` only. Nothing is built. Written
2026-10-11 after the owner's third round of answers; merged from six focused designs and a
consistency check that read the code. It goes with the main plan,
[2026-10-11-body-shapes-plan.md](2026-10-11-body-shapes-plan.md) (shapes, Slam, mouth, Ability
Box, keys, art, branch). Where an owner decision and a design disagreed, the owner decision won.
Defaults that still need the owner's yes are in section 12.*

## 0. Owner answers after this plan (2026-10-11)

- **The step after Tom is option B, Kiri's Three Marks** ([power curve](2026-10-11-world-power-curve.md)),
  replacing The Sealed Hollow below: the iron hollow, the silk nook and the Gloop Cavern each hold
  one piece of Kiri's note. When the slime places the three pieces at the right spot, a short
  cinematic plays and the Weaver Hollow's door rises out of the ground. The Gloop Cavern is on the
  main path then. Sections 2, 7 and 9 still describe The Sealed Hollow and change when this is
  built.
- **Pearl 2:** charges come with every shape from the start, so Pearl 2 does not give the Spin;
  Silk Reel is the default, and whether Pearls give upgrades or new moves is still open.
- **Chapter 1 enemies die within one combo** (one Spear combo is 51 damage); the Squint (32 HP) fits.
- **Story decisions wait;** the rework is built first for the playground.

## 1. What changed since the last plan

**Owner decisions**
- The Spear comes from **Old Veteran Yoi**, in a hidden cavern under Slimeshire called **Yoi's Hideout**. The First Thorn coffer, the hay heap and the Old Bramble lore are gone. A heap of suckable blocks in the same corner of Lili's yard hides the entrance.
- **Lili** gives the hint: during Gorge's war, slimes hid in hideouts around town.
- There is **no Roll in Chapter 1**, and none in Release 1 by default. `stone-tools` is retired. It was the only quest that grants `dodge`.
- **Squash Slam never breaks stone, iron or boulders.** The Slam's harvest path is dropped, and `AbilityWorld.strike_area` keeps skipping resources (`ability_world.gd:83`). The rest of the improved Slam (plan section 4) stays. Its "Rocks and trees" row becomes: trees shake, cracked ground breaks in the Stone form, rocks are left alone.
- **Rocks wait for the Hammer.** The Hammer can only be tested in the playground (`?shapes`).
- **No boss lives in the open world.** Fatty moves into **Fatty's Lair** (Chapter 1) and the Matron into the **Weaver Hollow** (Chapter 2). Each boss leaves its Pearl in its dungeon and never comes back.
- **The Axe is found halfway through the Weaver Hollow**, because the owner liked the dungeon idea. The second half and the Matron need it.
- **Thick webs** can only be cut by the Axe, and not even the Silk form passes them. The **east-road curtain** in front of the Crystal Caverns is approved. More secrets hide behind thick webs.
- **Q handles the whole mouth.** Hold to suck. Hold 2 s with an essence to swallow it. A quick release throws or spits. Hold in a form to spit the form out. The Swallow key is gone.
- **Ability Box.** Squash Slam and all later items go in a box and are used with **S**. Only the Roll keeps its own key. The plan's "Item key and Items screen, Chapter 3+" moves into Release 1 as the Ability Box.
- **Pip's Forge comes after the Hammer.** The Spear Lunge and `rekindle-the-forge` leave Release 1. Stone and ore have no use in Release 1.
- **Stretch Lash comes later.** Sunny's basket becomes a come-back-later secret.

**Editor decisions** (defaults; see section 12)
- Every shape has its charge from the start (owner, 2026-10-11), so the Axe's Spin is not a reward. Pearl 2 gives **Silk Reel** (proposal, [power curve](2026-10-11-world-power-curve.md)): the one-second suck reaches 160 px instead of 80 and pulls light things over water, holes and through bars.
- Fatty's Lair has **no new item**: a big key opens the boss door. I chose this over the Heavy Gulp idea (see below).
- One **dungeon framework** serves both dungeons. Each dungeon is **one scene**, and its floors sit side by side in it.
- Yoi's Hideout is a **cave, not a dungeon**: follow camera, no keys, no fights. It can be built before the dungeon framework.
- Shared new pieces: a **secret cover** that plays an original **SecretFound** jingle, and one **strike switch** script, extended from `lash_bell.gd`. The switch has four looks: alarm bell, stone eye, gong and weaver's eye.
- **Hearts:** four quarters per region (the region's caves and dungeons count toward its four), plus one full heart (+20) per boss.
- Chapter 2's step between Tom and the dungeon is **The Sealed Hollow**. The Stone form presses the iron hollow plate, and inside is Kiri's war cache with the dungeon map. The Gloop Cavern stays an optional secret holding the 20-slot bag.
- **Lili's war hideouts** become Slimeshire's come-back thread. Each one opens with a different verb.
- `world-map.json` now needs edits: new interiors, dungeon markers, and the Crystal seal needing the Axe. The atlas session makes them. The old plan said it would not be touched.

**Design proposals overruled because they break an owner decision or a written rule**
- *Fatty's Lair design:* two heavy boulders on the boss stairs, sucked away with a Heavy Gulp. Boulders are Hammer things ("rocks wait for the Hammer"). Replaced by a big key, and Fatty's phase-2 clods become light.
- *Q design:* a liftable thrown on the *press*. The owner said a quick *release* throws. Throw on release. The press version can be compared in the playground.
- *Hideout design:* a 40 x 28 map. `03-world.md` rule 5 says bigger caves are made of whole screens. Widened to 48 x 28.
- *Weaver Hollow design:* three separate maps. The framework rule is one scene per dungeon. The three floors become three areas of one scene.

## 2. Release 1 in play order

### Chapter 1: Slimeshire
1. **Spawn (640, 704), Plop (525, 704):** Slime Basics. Accepting it gives the 10-slot bag. The slime learns the bag, journal, map and pause.
2. **West of Plop, two clay pots (about (420, 760) and (460, 790)):** hold Q to suck, tap Q to throw. The slime learns the mouth.
3. **Lili (435, 915):** What the Old Slimes Hid. She tells of the war hideouts and the brick heap by her haystack.
4. **Lili's west yard (112, 730):** the slime sucks and throws away 7 blocks. SecretFound plays and a hatch opens. This opens Yoi's Hideout.
5. **Yoi's Hideout:** the slime wades the water maze and throws a pot at the old alarm bell, which opens the west gate. It finds berries, a chest, and a heart quarter behind bricks (HQ1).
6. **Yoi's den:** Yoi asks who the slime is. In The Thorn Guard he teaches the Spear (New shape). The slime practises on two dummies. A spear-only bell opens the east-gate shortcut home.
7. **Village (optional):** A Tonic for Lili (craft a Slime Tonic), then Snack for the Road (a Berry Basket from woodpile wood).
8. **Mossy (858, 692):** Worm Trouble. Kill 3 worm swordsmen at the camp (1132, 1509). The turn-in pulls the planks off the worms' burrow.
9. **Optional:** Sunny's Spiders in the Webwood (2528, 307). Plop's A Home of Your Own (home door at (1081, 903): the bed and the vault).
10. **Plop:** The One-Eyed Guardian. The slime crosses the Fatty Maze to the burrow mouth (about (2528, 1150)).
11. **Fatty's Lair:** stone eyes, a gong, 2 small keys, an ambush, the Big Squint, the big key, then Fatty.
12. **Pearl Shrine:** the slime takes Pearl 1, and Squash Slam goes into the Ability Box (S). It slams the worm drum and a root ladder climbs out. The green key is in a chest. The boss heart is in the arena.
13. **Plop:** the slime hands over the Pearl. This sets `chapter-1-complete`. Mossy and Sunny leave for the forest.
14. **Slam come-back:** a stuck hatch by the Wishing Well (723, 851) opens the well-cellar hideout (HQ2).
15. **Verdant Gate (3776, 768):** the green key opens it, and the slime enters Gloop Forest.

### Chapter 2: Gloop Forest
1. **Mossy's camp (1816, 1762):** Beyond the Verdant Gate. Kill 5 orb-weavers.
2. **Tom's web (860, 2470):** the slime frees Tom with the Spear. Tom in the Web teaches Swallow: hold Q 2 s to swallow, hold Q in a form to spit it out.
3. **Silk nook (optional):** the Silk form passes the web to GQ1 (800, 1176).
4. **Mossy:** The Sealed Hollow. The Stone form presses the plate (2880, 3016) and the hollow gate opens. Inside are GQ2 and Kiri's war cache with the Weaver Hollow map and Kiri's note. The iron nodes say a hammer could crack them.
5. **Gloop Cavern (optional):** a Stone-form Slam breaks the cracked ground (1344, 2368). Inside are the 20-slot bag and GQ3.
6. **Slimeshire (optional):** the slime carries a stone essence home in the bag. The smith's storeroom plate by the Forge (1190, 1068) gives HQ3 and a letter for Pip's later story.
7. **Mossy:** The Matron's Nest. The slime swallows silk outside the nest ring, and the Silk form slips through the web door (the ring's west gap, about (2720, 800)). Inside the ring, the door of the Great Stump is at about (3060, 900).
8. **Weaver Hollow, first half:** Silk webs, weaver's eyes across water (Spear), the bag trick and a plate (Stone form), and a Stone-form Slam through the floor. Small keys 1 and 2, then the Brood Warden.
9. **Edge Shrine:** the big chest holds the Axe (New shape). From now on E switches shapes. Small key 3 is here too.
10. **Weaver Hollow, second half:** the Axe cuts thick webs, tethers and egg sacs. The Nursery gives the Spindle Key, which opens the boss door.
11. **The Crown:** the Matron. Pearl 2 gives Silk Reel (a longer suck). The boss heart appears, and a root lift returns to the forecourt. Sunny's basket across the north stream becomes its first use.
12. **Axe come-backs:** the east-road curtain (about (3330, 1728)) opens the way to the Crystal Caverns. Also the GQ4 cocoon, Tom's Cut Loose and the webbed caches.
13. **Plop:** Pearl 2 sets `chapter-2-complete`. Back in Slimeshire, the Axe opens the hideout store room (HQ4) and the Webwood coffer. End card.

## 3. Progression table

| Learned | Where | How | What it opens | Ceremony |
|---|---|---|---|---|
| Mouth: suck and throw (Q) | Start | Built in | Pots, crates, bricks; the hideout heap; thrown pots ring bells and gongs | None |
| 10-slot bag | Plop | Accepting Slime Basics (the owner's exception) | Carrying things; chests | Item |
| **Spear** (shape) | Yoi, Yoi's Hideout | Turning in The Thorn Guard | Attack (A); spear-only bells and stone eyes; Fatty's eye; Tom's web | Full, "New shape" |
| Small keys, big key (Bone Key) | Chests in Fatty's Lair | Finding them | Locked doors; the boss door | Short item rise (small keys: a sound only) |
| **Squash Slam** (Ability Box, S) | Pearl 1, Fatty's Lair | Beating Fatty, then W on the Pearl | The worm drum, stuck hatches (the well cellar), tree shakes; in the Stone form, cracked ground. Never rocks | Full, Pearl card |
| Green key | Chest beside Pearl 1 | Opening it | The Verdant Gate, Chapter 2 | Full (key) |
| **Swallow** (hold Q 2 s) | Tom, forest camp | Freeing Tom with the Spear | Stone form: plates, no knockback, cracked ground with the Slam. Silk form: plain webs, the web door. Swim form: placed essences only | Full |
| Weaver Hollow map | Kiri's cache, iron hollow | The Sealed Hollow | The dungeon's rooms on the minimap | Short item rise |
| 20-slot bag | Gloop Cavern chest | Stone-form Slam on the cracked ground | More slots | Item |
| **War Axe** (shape) | Big chest, Edge Shrine, Weaver Hollow | Midway through the dungeon | Thick webs, cocoons, tethers, egg sacs, bushes, vines, trees (wood); E switches shapes | Full, "New shape" |
| Spindle Key (big key) | Nursery, Weaver Hollow | Clearing the room | The Matron's door | Short item rise |
| **Silk Reel** (longer suck, 160 px) | Pearl 2, the Crown | Beating the Matron, then W on the Pearl | Sunny's basket, pots on islets, things behind bars | Full, Pearl card |
| Heart quarters (4 per region) and boss hearts | Secrets; after each boss | Finding them; beating bosses | 4 quarters = +20 max HP; each boss +20 (180 max HP after Chapter 2) | Quarter ring; full heart |

**Later (not in Release 1, testable in the playground):**
- the Roll (own key D);
- the Hammer (shape; stone and iron nodes, boulders, armour);
- the Spear Lunge (Yoi on a return visit, or Pip's Forge after the Hammer);
- Stretch Lash, Teleport, Glow (lantern), Goo Bombs (Ability Box);
- the two Heavy Gulp lift upgrades;
- the swim-essence enemy;
- Pip's Forge (tempers shapes) and the Workshop (makes box gadgets).

## 4. Yoi's Hideout

**Entrance.**
- Place: level-1 at (112, 730), the corner of Lili's west yard. It sits between the west tree wall (x < 64), the haystack `l1-haystack-001` (194, 682) and the bale `l1-hay-bale-001` (230, 762).
- Ground: plain moss with no elevation, south of the plateau the atlas session is editing. It is about 370 px from Lili and 530 px from the spawn, and far from the worm camp.
- A new `object.secret-hatch` holds two subtrees:
  - **Covered:** 5 `mossy-brick` and 2 `crate` liftables, all light.
  - **Open:** a hole sprite, a Door `yoi-hideout-hatch` to `yoi-hideout` / `yoi-hideout-ladder` with the prompt "Climb down", and an arrival at (112, 826).
- Clue: every 4 s a small dust puff rises between the bricks, like a draft from below.

**Reveal.** `secret_cover.gd` watches the liftables.
- A liftable that leaves the tree while queued for deletion counts as taken. One the StoryVariant parks does not count.
- When the last one is gone:
  - the script sets flag `secret.yoi-hideout`, and the StoryVariant shows Open;
  - dust puffs, the screen shakes a little and the hole pops in;
  - after 250 ms (after GulpCatch), the SecretFound jingle plays;
  - it emits `OBJECT_ACTIVATED`.
- There is no text, no pause and no camera move (pure Zelda).
- The flag is required, because liftables come back every time a map is entered (`liftable.gd:19`).
- The jingle must be original, not a copy of Nintendo's.

**Map.**
- `world.yoi-hideout`, **48 x 28** (3 x 2 screens), follow camera.
- The sketch below is 40 columns wide. The 8 extra columns go on the east side, so every position given here stays valid.
- Ground: shallow `water` in the corridors (wading splash), `deep-water` in the pool and channels (it blocks walking; throws and Spear lines pass over it), and dry `cavern-floor` at the ladder, the ledges and the den.
- Walls: the 31-piece `wall-stone-solid` kit, with `rock-wall` ground under the solid rock.
- Title: "The Old Hideout" (an AreaTitles AREAS entry, so Yoi's name stays a surprise). Interior ambience, no music.

```
Legend: # wall  ~ shallow  D deep  . dry  L ladder  Y Yoi  f fire  s statue/banner  T dummy
        G gate  B alarm bell  p clay pot  C chest  * berry  b brick  H heart quarter
        W thick web (Axe)  h come-back prize (HQ4)  F frog  m minnows
    0123456789012345678901234567890123456789
 1 ########################################
 2 ##~~~~~~~~~~~~~.s......s.###############
 3 ##~~~~~~~~~~~~~..........###############
 4 ##GG###########....Y.f...####~~~~m~~~~##
 5 ##~~~~~DD..####..........####~~~~~~~~~##
 6 ##~~m~~DDB.####..TT......####WW#####~~##
 7 ##~~~~pDD..####............##...####~~##
 8 ##~p~~~DD######............##.h.####~~##
 9 ##~~~p~########DDDDDDDDDD~~#########~~##
10 ##~~######.C.##DDDDDDDDBD~~#########~~##
11 ##~~######...##DDDDDDDDDD~~###..####~~##
12 ##~~######~~###DDDDDDDDDDGG###H.~bbb~~##
13 ##~~~~~~~~~~###DDDDDDDDDD~~###..####~~##
14 ##~~~~~~~~~~###DDDDDDDDDD~~#########~~##
15 ######~~#######DDDDDDDDDD~~#########~~##
16 ######~~#######DDDDDDDDDD~~#########~~##
17 ######~~#######DDDDDDDDDD~~##~~~~~~~~~##
18 ##~~~~~~#######DDDDDDDDDD~~##~F~m~~~~~##
19 ##~~~~~~#~~**##~~DDDDDD~~~~##~~~~~~~~~##
20 ##~~#####~~~*##~~~~~~~~~~~~#########~~##
21 ##~~######~~###~~~~~~~~~~~~#########~~##
22 ##~~######~~###~~..L...~~###########~~##
23 ##~~~~~~~~~~~~~~~......~~~~~~~~~~~~~~~##
24 ##~~~~~~~~~~~~~~~......~~~~~~~~~~~~~~~##
25 ###############~~......~~###############
26 ########################################
```

The design checked this grid by search:
- With both gates shut, the den cannot be reached.
- The main path is 64 cells (about 20 s of walking). The shortcut is 30 cells.
- The cells are 295 shallow, 113 deep and 111 dry.

**Route.**
1. The slime lands on the dry island by the ladder (1248, 1440).
2. **North-east:** the shore corridor ends at gate G2 (1664, 832): "Barred from the other side." Bell B2 stands on an islet beyond it. This is the shortcut the slime sees first and opens later.
3. **East arm:**
   - a 1-wide squeeze is plugged by 3 bricks (a second secret cover, flag `secret.yoi-hideout-nook`, jingle once); behind it is HQ1 (1952, 808);
   - a frog pool;
   - a top corridor that ends at a thick web over a store room, the HQ4 come-back for the Axe.
4. **West arm (the true path):**
   - a berry dead end with 3 berries, +5 coins each;
   - a chest dead end (736, 680) with 2 berry mats and 1 potion;
   - the pot room.
5. **Pot room:** gate G1 (192, 320) is shut: "Shut fast. Long ago an alarm bell worked this gate." Bell B1 (608, 440) stands on a ledge across a 2-cell deep channel. A thrown clay pot (about 192 px, inside the 280 px throw range) rings it, and G1 opens for good.
6. The top corridor leads east to the den.

**Yoi.**
- Look: an old, sagging slime of faded moss-grey jelly, with an eye patch and scars. Where young slimes have a sprout, he has a chipped bone-white spike. He wears a frayed red war sash with a bronze thorn badge.
- The den: Yoi (1248, 300), a campfire, armour statues and banners.
- Talk 1: "Halt! Who goes there?" He asks who the slime is and what it is doing down there, and guesses that Lili sent it.
- Talk 2: he is Yoi of the Thorn Guard, which held the gate against Gorge's monsters. When the war was lost, Slimeshire hid under its own floor. The others went back up, and he stayed to keep watch. "Gather all of yourself, and push it out to one point."
- Default lines hint at Fatty: "A one-eyed thing only fears what can reach its eye."

**The Spear lesson.**
1. The full "New shape" ceremony plays.
2. Two straw dummies stand 48 px apart at (1104, 440) and (1152, 440). One thrust hits both, because the Spear hits everything on its line.
3. Bell B2 (1504, 700) stands on an islet across one deep cell, and only a hit with the `spear` tag rings it. It is in reach from the den edge and from the shore corridor north of G2, but not from south of G2. A thrown pot is refused.
4. G2 opens for good (`mark_gate_unlocked`).

**Exit.** The shore corridor leads to the ladder ("Climb up") and level-1's hatch arrival. Later visits use the open G2, a straight route to Yoi.

**What must be built.**
- `secret_cover.gd` and `secret-hatch.tscn`, built like `cracked-ground.tscn`.
- Exports on `lash_bell.gd`: `required_tag` and `opens_for_good`.
- A 2-cell `gate-wooden.tscn`. `gate-verdant.tscn` is too wide (pillars at ±112).
- The world `yoi-hideout.tscn`. An optional ASCII-to-tiles builder.
- Yoi: a scene from the Tom pattern, an `npc-definitions.json` entry (id `yoi`, displayName "Old Veteran Yoi"), and one 256 px still made with Magnific GPT 2.5 and a transparent background.
- Two quests (section 9) and the SecretFound cue.
- Level-1 edits, after the atlas session's elevation work is merged: the hatch and the 2 practice pots.
- If the slime has no bag yet, the chest says so and keeps its contents.

## 5. Dungeon framework

**The shape of a dungeon.**
- A dungeon is one interior world `game/scenes/worlds/<id>.tscn` with `camera_mode = "rooms"` and a dungeon-definition node: id, name, region, exit door, boss, Pearl ability.
- The room cell is **16 x 14 tiles (1024 x 896 px)**. A room covers 1 x 1 up to 2 x 2 cells.
- Door slots are 2 tiles wide in the middle of each wall.
- Floors go side by side in the same scene, joined by in-scene warps. Height changes inside a floor are elevation stairs and ledges.
- Dungeons have no enemy-spawn areas. Rooms spawn their own enemies.

| Element | Reuse or new | Notes |
|---|---|---|
| World scene and dungeon definition | New (small) | `world_definition.gd` must accept `"rooms"`; a `scene_index.json` line |
| Room grid (`DungeonRoom`, group `dungeon_room`) | New | `room_id`, `cell`, `size_cells`, `floor_label`; an editor gizmo for the room rect, door slots and camera frame |
| Room camera | New, on `world_camera.gd` | Bounds = the room; a 450 ms scroll; the slime nudged 48 px in; a dark `#0b1020` curtain outside the room; zoom held at 1.0. The grey box can start with simple room bounds |
| `DungeonController` | New | Made by `main.gd` when a definition exists: current room, `room_entered` / `room_exited`, visited and cleared rooms |
| Doors in and out | Reuse | `door.gd`, `cave-ladder.tscn`, `world_exit.gd` (`entry_marker`) |
| Stairs, warps, floor drops inside the scene | New (small) | `AreaTravel.fade` + `player.teleport` + `suppress_movement`; a cracked floor's Broken door can point at a marker in the same scene |
| Dungeon doors: open, shutter, small-key, boss, one-way, sealed | New `dungeon_door.gd` in group `gate` | Plates and switches drive it through the gate API; `gate.gd` gains `close()` and saved state |
| Small keys, big key, map | New RunState `world.dungeons[id]` | Small keys are a counter shown by the minimap, never bag items; kept on death and on leaving. Compass later |
| Dungeon chests, small and big | New, from `chest.gd` | Each opens once (flag `chest.<dungeon>.<id>`): a key, the big key, the map, an ability (full ceremony), a quarter, items. Can be hidden behind a StoryVariant |
| Strike switch: alarm bell, stone eye, gong, weaver's eye | Reuse `lash_bell.gd` + exports | `required_tag` (`''`, `spear`, `thrown`), `opens_for_good`, `open_ms` (timed), `group` (all open together) |
| Pressure plates | Reuse `pressure_plate.gd` | Stone form only; add saved state. No plates on Chapter 1 main paths |
| Cracked floors | Reuse `cracked_ground.gd` | Stone-form Slam or a Clod Stomper stomp |
| Plain webs | Reuse `spider_web.gd` | `tears_when_crossed = false` in dungeons; the Axe cuts them for good |
| Thick webs, cocoons, tethers, egg sacs | New, from the `tom_web.gd` pattern | Cut by hits with the Axe's cut tag; the Spear only shakes them: "An edge would cut this" |
| Liftable heaps and pots | Reuse `liftable.gd` | Pots can drop a heart or coins (a small loot table, new) |
| Secret cover + SecretFound | New `secret_cover.gd` | Watches a cover (liftables, a web, a crack, a cleared room); flag, jingle, dust, small shake |
| Room fights | New `RoomEncounter` | Spawns placed enemies on entry inside the room rect (`configure_navigation`), despawns them on exit, closes shutters, emits `cleared`, reveals a reward; `once` for ambushes |
| Boss room | Reuse `boss_camp.gd` + new `once` | A rectangle arena the size of the room; shutters close on `boss_engaged` and open on `boss_defeated`; boss music already follows |
| Pearl | New `pearl.gd` | W: the Pearl card, learns the ability, flag `pearl.<boss_id>`, adds to `completed_dungeon_ids`, emits `OBJECT_ACTIVATED` |
| Boss heart | Part of the heart work (roadmap 5.3) | A full heart, +20 |
| Death inside | New rule in `player.gd` / `main.gd` | Wakes at the dungeon's player-spawn with keys and flags kept; the boss resets to full |
| Minimap and HUD | New, on `minimap.gd` | Room fog (visited rooms; with the map, all rooms dimmed); a small-key and big-key readout |
| Area titles | AREAS entries | "The Old Hideout", "Fatty's Lair", "Weaver Hollow" |
| Dev and tools | New | `?room=`, `?keys=`, `?bigkey`, `?dungeon-reset`; `dungeon-lab.tscn` (a door from the playground); `build_dungeon.gd`; `check_dungeons.gd` (rooms tile the grid, door slots line up, every room reachable with the keys found before each lock) |

**Dungeon rules.**
1. The first half uses only verbs the slime has when it arrives.
2. Each dungeon has one boss, one Pearl and one big key. Small keys equal small-key doors, and each key is reachable before its door.
3. Opened doors, switches, broken floors, cut webs, cleared ambushes and the beaten boss stay done.
4. Ordinary room enemies come back when the slime re-enters a room after leaving it.
5. No Roll anywhere in Release 1: every attack can be escaped by walking (200 px/s).
6. No bridges and no Chapter 1 plates.
7. Hits still ignore walls and cliffs. Only the Spear gets a wall line check, and that check ignores the water layer.

**How dungeons fit the world.**
- Dungeons are interiors, off the overworld grid (`03-world.md` rule 5).
- The atlas session adds each id to its region's `interiors` in `world-map.json`:
  - `yoi-hideout` and `fatty-lair` to `slimeshire-meadow`;
  - `weaver-hollow` to `gloop-forest`.
- The atlas session also updates three markers:
  - the Fatty "boss" marker (58, 52) becomes a dungeon marker;
  - the Matron's marker (86, 53) needs "web door: Silk form";
  - the Crystal seal (96, 61) needs the Axe.
- The world map window already rings a region from its interiors (`region_for_map`). The player dot stays hidden inside interiors.

**Coordination with the atlas session.**
- Tell the atlas session before editing `level-1`, `gloop-forest`, `scene_index.json` or `project.godot`. The input change goes in its own announced commit.
- Never hand-edit the 8 placeholder worlds.
- Dungeon elevation (stairs, ledges) waits for the atlas session's ramp and stair work to be merged. Grey boxes can start flat.

**Build order.**
1. The hideout pieces (secret cover, bell exports, wooden gate).
2. The dungeon kit and the dungeon lab in the playground.
3. Fatty's Lair as a grey box with existing enemies.
4. The Weaver Hollow as a grey box (it needs the Axe shape).
5. The new enemies and the boss reworks.
6. Art.

## 6. Dungeon 1: Fatty's Lair (Chapter 1)

**Story.** The worms never raided Slimeshire. Fatty came up from below, ate their winter stores and drove them out, and they nailed the burrow shut.

**Entrance (level-1).**
- Remove `Encounters/level-1-fatty-one-eye-camp` (2528, 1472) and its guarded chest (2528, 1077) with the green key.
- The old arena becomes the plaza, "Fatty's Hollow". The tree maze stays.
- On the plaza's north side, at about (2528, 1150):
  - a rock mound;
  - a Door `fatty-lair-door` ("Enter the burrow" to `fatty-lair` / `lair-entrance`), with its arrival at (2528, 1240), which the exit ladder also uses;
  - a plank barricade in a StoryVariant on flag `lair-barricade-down`, which the Worm Trouble turn-in sets.

**Map.** `world.fatty-lair`, 48 x 42 tiles (3 x 3 screens, 3072 x 2688 px), on two heights: level 0 (the upper burrow) and level -1 (the sunken halls). Walls are level-2 rock (`root-rock` or `cave-rock`).

| Room | Screen, level | What happens |
|---|---|---|
| R1 Entry Hall | B3, 0 | Arrival at (1536, 2560); a door "Leave the burrow". **North shutter:** Spear the stone eye above it and it opens for good. A thrown pot only clinks: the first lesson. **West doorway** to R2 is choked by 4 mossy bricks (suck them away). **East door:** small-key lock. 2 Squints. *Come-back:* a thick-web niche in the SE corner (Axe) holds 2 Slime Tonics and a lore note |
| R2 Pantry | A3, 0 (optional) | 8 pots (some drop hearts), 1 Squint. In the west wall, 3 twitching bricks hide an alcove: SecretFound, then the **map** chest |
| R3 Pit Hall (hub) | B2, 0 and -1 | A south balcony (0) over a pit (-1). The first way down is a drop off the rim. **SW stairs** are closed by a grate that a stone eye on the pit side opens (the shortcut back to R1). **North stairs** go up to R8, and the boss door is in sight from the balcony. 2 Squints, 4 pots |
| R4 Sump | A2, -1 | A floor of shallow water with a 2-tile deep channel. A **gong** on the far bank is out of Spear and suck reach. A pot thrown about 200 px rings it, the grate opens, and the chest holds **small key 1**. 3 Squints. *Come-back:* a Stone-form plate niche (Chapter 2) holds a chest |
| R5 East Burrows | C3, -1 | Small key 1 opens the door. **Ambush:** shutters close and 4 Squints drop from the ceiling. When all are dead, a chest appears with **small key 2**. The ambush never repeats. Stairs north lead up to R6 |
| R6 Eye Gallery | C2, 0 / trench -1 / 0 | Two stone eyes in the trench's north wall each stay open 3 s. With both open, the grate at the east end joins the two halves for good. Eye B is screened, so only a diagonal thrust reaches it. 2 slime-spiders shoot across. The north half has the **small-key door 2** to R7. A gap in the north rim is a ledge drop into the trench, and a one-way door leads from the trench into R3's pit (the shortcut back) |
| R7 Larder | C1, 0 | **Ambush:** the Big Squint and 2 Squints, with shutters. Then the big chest: the **big key** (Bone Key, keys sheet frame 10) |
| R8 Antechamber | B2 north balcony, 0 | Pots (2 hold hearts) and a worm mural: "The Big Eye came up from below and ate our winter stores." The **boss door** (big key) is at (1536, 896) |
| R9 Arena | B1, 0 | Fatty. Rectangle arena (1120, 96)-(1952, 800). A flat floor, because his leap ignores collision. The shutters to R10 open after his defeat, and the boss heart appears |
| R10 Pearl Shrine | A1, 0 | Pearl 1 on a worm altar (512, 360). The green-key chest. The worm drum: the first Slam on it brings down roots and a root ladder out under daylight (flag `lair-exit-open`). A mural of slimes and worms fighting Gorge's monsters together |

**Critical path:**
1. R1 eye, then R3 balcony, then the drop.
2. R4 gong (key 1), then the R3 grate eye and the stairs up to R1.
3. R1 east door (key 1), then the R5 ambush (key 2).
4. R6 eyes, then the R6 north door (key 2).
5. R7 (big key), then the drop into the trench.
6. The R3 pit, the north stairs and R8.
7. The boss door, R9 Fatty, R10.

The first play takes about 25-35 minutes.

**Puzzle rules, taught in R1 and kept everywhere.** Eyes want the Spear. Gongs want a throw. Twitching bricks want the mouth. Webs wait for an edge. A wrong hit clinks.

**Unique enemy: the Squint.** Built from `clod_stomper.gd`.
- A small one-eyed mud blob of Fatty's brood. HP 32, speed 55, aggro 260.
- It crouches 450 ms behind a ring telegraph, hops 380 ms, then slams: ring r52, 12 damage, knockback 220.
- Afterwards it is dazed 900 ms with its eye open. The eye takes Spear hits only, and only while dazed.
- A thrown object knocks it over (dazed 1.5 s). It drops no essence.
- **Big Squint** (mini-boss): the same script at 1.5x scale. HP 96, ring r84, 18 damage, two stomps in a row, dazed 1.1 s.
- The grey box uses the Fatty sheet at 0.5 scale with a tint.

**Item.** No new item. The big key is the boss lock. The Heavy Gulp is question 2.

**Secrets.** The R2 alcove (mouth: the map). The R1 web niche (Axe, later). The R4 plate niche (Stone form, later). The lair holds no heart quarters, because Slimeshire's four are elsewhere (section 10).

**Boss: Fatty One Eye.** 140 HP, damage from the `spear` tag only.
- **Phase 1** is as today:
  - he chases at 42 px/s and contact-hops for 15 damage;
  - every 5 s he does 3 hops, then a 1 s leap with a shadow telegraph, landing for 29 damage;
  - then he recovers for 700 ms with his eye open.
- **Phase 2**, below 70 HP:
  - two leaps in a row, the second with 700 ms of air time;
  - after each landing his eye squints shut (a clink);
  - 2 **light** mud clods fall at rubble spots behind a 600 ms shadow (12 damage), with at most 4 on the floor;
  - the slime sucks a clod and throws it at him: he is dizzy 1.6 s with his eye wide open, then the Spear.
- Every attack can be escaped by walking.
- **Defeat:** the boss burst and the Victory cue. He shrinks into a small, calm one-eyed slime and never respawns (`once`). The Pearl pops from his eye and drifts west into the shrine.

**Pearl.**
- W on the Pearl plays "Pearl of the Wellspring (1 of 8): Squash Slam".
- The Slam goes into the Ability Box and is selected, and the card names S.
- This sets flag `pearl.fatty-one-eye` and adds `fatty-lair` to `completed_dungeon_ids`.
- The worm drum then makes the slime use the new move at once.

## 7. Dungeon 2: the Weaver Hollow (Chapter 2)

**The Axe decision.**
- The Axe lies halfway through the dungeon, in the big chest of the Edge Shrine. The second half and the Matron need it.
- Lore proposal: the War Axe is the Old Bite, the war axe of **Kiri**, Yoi's comrade from Gorge's war. Kiri appears in lore only, through his cache and note.
- A design wanted the slime to suck and swallow the relic. I chose the big chest instead, so the Q rule stays "only essences are swallowed".
- Pearl 2 gives Silk Reel (the Spin is the Axe's charge from the start).
- Chapter 2's two items: Swallow opens the dungeon (the web door) and the Axe is the dungeon item (question 5).

**Entrance (gloop-forest).**
- The open nest becomes the dungeon's **forecourt**.
- The ring's west gap, between `gloop-nest-ring-c43-r10` (2784, 694) and `-c42-r14` (2720, 950), gets the **web door**. It is a plain side-view web, 192 px tall, with `tears_when_crossed = false`. The Silk form passes it, and later the Axe cuts it for good.
- `nest-silk-gulp-spot` moves from (2872, 1000) to just outside the door, at about (2600, 822).
- The **Great Stump** stands at about (3060, 900), with its door `nest-stump` to `weaver-hollow`.
- Remove:
  - the `gloop-ch2-matron-nest` camp at (3120, 940) and its guarded chest (iron bars);
  - the `matron-goo-heart` at (3120, 800) and its StoryVariant.
- Add a 2-weaver spawn area inside the ring, at about (2980, 1100).

**Map.** `world.weaver-hollow` is one scene, 96 x 28 tiles, with three floors side by side:
- the **Trunk** (F1), cells 0-2, x 0-3072;
- the **Roots** (B1), cells 3-4, x 3072-5120;
- the **Crown** (F2), cell 5, x 5120-6144.

The rooms below use cells inside each floor. Floor changes are in-scene warps: ladders, the crack, the lift.

| Room | Floor (cell) | What happens |
|---|---|---|
| F1-A Hollow Mouth | Trunk (1,1) | Arrival. **West:** a plain web (Silk). **East:** a heap of 4 mossy bricks and 2 rune urns. The slime spits its form out with a Q hold, clears the heap, then sucks the silk back and holds Q 2 s to swallow it. **North:** a thick web (Axe, later). A placed silk essence, 4 pots, 1 Silk Lurker. A root hatch, opened later from below |
| F1-B Web Gallery | Trunk (0,1) | A Silk walkway past plain webs along a deep channel; 2 orb-weavers spit, and a hit pops the form (placed silk to re-gulp). A **weaver's eye** across 64 px of water (Spear, 110 px reach) opens bars, and the alcove holds **small key 1**. *Secret S2:* a cracked floor (Stone-form Slam) drops into a Roots pocket with the Sap Spring (a full heal, once per visit) |
| F1-C Larder | Trunk (2,1) | Through the heap. 2 orb-weavers, an egg sac (4 Broodlings, once), victim cocoons. **Lock L1** on the north doorway. *S1:* a thick-webbed alcove (after the Axe) holds a chest of tonics |
| F1-F Weigh Room | Trunk (2,0) | Silk and stone essences on plinths, and two rows of plain webs. The slime puts the stone essence in the bag, goes Silk through the webs, takes the stone out and swallows it, then presses the plate. The bars open for good, and a Stone-form Slam on the crack drops it to the Roots. A Silk Lurker hangs over the plate |
| B1-A Root Fall | Roots (1,0) | The slime lands in the Stone form. A root ladder climbs to F1-A and opens its hatch for good (the shortcut). **West:** a plain web, and a Silk Lurker that always drops silk. **South:** a thick web, cut later from the other side |
| B1-B Root Pools | Roots (0,0) | An island in a ring of deep water. Its weaver's eye hides behind 3 pots on the rim. The slime sucks them across (80 px), then spears the eye, and a root drawbridge lowers to the island chest with **small key 2**. A Clod Stomper camp gives stone. **Lock L2** on the south doorway. *S3:* a channel for the Swim form (later) |
| B1-C Warden's Den | Roots (0,1) | Through L2; the shutters close. A placed stone essence. **Brood Warden** (mini-boss). When it is beaten, the east shutter opens |
| B1-D Edge Shrine | Roots (1,1) | **The big chest: the Axe.** An egg sac then hatches 5 Broodlings to test the arc. A cocoon holds **small key 3**. Cutting the north thick web leads back to the ladder |
| F1-D Spindle Hall | Trunk (1,0) | Through F1-A's north thick web. A root ladder hangs in the ceiling, held by 3 silk tethers. One tether is behind a plain web, a Silk Lurker re-spins another after 8 s, and the third is buried under bricks. With all 3 cut, the ladder drops: the way up to the Crown. **Lock L3** on the west doorway. This room is the boss's lesson |
| F1-E Nursery | Trunk (0,0) | Through L3; the shutters close. 4 egg sacs hatch Broodlings every 5 s (at most 6 alive) until they are cut; 2 orb-weavers drop in. When all are cut and dead, the big chest appears with the **Spindle Key** (keys sheet frame 4) |
| F2-A Spindle Stair | Crown (0,1) | Two terraces (stairs once the atlas session's stair work lands). Placed silk and stone essences, 6 pots, 1 Silk Lurker. The **boss door** (Spindle Key) |
| F2-B The Crown | Crown (0,0) | The Matron |

**Critical path:**
1. The web door and F1-A, then F1-B (key 1).
2. The F1-A heap, F1-C and lock L1.
3. F1-F, then down to B1-A.
4. B1-B (key 2), lock L2, the Warden.
5. B1-D (the Axe, key 3), then the ladder back up to F1-A.
6. Cut the north web, F1-D (the tethers), lock L3.
7. F1-E (the big key), F2-A, F2-B.

Small keys work on any lock in this dungeon, so every order works. The S2 sequence break cannot cause a dead lock either. The first play takes about 25-35 minutes.

**Object rules.**
- **Plain web:** catches a normal slime; Silk slips through without tearing; the Axe cuts it for good.
- **Thick web:** solid; nothing passes, not even Silk ("Too thick to slip through"); one Axe hit cuts it for good.
- **Weaver's eye:** Spear only; it remembers being opened.
- **Tether:** Axe only, one hit; it can regrow.
- **Cocoon:** the Axe cuts it and it drops what it holds.
- **Egg sac:** the Axe or the Slam pops it in 1 hit, the Spear in 3.

**Enemies.**
- **Silk Lurker** (new):
  - hangs on a thread over a floor shadow;
  - drops when the slime comes within 48 px (18 damage plus web);
  - scuttles for 4 s, then climbs back up;
  - HP 30; the Axe cuts its thread, and a Slam or a thrown pot knocks it down;
  - always drops silk.
- **Broodling** (new): the slime-spider at 0.5 scale. 8 HP, speed 140, 6 contact damage, no spit.
- **Brood Warden** (new mini-boss): an orb-weaver at 2x scale with a rust tint.
  - 160 HP, immune to knockback.
  - Its leg sweep alternates sides: 140° arc, r96, 600 ms telegraph, 20 damage.
  - Every third swing is a 200° double sweep, after which its legs stay planted for 1.2 s.
  - It spits at range.
  - A Slam during its rear-up topples it for 2.5 s with double damage.
  - The Spear's 110 px reach outranges its sweep.
- Existing enemies: orb-weavers, slime-spiders, Clod Stompers.

**Secrets.** S1 (Axe, inside the dungeon). S2, the Sap Spring (Stone-form Slam). S3 (Swim, later). The web door can be cut for good after the Axe.

**Boss: the Matron.** 300 HP. She is beaten without the Roll.
1. **Canopy.** She hangs out of reach and keeps her spit (2.2 s) and her four-circle volley (patches last 6 s).
   - Four tethers each take one Axe hit, and each cut drops a silk essence.
   - After the 2nd cut, 3 Broodlings drop.
   - After the 4th she crashes and is stunned 3 s.
2. **Floor.**
   - Leg sweeps alternate left and right every 2.4 s: 140° arc, r110, 700 ms telegraph, 24 damage, knockback 280.
   - Each sweep clears her own patches.
   - She keeps the spit and the volley; the 1.3 s rest after a volley is the opening.
   - At 150 HP she climbs back up (2 s, untargetable), the tethers regrow, and two anchors now stand behind plain webs.
3. **After the second crash.** She adds the **two-leg spin**: 900 ms crouch with a ring telegraph of r120, then 30 damage, then she is dizzy 1.5 s.

What the forms do: Silk passes her patches. Stone ignores the sweep's knockback, but a hit still pops the form. The Axe cuts patches. Her numbers move into scene properties.

**Pearl.**
- She shrinks into an ordinary orb-weaver and flees. She never respawns.
- The canopy falls and shows Pearl 2. W on it plays the Pearl card and grants **Silk Reel** (the suck reaches 160 px and pulls across water, holes and bars).
- A full boss heart (+20) appears.
- The root lift goes to the forecourt (arrival at about (3060, 980)).

**The iron hollow (The Sealed Hollow).**
- The Stone form on the plate (2880, 3016) opens the gate (2880, 2816).
- Inside:
  - GQ2 at about (2720, 2464);
  - **Kiri's war cache** at about (2880, 2560), with the Weaver Hollow map and Kiri's note about the stump, the web door and "an axe-memory below".
- Remove `hollow-ore-pile-1` and `-2`.
- `iron-1..3` say "Too hard. Something heavy could crush it." until the Hammer. A later Hammer prize waits behind one of them.

**The east-road curtain.**
- A side-view thick web, about 256 px tall, at about (3330, 1728), in front of `exit-1` (3440, 1728). The arrival `player-entry-east` (3200, 1728) stays on the forest side.
- Only the Axe opens it, for good (flag `web-cut.gloop-forest.east-curtain`).
- Mossy points at it after the Pearl. The atlas session updates the "Crystal seal" note.

## 8. The Q mouth and the Ability Box

Moved to the main plan, [2026-10-11-body-shapes-plan.md](2026-10-11-body-shapes-plan.md) sections 5 and 6, so the rules live in one place.

## 9. Quest chain

| Quest | Status | Steps | Reward |
|---|---|---|---|
| `slime-basics` | Rewrite (v3) | Giver Plop (it was automatic). Accepting gives the 10-slot bag (a new accept-time grant). Open the bag, journal and map, and pause. Turn in at Plop; his last line sends the slime to Lili | 10 coins |
| `what-the-old-slimes-hid` | **New** (Lili; the plan's Plop quest moves to her) | Needs area-entered level-1. One stage: discover-area `yoi-hideout`, which counts if the hideout was found first. Completes automatically | 10 coins |
| `the-thorn-guard` | **New** (Yoi) | Needs area-entered `yoi-hideout`. Talk, then npc-turn-in at Yoi | `shape-spear` (New shape) |
| `a-tonic-for-lili` | Rewrite (v2), prerequisite only | Needs `what-the-old-slimes-hid` completed. Craft a Slime Tonic | 2 berries |
| `snack-for-the-road` | Keep | Craft a Berry Basket; the text names the woodpile | 25 coins + 1 potion |
| `worm-trouble` | Rewrite (v3) | Needs `the-thorn-guard`. Delete `arm-yourself`. Kill 3 worm swordsmen. Turn in at Mossy (new line: something drove the worms out of their burrow) | 30 coins + flag `lair-barricade-down` |
| `spiders-in-the-webwood` | **New**, optional (Sunny) | Needs `worm-trouble`. Kill 3 slime-spiders in the Webwood. Turn in at Sunny, in town or at the camp (same NPC id). She hints at "a web nothing can tear" | 20 coins + 1 potion |
| `a-home-of-your-own` | **New**, optional (Plop) | Needs `worm-trouble`. Enter `slime-home`, use the bed, find the vault (needs new emitters and the vault work 5.8) | 10 coins |
| `the-one-eyed-guardian` | Rewrite (v2) | Needs `worm-trouble`. Stages: discover-area `fatty-lair`, defeat-boss `fatty-one-eye`, activate-object Pearl (flag `pearl.fatty-one-eye`). Turn in at Plop | 100 coins + `chapter-1-complete`. The Slam comes from the Pearl, and the green key and boss heart are in the lair |
| `the-old-workshop` | Park | Needs a Chapter 3 flag | — |
| `a-place-to-work`, `stone-tools` | Delete (retire) | Into `RETIRED_IDS` | — |
| `beyond-the-verdant-gate` | Rewrite (v3) | Needs `the-one-eyed-guardian`. Kill 5 orb-weavers; no fangs; "step aside" instead of "roll aside" | 30 coins (no Lash, no recipe) |
| `tom-in-the-web` | Keep (text v3) | Free Tom "with your spear". Tom's lines teach the Q holds | `swallow` + 20 coins |
| `the-sealed-hollow` | **New** (Mossy), replaces `a-harder-pick` | Needs `tom-in-the-web`. Stage 1: open the hollow (Stone form on the plate). Stage 2: open Kiri's cache. Completes at Mossy | 20 coins (the cache holds the map and the note) |
| `the-matrons-nest` | Rewrite (v2) | Needs `the-sealed-hollow`. Stages: discover-area `weaver-hollow`, defeat-boss `orb-weaver-matron`, activate-object Pearl (flag `pearl.orb-weaver-matron`). Turn in at Plop. The offer loses "An iron spear!" | 100 coins + `chapter-2-complete`. The War Axe comes from the big chest, Silk Reel from the Pearl |
| `cut-loose` | **New**, optional (Tom) | Needs flag `learned.shape-axe`. Cut 3 cocoons holding Tom's friends (about (730, 2663), (2080, 2583), (2806, 697)) | 30 coins |
| `a-harder-pick`, `iron-gear` | Delete (retire) | | — |
| `rekindle-the-forge` | Park | Needs `learned.shape-hammer`; the story is rewritten later (the Forge tempers shapes) | — |
| `sunnys-basket` | Come-back after Pearl 2 | Needs Silk Reel (Pearl 2), so it ends right after the Matron. The basket stays in sight at (1696, 168), and Sunny teases it until then | 20 coins + 2 berries |

The total is 14 active quests (9 in Chapter 1, 5 in Chapter 2), 3 parked and 4 retired.

New quest code:
- an accept-time grant (the bag);
- `_apply_known_facts` for every stage, not only the first;
- `OBJECT_ACTIVATED` from the Pearl, cocoons, secret covers, the bed and the vault;
- a flag `learned.<ability id>` set when an ability is learned;
- the plan's "never ignore a refused reward" fix;
- the header count in `quest_catalog.gd`.

## 10. Materials, crafting and come-back secrets

**Materials and crafting left.**
1. **Wood:** only the Berry Basket uses it (5). The 4 woodcutter-yard piles (about 40) cover Chapter 1, and after the Axe each tree gives about 10.
2. **Stone and iron ore:** no use in Release 1. Delete `level-1-loose-stone-01/-02`, `hollow-ore-pile-1/-2`, and the ore and charcoal in the cavern chest. The nodes stay as "A hammer could crack this" markers.
3. **Berries:** the Slime Tonic (3) and the Berry Basket (2 + 5 wood) are the only recipes, in the bag's Crafting tab.
4. **Deleted:** charcoal, iron bars, weaver fangs, silk clumps, the workbench, the camp bench (1880, 1712), 13 recipes, and the iron bars in the Matron's chest.
5. **Kept for later:** crystal shards (a Glow teaser). Essences can be carried in the bag. After the Hammer, the Forge tempers shapes with ore and stone, and the Workshop makes box gadgets.

**Heart quarters.**
- **Slimeshire:**
  - HQ1: the hideout brick nook (mouth, Chapter 1);
  - HQ2: the well cellar (Slam, after Fatty);
  - HQ3: the smith's storeroom (Stone form, Chapter 2);
  - HQ4: the hideout store room (Axe, Chapter 2).
- **Gloop Forest:**
  - GQ1: the silk nook (800, 1176), Silk form;
  - GQ2: the iron hollow, Stone form on the plate;
  - GQ3: the Gloop Cavern (1216, 420), Stone-form Slam;
  - GQ4: a cocoon at about (2806-2900, 640-700), Axe.
- **Boss hearts:** one after Fatty, one after the Matron.
- **Retired:** the Goo Hearts `meadow-lakeside` (176, 3040) and `meadow-autumn-thicket` (3300, 3190). Their spots become later Swim and Hammer secrets.

**Come-back secrets, by what opens them.**
- **Mouth (Chapter 1):** the hideout nook (HQ1); the lair's pantry alcove (the map).
- **Slam (after Fatty):**
  - the well-cellar hideout, through a stuck hatch by the Wishing Well (723, 851), for HQ2;
  - tree shakes for berries;
  - the lair's worm drum.
- **Stone form (Chapter 2):**
  - the smith's storeroom plate by the Forge (1190, 1068), for HQ3 and Pip's letter;
  - the lair's sump niche;
  - the iron hollow (GQ2);
  - the Gloop Cavern (GQ3 and the 20-slot bag).
- **Silk form:** the silk nook (GQ1); the Webwood ground webs (2380-2700, 300-420) leading to the dead tree (2214, 332) and coins.
- **Axe:**
  - the hideout store room (HQ4);
  - the Webwood thick-web coffer (around (2528, 307));
  - a west-meadow tree coffer;
  - vines over the Worm Ruins arch (a lore room);
  - the lair's R1 niche;
  - the forecourt cocoon (GQ4) and Tom's 3 cocoons;
  - the NE thicket web cache (around (2976-3232, 568));
  - a webbed hollow log in the SW thicket;
  - the Weaver Hollow's S1 and web shortcuts;
  - the east-road curtain (the way to Chapter 3).
- **Spin (the Axe's charge):** a silk knot by the forest camp hides a chest.
- **Silk Reel (Pearl 2):** Sunny's basket across the north stream (1696, 168), pots on islets, message bottles in Slimeshire's lake.
- **Later:**
  - Hammer: stone and iron nodes, the prize behind an iron node in the hollow, a boulder-sealed hideout at the autumn thicket, the Forge and the Workshop;
  - Lash: Sunny's basket and bells across water;
  - Swim: a lake-grotto hideout by the fisherman (1350, 732), the north stream's far bank, the Weaver Hollow's S3;
  - Stone-form Roll: cracked walls in both dungeons (open question 26).

## 11. What must be built

**Systems**
- Q mouth rework (`mouth_hold.gd`, the ring, constants, input removal, prompts, hints): **M**
- Ability Box (tab, R, HUD Ability slot, loadout, auto-select): **M**
- Dungeon core (definition, rooms, controller, room camera and curtain, RunState dungeon state, death at the entrance, area titles): **L**
- Dungeon doors, plus `gate.gd` `close()` and saved state: **M**
- Dungeon chests, Pearl pickup, boss full heart: **M**
- Strike-switch exports on `lash_bell.gd` (tag, for good, timed, group): **S**
- `secret_cover.gd` and the secret hatch: **S**
- `RoomEncounter` (ambush, clear, shutters): **M**
- `boss_camp.gd` `once` and the shutter links: **S**
- Thick web, cocoon, tether, egg sac, with the Axe's cut tags (depends on the shapes rework): **M**
- In-scene stairs, warps and floor drops: **S**
- Minimap room fog and the key readout: **M**
- Quest code (accept grant, known facts, emitters, `learned.*` flags): **M**
- Heart quarters and full hearts (roadmap 5.3); bags (5.7): **M** each
- Fatty phase 2 and the defeat shrink: **M**
- Matron rework (canopy, tethers, sweeps, climb, spin, flee): **L**
- Shape charges (Lunge, Spin, Quake smash), from the start: **M** (on top of the shapes rework itself, **L**, from the plan)
- Silk Reel (suck range and a rule for bars): **S**
- Enemies: Squint and Big Squint **M**, Silk Lurker **M**, Broodling **S**, Brood Warden **M**
- Dev: `dungeon-lab.tscn`, `build_dungeon.gd`, `check_dungeons.gd`, launch options: **M**

**Worlds**
- `yoi-hideout` (48 x 28): **M**
- `fatty-lair` (48 x 42, 10 rooms, two heights): **L**
- `weaver-hollow` (96 x 28, 12 rooms, three floors): **L**
- `well-cellar` and `smithy-store` (one-room hideouts from a room template): **S** each
- Level-1 edits (hatch, pots, burrow mouth and barricade, the camp removed, well hatch, storeroom plate, Webwood web, vines, loose stone removed, two Goo Hearts retired): **M**
- Gloop Forest edits (web door, stump, nest camp and heart removed, curtain, cocoons, Kiri's cache, GQ2, ore piles and bench removed): **M**
- Gloop Cavern chest (20-slot bag, potion) and a mural: **S**

**NPCs and art**
- Yoi: still, NPC entry, dialogue: **S**
- Dialogue rewrites for Lili, Mossy, Tom, Sunny and Plop; Kiri as lore: **S**
- Grey-box first, then art (after the playtest), **L** in all:
  - door set (shutter, key lock, boss lock, sealed; 4 facings);
  - small and big chests;
  - stone eye, gong and weaver's eye;
  - Pearl with a glow;
  - floor hatch, burrow mound and plank barricade;
  - thick web (front) and curtain (side);
  - tethers, cocoons, the Great Stump;
  - burrow and hollow wall dressing;
  - Squint, Lurker and Warden looks;
  - map icon.

**Sounds:** **M**
- SecretFound (original);
- ShutterClose and ShutterOpen, KeyUnlock, BossDoorOpen, ChestOpen and ItemGet;
- SwitchHit, EyeOpen and EyeShut, a gong;
- GulpHold, GulpSwallow, GulpPuff;
- web cut, tether snap, canopy crash, sweep, spin;
- one music loop per dungeon.

**UI:** **M**
- the Ability Box screen and HUD slots;
- the key counter and minimap fog;
- the Pearl and "New shape" cards;
- control labels and hints;
- the gulp prompts.

**Docs and tests:** **M**
- New: `docs/godot/DUNGEONS.md` and `specs/dungeon.md`.
- Specs to update: boss, matron, abilities, quests, world-objects, interaction, audio, water.
- Story docs: 01, 03, 04, 05, 06 and both chapter docs.
- `MOUSE_CONTROLS.md`, `GAME_GUIDELINES` (Gulp) and the main plan.
- Tests: new ones for each new system. Rewrites of the tests that use the open-world camps (`test_boss`, `test_matron`, `test_chapter_one_flow`, `test_quests`, `test_map`, `test_audio`, `test_chest_window`), plus `test_gulp`, `test_ability_bar` and `test_mouse_controls`. None of them run until the owner asks.

## 12. Open questions for the owner

1. **Pearl 2 and the Roll.** Answered in part: charges come with every shape from the start, so Pearl 2 no longer gives the Spin. *Default now:* Pearl 2 gives Silk Reel, and the Roll comes in Chapter 6 (the Desert) on its own key D; see the [power curve](2026-10-11-world-power-curve.md).
2. **Fatty's Lair item.** *Default:* no new item. A big key opens the boss door, and Fatty's phase-2 clods are light, so the mouth dazes him. *Other option:* the Heavy Gulp, the first of the two planned lift upgrades, in the Larder. It would open heavy-block secrets in Slimeshire, but boulders still wait for the Hammer.
3. **Dungeon rules.** *Default: yes to all:*
   - a Zelda room camera (a scroll, a dark curtain, no zoom inside);
   - small keys counted per dungeon and shown by the minimap, never bag items;
   - one big key per dungeon;
   - the map in a chest (the compass later);
   - dying inside wakes the slime at the entrance with keys and opened doors kept;
   - room enemies come back, while puzzles and ambushes stay done.
4. **Q details.** *Default: yes to all:*
   - one long hold works (suck an essence in and keep holding; it is swallowed 2 s after the catch);
   - in a form with an empty mouth, Q sucks for 0.25 s first, then becomes the spit ring;
   - letting go between 0.25 and 2 s cancels;
   - the slime stands still while the ring fills;
   - 2 s for both, tuned in the playground;
   - the throw happens on release, as you said.
5. **The key-item rule.** *Default new wording:* "Each region has one key item. It opens the region's dungeon or is found inside it, and the boss needs it." In Chapter 1 that is the Spear. In Chapter 2 Swallow opens the Weaver Hollow, and the Axe is found inside. *Other option:* name only the Axe as Chapter 2's key item.
6. **Hearts.** *Default:* four quarters per region, its caves and dungeons included, plus a full heart (+20) per boss, so max HP is 180 at the end of Chapter 2. *Other option:* each cave and dungeon hides its own four.
7. **Chapter 2's step after Tom.** *Default:* The Sealed Hollow. The Stone form presses the plate, and Kiri's war cache holds the dungeon map and a note (Kiri is Yoi's comrade, lore only). The Gloop Cavern stays an optional secret with the 20-slot bag. *Other option:* the cavern on the main line ("The Humming Ground") and the hollow optional.
8. **Pearl homecoming.** *Default:* both Pearl quests end with Plop in Slimeshire, and he tells a piece of the story. The Pearl sinking into the Wellspring waits for the Wellspring map. *Other option:* each chapter ends inside its dungeon.

## 13. New conflicts the build must fix

Plan section 14 items 4, 6 and 7 are no longer conflicts: the Slam must *not* break rocks, the Forge is parked, and the loose ore is deleted. Item 15's "Silk Armor" wording now also needs the two web kinds (plain and thick). These are new:

1. **`boss_camp.gd` has no "never again" mode.**
   - On defeat it sets a respawn time (`respawn_ms`: 180000 for Fatty, 300000 for the Matron).
   - `NO_RESPAWN` (-1) means "may spawn now" (`BossArena.spawn_eligible` returns true), so it cannot be used for a beaten dungeon boss.
   - A `once` export that checks `is_boss_defeated()` is needed.
2. **`world_definition.gd` `validate()`** accepts only `follow` and `fixed` (lines 70-71).
3. **`world_camera.gd`.** `center_on` pins the left and top edge when the view is larger than the bounds (lines 200-201), and zoom goes from 0.5 to 1.25. So rooms are not centred, and the next rooms show.
4. **Death** goes to the last bed, even in another world (`player.gd:751-758`, `main.gd:266 respawn_in_world`).
5. **`gate.gd`** has no `close()`. Plates and bells open gates "for this visit only, nothing saved" (lines 6, 78).
6. **`pressure_plate.gd`** feels only a Heavy (Stone-form) slime.
7. **`lash_bell.gd`.** `lash_only` is true by default. With it off, `can_receive_damage` accepts every hit (thrown pots, the Slam), and nothing is saved.
8. **`spider_web.gd`.** `tears_when_crossed` defaults to true, so a Silk puzzle would work only once.
9. **`liftable.gd`.** Liftables are part of the world scene and come back on every entry, so secret covers need a flag and a StoryVariant.
10. **Quests have no accept-time grant.** No quest JSON has one, and the bag system is not built (20 slots from the start). Chests move stacks into the bag, so the hideout chest needs a no-bag case.
11. **`OBJECT_ACTIVATED`** is emitted only by `restoration_site.gd:118` and `tom_web.gd:127`.
12. **`area_titles.gd`.** Interiors get a title-cased id unless AREAS has an entry.
13. **No Wellspring object or map exists** in any scene. `02-premise.md` puts it on a new map east of level-1. Pearl turn-ins go to Plop until it exists.
14. **`gulp_controller.gd` `swallow`** drops the old form's essence with the 3 s `popGrabMs` fade, even on a deliberate swap (lines 47-48).
15. **`player.gd` Q handling.**
    - Q with an essence spits on the *press* (lines 1317-1326); the new rule spits on release.
    - Q with an empty mouth sucks in *any* form today, so a Dungeon 2 design note was wrong to say "a slime in a form cannot suck". The suck-first rule keeps this.
16. **Input code.**
    - `project.godot` has `swallow` 1, `dodge` 2, `stretch_lash` 3, `squash_slam` 4, `teleport` 5.
    - `ability_definitions.gd` `BAR_SLOTS` and `DISPATCH_ORDER` list the old five.
    - `key_bindings.gd` LAYOUT rebinds only the move, attack, interact and weapon actions.
17. **Open-world bosses and their chests.**
    - `level-1` `Encounters/level-1-fatty-one-eye-camp` (2528, 1472), with the green-key chest at (2528, 1077).
    - `gloop-forest` `matron-nest` (3120, 940), with the iron-bar chest and the +10 `matron-goo-heart` (3120, 800).
    - `goo_heart.gd` still gives "+10 max HP". The quarter rule (+20 per heart) is not built.
18. **`world-map.json`** (the atlas session's file):
    - Slimeshire's interiors are only `slime-home` and `mushroom-home`; Gloop Forest's are `gloop-hut` and `gloop-cavern`;
    - the Fatty marker says "Guards the chest with the green key";
    - the Matron marker says "web door: Silk Armor (Planned)";
    - the Crystal seal says "open without a key for now".
19. **Story docs.**
    - `03-world.md` says "Dungeons: None are built yet... from Chapter 3 on", calls the Crystal Caverns the first dungeon, and counts "four heart quarters per map".
    - `05-unlock-map.md` lines 22 and 32 say Pearl 2 grants Stretch Lash.
    - `01-direction.md`'s 2026-10-08 rows still say "Roll on key 2" and "Swallow before the iron hollow".
20. **The key-item rule.** `01-direction.md` ("one key item per region; the boss requires it") and `03-world.md` (the key item in the middle of the dungeon) do not fit a Chapter 2 with both Swallow and the Axe (question 5).
21. **Quest data.**
    - `stone-tools` is the only `dodge` grant.
    - `the-one-eyed-guardian` grants `squash-slam` as a quest reward and ends with a `verdant-gate` discover stage; both move to the Pearl and the green-key chest.
    - `slime-basics` is automatic and needs `a-place-to-work`.
22. **Names.** Lili now leads the first quest, so the Lili and Lily clash (`06-open-questions.md` Q7) mattered. The owner decided (2026-10-11): Lily the fisher becomes **Dora**. Her NPC id `fisherman-slime` stays; her display name, dialogue and the docs change.
23. **03-world rule 5** ("bigger caves are made of whole screens") must be checked for every new interior. The one-room hideouts fit in one screen (16 x 14 at most).