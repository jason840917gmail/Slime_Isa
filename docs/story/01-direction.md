# Direction

The game's backbone: what the game is, where the slime's powers come from, and
how a region plays. The dated decisions behind it are in [History](#history).
Story details are in [Premise](./02-premise.md); every permanent item and where
it is earned is in the [Unlock map](./05-unlock-map.md).

> **Status words.** *Built* is in the game. *Rework* is built in the **rework
> mode** (merged 2026-10-15): on in the playground, and in any world with
> `?shapes`; with it off the classic game runs unchanged
> ([BODY_SHAPES.md](../godot/BODY_SHAPES.md)). Once the three skins are built,
> the rework becomes the only game (owner, 2026-10-15). *Planned* is decided
> but not built. *Open* is not decided.

## The game in one line

Slime Isa is a top-down adventure in the spirit of Zelda. Gorge broke the
Wellspring's heart, the source of every new slime, into eight Pearls and gave
them to his eight vassals. The last slime born explores a growing world, wins
the Pearls back from those bosses and, with them, the powers that open new
places. A short prologue opens the game: the slime is born at the Wellspring,
learns to move and to gulp, saves the veteran Yoi from the worms and learns
the Spear from him (Planned, owner, 2026-10-16,
[prologue](../design/2026-10-16-prologue.md)). Crafting stays, but it is small, and it is not a survival game ("the
adventure version, with a little bit of crafting", owner, 2026-10-02). In
Release 1 it makes only potions and food, "maybe the vault", and nothing is
harvested (owner, 2026-10-15). Their ingredients are picked up or dropped, and
the vault waits for a later release (owner, 2026-10-16).

## The rule behind every chapter

> **Permanent things are earned and celebrated. Consumable things are crafted
> and farmed.**

| Permanent: earned once, kept forever, celebrated | Consumable: crafted or farmed, used up |
|---|---|
| Skins (from the Pearls) | Potions and food |
| Shapes (spear, axe, hammer, ...) | Energy shards |
| Abilities (Roll, Stretch Lash, Bomb, ...) | Charcoal, iron bars and other materials (none in Release 1, which has no harvesting) |
| Evolutions of shapes and abilities (after Release 1) | Anything that stacks in the bag |
| Bags and vaults | |
| Heart quarters and energy upgrades | |
| Keys and story items (Pearls, manuscripts) | |

Earning any permanent thing is a moment: the game pauses, the item rises out of
the slime with light rays and a fanfare, and a card shows its name, one line of
text and how to use it.

## Each thing is told apart

> **Each thing must be told apart. Different things never look alike, and
> options are sacrificed for clarity** (owner, 2026-10-16,
> [question 77](06-open-questions.md#contradictions-left-after-the-review-2026-10-15)).

- Each lock has one power and a look of its own, by what the thing is
  (owner, 2026-10-16, questions 92 and 93):
  - **the War Axe:** living, green things: trees in leaf, bushes, leafy
    vines, webs, tethers;
  - **the Heavy Roll:** old dead or built things that lie or lean in the
    way: grey leaning old trees, rotten trunks across a path, old fences,
    plank barricades, rotten mine timbers, loose rocks, rubble heaps. A Heavy
    Roll knocks the grey, leaning old tree over the river as a bridge
    (question 101);
  - **the Lantern:** dry plant growth (deadthorn, hay, dry roots, old
    banners), and the wood a Heavy Roll knocked down once it lies there;
  - **the Hammer:** big single boulders (question 77);
  - **the Spear:** a lever behind bars, which only a thrust reaches ("through
    bars"), first met at the prologue's gate (question 97).

  So the three woods have three looks: the Axe's are alive and green, the
  Roll's are old, grey and dead, and the Lantern's are dry growth.
- A climbable wall shows thick roots and rocky handholds on the cliff face;
  the Axe's vines are leafy curtains hanging in front of an opening
  (question 86).
- A climbable wall and a heavy block never stand side by side. Held W next to
  both does whichever the slime faces (question 91).
- When a new thing would look like another, it changes or it goes.
- The War Axe waits for the next release (question 94), so in Release 1 its
  locks are come-back secrets. Its living-tree bridge, a tree cut to fall
  over the water, may come back with it (question 101).

## The slime's powers

The slime has three kinds of power. Each has one source and one job.

| System | What it is | Where it comes from | Its job | Energy |
|---|---|---|---|---|
| **Skins** | A Pearl's power that becomes part of the slime: always on once learned, with no key. Each has its gate and a change to a move the slime already has ([The skins](#the-skins)). | One per **Pearl**: each of the eight bosses holds one | Open the next region, reach secrets in old ones, and beat later bosses | Free |
| **Shapes** | The slime shapes itself into a weapon or tool: spear, axe, hammer, ... They replace crafted weapons. Each has a combo chain and a hold-to-charge attack. | **NPCs** teach them, or **old manuscripts** the slime finds, whole or in pieces. In Release 1 NPCs teach and chests hold the finds; manuscript pieces come later. *Since 2026-10-16: Release 1 has whole manuscripts, each found in a chest as one find (question 65); what they teach is question 108 (Open)* | Fight and break (no chopping or mining: Release 1 has no harvesting) | Free; a charged attack costs energy |
| **Abilities** | Moves the slime uses at will: Roll, Stretch Lash, Goo Bomb, Lantern, ... All but the Roll share one key: the player picks which one it fires in the bag (the Ability Box), and the game pauses while the bag is open. The main path never needs a combo; a few optional secrets may combine a skin and an ability, each clearly different ([The skins](#the-skins); owner, 2026-10-16, question 84). | **NPCs** (taught, or rescued) and **manuscripts**; in Release 1 NPCs and chests, as for shapes | Movement, puzzles and the tools a boss needs | Every use costs energy; the quick Roll is free |

- **The Slime Forge** (a new building) evolves shapes and abilities. The slime
  stays at the Forge while it evolves, and it ends in the full ceremony.
  Evolutions come after Release 1 ("upgrades of skins and abilities come
  later in the game", owner, 2026-10-15). Skins do not evolve: only shapes
  and abilities do, and all of it comes after Release 1 (owner, 2026-10-16,
  question 67).
- **The Gulp** only grabs light objects (pots and the like, never a live enemy)
  and throws them.
- **Energy refills slowly by itself**, 1 a second ("energy can recover but
  really slow, like 1 per second; in addition we will add more ways to
  recover energy", owner, 2026-10-15). Potions and energy shards bring back
  more (a kill drops a shard now and then), so the player still chooses when a
  power is worth it. Planned:
  - refills that grow back (energy flowers or pots) through the world and in
    the dungeons' rooms, but not inside a boss chamber unless the boss makes
    minions the slime kills;
  - a full refill from beds, the Wellspring and Slimeshire's well once
    Pearl 1 restores it (a drink in town), and beds also restore life
    (owner, 2026-10-16, questions 62 and 105). There are no save points:
    like Zelda, the slime saves everywhere except inside dungeons
    (question 62). *Until 2026-10-16 the plan said "a full refill at the
    Wellspring and at save points".*
  - the quick Roll stays free, and no puzzle costs more than the starting max
    energy;
  - before more is built, one chapter's route is played and its energy
    counted.

  Max energy grows over the game.

### The skins

Like Zelda's flippers and gloves or Super Metroid's suits, a skin is never put
on or switched: once the Pearl is won, its power is part of the slime for good
(owner, 2026-10-15). The rules:

- **Contextual.** A skin acts in its own places and on its own move: its gate
  (a heavy plate, a web wall, a wall to climb) and one change to a move the
  slime already has (owner, 2026-10-15). It shows while it works: the slime
  turns stony as it grabs a block or stands on a plate, silky in a web, and
  shows claws as it climbs. The rest of the time the slime looks and moves as
  itself.
- **Pure additions.** A skin never has a downside (Heavy does not slow the
  slime down) and never clashes with another: each answers its own kind of
  place (webs, plates, walls to climb, water, lava, ...), so all of them stack.
- **No keys.** The controls stay attack, shape, mouth, ability, roll and
  interact, whatever the slime has learned. The Feral skin climbs with a held
  interact.
- **Gated by region.** Each region's places need its own skin, as Zelda gates
  with items, so having every skin on does not make later regions easy; their
  challenge is in fights and energy.
- **A look of one's own.** The player may pick a learned skin as the slime's
  everyday look (cosmetic only).

No ability is locked to a skin. The "depth from combos" rule (skins combined
with shapes and abilities) was dropped in the review of 2026-10-15 ("depth
from combos makes no sense to me, remove that", owner). *Open since
2026-10-16: the owner wants a few combos used wisely, such as a Heavy Roll
that knocks an old tree down into dry wood the Lantern burns ("we should not
abuse combos, but used wisely they bring more depth to the game"); how that
sits with this rule is question 84.* *Answered 2026-10-16 (owner, question
84): the main path never needs a combo. A few optional secrets may combine a
skin and an ability, and each looks clearly different. For example, a Heavy
Roll knocks down a grey, leafless, leaning old tree, made of old material the
Axe cannot cut, and the Lantern burns it once it lies there as dry wood.*

Why always on: no switching key or skin-ability key, no wrong-skin mistakes
that waste energy, and backtracking that just works. What it could cost, and
the rule that answers it:

| Risk of always-on skins | Answered by |
|---|---|
| Skins lose their trade-offs (the old Stone form was slow) | Contextual: a skin acts only in its own places and on its own move, so it never slows or limits the slime elsewhere |
| Skins clash when all are on (Heavy sinks, Cloud floats) | Pure additions: each answers its own kind of place, so they stack like Super Metroid's suits |
| Power creep late in the game | Gated by region: each region's places need its own skin; challenge stays in fights and energy |
| The transformation fantasy fades | A skin shows while it works, and the player can pick one as the everyday look |

The first three skins are Release 1's (owner, 2026-10-15):

| Skin | Pearl | Its gate | Its change to a move | Status |
|---|---|---|---|---|
| **Heavy** | 1, Fatty One Eye | Sinks the heavy plates, and moves statues, pedestals and blocks | A Roll that hits a wall, a tree and so on shakes things loose, so objects fall, and it breaks the small loose things lying in its way: a loose rock, a rubble heap, a rotten trunk across a path (owner, 2026-10-16, question 77). It also knocks down or breaks the old dead or built things that lie or lean in the way: grey leaning old trees, old fences, plank barricades, rotten mine timbers (owner, 2026-10-16, question 93). It knocks the grey, leaning old tree over the river as a bridge (owner, 2026-10-16, question 101). Its screen shake is strong; without the Heavy skin a Roll's bonk shakes much less (owner, 2026-10-16). It does not push enemies away: that is a later upgrade from another skin | Planned as a skin. Rework: the heavy plates and the pushable pedestal and statue work, but for the Stone form, still swallowed from a stone essence (and slower); the Roll still bonks off enemies, its bonk only wobbles things, and the Goo Bomb, not the Roll, breaks rubble heaps |
| **Silk** | 2, the Matron | Passes web walls at −50% speed, and webs no longer slow it. A maze of web walls leads to the Crystal Caverns, so the skin opens Chapter 3 (owner, 2026-10-16, question 81). From the Wilds a second web maze leads into Gloop Forest, and only the Silk skin passes it (owner, 2026-10-16, question 87) | The shapes cut webs, which they cannot do before the Silk skin. In Release 1 that is the Spear, the only shape (owner, 2026-10-16, question 94) | Planned. Web walls and the 50% slowdown are not built; today the Silk form, from a silk essence, passes webs |
| **Feral** | 3, the Crystal Colossus | Climbs some walls it could not climb before, which opens the world. A climbable wall looks different from the others: thick roots and rocky handholds on the cliff face (owner, 2026-10-16, questions 68 and 86; first described as vines and irregularities), while the Axe's vines are leafy curtains hanging in front of an opening. The player holds W (interact) to climb, claws show, and the slime climbs up and down; letting go midway drops it, and a fall costs nothing (owner, 2026-10-16, [question 68](06-open-questions.md#contradictions-left-after-the-review-2026-10-15)). A climbable wall never stands beside a heavy block, and held W next to both does whichever the slime faces (question 91). From the Wilds a hill that only the Feral skin climbs leads into the Crystal Caverns, so that way opens once Feral is won (question 87) | The Spear's attacks hit twice as fast | Planned (owner, 2026-10-16, question 56); not built. The Colossus shows the Pearl's power in his fight: he climbs out of reach and throws minions down (question 69). Swim was Pearl 3's skin until 2026-10-16: it does not fit the Colossus (owner) |
| Swim, acid, lava, cloud, ... | 4 to 8 | Swim: deep water; the deep-water secrets are come-back secrets that wait for it (owner, 2026-10-16). The others: Open | Open | Idea. Swim moved here on 2026-10-16, to a later Pearl after Release 1; which one is Open (Old Gullet, the Sticky Swamp's catfish, fits best: question 56). Today the Swim form, from a swim essence, crosses deep water. The essence goes, but the Swim form is not dropped: its scene mechanics are refactored into a permanent power that works in deep water, this skin (owner, 2026-10-16, question 75) |

### Webs (Chapter 2)

| | Webs | Web walls |
|---|---|---|
| **Without the Silk skin** | Speed −50% | Cannot pass |
| **With the Silk skin** | Full speed | Pass at −50% speed |

- The shapes cut webs only once the Silk skin is learned, so the player has to
  deal with the webs to defeat the Matron (owner, 2026-10-15). With the skin, a
  cut opens a web wall for good and frees things wrapped in silk: a chest, a
  key, a trapped slime (owner, 2026-10-16, question 55). Tom hangs in a
  cocoon, which a weapon tears before the skin (owner, 2026-10-16,
  question 54). In Release 1 the Spear, the only shape, does both
  (question 94). *Since 2026-10-16 (question 95): the maze that leads to Tom
  has webs that slow the slime and cannot be cut before the Silk skin.*
- The Matron's fight is played with the slowdown before the number is fixed.

No web wall blocks the way to the Matron. The slime meets her without the Silk
skin, so her web attacks hit it with their full effect. Her Pearl grants the
Silk skin, which then opens the web walls all over the forest and in the maps
already visited. It also opens Chapter 3, as a skin opens the next region: the
way to the Crystal Caverns is a maze of web walls that only the Silk skin
passes (owner, 2026-10-16, question 81). From the Wilds a second web maze
leads into Gloop Forest, and only the Silk skin passes it (owner, 2026-10-16,
question 87).

## How a region plays

```mermaid
flowchart LR
  A[Enter the region] --> B[Explore its maps]
  B --> C[Learn a shape or ability<br/>from an NPC, or find it]
  C --> D[The boss's dungeon]
  D --> E[Beat the boss with it]
  E --> F[Its Pearl: a new skin]
  F --> G[The skin opens the next region<br/>and secrets in old ones]
  F --> H[Return the Pearl:<br/>Slimeshire grows]
  G --> A
```

**The tool you find beats the boss; the skin the boss gives opens the world.**

## How it borrows from Zelda

- **A big world.** Many regions, and each region can span several maps. A
  chapter can span several maps but stays within one region. Some maps have no
  boss; each region has exactly one, placed on whichever map suits the
  adventure (Fatty One Eye could move to his own cavern map, for example).
  Release 1 (Chapters 1 to 3, owner, 2026-10-15) is only the opening of that
  world.
- **Key tools per region.** Each region teaches one or more shapes or
  abilities, and its boss needs them.
- **One skin per boss**, always on once won. The skin opens the next region
  and secrets in places the player has already visited, which rewards going
  back.
- **Bosses live in their dungeons.** Once the slime enters a boss's chamber it
  cannot leave until the boss is beaten.
- **Growth through exploration.** Max health and max energy grow through
  secrets and bosses, never through levels.
- **Movement in order.** Basic moves come early and powerful ones later.
- **Secrets spread over the whole game.** They are not packed into the first
  maps.

## Decisions in effect

| Topic | Decision | The game today |
|---|---|---|
| **Release 1** | Chapters 1 to 3, with three skins: Heavy, Silk and Feral (Pearl 3, owner, 2026-10-16, question 56). The Swim skin waits until after Release 1, and the deep-water secrets are come-back secrets for it (owner, 2026-10-16). NPCs teach, and chests hold the finds. Manuscript pieces and Slime Forge evolutions wait ("upgrades of skins and abilities come later in the game"). Its content ends when the Crystal Colossus falls, but the game goes on: the player explores the first three chapters' regions, part of the West village and the Wilds that connect them with the new powers, and the game says that from here on it is exploration and that more areas come in later releases (owner, 2026-10-16, question 58). Barriers in the world close the ways to the other regions (a fallen bridge, a landslide, a Thorn Guard post), each saying that more lies beyond (owner, 2026-10-16, question 73); how long it plays is still to be measured. From the Wilds, the Crystal Caverns are reached up a hill that only the Feral skin climbs, and Gloop Forest through a second web maze that only the Silk skin passes (owner, 2026-10-16, question 87). **Its powers:** eight besides the Gulp, about three a chapter. Chapter 1: the Spear (Yoi), the Roll (young Burr) and the Heavy skin (Pearl 1). Chapter 2: the Goo Bomb, the chapter's key tool, and the Silk skin (Pearl 2). Chapter 3: the Lantern (the smith), the Feral skin (Pearl 3) and the Bow (Burr). The War Axe and Stretch Lash wait for the next release, and their locks become come-back secrets (owner, 2026-10-16, question 94). Where the Goo Bomb comes from is question 95, and Release 1 with one shape is question 96 (both Open). *Changed 2026-10-16 (sixth round): a short prologue comes before Chapter 1, where Yoi teaches the Spear (question 97); Tom teaches the Goo Bomb (question 95); the Spear is the only shape (question 96). Release 1 has whole manuscripts, each found in a chest as one find, and pieces come later (question 65); what they teach is question 108 (Open).* | Chapters 1 and 2 are built; the Crystal Caverns are a placeholder world, open without a key |
| **Prologue** | A short, closed opening before Chapter 1, like Zelda's and Super Metroid's (owner, 2026-10-16, question 97; the [prologue design](../design/2026-10-16-prologue.md), accepted as written). The slime is born at the Wellspring, learns to move and to gulp (it clears a blocked path), sees Yoi fall to four worms in a camera scene, saves him by throwing things (the prologue's worms die from one hit), and learns the Spear from him. A barred gate, the Spear's "through bars" lock, opens into Slimeshire, and at the town's edge Plop meets the slime, gives it the 10-slot bag and its first tips, with the exclamation mark, and later sends it to Burr (question 100). It sits between chunks B4 and C4 in the south; chunk content may move to fit it, or it can be an underground cavern. Its lake is **the Wellspring**: after the prologue a short forest path from Slimeshire's south-west reaches it, and each Pearl's homecoming is a short scene there (question 98). | Not built: a new game starts in Slimeshire's clearing, where Plop greets the slime and Slime Basics starts |
| **One game** | Once the three skins are built, the rework becomes the only game. The old system goes with all its code: the classic mode, Swallow, essences, the forms, crafted weapons and tools, harvesting, Squash Slam and the classic number-key abilities. Their art waits "until we are sure we don't need it" in `asset/to-delete/` at the repo root, outside the Godot project so it is no longer imported, each file keeping its relative path. The Swim form is not dropped: its scene mechanics are refactored into a permanent power that works in deep water, the later Swim skin; only its essence goes (owner, 2026-10-16, question 75). | Both run: the classic game, and the rework mode in the playground and with `?shapes` |
| **Quests** | Quests no longer make sense: NPCs give info and tips, perhaps with one main quest like Zelda's, winning back the eight Pearls (owner, 2026-10-15, question 50). The journal keeps one main quest, "Win back the Pearls", and a page of the tips NPCs give; its Pearl slots show empty and fill as the Pearls are won, each lighting up its part of a picture and saying what the Pearl does. An NPC hands over or teaches its find when the slime talks to it, and the other finds lie in chests, each with its ceremony. A building is restored when a Pearl comes home ("Return the Pearl: Slimeshire grows") (owner, 2026-10-16, question 60): Pearl 1 restores Slimeshire's well, which then refills energy (question 90), and Pearl 2 relights the Forge (question 79). With no quests, an NPC that has a tip that matters to the story shows the exclamation mark (owner, 2026-10-16, question 82). *Changed 2026-10-16 (sixth round): after Fatty, the freed Burr says the town must see the Pearl, the journal's main quest points home, and the well comes back when the slime brings the Pearl to it (question 103); each Pearl's homecoming is a short scene at the Wellspring (question 98).* | Every chapter beat is a quest, with the journal, quest offers and rewards |
| **Getting an item** | The full ceremony for every permanent thing the first time; a smaller sting for new recipes; nothing for materials. | Built 2026-10-09 for abilities, permanent items and Goo Hearts (owner's playtest open); the recipe sting is not built |
| **Bags** | The slime starts with no bag. Release 1 has **one bag** (owner, 2026-10-16, question 53): Elder Plop's **10-slot bag**, and the 20-slot bag waits for the next release ("since we don't have many collectibles now", owner, 2026-10-16, question 74). What the Gloop Cavern's coffer holds instead is question 63 (*answered 2026-10-16: heart quarters, potions, coins or a piece of the story*). The 2026-10-02 plan had Plop give the 10-slot bag with the first quest and the 20-slot bag wait in that coffer, replacing it. *Changed 2026-10-16 (sixth round, question 100): Plop gives it at the town's edge, as the slime comes out of the forest after the prologue.* | 20 slots from the start |
| **Vault** | Waits for a later release (owner, 2026-10-16, question 53). The plan for it: found inside a house during a quest that also teaches sleeping to recover; **50 slots**; the vault screen shows the bag on the left and the vault on the right, with drag and drop both ways. | Chests are take-only |
| **Crafting** | Release 1 crafts only potions and food, "maybe the vault", and nothing is harvested: the Axe and the Hammer give no wood, stone or iron (owner, 2026-10-15). Their ingredients come from pickups and drops: berries, mushrooms and herbs taken by hand, and enemy drops, with no tool (owner, 2026-10-16, question 52). The vault waits (question 53). Quick recipes stay instant. The Forge brews the potions until evolutions arrive (owner, 2026-10-15, question 51). Pearl 2, the Matron's, relights it when it comes home: Pip and the slime light it, and from then on it brews the potions and knows their recipes, in place of the quest Rekindle the Forge and its ore cost (owner, 2026-10-16, questions 79 and 82). An NPC tip or a chest teaches each of the few other recipes (question 82). Before the Forge is relit, potions are found (chests, drops, the shop), the one or two simple recipes of Chapter 1 are made at a campfire, and a secret in the West village teaches a simpler potion (owner, 2026-10-16, question 89). *Changed 2026-10-16 (sixth round, question 104): any campfire makes them, and campfires stand by the Wellspring, in the town and at each camp, so a fresh save can always heal. Potions and food are both crafted at a campfire (question 66).* The West village shop sells potions and food ingredients, so coins have a use in Release 1 (question 88). Its timed smelting of charcoal and iron bars (decided 2026-10-02) leaves Release 1 with the materials. What the Workshop does in Release 1 is Open (question 51). Shapes and abilities evolve at the Slime Forge, later in the game; skins do not (owner, 2026-10-16, question 67). | Every recipe is instant. Classic: stone tools chop and mine, the Forge smelts iron, and the workbench makes tools and weapons. Rework: the Axe chops trees and the Hammer mines rocks |
| **Shapes** | Replace crafted weapons and tools. Learned from NPCs or manuscripts; in Release 1 NPCs teach and chests hold the finds. The **Spear** comes from Old Veteran Yoi in Yoi's Hideout (owner, 2026-10-11, confirmed in question 50). The smith teaches the **Hammer** at the Workshop in Chapter 5 or 6, after Release 1 (question 51). The **War Axe** waits for the next release (owner, 2026-10-16, question 94), so the Spear is Release 1's only shape (question 96, Open). Who teaches the Axe is Open (question 33). *Changed 2026-10-16 (sixth round): Yoi teaches the Spear in the prologue, for the slime's help, and his hideout becomes his home, an optional secret with a heart quarter, his tips and later the Spear's upgrades (questions 97 and 99). Release 1 has the Spear alone: E stays hidden until a second shape is learned, and the Axe opens the next release with its come-back secrets (question 96).* | Rework: the Spear, the War Axe and the Hammer, each with a 3-step chain and a charge (Lunge, Spin, Quake); E switches. Nothing teaches them yet (the rework lends them all). The classic game still crafts weapons |
| **Skins** | Two systems: shapes, and skins from the Pearls. Swallowing essences no longer gives forms. Skins are always on, with no key, and each has its gate and a change to a move ([The skins](#the-skins)). Release 1 has Heavy (Pearl 1), Silk (Pearl 2) and Feral (Pearl 3, the Crystal Colossus's; owner, 2026-10-16, question 56). Swim moves to a later Pearl, after Release 1 (owner, 2026-10-16). | Not built as skins: the Stone, Silk and Swim forms still come from swallowed essences, held by a Q hold |
| **Gulp** | Grab and throw only. The prologue teaches it first: the slime clears a blocked path and saves Yoi by throwing things at the worms (owner, 2026-10-16, question 97). | Built. Rework: Q is the whole mouth: hold to suck, tap to throw, hold 2 s to swallow an essence |
| **Swallow and essences** | **Marked for deletion.** The game does not use them: no Swallow lesson from Tom, no essence drops. Their code goes once the three skins are built (One game, above). | Built 2026-10-09 (Tom in the Web teaches it; the Clod Stomper drops stone essences, spiders drop silk) |
| **Roll** | The Dodge became the Roll: a Pegasus-boots dash that goes straight, bonks off walls, and drains energy while held. The quick Roll is free. Release 1 teaches it in Chapter 1, before Fatty One Eye: young Burr in the West village shows it, and it opens the worms' burrow, whose falling slabs only a rolling slime crosses (owner, 2026-10-16, question 61). The quick roll is the Roll, and the held, charged roll is a later upgrade, like the Roll's enemy push; this replaces the 2026-10-09 rule that the Roll comes whole (owner, 2026-10-16, question 78). With the Heavy skin it shakes things loose and breaks the small loose things lying in its way: a loose rock, a rubble heap, a rotten trunk across a path, and the old dead or built things that lie or lean in the way: grey leaning old trees, old fences, plank barricades, rotten mine timbers ([The skins](#the-skins); question 93); it does not push enemies away. | Built 2026-10-09 (Stone Tools teaches it). Rework: on Space; a tap rolls a quick roll (free), and the `roll-charge` upgrade adds the held, charged roll |
| **Goo Bomb** | An ability that costs energy, and Chapter 2's key tool (owner, 2026-10-16, question 94); where it comes from is question 95 (Open). *Changed 2026-10-16 (sixth round, question 95): Tom teaches it. Reaching him is hard: a maze with several secrets and tests, solved with the Spear, the Roll, the Heavy skin and the Gulp, whose webs slow the slime and cannot be cut before the Silk skin.* It breaks cracked walls and cracked ground; rubble heaps break under a Heavy Roll instead (owner, 2026-10-16). It blows only on its own fuse: no other ability sets it off (owner, 2026-10-15). A bomb caught in another bomb's blast still goes off: the chain stays (owner, 2026-10-16, question 57). In the playground the islet's prize moves behind a cracked rock face, the bomb's lock, and the heap by the map's edge waits for a Heavy Roll (owner, 2026-10-16, question 72). | Rework: 20 energy, a 2 s cast, then a 3 s fuse; Q can suck it up and throw it. It blows cracked walls (a blown wall can be a door) and rubble heaps, hurts the slime too, and sets off other bombs in its blast. Cracked ground still breaks under a Squash Slam in the Stone form, not under a bomb |
| **Lantern** | An ability: an ember lights the slime in dark rooms, and a short flame hurts, lights candles and burns dry plant growth (deadthorn, hay, dry roots, old banners) and the wood a Heavy Roll knocked down, once it lies there as dry wood (owner, 2026-10-16, questions 84 and 93). Plank barricades, old fences and rotten mine timbers are the Heavy Roll's, not the Lantern's, and so is a rotten trunk lying across a path (questions 72 and 93). It does not set off bombs. The smith gives it at his mine camp in the Crystal Caverns: it is the Forge's ember (owner, 2026-10-16, question 59). | Rework: 10 energy a flame; dark rooms, candles and deadthorn hedges are built; the flame stopped setting off bombs on 2026-10-15 |
| **Energy** | Every ability costs energy, per use (Goo Bomb, Lantern, Stretch Lash, Teleport) or over time (the held Roll); the quick Roll is free. Skins and shapes are free, except a shape's charged attack. It refills by itself, slowly: 1 a second (owner, 2026-10-15). Potions and energy shards bring back more. Planned: refills that grow back, and full refills from beds, the Wellspring and Slimeshire's well, with no save points (owner, 2026-10-16, question 62; [The slime's powers](#the-slimes-powers)); until 2026-10-16 the plan said "a full refill at the Wellspring and at save points". Slimeshire's well refills energy once Pearl 1 restores it (owner, 2026-10-16, question 90). *Changed 2026-10-16 (sixth round, question 105): the well gives a full refill, a drink in town, and beds also restore life.* No puzzle costs more than the starting max energy. Max energy grows over the game. | Classic: it refills by itself, 8 a second. Rework: 1 a second (since 2026-10-15; not while rolling); a kill drops an energy shard (+15) one time in five; max 100 |
| **Life and energy display** | A bottom console, from the approved [mockup](../design/2026-10-07-hud-console-mockup.md): numbers show only when a value changes, and the ring shows each heart quarter. The boss bar is at the top. | Built 2026-10-08 (owner's playtest open); the heart quarter pips wait for the quarters |
| **Hearts** | Four heart quarters make one heart, worth **+20 max HP**. A quarter adds nothing on its own, and the slime starts with no hearts. | Five Goo Hearts of +10 each |
| **Bosses** | One per region, inside its dungeon; the slime cannot leave the chamber until the boss is beaten. A beaten boss never comes back. | Bosses live in the open world, heal after 60 s with the slime outside their arena (their bar hides meanwhile), and respawn |
| **Saving** | Like Zelda: the slime can save everywhere except inside dungeons, and there are no save points. The full energy refills come from beds, the Wellspring and Slimeshire's well (owner, 2026-10-16, question 62). What happens on quitting or dying inside a dungeon is question 109 (Open; the proposal: the slime resumes at the dungeon's entrance). | Save anywhere from the pause menu (three slots and an autosave); a bed sets where the slime wakes; no dungeons yet |
| **Enemies** | Release 1 has **29 enemies**, the [bestiary](../design/2026-10-16-bestiary.md) accepted as written (owner, 2026-10-16, question 107): each has a tell, can be beaten with the Spear and the Roll and is easy with its right tool, and brings a kind of its own (chaser, turret, burrower, patroller, mimic, ...); each dungeon has two or three of its own and a mini-boss. The Clod Stomper stays as it is: its slam still breaks cracked ground near it, and it is an enemy, not a power (question 64). | Six are built: the worm swordsman, archer and brawler, the slime spider, the orb-weaver and the Clod Stomper |
| **The Matron** | New art. Her normal attack is a Stretch Lash in three directions: a hit deals damage, pulls the slime toward her, and traps it. The slime has no Silk skin yet, so it takes the full effect, and its shapes cannot cut her webs: it has to deal with them. Her Pearl grants the Silk skin. | One web spit; placeholder art |
| **The Crystal Colossus** | Four braziers ring his arena. Only when all four burn (the Lantern lights them) is a weak spot on his armour bared, at a random place, for the Spear (the Spear alone since the War Axe waits for the next release: owner, 2026-10-16, question 94); his stomps blow the braziers out one at a time. The Pearl in him shows: he climbs out of reach to throw some of his minions down, and killed, they can drop energy shards (owner, 2026-10-16, question 69). He has blocked the smith's crystal mine. His Pearl grants the Feral skin (owner, 2026-10-16, questions 56 and 59). | Not built: `crystal-caverns` is a placeholder world |
| **The West village** | Part of it joins Release 1, with more NPCs, houses and things to do, like Zelda's town: Burr the gatekeeper's house is there, and young Burr teaches the Roll (owner, 2026-10-16). Its Release 1 part is a small town, like Kakariko: Burr's house, three or four more houses, a shop and a game to play (owner, 2026-10-16, question 73). The shop sells potions and food ingredients (question 88), and a secret in the village teaches a simpler potion (question 89). Burr gives the Bow there when the slime comes back after Chapter 2 (question 94). *Changed 2026-10-16 (sixth round, questions 102 and 106): Burr builds it from the Matron's thread once Pearl 2 is home (the Bow row below).* | A placeholder world (`west-village`) |
| **Webs** | Without the Silk skin a web slows the slime by 50% and a web wall stops it; with it, webs do not slow it and web walls slow it by 50%. The shapes cut webs only with it ([Webs](#webs-chapter-2)). | A web holds the slime for a moment and pushes it back; the Silk form passes it and tears it open; there are no web walls |
| **Stretch Lash** | Waits for the next release (owner, 2026-10-16, question 94): Sunny's basket and the Lash's other uses become come-back secrets (question 65). Learned from manuscripts; where it is learned is Open (question 33). | Mossy teaches it in Chapter 2 |
| **Bow** | An Ability Box power; each arrow costs energy. On press the slime aims in the direction it is moving, on release it shoots that way, and the arrow does not change direction. Its locks are far targets in a straight line across gaps and water; it also hits far enemies that cannot be reached otherwise, and some enemies open doors when they die, as in Zelda (owner, 2026-10-16, question 76). Burr gives it as his thanks (question 80). It is in Release 1, in Chapter 3: Burr gives it when the slime comes back to the West village after Chapter 2, no longer right after Fatty's Lair (owner, 2026-10-16, questions 85 and 94). It is the one bow: the old Bouncy Bow idea is dropped (question 83). *Changed 2026-10-16 (sixth round, questions 102 and 106): visited before Pearl 2, Burr thanks the slime and gives a tip ("I am making you something, come back when the forest is free"). He needs silk and other things to build the Bow. The silk is one find, the **Matron's thread**: a spool the slime finds in her nest after she falls, taken from her web with the Silk skin; the other things are already in his workshop. With the thread and Pearl 2 home he teaches the Bow: one find, one trip back, no crafting. Chapter 3 uses it on its main path at least once (a far eye switch across the mine's chasm), but the Colossus does not need it.* | Not built |
| **Squash Slam** | **Removed** (owner, 2026-10-15): it had no job left. The Goo Bomb breaks cracked ground instead, and The One-Eyed Guardian's reward loses the Slam. | Finishing The One-Eyed Guardian teaches it, and in the Stone form it breaks cracked ground. Rework: an improved Slam whose outer ring bounces enemies in place for a follow-up |
| **Jump** | Removed (2026-10-08): it hopped over walls and gates and misbehaved around hills. The code stays; nothing teaches it. | Removed |
| **Keys** | Left click attacks with the shape (hold to charge); E switches shapes; Q is the mouth; F uses the ability chosen in the bag, which pauses the game while it is open; Space rolls; right click interacts, and held on a heavy block grabs it to push or pull. Planned: held at a climbable wall (thick roots and rocky handholds, questions 68 and 86), it climbs up and down with the Feral skin; a climbable wall and a heavy block never stand side by side, and held next to both it does whichever the slime faces (question 91). With the Spear the only shape in Release 1, what E does there is question 96. *Answered 2026-10-16 (sixth round): E stays hidden until a second shape is learned (question 96).* Keys-only: A, E, Q, S, D, W. | Rework. The classic game keeps 1 Swallow, 2 Roll, and 3 to 5 for Lash, Slam and Teleport until it goes (One game, above) |

The roadmap carries these as Release 1 tasks:
[2026-10-02 decisions](../GAME_ROADMAP.md#the-2026-10-02-decisions),
[2026-10-08 decisions](../GAME_ROADMAP.md#the-2026-10-08-decisions),
[2026-10-15 decisions](../GAME_ROADMAP.md#the-2026-10-15-decisions) and
[2026-10-16 decisions](../GAME_ROADMAP.md#the-2026-10-16-decisions). The
rework's own plan for Release 1
([dungeons plan](../design/2026-10-11-release-1-dungeons-plan.md), not built)
predates the 2026-10-15 decisions: it has Old Veteran Yoi teach the Spear
(confirmed on 2026-10-15), the War Axe found in the Weaver Hollow, and Pearls
that give abilities (skins since 2026-10-15). *Changed 2026-10-16: the War Axe
waits for the next release (question 94).* *Changed 2026-10-16 (sixth
round): Yoi teaches the Spear in the
[prologue](../design/2026-10-16-prologue.md), not in his hideout, which
becomes his home (questions 97 and 99), and the Weaver Hollow's big chest
holds a heart or the dungeon's big key instead of the Axe (question 95).*

## Open

- **Skins 4 to 8**, and which boss holds each (question 32); Swim is one of
  them, and Old Gullet fits it best (question 56).
- **Where Teleport is learned, and who teaches the War Axe and Stretch Lash**
  in the next release (question 33).
- **How each skin shows** while it works (Heavy on a plate, a grab and in the
  Roll; Silk in a web, a web wall and a cut; Feral's claws as it climbs;
  question 34).
- **What Release 1's whole manuscripts teach** (question 108; the proposal:
  recipes and lore).
- **Quitting or dying inside a dungeon**, where the slime cannot save
  (question 109; the proposal: it resumes at the dungeon's entrance).

More questions are in [Open questions](./06-open-questions.md).

## History

<a id="decisions-of-2026-10-02-planned-not-built"></a>
<a id="decisions-of-2026-10-08"></a>

- **2026-10-02:** adventure first, with a little crafting. Item ceremony, bags,
  vault, timed crafting, heart quarters, the orb HUD, webs that trap the slime.
  Sprint becomes a mid-game power. Gulp forms become armors the slime keeps.
- **2026-10-07:** the HUD becomes a bottom console (mockup approved 10-08).
- **2026-10-08:** Jump removed. Sprint removed; the Dodge becomes the Roll.
  Armors replaced by **essences**: Gulp sucks an essence, Swallow turns it into
  a form; Tom teaches Swallow in Chapter 2. Cracked ground breaks under a Squash
  Slam in the Heavy form.
- **2026-10-09:** Gulp and essences, the Roll and the new keys built.
- **2026-10-15:** forms become **skins**, earned from the **Pearls**, permanent
  and free. **Shapes** replace crafted weapons and are learned from NPCs and
  manuscripts. The **Bomb** (an energy ability) breaks cracked walls and ground.
  Swallow and essences are marked for deletion; Gulp only grabs and throws.
  Energy no longer refills on its own. The Slime Forge evolves shapes and
  abilities. Webs slow the slime by 80% and web walls stop it without the Silk
  skin. Bosses keep the slime in their chamber until beaten.
- **2026-10-15 (merge):** the rework mode reached main: shapes, the Ability
  Box on F, the Goo Bomb, the Lantern, heavy plates and blocks, energy without
  regeneration and energy shards, the quick roll, and doors entered by walking
  into them.
- **2026-10-15 (later):** skins are **always on** once won, like Zelda's
  flippers or Super Metroid's suits: contextual, pure additions, no keys. The
  idea of up to three abilities locked to each skin is dropped; skin × shape ×
  ability combos take its place.
- **2026-10-15 (review):** the owner answered the review
  ([questions 40 to 49](06-open-questions.md#review-of-the-2026-10-15-direction)).
  Energy refills by itself after all, slowly (1 a second), with more refills
  to come. Each skin has its gate and a change to a move, and "depth from
  combos" is dropped. Abilities are chosen in the bag, which pauses the game,
  and no ability requires another: the Lantern no longer sets off bombs.
  Release 1 is Chapters 1 to 3 with three skins (Heavy, Silk, Swim); NPCs
  teach and chests hold the finds, and manuscript pieces and Slime Forge
  evolutions come later. Webs slow the slime by 50%, not 80%, and only the
  Silk skin lets shapes cut them. Squash Slam is removed, and the Goo Bomb
  breaks cracked ground. Release 1 crafts only potions and food, with no
  harvesting. Pearl 3, the Crystal Colossus's, grants the Swim skin
  (*changed 2026-10-16: the Swim skin does not fit the Colossus, so Swim
  moves to a later Pearl, after Release 1, and Pearl 3 grants the Feral skin,
  question 56*). Once the three skins are built, the rework is the only game
  and the old system goes, its art held in `asset/to-delete/`. The roadmap
  carries the decisions as tasks, and the guidelines mark what they replace.
  The same day the owner
  answered questions 50 and 51: quests no longer make sense (NPCs give info
  and tips, perhaps with one main quest for the Pearls), the Spear comes from
  Old Veteran Yoi, the smith teaches the Hammer in Chapter 5 or 6, after
  Release 1, and the Forge brews the potions until evolutions arrive.
- **2026-10-16:** the owner answered questions 52 to 61
  ([open questions](06-open-questions.md#contradictions-left-after-the-review-2026-10-15)).
  - Tom hangs in a cocoon a weapon can tear, and with the Silk skin a shape
    cuts web walls open for good and frees what is wrapped in silk.
  - The journal keeps the main quest and the NPCs' tips, and its Pearl slots
    light up a picture as the Pearls are won. NPCs hand over their finds,
    chests hold the rest, and a returned Pearl restores a building.
  - Swim does not fit the Crystal Colossus. Pearl 3 grants the **Feral**
    skin: it climbs some walls while W is held, claws showing, and its Spear
    hits twice as fast. The ideas Prism, Burrow, Echo and Shard are declined.
  - **Young Burr** teaches the Roll in the West village, in Chapter 1, before
    Fatty One Eye. His father **Burr**, the gatekeeper, waits in a cell in
    Fatty's Lair, behind a gate that shuts fast and falling slabs over lava,
    spikes or the void. Release 1's Roll is the quick roll.
  - The Heavy skin's Roll shakes things loose and breaks loose rocks, rubble
    heaps and old trunks; it does not push enemies away. Rubble heaps leave
    the Goo Bomb, and bombs still chain.
  - Ingredients are picked up or dropped. Release 1 has one bag, and the
    vault waits.
  - Release 1's content ends when the Colossus falls, and the player goes on
    exploring the three chapters, part of the West village and the Wilds.
  - All four braziers, lit by the Lantern, bare a random weak spot on the
    Colossus. The smith, safe at his crystal mine, gives the Lantern and goes
    home once the Colossus falls; Pip's story is relighting the Forge.
  - Deep water waits for the Swim skin, and the swimming code stays.
  - A **Bow** comes later. *Changed the same day (third round, below): Burr
    gives it, and when is question 85.*
  - Questions 68 to 76 follow from these answers.
- **2026-10-16 (third round):** the owner answered questions 68 to 83
  ([open questions](06-open-questions.md#contradictions-left-after-the-review-2026-10-15)).
  - A climbable wall has vines and irregularities. The slime climbs up and
    down, and a fall costs nothing. The Colossus climbs out of reach and
    throws minions down, which can drop energy shards.
  - Chapter 1's slabs cross the void and spikes; lava waits for a fire
    region, and one hazard script serves them all. A slab falls a set time
    after it is touched, so quick rolls in a row cross it and walking never
    does.
  - The playground's islet prize goes behind a cracked rock face, and its
    edge heap waits for a Heavy Roll. A Heavy Roll breaks small loose things
    lying in the way; the Hammer keeps big boulders, and the Axe standing
    trees. Each thing must be told apart, and options are sacrificed for
    clarity. A few combos used wisely are welcome (question 84).
  - The West village's Release 1 part is a small town, and barriers in the
    world close the later regions. Release 1 has Plop's 10-slot bag; the
    20-slot bag waits.
  - The Swim form's mechanics become the later Swim skin. The Bow is an
    Ability Box power that costs energy per arrow, hits far targets and far
    enemies, and Burr gives it (question 85). The Bouncy Bow goes.
  - The quick roll is the Roll; the charged roll is a later upgrade. This
    replaces the 2026-10-09 rule that the Roll comes whole.
  - Pearl 2 relights the Forge, which knows the potion recipes. An NPC with a
    tip shows the exclamation mark.
  - A web-wall maze that only the Silk skin passes leads to the Crystal
    Caverns; the crystal seal and the end-of-Chapter-2 card go.
  - Questions 84 to 86 follow from these answers.
- **2026-10-16 (fourth and fifth rounds):** the owner answered questions 84
  to 94
  ([open questions](06-open-questions.md#contradictions-left-after-the-review-2026-10-15)).
  - The main path never needs a combo; a few optional secrets may combine a
    skin and an ability, each clearly different. A Heavy Roll knocks down a
    grey, leafless, leaning old tree the Axe cannot cut, and the Lantern
    burns it.
  - The War Axe owns living, green things; the Heavy Roll owns old dead or
    built things lying or leaning in the way (plank barricades and mine
    timbers move to it from the Lantern); the Lantern owns dry plant growth
    and the wood the Roll knocks down. Three woods, three looks.
  - Climbable walls show thick roots and rocky handholds; the Axe's vines
    are leafy curtains. A climbable wall and a heavy block never stand side
    by side.
  - From the Wilds, a hill only the Feral skin climbs leads into the Crystal
    Caverns, and a second web maze only the Silk skin passes leads into
    Gloop Forest.
  - The West village shop sells potions and food ingredients. Before the
    Forge, potions are found or made at a campfire, and a West village
    secret teaches a simpler potion.
  - Pearl 1 restores Slimeshire's well, which then refills energy.
  - Release 1 has eight powers besides the Gulp, about three a chapter: the
    Spear, the Roll and the Heavy skin; the Goo Bomb (Chapter 2's key tool)
    and the Silk skin; the Lantern, the Feral skin and the Bow, which Burr
    gives after Chapter 2. The War Axe and Stretch Lash wait for the next
    release, their locks becoming come-back secrets.
  - Questions 95 and 96 follow from these answers.
- **2026-10-16 (sixth round):** the owner answered questions 95 to 105, took
  the proposal of question 106, then answered questions 62 to 67 and
  accepted the bestiary (question 107)
  ([open questions](06-open-questions.md#contradictions-left-after-the-review-2026-10-15)).
  - A short **prologue** comes before Chapter 1, as the
    [prologue design](../design/2026-10-16-prologue.md) writes it: the slime
    is born at the Wellspring, learns to move and to gulp, saves Yoi from four
    worms by throwing things and learns the Spear from him; a barred gate
    opens into Slimeshire. It sits between chunks B4 and C4.
  - The Wellspring is the prologue's lake, reached later by a forest path
    from Slimeshire's south-west, and each Pearl comes home there. Yoi's
    Hideout becomes Yoi's home, an optional secret. Plop meets the slime at
    the town's edge with the 10-slot bag and the first tips.
  - Tom teaches the Goo Bomb at the end of a maze of secrets and tests, and
    the Weaver Hollow's big chest holds a heart or the big key. The Spear is
    Release 1's only shape, and E stays hidden until a second one.
  - A Heavy Roll knocks the grey, leaning old tree over the river as a
    bridge.
  - Burr builds the Bow from the Matron's thread once Pearl 2 is home, and
    Chapter 3's main path uses it once. After Fatty, Burr and the journal
    send the slime home, where the well comes back.
  - Any campfire makes Chapter 1's recipes, and campfires stand by the
    Wellspring, in the town and at each camp. The well gives a full refill,
    and beds also restore life.
  - Like Zelda, the slime saves everywhere except inside dungeons, with no
    save points; beds, the Wellspring and the well give the full refills.
  - The iron hollow and the Gloop Cavern's coffer hold heart quarters,
    potions, coins or a piece of the story, and the weaver fangs go. The
    Clod Stomper stays as it is. Release 1 has whole manuscripts, one find
    each. Potions and food are both crafted at a campfire. Shapes and
    abilities evolve at the Slime Forge after Release 1; skins do not.
  - Release 1 has 29 enemies, as the
    [bestiary](../design/2026-10-16-bestiary.md) writes them.
  - Questions 108 and 109 follow from these answers.
