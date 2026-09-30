# Chapter 2 Outline — Gloop Forest (roadmap 8.1)

## Status

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
Reinforced Pickaxe, mine iron, rekindle the Forge, upgrade the Workshop, and
break the Matron's web.**

## Places

- **Gloop Forest** (`gloop-forest`, 54 × 54, today: decoration, walls, two
  exits, no NPCs or enemies):
  - **Forest camp** by the Verdant Gate entrance: Mossy, the hut (8.8, bed =
    respawn), a campfire. Safe zone.
  - **Weaver thickets** (two or three spawn areas, 8.2) between the camp and
    the rest of the forest.
  - **Iron hollow**: iron nodes (8.4) behind a Heavy plate gate (puzzle 1).
  - **Silk path**: a web-choked shortcut only the Sticky form crosses, with a
    Goo Heart at its end (puzzle 2).
  - **Cracked clearing**: cracked ground over a small cavern with the second
    Goo Heart and a chest (puzzle 3, reusing 7.4).
  - **The Matron's nest** in the north-east: the boss arena (8.7).
  - **The Crystal Caverns exit**: stays locked, "Chapter 3" (8.11).
- **Slimeshire** (`level-1`): the ruined Forge (the red forge house by the
  plaza is already a ruin) is restored in this chapter; the Workshop gets its
  second tier.

## Characters

Existing sheets only, no new NPC art:

- **Mossy** (scout) moves from the Meadow to the forest camp once
  `chapter-1-complete` is set (a 6.1 story variant in each world). Main-line
  giver in the forest.
- **Elder Plop** stays in Slimeshire: the Forge and the Workshop upgrade.
- **Red Slime Boy** becomes **Pip**, the smith's son, who has wanted to light
  the Forge again; he gives the Forge quest (a name change in
  `NpcDefinitions.ts`, a conversion input).
- **Yellow-Blond Slime Girl** becomes **Sunny**, an optional giver of the
  Stretch Lash quest (she lost her basket across a web gap).

## Quests

Six quests, all with objective kinds that already have producers (talk,
kill, collect, craft-item, activate-object via restoration sites, defeat-boss,
discover-area).

| # | Quest | Giver | Needs | Objectives | Rewards |
|---|---|---|---|---|---|
| 1 | **Beyond the Verdant Gate** (main) | automatic on entering Gloop Forest, turned in to Mossy | `the-one-eyed-guardian` | Talk to Mossy at the forest camp; rest in the hut bed (sets respawn; a `rest` objective needs a small producer, else "talk to Mossy" only); defeat 3 orb-weaver slimes | 30 coins; Mossy explains fangs and iron |
| 2 | **A Harder Pick** (main) | Mossy | Q1, **The Old Workshop** | Collect 3 weaver fangs (8.3); craft the Reinforced Pickaxe at the Workshop; collect 6 iron ore | recipe unlock is the pickaxe itself; 20 coins |
| 3 | **Rekindle the Forge** (main, 8.5) | Pip (Slimeshire) | Q2 | Restore the Forge (restoration site: 40 stone, 20 wood, 6 iron ore); smelt 2 charcoal and 3 iron bars | Forge recipes; 40 coins |
| 4 | **Iron for the Workshop** (main, 8.6) | Elder Plop | Q3 | Upgrade the Workshop (restoration site on the restored Workshop: 6 iron bars, 30 wood; flag `workshop.tier-2`); craft an Iron Spear | Iron Axe recipe learned; 40 coins |
| 5 | **Sunny's Basket** (optional) | Sunny (forest camp) | Q1 | Collect the basket across the silk path (a collectible behind the Sticky puzzle) | **Stretch Lash**; 2 purple berries |
| 6 | **The Matron's Nest** (main, 8.7) | Mossy | Q4 | Defeat the Orb-Weaver Matron | Goo Heart (her chest), **Squash Slam**, 100 coins, flag `chapter-2-complete` (end card, 8.11) |

Notes:

- **The Old Workshop dependency.** Q2 needs the Workshop, which Chapter 1
  offers as optional. If it is not restored, Q1's closing line sends the
  player to Elder Plop and the tracker shows The Old Workshop; open question
  below.
- Stretch Lash is a ranged lash (180 px, 18 damage), a good answer to
  orb-weavers that keep their distance; offering it from an optional quest
  keeps the main line short. Moving it to Q2's reward is the alternative.
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
| Reinforced Pickaxe (8.4) | Workshop 1 | 10 wood, 15 stone, 3 weaver fangs | breaks iron nodes |
| Smelt Charcoal | Forge 1 | 5 wood | 2 charcoal |
| Smelt Iron Bar | Forge 1 | 2 iron ore, 1 charcoal | 1 iron bar |
| Iron Spear (8.6) | Workshop 2 | 10 wood, 4 iron bars | beats an orb-weaver in fewer hits than the Stone Spear |
| Iron Axe (8.6) | Workshop 2 | 10 wood, 3 iron bars | faster chopping, some combat |

The Workshop upgrade itself is a second restoration site on the restored
Workshop (flag `workshop.tier-2`), and a story variant swaps its station for
a tier-2 one: the 6.3 pieces, reused.

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

## Balance targets

- About 25–40 minutes for a first-time player (the release target is 45–75
  minutes for Chapters 1 and 2 together).
- Iron Spear: an orb-weaver in 2–3 fewer hits than the Stone Spear.
- Orb-weaver web: roots for 0.9 s (as the spider web today), never stacks.

## Build order

8.2 orb-weaver (playground first) → 8.3 fang → 8.4 iron nodes and the
Reinforced Pickaxe → 8.5 Forge restoration → 8.6 Workshop tier 2 and iron gear
→ 8.8 forest hut → 8.9 puzzles and hearts → 8.7 the Matron → 8.10 the quests
above → 8.11 the locked exit and end card.

## Questions for the owner

1. Should **The Old Workshop** become part of the main line (for example,
   offered again at the start of Chapter 2 as mandatory when it is not done),
   or stay optional with Q2 simply waiting for it?
2. **Pip** (Red Slime Boy) and **Sunny** (Yellow-Blond Slime Girl): happy to
   rename and give them these roles, or do you want new characters?
3. **Stretch Lash** from Sunny's optional quest, or from the main line (Q2)?
4. **The Matron**: is a web-volley boss that you cross with the Sticky form
   the direction you want (the guidelines list the boss design as open)?
5. **Orb-weaver art.** The green orb-weaver sheet is already the Meadow slime
   spider's look (an earlier, deliberate change); the old yellow spider sheet
   (same 8 × 10 layout) is unused. Should the Meadow spider go back to the
   yellow sheet so the orb-weaver is new in Gloop Forest, or should Chapter 2
   get a different new enemy with new art?
