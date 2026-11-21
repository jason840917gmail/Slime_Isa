# Story — Index

> **Status: first draft, started 2026-10-02.** This folder is the story script
> of Slime Isa: what happens, why it happens, and where the slime earns every
> permanent item. It is written to be argued with. Most of the plot is still a
> proposal; the owner's answers in [Open questions](06-open-questions.md)
> turn proposals into decisions.

## Index

1. [Direction](01-direction.md): adventure first with a little crafting, the
   slime's two kinds of power (skins and abilities; shapes were dropped on
   2026-11-17), the throw as the fight, how a region plays, and the decisions
   in effect.
2. [Premise](02-premise.md): the story on one page, covering the
   Wellspring, the newborn slime, the goal and the ending.
3. [World](03-world.md): the regions in order, the world size and screen
   rules (8 × 8 chunks of 32 × 32 tiles, 16 × 14 tiles on screen), what has
   gone wrong in each region, where dungeons go, and the world map sketch.
   The sketch is drawn with `pnpm story:map` and saved as the game's world
   layout, `godot/game/data/world-map.json`; its picture,
   `world-map.png`, stays in this folder.
4. [Characters](04-characters.md): the slime, the people of Slimeshire, the
   bosses and the villain.
5. Chapters, one file each, after the
   [prologue](../design/2026-10-16-prologue.md) (Planned, the owner's of
   2026-10-16):
   - [Chapter 1 — The Clearing](chapters/chapter-1-the-clearing.md)
   - [Chapter 2 — Gloop Forest](chapters/chapter-2-gloop-forest.md)
   - [Chapter 3 — Crystal Caverns (sketch)](chapters/chapter-3-crystal-caverns.md)
6. [Unlock map](05-unlock-map.md): every permanent item, where and how it
   is earned, and what it opens. How maps teach, test and hide those powers'
   locks is the [level design guide](../design/2026-10-16-level-design.md).
7. [Open questions](06-open-questions.md): the decisions waiting on the owner.
8. [Decisions archive](07-decisions-archive.md): the answered questions, cut down to their
   decisions, with their numbers kept.

## Status tags

Every beat, item and idea carries one tag:

| Tag | Meaning |
|---|---|
| **Built** | In the game today. Quest text in code is the source for its dialogue. |
| **Rework** | Built in the rework mode ([BODY_SHAPES.md](../godot/BODY_SHAPES.md)). It has been the only game since 2026-10-24, with throw combat on top since 2026-11-01 ([THROW_COMBAT.md](../godot/THROW_COMBAT.md)), so Rework now reads as Built. |
| **Planned** | Decided by the owner, not built yet. |
| **Proposal** | A suggestion in this draft. It needs the owner's yes. |
| **Open** | Undecided. It is listed in [Open questions](06-open-questions.md). |
| **Idea** | From the roadmap's parking lot. Kept for reference, not committed. |

## How this folder relates to the other docs

- [Game Guidelines](../GAME_GUIDELINES.md) describe the game as it is designed
  today. The [Game Roadmap](../GAME_ROADMAP.md) owns task order. Anything
  tagged Planned here changes those docs only once the work is scheduled. Until
  then, both still describe the current build.
- The decisions of 2026-10-15 (skins from the Pearls, shapes instead of
  crafted weapons, the Goo Bomb, Swallow and essences marked for deletion) and
  the owner's answers to the review the same day (slow energy regeneration,
  Release 1 as Chapters 1 to 3, no harvesting, one game) are in the roadmap as
  tasks ([the 2026-10-15 decisions](../GAME_ROADMAP.md#the-2026-10-15-decisions)).
  The guidelines mark the parts these decisions replace, starting with their
  Gulp section, and link to [Direction](01-direction.md).
- The owner's answers of 2026-10-16 (the Feral skin from Pearl 3, the Roll
  from young Burr, the Heavy skin's Roll, one bag, Release 1's end, the
  Colossus's braziers and the smith's mine camp) are in the roadmap as tasks
  too ([the 2026-10-16 decisions](../GAME_ROADMAP.md#the-2026-10-16-decisions)),
  and so is their third round (climbable walls, the slabs' hazards and timing,
  the West village town and Release 1's borders, Plop's 10-slot bag, the Swim
  form kept as the Swim skin, the Bow from Burr, the Forge relit by Pearl 2,
  and the web-wall maze to the Crystal Caverns), and their fourth and fifth
  rounds (combos only in optional secrets; what the War Axe, the Heavy Roll
  and the Lantern each own; climbable walls; the Wilds' ways into the forest
  and the caverns; the West village shop; potions before the Forge; Pearl 1's
  well; and Release 1's eight powers, with the Bow in Chapter 3 and the War
  Axe and Stretch Lash saved for the next release), and their sixth round
  (the prologue and its lake, the Wellspring; Yoi's home; Plop at the town's
  edge; Tom's Goo Bomb and his maze; one shape; the river bridge; Burr's Bow
  from the Matron's thread; Pearl 1's homecoming; campfires and the well;
  then saving like Zelda, the prizes that were materials, the Clod Stomper,
  whole manuscripts, food at a campfire, the Slime Forge and the
  [bestiary](../design/2026-10-16-bestiary.md)'s 29 enemies), and their
  seventh round (manuscripts that teach recipes and lore; dungeons that
  resume at their entrance; the Pearls' power flowing from the Wellspring
  into the town; the Spear's upgrades after Release 1; chunk B4 shared by the
  prologue and the West village's town; the prologue's saving and HUD, Tom's
  lesson, the Weaver Hollow's heart quarter and the well's refill; the
  Spear-only bells; and enemies placed in the world, not spawned), their
  eighth round (a full heart from each boss; max energy from potions, the
  well and bosses; the energy rules and drops; no coffer in the Gloop Cavern; bells as a
  ranged lock for a thrown pot or an arrow, in place of the Spear-only
  bells; the level design guide's looks and first locks; a Roll that sticks
  in a floor web; the Matron at the top of the Weaver Hollow; the skeletons'
  story; the War journal page; and the Forge's strong potions), and their
  ninth round (the later vassals and their Swim, Polar, Sand, Cloud and Lava
  skins, and bells that stay open for good), and their tenth round (the
  Gloop Cavern kept as a small secret cave, grass cut by the Spear, wooden
  clappers as the worm army's alarms, and the refill pause).
- The owner's decision of 2026-10-17 (each Pearl found inside its dungeon,
  before the boss, who seals the exits; the dungeon's second half teaches the
  skin, and the boss fight is its exam) is in the roadmap too
  ([the 2026-10-17 decisions](../GAME_ROADMAP.md#the-2026-10-17-decisions)),
  with the three built dungeons' rework (12.8).
- The owner's answers of 2026-11-17, after the docs were checked against the
  build of 2026-11-14 (throw combat for good, skins and abilities with no
  shapes, abilities improved by upgrades found in secrets, the belt, Bob,
  Glimmerhill and its fountains, Burr's house in C4, a fallen tree for the
  Verdant Gate), are in the
  [decisions archive](07-decisions-archive.md#decisions-by-date). They are not
  in the roadmap yet.
- Dialogue already in the game lives in
  `godot/game/data/quests-main.json` (the main quest and Pip's Workshop),
  `quests-chapter-1.json`, `quests-chapter-2.json` and
  `godot/game/data/npc-definitions.json` (the NPCs' talks and tips). When a chapter file and the game
  disagree about something tagged Built, the game is right; fix the chapter
  file, or plan the change.

## Writing rules

- One chapter is one file. Each beat says where it happens, who is involved,
  what the player does, what they get, and its status tag.
- Every permanent item appears in the [unlock map](05-unlock-map.md).
- Dialogue stays short: one to three lines per page. Quest text never names
  keys, because the HUD shows the controls.
- Keep the tone cozy storybook. There is danger, but no gore, and bosses are
  beaten, not killed (see [Premise](02-premise.md#tone)).
