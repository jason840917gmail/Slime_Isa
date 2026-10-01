# Chapter 2 Outline — Gloop Forest (roadmap 8.1)

## Status

**Built 2026-10-01** (roadmap 8.3–8.11; see the roadmap entries for what was
played and what is open). Where the build differs from this draft, the
draft below has been corrected: the camp is the walled clearing at the forest's
heart, the Forge is an outdoor furnace beside the player's home (the red forge
house is the home), Sunny's stream is at the north edge, and the Matron has her
own spec ([2026-10-01-orb-weaver-matron.md](./2026-10-01-orb-weaver-matron.md)).

Draft, 2026-09-30, for the owner's review before 8.2–8.11 are built. Nothing
here is registered in the quest catalog yet: `validateQuestCatalog` requires
every item, recipe and NPC a quest names to exist, and most of Chapter 2's
items (enemy material, iron bar, iron gear) arrive with 8.3–8.6. The quests
below become `content/quests/quests/chapterTwo.ts` as those tasks land (8.10).

Follows the Gulp verdict (7.0, "I like the Gulp"): Heavy and Sticky are the
chapter's two forms, and the boss fight is built around Sticky.

## Premise

Past the Verdant Gate, Gloop Forest is choked with webs. Orb-weaver slimes
spin them, and their Matron nests deep in the north-east. The forest holds
iron, but iron is too hard for stone tools, and Slimeshire's Forge has been
cold since the worms came. The slime needs metal gear to reach the nest.

Chapter goal in one line: **fight orb-weavers for their fangs, make a
Reinforced Pickaxe, mine iron, rekindle the Forge, forge iron gear, and break
the Matron's web.**

**2026-09-30: the Workshop moved after Chapter 2** (owner: it comes too
early; it should be a later upgrade of the workbench once the Forge makes iron
bars). Chapter 2 crafts at the workbench and restores the Forge; nothing here
needs the Workshop any more.

## Places

- **Gloop Forest** (`gloop-forest`, 54 × 54, today: decoration, walls, two
  exits, no NPCs or enemies):
  - **Forest camp**, the walled clearing at the forest's heart (east along the
    path from the Verdant Gate): Mossy, Sunny, a workbench, a campfire and the
    hut (the blue cottage; 8.8, bed = respawn). Safe zone.
  - **Weaver thickets** (two or three spawn areas, 8.2) between the camp and
    the rest of the forest.
  - **Iron hollow**: iron nodes (8.4) behind a Heavy plate gate (puzzle 1).
  - **Silk nook** (north-west): a walled nook behind a spider web only the
    Sticky form crosses, with a Goo Heart inside (puzzle 2).
  - **Cracked clearing**: cracked ground over a small cavern with the second
    Goo Heart and a chest (puzzle 3, reusing 7.4).
  - **The Matron's nest** in the north-east: the boss arena (8.7).
  - **The Crystal Caverns exit**: stays locked, "Chapter 3" (8.11).
- **Slimeshire** (`level-1`): the cold Forge, an outdoor smelting furnace in
  the forge yard beside the player's home, is restored in this chapter (the red
  forge house itself is the home: its door leads to the Slime Home). The Workshop ruin
  stays as it is until after Chapter 2.

## Characters

Existing sheets only, no new NPC art:

- **Mossy** (scout) moves from the Meadow to the forest camp once
  `chapter-1-complete` is set (a 6.1 story variant in each world). Main-line
  giver in the forest.
- **Elder Plop** stays in Slimeshire: the Forge and the iron gear.
- **Red Slime Boy** becomes **Pip**, the smith's son, who has wanted to light
  the Forge again; he gives the Forge quest (a name change in
  `NpcDefinitions.ts`, a conversion input).
- **Yellow-Blond Slime Girl** becomes **Sunny**, who gives an optional quest
  (her basket is stuck on the far bank of a stream).

## Quests

Six quests, all with objective kinds that already have producers (talk,
kill, collect, craft-item, activate-object via restoration sites, defeat-boss,
discover-area).

| # | Quest | Giver | Needs | Objectives | Rewards |
|---|---|---|---|---|---|
| 1 | **Beyond the Verdant Gate** (main) | automatic on entering Gloop Forest, turned in to Mossy | `the-one-eyed-guardian` | Talk to Mossy at the forest camp; rest in the hut bed (sets respawn; a `rest` objective needs a small producer, else "talk to Mossy" only); defeat 3 orb-weaver slimes | 30 coins; **Stretch Lash** (Mossy shows how to pull things across water); Mossy explains fangs and iron |
| 2 | **A Harder Pick** (main) | Mossy | Q1 | Collect 3 weaver fangs (8.3); craft the Reinforced Pickaxe at the workbench; collect 6 iron ore | recipe unlock is the pickaxe itself; 20 coins |
| 3 | **Rekindle the Forge** (main, 8.5) | Pip (Slimeshire) | Q2 | Restore the Forge (restoration site: 40 stone, 20 wood, 6 iron ore); smelt 2 charcoal and 3 iron bars | Forge recipes; 40 coins |
| 4 | **Iron Gear** (main, 8.6) | Elder Plop | Q3 | Craft an Iron Spear at the workbench (4 iron bars) | Iron Axe recipe learned; 40 coins |
| 5 | **Sunny's Basket** (optional) | Sunny (forest camp) | Q1 | Pull her basket back across the stream with the Stretch Lash (a collectible on the far bank) | 2 purple berries; 20 coins |
| 6 | **The Matron's Nest** (main, 8.7) | Mossy | Q4 | Defeat the Orb-Weaver Matron | Goo Heart (her chest), **Squash Slam**, 100 coins, flag `chapter-2-complete` (end card, 8.11) |

Notes:

- **As built (2026-10-01):** Q1 is offered by Mossy at the camp rather than
  started automatically (an automatic first stage "talk to Mossy" would be
  filled in at once from Chapter 1, where the player already talked to
  Mossy). It has no rest objective, and it also teaches the Reinforced Pickaxe
  recipe, so Q2 starts with the fangs. Q3 teaches the Iron Spear and Q4 the
  Iron Axe. Q5's stream is at the north edge.
- **No Workshop in Chapter 2** (changed 2026-09-30). Question 1 had made The
  Old Workshop required; the owner then moved the Workshop after Chapter 2,
  so Q2 and Q4 craft at the workbench.
- Stretch Lash (question 3, answered: option B; reworked 2026-09-30) is a
  goo hook with no damage: a pickup it touches flies back to the slime, and
  anything solid it catches pulls the slime across to it, over water too;
  bell posts it catches ring and open gates. Chapter 2's puzzles use it, so
  the main line teaches it (Q1's reward).
- Squash Slam comes from the boss, as the ability bar already says.

## Materials and where they come from

Every recipe input has a renewable source (5.5 regrowth or respawning
enemies), so nothing softlocks.

| Material | Source | Notes |
|---|---|---|
| Wood, stone | trees and rocks in both maps (regrow) | as today |
| **Weaver fang** (new, 8.3) | orb-weaver slimes only, e.g. 60 % per kill | the only enemy-only material |
| Iron ore | iron nodes in the iron hollow (Reinforced Pickaxe, regrow) and two loose piles | `iron-ore` exists |
| Charcoal | Forge recipe (wood → charcoal) and a few loose piles | `charcoal` exists; the recipe makes it renewable |
| **Iron bar** (new, 8.5) | Forge only | never a weapon |
| Silk clump | slime spiders (Webwood) and the forest's silk cocoons | exists; Sticky form |

## Recipes

| Recipe | Station, tier | Inputs | Output |
|---|---|---|---|
| Reinforced Pickaxe (8.4) | Workbench | 10 wood, 15 stone, 3 weaver fangs | breaks iron nodes |
| Smelt Charcoal | Forge 1 | 5 wood | 2 charcoal |
| Smelt Iron Bar | Forge 1 | 2 iron ore, 1 charcoal | 1 iron bar |
| Iron Spear (8.6) | Workbench | 10 wood, 4 iron bars | beats an orb-weaver in fewer hits than the Stone Spear |
| Iron Axe (8.6) | Workbench | 10 wood, 3 iron bars | faster chopping, some combat |

The iron recipes are workbench recipes taught by Q3 and Q4 (`learnedByQuest`),
so they stay locked until the Forge burns. The Workshop and its second tier
come after Chapter 2.

## Enemies and the boss

- **Orb-weaver slime** (8.2; its sheet is the Meadow spider's art today, see
  question 5): keeps its distance,
  spits webs (the existing web projectile and web-cover effect root the
  player briefly), drops weaver fangs. Two or three spawn areas outside the
  safe zones; none in the iron hollow or the camp.
- **Orb-Weaver Matron** (8.7, Fatty model): a telegraphed web volley that
  leaves web patches on the arena floor (the 7.2 web barrier as a ground
  hazard); a normal slime is caught in them, a Sticky one crosses. A silk
  cocoon Gulp spot at the arena edge keeps the fight solvable without carried
  silk. Every attack telegraphs for at least half a second. Chest: a Goo
  Heart. Short spec before building, as the roadmap asks.

## Gulp puzzles (8.9)

1. **Iron hollow gate** (Heavy): a pressure plate opens the hollow's gate
   (`Opens Gate ID`, 7.3); a stone Gulp spot beside it.
2. **Silk path** (Sticky): webs across a narrow path; a silk cocoon at its
   start; Goo Heart and Sunny's basket at the end.
3. **Cracked clearing** (Heavy): cracked ground over a small cavern with the
   second Goo Heart and a chest; the ladder climbs back up (7.4 pieces).
4. **Bell across the stream** (Stretch Lash): a lash bell post on the far
   bank opens the iron hollow's back gate and pulls the slime across; a
   stump or statue on each bank is the hook back. Sunny's basket waits on
   the far bank (Q5).

## Balance targets

- About 25–40 minutes for a first-time player (the release target is 45–75
  minutes for Chapters 1 and 2 together).
- Iron Spear: an orb-weaver in 2–3 fewer hits than the Stone Spear.
- Orb-weaver web: roots for 0.9 s (as the spider web today), never stacks.

## Build order

8.2 orb-weaver (playground first) → 8.3 fang → 8.4 iron nodes and the
Reinforced Pickaxe → 8.5 Forge restoration → 8.6 iron gear
→ 8.8 forest hut → 8.9 puzzles and hearts → 8.7 the Matron → 8.10 the quests
above → 8.11 the locked exit and end card.

## Questions for the owner

1. Should **The Old Workshop** become part of the main line (for example,
   offered again at the start of Chapter 2 as mandatory when it is not done),
   or stay optional with Q2 simply waiting for it? (Answered 2026-09-30:
   **required**; then superseded the same day: the Workshop moved after
   Chapter 2, and Chapter 2 crafts at the workbench.)
2. **Pip** (Red Slime Boy) and **Sunny** (Yellow-Blond Slime Girl): happy to
   rename and give them these roles, or do you want new characters?
   (Answered 2026-09-30: either works; **reuse** these two sheets for Pip and
   Sunny, and make new art for any further characters.)
3. **Stretch Lash** from Sunny's optional quest, or from the main line (Q2)?
   (Answered 2026-09-30: **option B**, the lash is a tool as well: it pulls
   pickups across water and rings bell posts, so the main line teaches it,
   as Q1's reward. Built and playable in the playground's lash yard.)
4. **The Matron**: is a web-volley boss that you cross with the Sticky form
   the direction you want (the guidelines list the boss design as open)?
   (Answered 2026-09-30: **yes, for now**.)
5. **Orb-weaver art.** (Answered 2026-09-30: use the orb-weaver art for now;
   built in 8.2 as a larger, darker, tougher variant.) The green orb-weaver sheet is already the Meadow slime
   spider's look (an earlier, deliberate change); the old yellow spider sheet
   (same 8 × 10 layout) is unused. Should the Meadow spider go back to the
   yellow sheet so the orb-weaver is new in Gloop Forest, or should Chapter 2
   get a different new enemy with new art? (Answered 2026-10-01: the Meadow
   spider is yellow again, `character.enemy.meadow-spider`.)
