# Chapter 1 — The Clearing

| | |
|---|---|
| **Region** | Slimeshire Meadow (`level-1`, `slime-home`, `mushroom-home`); Planned: the prologue between chunks B4 and C4 (the Wellspring and the glade), part of the West village and Fatty's Lair (owner, 2026-10-16). *Changed 2026-10-16 (seventh round, question 112): in B4 the prologue takes the south edge, sealed off by forest, and the West village's town sits in B4's north and A4* *Changed 2026-11-17 (owner, question 150): Burr's house is in Slimeshire's C4, so Chapter 1 no longer goes to the West village, whose town is Glimmerhill (question 149)* |
| **Goal** | Grow from a newborn puddle into a slime that can leave home, and open the Verdant Gate |
| **Boss** | Fatty One Eye |
| **Earned** | Today: the first bag, stone tools, the Roll, home and vault, spears and Squash Slam (the green key went on 2026-11-20 with the Verdant Gate, question 163). Planned: the **Spear** shape from Old Veteran Yoi, the **Roll** from young Burr, a small key, Pearl 1 with the **Heavy skin** and a boss heart. Burr's thanks, the **Bow** (question 80), waits until the slime comes back to the West village after Chapter 2, in Chapter 3 (owner, 2026-10-16, questions 85 and 94). Shapes replace the crafted tools and spears (built in the rework mode), and Squash Slam is removed (owner, 2026-10-15). The vault waits for a later release (owner, 2026-10-16). *Changed 2026-10-16 (sixth round): Yoi teaches the Spear in the prologue (question 97), Plop gives the 10-slot bag at the town's edge (question 100), and Burr builds the Bow from the Matron's thread once Pearl 2 is home (questions 102 and 106).* *Changed 2026-11-17 (owner): shapes are dropped as a concept, and the Spear is an ability, still Yoi's (question 146). Burr's son teaches the Roll in their house in Slimeshire's C4 (question 150). A fallen tree that a Heavy Roll breaks replaces the Verdant Gate, so the green key goes (question 163). The Charged Roll is Release 1's first ability upgrade, found in a secret (question 160).* *Changed 2026-11-20 (owner): the Bow is no longer Burr's thanks: Pip carves its rune in Chapter 3. Burr gives the first of four Roll Fragments in Fatty's Lair, and Yoi's chest holds the second; the fourth, found later, teaches the Charged Roll.* |
| **Status** | Built. The beats below mark each Planned change and Proposal. Every beat is a quest as built; quests no longer make sense (owner, 2026-10-15: NPCs give info and tips, question 50). In their place the journal keeps one main quest and the NPCs' tips, and an NPC hands over or teaches its find when the slime talks to it (owner, 2026-10-16, question 60). *As built (2026-11-14): the quests in the data are still the old crafting chain, and they cannot be finished: no story chunk has any wood, so the chain stops at A Place to Work. The slime has the Roll from the end of the prologue.* *Built 2026-11-19: the old quests are retired (their beats below are the record); the journal keeps the main quest "Win back the Pearls", Slime Basics and the NPCs' tips, and Fatty's fall sets `chapter-1-complete` ([quests spec §14](../../godot/specs/quests.md#14-the-main-quest-talks-and-tips-2026-11-19)).* |

Quest IDs are in brackets. Their dialogue lives in
`godot/game/data/quests-chapter-1.json`. Lines quoted here that already
exist are marked *(in game)*; every other line is a draft.

---

## Beat 0 — The prologue (Built 2026-10-16; planned by the owner the same day)

**Where:** a lake ringed by forest in the south, between chunks B4 and C4
(the owner's place). Chunk content may move to fit it; if it does not fit
naturally, it can be an underground cavern. The
[prologue design](../../design/2026-10-16-prologue.md) has the polished
version, which the owner accepted
([question 97](../07-decisions-archive.md#contradictions-left-after-the-review-2026-10-15)).
*Built 2026-10-16 ([PROLOGUE.md](../../godot/PROLOGUE.md)): both screens on
B4's south edge (`west-village-b4`), the Wellspring in its south-west and
the glade in its south-east against C4; the glade's barred gate and a short
forest path lead out onto Slimeshire's west edge (`level-1-c4`), where Plop
meets the slime. A new game starts at the birth; quitting during the
prologue starts it again from the birth.*
About 3 to 5 minutes, closed off: neither the West village nor
Slimeshire can be seen from it. *Changed 2026-10-16 (seventh round): the
Wellspring takes B4's south edge, sealed off by forest, and the West
village's town sits in B4's north and A4 (question 112). The prologue cannot
be saved (question 113).*

1. **Born at the Wellspring (B4).** At dawn a bubble rises from the glowing
   pool, wobbles and pops: the last slime born opens its eyes. No voice, no
   text, no HUD yet. The slime has nothing: no bag, no shape, no moves beyond
   walking. *Since 2026-10-16 (seventh round, question 113): the HUD appears
   right after the birth scene.*
2. **Moving.** The first-time control hints show the arrows; a drifting
   firefly and the pool's wading edge give it things to walk to.
3. **The blocked path.** The way out is choked with pots, a crate and a mossy
   log end. The hint shows the Gulp: hold to suck, tap to throw. The slime
   clears the path piece by piece, and the secret jingle plays as it opens.
4. **The attack (a camera scene, C4's south-west edge).** The camera pans
   ahead to an old slime with an eye patch fighting four worms with a spear
   grown from his body. One thrust drops two worms on one line; a third bites
   him, and he falls to one knee: "You there! Kid! Throw something,
   anything!"
5. **The rescue.** The two worms left turn on the slime. It saves him by
   throwing the glade's pots, stones and crate; each prologue worm dies from
   one throw. If the slime faints, it wakes at the glade's edge and the worms
   are back: the prologue has no game over.
6. **Yoi teaches the Spear.** He is Old Veteran Yoi of the Thorn Guard. He
   tells his story in a few lines (he held the gate against Gorge's monsters
   in the great war; the worms are Fatty One Eye's, grown bold) and teaches
   the **Spear** for the slime's help, with the full ceremony.
   - Yoi (draft): "Gather all of yourself, and push it out to one point."
7. **The first lock.** The glade's way out is an old Thorn Guard gate whose
   lever is behind bars: only a thrust fits between them, the Spear's own
   "through bars" lock. Yoi limps off: "Find old Yoi if you need a soldier's
   advice."
8. **Out of the forest.** At the town's edge **Elder Plop** meets the slime,
   amazed (owner, 2026-10-16, question 100):
   - Plop: "No slime has come out of the Wellspring in years... and here you
     are."
   - He gives it the **10-slot bag** (Beat 1) and its first tips, with the
     exclamation mark, and later sends it to Burr
     ([below](#the-west-village-young-burrs-roll-built-2026-11-19-owner-2026-10-16)).

After the prologue, a short forest path from Slimeshire's south-west leads
back to the Wellspring, and each Pearl's homecoming is a short scene there
(owner, 2026-10-16, question 98). A campfire stands by it (question 104).
*Since 2026-10-16 (seventh round): the path leaves Slimeshire, not the West
village's town (question 112). Every Pearl goes home there, and its power
flows into the town (question 110).* *Built 2026-11-20: the homecoming and
the campfire by the pool
([PROLOGUE.md](../../godot/PROLOGUE.md#the-homecoming-2026-11-20)).*

- **The game before the prologue (Built until 2026-10-16):** a new game
  started in the clearing, where Plop greets the slime (his quest offer
  still opens with it):
  - Plop: "Ah, a new slime in the clearing! Welcome, little one." *(in game)*
- **Since 2026-10-16 (Built):** a new game starts in the prologue, and
  Plop's meeting at the town's edge is in game: "No slime has come out of
  the Wellspring in years... and here you are." He gives his satchel (10
  pockets) and his first tips; the Chapter 1 quests begin when the slime
  first comes into Slimeshire.
- **Slime Basics** [`slime-basics`] starts at once (Built). Planned change:
  drop its "Sprint" step, because sprinting is now a mid-game ability.
- *Until 2026-10-16 (Proposal): the Wellspring was its own new map east of
  level-1, the game's first map, and Plop hurried over at the birth, taught
  the slime to move and asked it to meet him in town (questions 98 and
  100).*

## Beat 1 — A Place to Work [`a-place-to-work`] (Built)

**Giver:** Elder Plop.

- **Planned change: the first bag.** When the player accepts the quest, Plop
  hands over a **10-slot bag**. This is the game's first item ceremony, which
  teaches the player what that moment means.
  - Plop: "Goo is no good for carrying things. Here, my old satchel. Ten
    pockets, and only one hole."
- **The player does:** picks up wood, crafts a Workbench (40 wood), and places
  it.
- **Reward:** 20 wood and the Stone Axe and Stone Pickaxe recipes.
  - Plop: "A fine bench! You have a knack for this." *(in game)*
- **2026-10-15:** the stone tools go with the crafted tools, and Release 1
  crafts only potions and food.
- **2026-10-16 (owner):** Release 1 has one bag (question 53); its size and
  who gives it are question 74. An NPC hands over its find when the slime
  talks to it (question 60). *Changed 2026-10-16 (third round): it is Plop's
  10-slot bag, and the 20-slot bag waits for the next release (question 74).*
  *Changed 2026-10-16 (sixth round, question 100): Plop gives it when he
  meets the slime at the town's edge, as it comes out of the forest after the
  prologue (Beat 0).*

## Beat 2 — Stone Tools [`stone-tools`] (Built)

**Giver:** Elder Plop.

- **The player does:** crafts the Stone Axe and Stone Pickaxe, switches tools
  on the belt, chops 20 wood and mines 20 stone.
- ~~**Planned change:** tools are made by staying at the bench and hammering.
  This is the first hammering moment, and each tool ends in the item
  ceremony.~~ Dropped 2026-10-15: shapes replace crafted tools.
- **Reward:** **the Roll** (ceremony; the Dodge until 2026-10-09), the Wooden
  Spear recipe, 20 coins, 10 wood.
  - Plop: "A slime that stands still gets squashed. When something swings at
    you, tuck in and roll away!" *(in game)*
- **Question 60:** with shapes, no crafted tools and no harvesting in Release
  1, this quest loses its point, and the quests go. In the plan young Burr
  teaches the Roll in the West village
  ([below](#the-west-village-young-burrs-roll-built-2026-11-19-owner-2026-10-16);
  owner, 2026-10-16, question 61).

## Beat 3 — A Home of Your Own (new, Planned)

**Giver:** Elder Plop (Proposal). **Where:** the slime's house, the red forge
house whose door leads to the Slime Home (Proposal; the mushroom house is the
alternative, Open). *Since 2026-10-16 (eighth round, question 11): Release 1
has no quests, so there is no house quest; an NPC hands the home over when
the slime talks to it.* *Changed 2026-11-12 (owner): the forge has no door,
so it has no interior; the slime's home is behind the round mushroom house of
C4 (`home-door`). Plop's draft line below, "the house by the forge yard", no
longer fits.*

- **Why here:** after Stone Tools, the 10-slot bag is full of tools, wood and
  stone, and the first fight comes next. This is the moment to learn to rest,
  and to get somewhere to store things.
- **Questions 53 and 60:** with no tools and no harvesting in Release 1 that
  reason goes. The vault waits for a later release (owner, 2026-10-16,
  question 53), so in Release 1 this beat gives the house and its bed. An NPC
  hands over its find when the slime talks to it (question 60).
- **The story:**
  - Plop: "A slime needs somewhere to rest its goo. The house by the forge yard
    has stood empty since the smith left. It is yours now."
  - Proposal: the door stays shut until now, and Plop's house key is a small
    ceremony.
- **The player does:**
  1. Explores the house.
  2. Sleeps in the bed. This teaches resting to recover, and that the slime
     wakes here after a defeat.
  3. Finds the **vault**: 50 slots. Full ceremony. *Waits for a later
     release (2026-10-16, question 53).*
- **Open until 2026-10-16:** do all vaults share one storage? *Closed in the
  eighth round (questions 12 and 38): it is decided with the vault, in a later
  release.* The old proposal: vaults are
  sealed with Wellspring goo, so everything put in one can be taken out of any
  other.
  - Plop: "Whatever you put in a vault, every vault remembers."
- **Open until 2026-10-16, closed with the vault (question 12):** after this
  first one, can the slime craft more vaults, for
  example one at the forest camp?

## Side quests (Built)

- **A Tonic for Lili** [`a-tonic-for-lili`]: brew a Slime Tonic from three
  purple berries. Reward: 2 purple berries.
- **Snack for the Road** [`snack-for-the-road`], from Lily the Fishergirl: make a
  Berry Basket. Reward: 25 coins and a Slime Tonic.
- **2026-10-16 (owner, question 82):** with no quests, the relit Forge knows
  the potion recipes, and an NPC tip or a chest teaches each of the few
  others. An NPC with a tip that matters to the story shows the exclamation
  mark.
- **2026-10-16 (owner, question 89):** the Forge is relit only at the end of
  Chapter 2, so before that potions are found (chests, drops, the West
  village shop), and the one or two simple recipes of Chapter 1 are made at
  a campfire. A secret in the West village teaches a simpler potion. Which
  recipes those are is not decided yet. *Changed 2026-10-16 (sixth round,
  question 104): they are made at any campfire, and campfires stand by the
  Wellspring, in the town and at each camp, so a fresh save can always
  heal. Potions and food are both crafted at a campfire (question 66).*
  *Since 2026-10-16 (seventh round, question 108): Release 1's whole
  manuscripts, found in chests, teach campfire recipes (potions and food) and
  lore, pages of the Thorn Guard's war journal.* *Changed 2026-11-20 (owner):
  the Forge is relit at the end of Chapter 3, when Pearl 3 comes home.*

## Yoi's home (Built 2026-11-20; planned by the owner, 2026-10-16)

**Where:** under Lili's west yard, in Slimeshire. An optional secret
([question 99](../07-decisions-archive.md#contradictions-left-after-the-review-2026-10-15)).
*Built 2026-11-20: seven light crates on a hatch south of Lili's mushroom house
(level-1-c4, `object.heap-hatch`; at (169, 1313) since the owner moved it the same day); once the last is gulped away the hatch opens
for good with the secret jingle (flag `level-1.yoi-hatch-open`), and a stair leads
down to Yoi's den (`slimeshire-yoi-home`): Yoi, who welcomes the kid who saved him
and gives four war tips, one a visit; Slimeshire's fifth heart quarter; and a
chest by his cot with the Charged Roll, which plays its card. A ladder climbs
back up to the hatch ([quests spec 14.3](../../godot/specs/quests.md#143-talks-talks-in-npc-definitionsjson),
[14.8](../../godot/specs/quests.md#148-finds-the-war-journal-the-recipe-page-and-the-charged-roll-2026-11-20)).*
*Changed 2026-11-20 (owner): the chest holds one of the four Roll Fragments
that make the Charged Roll, and it sits behind a small Heavy statue maze, so
it always comes after Burr's fragment: stone dividers close its corner, and
two heavy statues fill the one gap, one behind the other, so pushing jams and
only pulling both out with the Heavy skin opens the way. Built the same day;
the room's walls are being redone, and the maze with them.*

- Lili tells of the hideouts slimes dug during Gorge's war. Her tip goes in
  the journal: NPCs give tips, and the journal keeps them (owner, 2026-10-16,
  question 60).
- In her west yard the slime sucks away a heap of seven crates. The secret
  jingle plays, and a hatch opens. *Since 2026-10-16 (eighth round, question
  128): the heap is crates, no longer bricks and crates, so it does not look
  like the Heavy Roll's rubble heap.*
- Below is the home of **Old Veteran Yoi**, the veteran the slime saved in the
  prologue (Beat 0). Inside are a **heart quarter**, Yoi's tips, and later
  the Spear's upgrades. *Changed 2026-10-16 (seventh round, question 111):
  who upgrades the Spear, Yoi's techniques or the Forge, is decided after
  Release 1.* *Since 2026-11-17 (owner, question 151): its quarter is
  Slimeshire's fifth, as the other four are placed.*
- The Spear shape, from the prologue, replaces the Wooden and Stone Spears
  below. *Since 2026-11-17 the Spear is an ability, not a shape
  (question 146).*
- *Until 2026-10-16 this was Yoi's Hideout, where the Spear was learned
  (owner, 2026-10-11, confirmed on 2026-10-15 in question 50; the
  [dungeons plan](../../design/2026-10-11-release-1-dungeons-plan.md#4-yois-hideout)):
  below the hatch a water maze, where a thrown pot rang an old alarm bell
  that opened a gate, led to Yoi's den. He taught the Spear there, and a bell
  that only the Spear rang opened the shortcut home. The prologue teaches the
  Spear now (questions 97 and 99).* *Changed 2026-10-16 (seventh round,
  question 114): Spear-only bells come back across the world as a second
  kind of Spear lock ([Secrets](#secrets-planned)).* *Changed again
  (eighth round, question 115): no bell is the Spear's; bells are a ranged
  lock for a thrown pot or an arrow.*

## The West village: young Burr's Roll (Built 2026-11-19, owner, 2026-10-16)

**Where:** Burr's house in the West village, west of Slimeshire Meadow. Part
of the village joins Release 1: a small town like Kakariko, with Burr's house,
three or four more houses, a shop and a game to play (owner, 2026-10-16,
[question 73](../07-decisions-archive.md#contradictions-left-after-the-review-2026-10-15)).
Not built.

*Changed 2026-11-17 (owner, question 150): Burr's house is in Slimeshire's C4
(`burr-house`), and his son, inside, teaches the Roll there. The lesson no
longer sends the slime west: the West village's town is Glimmerhill, which the
slime reaches only with the Heavy Roll (question 149). The rickety plank over
a dry ditch goes to the yard of the house in C4. As built (2026-11-19): young
Burr waits inside the house in C4 (moved from Glimmerhill's B4 gatehouse on
2026-11-18); his first talk is the lesson, with the Roll's ceremony and a tip
about the planks, and he asks the slime to find his father. The slime no
longer has the Roll from birth; a save already past Burr's cell or a Pearl
learns it quietly.*

1. **Plop's tip.** After the Spear, Plop says the worms have shut their
   burrow with the old Thorn Guard gate, and only **Burr**, the gatekeeper in
   the West village, knew its trick. *Since 2026-10-16 (sixth round) the
   Spear comes first, in the prologue, so this is the tip Plop gives later,
   after meeting the slime at the town's edge (question 100).* *Changed
   2026-11-17: the tip points to Burr's house in C4 (question 150).*
2. **Burr's house is empty.** His son, **young Burr**, says his father went to
   fight Fatty and never came back. He shows the trick his father taught him:
   curl up and roll. The slime learns the **Roll**, with its ceremony, and
   promises to find his father.

- It is the quick roll. The held, charged roll (the rework's `roll-charge`
  upgrade) comes later with the other upgrades ("upgrades of skins and
  abilities come later in the game"). The quick roll is the Roll, and the
  charged roll is a later upgrade, like the Roll's enemy push: this replaces
  the 2026-10-09 rule that the Roll comes whole (owner, 2026-10-16,
  question 78).
- The Roll comes before Fatty One Eye, so the Heavy skin's Roll works as soon
  as the skin is won (Beat 5).
- **Its first lock** (Built 2026-11-19, owner, 2026-10-16, question 132): a
  rickety plank over a dry ditch in Burr's yard, right after the lesson. The same
  yard later holds the Bow's first targets
  ([Chapter 3](chapter-3-crystal-caverns.md#beats)); *moved 2026-11-20 to the
  lake camp's river in C5 (owner: C4 was overcrowded).* *As built: a short dry
  ditch with earth walls beside the cottage's west side, two old planks across
  it that drop under a walking slime (one quick Roll crosses both), and a
  small chest with 15 coins in the nook beyond; a fall puts the slime back in
  the yard.*
- The town's shop sells potions and food ingredients, so coins have a use
  (owner, 2026-10-16, question 88), and a secret in the village teaches a
  simpler potion (question 89). *Since 2026-11-17 the town is Glimmerhill,
  asleep until the Pearls wake its parts (question 149); built 2026-11-20
  ([VILLAGERS.md](../../godot/VILLAGERS.md#asleep-until-its-pearl-comes-home-2026-11-20)).*

## Beat 4 — Worm Trouble [`worm-trouble`] (Built)

**Giver:** Mossy.

- **The player does:** crafts a Wooden Spear, then clears the worm camp
  south-east of the clearing (3 worm swordsmen). Since 2026-10-15 the crafted
  spears go (the Spear shape from Yoi replaces them; their hammering is
  dropped), and so do the quests: NPCs give tips in their place
  (question 60).
- **Reward:** the Stone Spear recipe and 30 coins. Until 2026-10-08 it also
  taught Jump, with a jump lesson from Mossy; the jump has been removed from
  the game.
- **Proposal, a story hint:** the worms are not raiders, they are refugees.
  - Mossy: "Funny thing. They fight like something chased them out of their
    own burrows."
  - *Dropped: the owner's decision of 2026-10-16 makes the worms Gorge's
    army, with mean faces, never cute or scared
    ([Premise](../02-premise.md#backstory)).*

## Fatty's Lair: the gate, the slabs and Burr's cell (Planned, owner, 2026-10-16)

**Where:** the worms' burrow, Fatty One Eye's dungeon. Not built; the
[dungeons plan](../../design/2026-10-11-release-1-dungeons-plan.md#6-dungeon-1-fattys-lair-chapter-1)
of 2026-10-11 has an earlier map of the lair. *Built 2026-10-17
([DUNGEONS.md](../../godot/DUNGEONS.md#fattys-lair-built)); the same day its
gate moved from D4's clearing into the face of a hill in D5, reached through
the old fort's field maze and over a moat's falling slabs (owner, 2026-10-17;
[Slimeshire's places](#slimeshires-places-built-2026-10-17)).* The Roll opens the burrow, and
the Spear's job in the lair is Fatty's eye.
Its own enemies, the Pipe Worm, the Dung Roller and the Squint with its
mini-boss, the Big Squint, are in the
[bestiary](../../design/2026-10-16-bestiary.md) (owner, 2026-10-16,
question 107). Like every dungeon, the slime cannot save inside it
(question 62). *Since 2026-10-16 (seventh round, question 109): quitting or
fainting inside it resumes at its entrance, and the lair keeps what the
slime did there: small keys, opened doors, the map, the big key. The
autosave waits until the slime is out.*

1. **The burrow's lock.** A worm lever lifts the old Thorn Guard gate, and
   the gate drops shut a moment later, too fast to walk through. A rolling
   slime gets through.
2. **Falling slabs.** Behind the gate, loose slabs and bridges fall too fast
   to cross walking, but slowly enough to cross rolling. They come back after
   10 seconds. Under them are holes:
   - **lava:** damage over time until the slime walks out by a stair set
     there, so it can try again;
   - **spikes:** normal damage each time its invulnerability ends, until it
     steps off;
   - **the void:** damage, and the slime goes back to the start of the
     bridge.

   Chapter 1's slab bridges cross the void and spikes; lava waits for a fire
   region. The slabs, the spikes and the lava share one hazard script, and
   the void works like the elevation's holes (owner, 2026-10-16,
   question 70). A slab falls a set time after the slime touches it (a value
   in `game-constants.json`), tuned in the playground so quick rolls in a
   row cross a bridge and walking never does (question 71).
3. **Burr's cell.** In the lair's first half Burr sits in a cell. A **small
   key** found in the lair (a key from the planned dungeon kit) frees him; he
   thanks the slime and asks it to visit him at home. *Since 2026-10-16
   (eighth round, question 134): the cell lies on the lair's main path, so
   freeing him cannot be skipped.* The lair's deep rooms hold the skeletons,
   the fallen Thorn Guard whose bones Gorge's vassals raised to guard the old
   forts (question 125). *Since 2026-10-19 (owner): Burr pays back his
   freeing at once. The hub's drawbridge, the short way to Fatty's door,
   takes two: one body on each of its two plates. Burr holds one; the slime
   sinks the other, the bridge comes down for good, and Burr says goodbye,
   wishes it luck and leaves to wait outside. The bridge no longer needs the
   Heavy skin.* *Since 2026-11-20 (owner): as he is freed, after "My boy
   taught you the trick..." and before the Inner Stair and the drawbridge,
   Burr gives the first **Roll Fragment**: he has been perfecting a better
   trick, the Charged Roll, carved into a training disc that Gorge's lot broke
   in four and hid; he kept this piece in his boot; find the other three.
   Owner: Burr's must be the first fragment. Built the same day.*
4. **Fatty One Eye.** The Spear on his eye beats him, and Pearl 1 gives the
   Heavy skin (Beat 5). *Since 2026-10-16 (eighth round): he also leaves a
   full heart (question 17), and the lair's way out is the Heavy skin's first
   lock, opened with the new skin (question 132; which lock is not
   decided).* *Changed 2026-10-17 (owner): Pearl 1 lies in the lair, before
   Fatty: he cannot swallow it whole, so he hides it close to draw on its
   power. When the slime takes it he notices, enraged (his strength stays the
   same), and seals the lair's exits: the only way out is to beat him. The
   lair's second half teaches the Heavy skin, and his fight is its exam.
   *Changed 2026-11-21 (owner, the boss rework): his fight no longer tests
   the Heavy skin (the lair's second half does). The Spear still hurts his
   eye, his weak spot, and thrown things hurt for half a Spear hit. Each
   jump brings dirt down from the roof at random (it hurts where it lands,
   and the last fall's clods melt before the new ones fall); a hit shuts his
   eye for 3 seconds. In his second phase his eye stays shut until two
   thrown things knock him down, his eye wide open, as before; only his
   first jump makes the mud wave. Built the same day.*
   Fainting or quitting after the Pearl resumes at the entrance, inside, with
   the doors to the outside sealed until he falls. The built lair keeps the
   old order until its rework
   ([roadmap 12.8](../../GAME_ROADMAP.md#the-2026-10-17-decisions)).*
   *Changed 2026-10-19 (owner): once Fatty falls the lair caves in, as a
   Zelda dungeon is done for good. The slime escapes by the postern and the
   bolt-hole into D4, and the gate in Fatty's Hollow lies buried after. Its
   come-back secrets move outside into Slimeshire
   ([the plan](../../design/2026-10-19-lair-secrets-outside.md)).*
   *As built (since 2026-10-24): in his second phase a thrown mud ball throws
   him off balance for 2 s, a Heavy Roll then knocks him down for 3 s, and the
   Spear hits his eye. The green key lay in the Postern's chest (R14); since
   2026-11-20 the chest holds coins and a potion (question 163).*
   *Changed 2026-11-17 (owner, question 146): bosses are hurt by throws, or by
   something the slime throws into a mechanism; his fight changes when the
   bosses are revisited (question 166).*
5. **After Fatty** (Planned, owner, 2026-10-16, question 103). The freed Burr
   says the town must see the Pearl, the journal's main quest points home,
   and Slimeshire's well comes back when the slime brings the Pearl to it
   (Beat 5). *Changed 2026-10-16 (seventh round, question 110): the slime
   takes the Pearl home to the Wellspring, which brightens, and its power
   flows into the town and brings the well back.* *Changed 2026-11-17 (owner,
   questions 149 and 153): Pearl 1's power fills Glimmerhill's first fountain
   and wakes Market Hill, and a woken fountain refills energy in place of
   Slimeshire's well.* *Built 2026-11-20: Pearl 1's homecoming at the
   Wellspring wakes Market Hill, and the camera shows its fountain burst into
   flow.* *Built 2026-11-21: a woken fountain offers a drink that fills the
   slime's energy, then rests a minute (`fountain.drinkRestMs`).*
6. **Back home.** In the West village Burr gives his thanks: an energy
   upgrade (max energy grows only through secrets and bosses, question 19) or
   a heart. Which one is not decided. *Since the eighth round (question 19):
   potions, the well and bosses raise max energy.* *Changed 2026-10-16 (owner,
   question 80): his thanks is the **Bow**, an Ability Box power. It was to
   come after Release 1, so when it comes is question 85.* *Changed again
   2026-10-16 (owner, questions 85 and 94): the Bow is in Release 1, in
   Chapter 3. Burr gives it when the slime comes back to the West village
   after Chapter 2, no longer right after the lair
   ([Chapter 3](chapter-3-crystal-caverns.md#beats)).*
   *Changed 2026-10-16 (sixth round, questions 102 and 106): visited before
   Pearl 2, Burr thanks the slime and gives a tip: "I am making you
   something, come back when the forest is free." He needs silk and other
   things to build it: the silk is the **Matron's thread**, a spool the
   slime finds in her nest after she falls (with the Silk skin it can take it
   from her web), and the other things are already in his workshop. With the
   thread and Pearl 2 home, he teaches the Bow: one find, one trip back, and
   no crafting.* *Changed 2026-11-17 (owner, question 150): home is his house
   in Slimeshire's C4, so his thanks waits there, not in the West village.*
   *Changed 2026-11-20 (owner): Burr no longer teaches the Bow. His thanks
   tells how the Thorn Guard's bows were shaped from goo by carved runes, and
   that Pip could carve one once Slimeshire's old Workshop stands; Pip carves
   it in Chapter 3 ([Chapter 3](chapter-3-crystal-caverns.md#beats), beat 1).
   Built the same day.*

## Beat 5 — The One-Eyed Guardian [`the-one-eyed-guardian`] (Built)

**Giver:** Elder Plop.

- **The player does:** crafts a Stone Spear (it goes with the crafted weapons
  since 2026-10-15: the Spear shape replaces it), then beats **Fatty One Eye**
  by aiming for his eye.
- Plop: "Beyond it lies Gloop Forest, and the rest of the world." *(in game)*
- **Proposal, Pearl 1:** Fatty's eye glows because a Pearl is lodged behind it.
  - Beaten, he shrinks and the Pearl pops free. This is the full ceremony and
    the first time the player sees a Pearl.
  - *Changed 2026-10-17 (owner): the Pearl is not in him. He hides it in his
    lair, and the slime takes it there before facing him, with the full
    ceremony ([Fatty's Lair](#fattys-lair-the-gate-the-slabs-and-burrs-cell-planned-owner-2026-10-16),
    step 4). Why his eye glows, and whether he
    shrinks when he is beaten, are not decided.*
  - The Pearl transfers the **Heavy skin**, his own weight, permanently into
    the slime: it sinks the heavy plates and moves statues, pedestals and
    blocks (owner, 2026-10-15). Its Roll shakes things loose and breaks small
    loose things lying in its way (a loose rock, a rubble heap, a rotten
    trunk across a path), with a strong screen shake; it does not push
    enemies away (owner, 2026-10-16, questions 61 and 77). The skin stays
    when the Pearl later returns to the Wellspring.
  - Plop explains what it is when the slime next returns to Slimeshire, which
    the Forge quest in Chapter 2 makes happen. In the plan the journal's first
    Pearl slot fills and lights up its part of the picture (question 60).
    *Changed 2026-10-16: the Forge quest goes, and Pearl 2 relights the Forge
    (question 79). What brings the slime home with Pearl 1, and which
    building Pearl 1 restores, are not decided yet.* *2026-10-16 (owner,
    question 90): Pearl 1 restores Slimeshire's well, which then refills the
    slime's energy. What brings the slime home with it is still not
    decided.* *Answered 2026-10-16 (sixth round, owner, questions 98, 103
    and 105): after Fatty, the freed Burr says the town must see the Pearl,
    the journal's main quest points home, and the well comes back when the
    slime brings the Pearl to it. The well then gives a full refill, a drink
    in town, and beds also restore life. Each Pearl's homecoming is a short
    scene at the Wellspring, the prologue's lake.* *Changed 2026-10-16
    (seventh round): the Pearl goes home to the Wellspring, not to the well;
    the Wellspring brightens, and its power flows into the town and brings
    the well back (question 110). The well's refill grows back after a while
    (question 113).*
- **Boss heart** (Planned, owner, 2026-10-16, question 17): Fatty also leaves
  one full heart (+20 max HP), and beating him raises max energy
  (question 19).
- **The player does next:** takes the green key from the chest and opens the
  Verdant Gate.
  *Changed 2026-11-17 (owner): outside the dungeons a way is shut by
  something a power removes, not by a key gate. A fallen tree that a Heavy
  Roll breaks replaces the Verdant Gate, so the green key goes; what the
  Postern's chest holds instead is question 163. Another fallen tree, broken
  the same way, blocks the way from C4 into Glimmerhill's Market Hill
  (question 149).* *Built 2026-11-20 (owner, question 163): the place keeps
  its name, its gate long gone; a grey fallen tree lies across its road in D4,
  another north to south across the Market Hill road a little inside C4's
  west edge, and only a Heavy Roll breaks them (flags
  `level-1.verdant-tree-smashed`, `level-1.market-hill-tree-smashed`). The
  Postern's chest holds coins and a potion.*
- **Reward:** 100 coins, the flag `chapter-1-complete` and, today, **Squash
  Slam** (Built 2026-10-08). Planned: the reward loses the Slam, which is
  removed (owner, 2026-10-15). Mossy moves to the forest camp.

## Slimeshire's places (built 2026-10-17)

The owner (2026-10-17): "move Fatty's Lair entrance to D5, put it in a hill
with a nice maze to get to it, with some falling slabs to try the Roll", and
make Chapter 1's maps nicer by the
[level design guide](../../design/2026-10-16-level-design.md#slimeshires-chunks-and-the-west-village).
Built by `godot/tools/build_slimeshire_chunks.gd` (it rewrites only its own
rects of the four chunk scenes). Each chunk's card, as the guide's template
asks:

```
Chunk: level-1-c4 (the village)
Landmark: the plaza's well
Main way: the forest path from the prologue onto the fenced level-1 plateau; north stairs
          to town, south stairs to C5. The river bridge crosses the C4/D4 border. Three
          fence gaps offer ledge drops; the river and lake rims remain fenced.
Secrets: [first lock, open now] the first bell, on an islet in the little pond at the town's
         edge, pots on its shore: a thrown pot rings it and unlocks the keeper's storehouse.
         Its door is built into the timber facade; the coffer (coins, a tonic) is hidden from
         outside in a separate interior with pots, grain sacks, a barrel, crate, desk and shelf.
         Tell: an ordinary shut storehouse and the pond bell. Way back: the bell's unlock stays
         remembered (question 136). The coffer retains its old save record.
         [come-back] Yoi's home under Lili's west yard (built 2026-11-20, roadmap 5.12)
Enemies: the starter camp (3 worm swordsmen, unchanged); a quiet road from the forest path
Rest: the town's campfire (the camp square)

Chunk: level-1-c5 (the lake)
Landmark: the blossom tree on its island in the lake
Main way: from C4's south stairs across the road bridge, down the lake road on the east shore
          to the camp, east into D5 (rows 8-9)
Secrets: [open now] the lookout rock by the copse (no way up): a bell on its top, rung by a
         pot thrown from its foot, raises a chest (coins, an energy potion)
         [open now] south-west islet chest and pots, reached by a shallow ford
         [come-back, charged Roll + Goo Bomb] six falling planks without a landing to the
         north island; two swordsmen and an archer guard a cracked rock. The cave beyond
         holds chests and pots; its future secret spot is empty.
         [come-back, Swim skin] the dark square in the shallows near the fishing jetty
         [come-back, Bow] the Bow's first lock (2026-11-20, from Burr's yard): two crystal
         lenses on the river's north bank by the road, shot from the camp's bank across the
         water; both struck, a chest of 20 coins rises by the camp
Enemies: the south meadow camp (2 brawlers, a slime spider); three island worms
Rest: the lake camp's campfire
Comes back: deep water for the Swim skin, after Release 1 (no heart quarter behind it: the
            goo heart that waited on the west islet moved to D4's pen, question 135)

Chunk: level-1-d4 (the Verdant Gate)
Landmark: the Verdant Gate
Main way: the road from C4's bridges east to the gate; south through Fatty's old camp
          clearing (a torn banner, crates) to D5's north road
Secrets: [come-back, Heavy] an old Thorn Guard pen by the road, its gap shut by grey planks
         (the Heavy Roll): the lake's goo heart hidden in a chest inside. Seen on the
         way to the Verdant Gate; opens on the way home with Pearl 1.
         [open] the plateau's goo heart hidden in a chest (the cliff secret)
Enemies: the Webwood's 3 slime spiders (unchanged)
Out of the Lair: the bolt-hole's mouth by the Verdant Gate, Burr waiting
The Verdant Gate (since 2026-11-20): no gate, a grey fallen tree across the lane north of the
         banners; a Heavy Roll breaks it (`verdant-tree`)
The south-east field's way into D5 closed with trees (the hill stands behind it)

Chunk: level-1-d5 (Fatty's Hollow)
Landmark: a red-rock hill crowned with maples and ginkgos, the Lair's gate in its face
Main way: the north road from D4's clearing and the lake road from C5 meet at a lamp, run to
          the plaza before the maze's door; through the old fort's field (a maze of
          fieldstone walls, 2-cell corridors, a loop, two dead ends); over the dry moat on a
          bridge of two falling slabs (one Roll; a walk falls, back on the rim, little cost);
          stairs up to the forecourt; the worm lever and the drop gate (a Roll north under it)
Secrets: [open] the west dead end: two pots, a heart and coins; the east dead end: a chest
         (coins, a tonic), guarded by an archer
         [come-back, Goo Bomb] a crack in the hill's face beside the gate: blown, a passage
         into hollow-hill-cave, a separate room with the grove's goo heart hidden in a chest
Enemies: an archer alone in the maze's long west row (step off its line by the loop);
         an archer by the east chest, two brawlers before the stairs
Rest: the forecourt's campfire, an energy flower, a pot hiding a heart (the calm spot
      before the Lair)
Loop back: the forecourt's west rim is a ledge drop to the maze's door
```

Not built here: the forest path's skin locks (B4), Thorn
Guard border posts (question 130: they need a striped barrier and a guard,
no art yet), the grey leaning tree over a river (question 101: D5 has no
river), a climbable wall (Feral).

*Since then:*

- *2026-10-19 (owner): the Lair's come-back secrets moved outside
  ([the plan](../../design/2026-10-19-lair-secrets-outside.md)): the
  **sally port** in C4, an open hole in a fenced pen with a hatch exit (its
  planned prize a campfire recipe); the **Glow-moss Burrow** in D4's
  dark-forest maze, opened when the Lantern burns a dry trunk (a heart
  quarter); and the **Old Armoury** in D4, a level-2 hill with a hidden crack
  for the Goo Bomb, whose chest the Lantern opens (coins until its war-journal
  page is built).* *Built 2026-11-20: the sally port's chest holds a recipe
  page for the Berry Basket, and the Old Armoury's the war journal's first
  page, "The Old Gates".*
- *2026-11-12 (owner): the forge has no door, so it has no interior; the
  slime's home is behind the round mushroom house of C4.*
- *2026-11-17 (owner, question 150): **Burr's house** stands in C4, his son
  inside, who teaches the Roll; the rickety plank over a dry ditch goes in its
  yard, and later the Bow's first targets. A fallen tree that a Heavy Roll
  breaks takes the Verdant Gate's place in D4, and another blocks the way from
  C4 into Glimmerhill (question 149). Not built yet.* *Built 2026-11-20: both
  trees ([SKINS.md](../../godot/SKINS.md#heavy)); C5's way south into the
  Wilds is planted shut (question 164).*

## Secrets (Planned)

- **Four heart quarters** are hidden in Slimeshire Meadow. Their spots are
  Open. *Since 2026-10-16 (question 99): one is in Yoi's home.* *Changed
  2026-11-17 (owner, question 151): five, the fifth in Yoi's home.*
- Today two Goo Hearts are placed in `level-1`. They become quarter spots, or
  move to harder ones. *Since 2026-10-17 three goo hearts stand in for
  quarters ([Slimeshire's places](#slimeshires-places-built-2026-10-17)): D4's
  pen (the Heavy Roll), D5's hill cave chest (the Goo Bomb) and D4's plateau
  (open); Yoi's home holds the fourth when it is built.* *As built
  (2026-11-14): all are quarters since 2026-10-26, and the four placed are
  D4's pen (the Heavy Roll), D4's cliff (open), the hill cave (the Goo Bomb)
  and the Glow-moss Burrow (the Lantern); Yoi's home holds a fifth
  (question 151), built 2026-11-20.*
- At least one quarter should need a later power (the Silk skin, the Feral
  skin's climbing, the Heavy skin's Roll, the Goo Bomb), so that coming back
  pays off. A few optional secrets may combine a skin and an ability, each
  clearly different (owner, 2026-10-16, question 84). The War Axe's and
  Stretch Lash's locks wait for the next release (question 94). The water
  secrets wait for the Swim skin (owner, 2026-10-15).
  *Changed 2026-10-16: the Swim skin comes from a later Pearl, so they wait
  until after Release 1 (question 56): the deep-water secrets are come-back
  secrets (question 75).*
- **Bells** (Planned, owner, 2026-10-16, eighth round, question 115): a
  ranged lock across the world, rung by a thrown pot or an arrow, never by
  the Spear or the Stretch Lash. The first stands near the town's edge, soon
  after the prologue, rung by a thrown pot (question 132), and what a bell
  opens stays open for good (question 136). *Built 2026-10-17: the first in
  C4's pond at the town's edge, a second on C5's lookout rock
  ([Slimeshire's places](#slimeshires-places-built-2026-10-17)).* *Until then (seventh round,
  question 114): Spear-only bells, a second kind of Spear lock that a thrown
  pot could not ring.*
- **Every heart quarter** here can be reached with Release 1's powers: none
  waits behind deep water or another later-release lock, and those locks
  are few, each with a line that says it needs something not found yet
  (owner, 2026-10-16, question 135).
- **The worm camps** (Planned, owner, 2026-10-16): enemies in the world are
  placed by hand, a fixed number per chunk, each with its own wandering area,
  and they come back when the chunk is reloaded. Today the worm camp spawns
  from an enemy-spawn area and refills on a timer
  ([World](../03-world.md#enemies-in-the-world-planned)).

## Chapter 1 checklist

| Item | Beat | Status |
|---|---|---|
| The prologue: the Wellspring, the glade, Yoi and the barred gate | 0 | Built 2026-10-16 ([PROLOGUE.md](../../godot/PROLOGUE.md); planned by the owner the same day, question 97) |
| The one bag (10 slots, from Plop) | 0 (the town's edge), 1 | Built 2026-10-16: Plop's satchel, given at the town's edge (questions 53, 74 and 100) |
| Stone Axe, Stone Pickaxe | 1–2 | Built; they go with the crafted tools (2026-10-15) |
| Spear (an ability since 2026-11-17, question 146) | 0, the prologue | Built 2026-10-16: Yoi teaches it in the prologue (owner, 2026-10-16, question 97; Yoi's Hideout from 2026-10-11, question 50); a box ability (15 energy) in throw mode |
| Yoi's home (a heart quarter, his tips) | Yoi's home | Built 2026-11-20, an optional secret (owner, 2026-10-16, question 99): the heap hatch in Lili's west yard, his den with Yoi and his four war tips; its quarter is Slimeshire's fifth (owner, 2026-11-17, question 151) |
| Roll | Burr's house in C4 (question 150) | Built 2026-11-19: the lesson from Burr's son in their house in C4, with its first lock in the yard (owner, 2026-11-17, question 150; young Burr in the West village from 2026-10-16, question 61) |
| Burr's house (C4) | The West village section | Built (owner, 2026-11-17, question 150): the cottage, its room with young Burr (2026-11-18) and the yard's dry ditch, planks and chest (2026-11-19) |
| Home (bed) | 3 | Planned (question 60); the home is behind the round mushroom house in C4 since 2026-11-12 |
| Vault | 3 | Waits for a later release (owner, 2026-10-16, question 53) |
| Wooden Spear, Stone Spear | 2–5 | Built; they go (the Spear replaces them) |
| Small key (Burr's cell) | Fatty's Lair | Built 2026-10-17 ([DUNGEONS.md](../../godot/DUNGEONS.md)); planned by the owner on 2026-10-16 |
| Burr's thanks (the Bow until 2026-11-20) | Fatty's Lair, then his house in C4 (question 150) | Planned (owner, 2026-10-16, questions 80, 94, 102 and 106); it is given in Chapter 3; Built 2026-11-20 (Burr at home in C4, his talks and the first lenses, by the lake camp's river in C5 since the same day). *Changed 2026-11-20 (owner): his thanks points to Pip, who carves the Bow's rune in Chapter 3; Burr's lesson is gone* |
| Squash Slam | 5 | Built (quest reward); its removal (2026-10-15) is Planned |
| Green key | 5 | Gone from the main path (owner, 2026-11-17): since 2026-11-20 the Postern's chest holds coins and a potion (question 163) |
| The fallen tree in the Verdant Gate's place, and the one on the way into Glimmerhill | 5 | Built 2026-11-20 (owner, 2026-11-17, questions 149 and 163): `object.fallen-tree` in D4, `object.fallen-tree-ns` on the Market Hill road in C4 |
| Pearl 1 | 5; Fatty's Lair, before Fatty, since 2026-10-17 | Built 2026-10-17 in the Larder (R12); its homecoming, which wakes Market Hill (question 149), built 2026-11-20 |
| Heavy skin | 5; Fatty's Lair's second half since 2026-10-17 | Built 2026-10-17 ([SKINS.md](../../godot/SKINS.md#heavy)) |
| Boss heart (Fatty) | 5 | Built: a full heart, +20 max HP and +20 max energy (owner, 2026-10-16, questions 17 and 19) |
| The first bell, by the town's edge | Secrets | Built 2026-10-17 in C4's pond (questions 115 and 132) |
| 5 heart quarters (question 151) | Secrets | Built and placed (quarters since 2026-10-26); Yoi's home's fifth since 2026-11-20 |
| The Charged Roll, an ability upgrade | Secrets | Built 2026-11-20: found whole in Yoi's chest, with its card (owner, 2026-11-17 and 2026-11-19; which others, question 160); the `roll-charge` upgrade, lent in the playground too. *Changed the same day (owner): four Roll Fragments make it, the fourth teaching it with the card* |
| Roll Fragments 1 and 2 (of 4) | Fatty's Lair (Burr, as he is freed); Yoi's home (his chest, behind a Heavy statue maze) | Built 2026-11-20 (owner, the same day); the other two lie in Glimmerhill's A4 barn and the Gloop Cavern ([unlock map](../05-unlock-map.md)) |
| The war journal's first page; the sally port's recipe page | Secrets | Built 2026-11-20: the Old Armoury's chest ("The Old Gates") and the sally port's chest (the Berry Basket at a campfire); each opens a reading panel |

Second pass (2026-10-17): the maps and cave scenes are built; visual review and the owner's playthrough remain. The island bridge requires `roll-charge`, unavailable in Release 1. *Changed 2026-11-17 (owner): the Charged Roll is Release 1's first ability upgrade, found whole in a secret place (question 160), so the island bridge becomes its come-back.* *Built 2026-11-20: the Charged Roll is in Yoi's chest.* *Changed the same day (owner): the fourth Roll Fragment teaches it, so the island waits for all four (Burr's, Yoi's, the A4 barn's in Glimmerhill, the Gloop Cavern's).*
