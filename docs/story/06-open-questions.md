# Open Questions

Decisions waiting on the owner. When one is answered:

1. Write the answer and its date under the question.
2. Change the matching tags in the other files: a Proposal or Open item becomes
   Planned.

## Scope

1. **Which 2026-10-02 decisions go into Release 1, and which wait?** Several
   of them change Release 1 content: the bags, sprint moving to mid-game, the
   armors, the webs, the vault, the timed crafting and the HUD orbs. The
   roadmap's rule is that a new idea goes to the parking lot unless it replaces
   work of the same size.
  response 10/02/2026 All decisions go into release 1 and should affet the road map , most of them ar importan fro the game and the story so they need to be implemented when approved.
  2026-10-07: the [roadmap](../GAME_ROADMAP.md#the-2026-10-02-decisions) now carries them as Release 1 tasks: 4.12 (bottom console HUD with the orbs and the boss bar), 4.13 (item ceremony), 5.3 (heart quarters), 5.6 (energy), 5.7 (bags), 5.8 (vault and house quest), 5.9 (Pearls grant abilities), 6.5 (hammering), 7.5 (armors), 7.6 (webs), 7.7 (the roll), changes to 8.5–8.10, and 8.12–8.13 (earning the armors); weapon dropping (UX.3) moved to its Dropped list.

## Story

2. **The premise.** The Wellspring, the Pearls and Gorge in the
   [Premise](02-premise.md): keep them, change them, or use something else?
3. **The hero's name.** "The slime", or Isa?
4. **Does the hero talk?** This draft proposes a silent hero.
5. **Where is the Wellspring?** In the plaza, or in the clearing where the
   slime is born?
   *Owner: in its own new map east of level-1, the game's first map.*
6. **Bosses after their Pearl is gone.** Should they keep respawning every five
   minutes, as today? Or stay calm for good, as in Zelda, perhaps leaving a
   smaller rematch version?
   *Owner: a beaten boss does not appear again.*
7. ~~**Lili and Lily.**~~ The names are too close. Rename one?
   *2026-10-11 (owner, in the
   [dungeons plan](../design/2026-10-11-release-1-dungeons-plan.md)): Lily the
   fisher becomes **Dora**; her NPC id `fisherman-slime` stays, and her
   display name, dialogue and the docs change. Not applied yet: the game and
   the generated world tables still say Lily.*
8. ~~**Pip's dad.**~~ Is he found in Chapter 3, as the
   [sketch](chapters/chapter-3-crystal-caverns.md) proposes?
   *2026-10-16 (owner, question 59): yes, but not trapped. The smith runs the
   crystal mine, and the slime finds him safe at his mine camp, where he gives
   it the Lantern; he goes home once the Colossus falls.*
9. **The midpoint.** In which chapter does Gorge wake, and what does he do
   first?
10. **How many regions?** Also: what order for Sticky Swamp and Frostpeak, and
    where do castles and mazes go?

## Progression

11. **The house quest.**
    - Is the house the slime's own (the red forge house leading to the Slime
      Home, recommended) or the mushroom house?
    - Does Plop give the quest?
12. **More vaults.** After the first vault is found, can the slime craft more?
    One at the forest camp, for example.
13. **The Stone Armor.** Is it earned in a stone shrine in the forest, or as
    Fatty One Eye's reward? It must come before the iron hollow.
    *2026-10-08: no armors. The Clod Stomper drops stone essences, and Tom
    teaches Swallow before the iron hollow. Both built 2026-10-09.*
    *2026-10-15: Fatty One Eye's Pearl grants the Heavy skin, so the slime has
    it before the iron hollow.*
14. **The Silk Armor.** Is the Weaver Hollow mini-dungeon the place? And
    should today's silk cocoon Gulp spots be removed, or become energy refills?
    *2026-10-08: no armors. Spiders drop silk essences, and the cocoon spots
    become placed silk essences. Still open: whether the Weaver Hollow stays as
    a dungeon (question 25).*
    *2026-10-15: the Matron's Pearl grants the Silk skin. Silk essences are
    marked for deletion.*
15. **Wearing armors.**
    - Is only one armor worn at a time?
    - Does an armor drain energy the whole time it is worn, or only when its
      power is used (passing a web, breaking ground)?
    - How does the slime switch armors? Q is the Gulp key today.
    *2026-10-08: replaced by essences. One form at a time, from the last
    essence swallowed; no timer and no energy cost.*
    *2026-10-15: armors and forms became skins from the Pearls, free and
    permanent. How the slime switches skins is question 34.*
16. **The sprint roll.**
  - ~~Which of the remaining six Pearls grants it, and in which chapter?~~
    *2026-10-15: no Pearl teaches it; a manuscript or a rescued NPC
    (question 33).*
    - Should it share one button with Dodge (tap to dodge, hold to keep
      rolling), with the hold unlocked mid-game as an upgrade of the Dodge?
    *2026-10-08: the Dodge becomes the Roll (on key 2 since 2026-10-09), and it keeps rolling
    while held. Its other rules come later (question 26). Built 2026-10-09:
    tap to spin up and shoot off, hold to keep rolling.*
    *2026-10-09 (owner): no upgrade. Once the slime learns the Roll, it learns
    everything about it, holding included (Stone Tools teaches it today).*
17. **Boss hearts.** Does each boss also give a full heart (+20) on top of the
    map's four quarters?
18. **The Gloop Cavern.** Is it its own map with four quarters, or does it
    share Gloop Forest's four?
19. **Energy growth.** What item raises max energy, and where is it found?

## Energy rework details

These are proposals from the planning talk that have not been answered:

20. After spending, the refill pauses for about one second, then refills at a
    fair speed. The pressure comes from the pause, not from long waiting.
    *2026-10-15 (owner): no regeneration at all. Only potions and energy shards
    refill energy, so the player is careful with abilities.*
    *Changed 2026-10-15 (review, question 40): energy refills by itself after
    all, but slowly, 1 a second, and more ways to recover it are to come.
    Whether the refill pauses after spending is still open.*
21. Basic attacks stay free, so the slime is never helpless.
22. Tiny cooldowns stay as an anti-spam guard.
23. Rolling needs a minimum amount of energy to start.
24. Enemies and grass sometimes drop energy (like Zelda's magic jars), which
    rewards fighting over waiting.

## Gulp, Roll and essences (2026-10-08)

25. **The Weaver Hollow.** It was the place to earn the Silk Armor. Keep it as
    a small dungeon, or drop it?
26. **The Roll's rules.** Is holding to keep rolling there from the dodge's
    lesson, or earned later? What does it cost in energy, how fast is it, and
    can it steer? Does a roll in the Stone form break cracked walls?
    *2026-10-09: built for the owner to try (roadmap 7.7). Holding keeps it
    rolling from the start, and only the held part drains energy (12 per
    second).*
    *2026-10-09 (owner): it feels like Zelda's Pegasus Boots dash. It goes
    straight and cannot steer or move sideways; hitting a wall shakes things
    and the screen, and the slime bounces back. Everything comes with the
    lesson. Rebuilt the same day. Still open: the feel and numbers, its energy
    cost, and the Stone-form roll (not built).*
    *2026-10-15 (review): the quick Roll stays free (question 40), and the
    Heavy skin replaces the Stone-form roll: its Roll pushes enemies away and
    shakes things loose (question 41). Cracked walls are the Goo Bomb's.*
27. **Webs after the Silk form passes.** Does a web stay, or tear open as it
    does today?
28. **The lift upgrades.** What are the two upgrades that suck in heavy rocks,
    and where are they found?
29. ~~**The swim essence's monster.**~~ *2026-10-15: essences are marked for
    deletion.*
30. ~~**Essence recipes.**~~ *2026-10-15: essences are marked for deletion.*

## Skins, shapes and abilities (2026-10-15)

31. ~~**Chapter 2's key tool.**~~ Swallow was it. The Goo Bomb, the Lantern (both
    built in the rework mode), the War Axe (the 2026-10-11 dungeons plan), or a
    new item or ability? Does Tom teach it, or does his beat go?
    *Proposal (review, 2026-10-15): the Goo Bomb. It opens the cracked
    clearing into the Gloop Cavern, Chapter 1 can tease cracked walls, and the
    Matron's fight can be built around it (for example, bombs that knock her
    down from her web). The Lantern stays Chapter 3's light: the dark caverns
    and the Crystal Colossus's braziers.*
    *2026-10-16 (owner, question 59): the Lantern is Chapter 3's, from the
    smith at his mine camp, so it is no longer a Chapter 2 candidate. Still
    open: the Goo Bomb, the War Axe or something new.*
    *2026-10-16 (owner, question 94): the Goo Bomb. Who teaches it or where it
    lies, and Tom's beat, are question 95.*
32. **Skins 3 to 8.** Which skins (aquatic, acid, lava, cloud, ...), and which
    boss holds each?
    *2026-10-15 (review, question 47): Pearl 3, the Crystal Colossus's, grants
    the Swim skin. Still open: skins 4 to 8 and their bosses.*
    *Changed 2026-10-16 (owner, question 56): the Swim skin does not fit the
    Colossus. Pearl 3's skin is Open again, and Swim moves to a later Pearl.*
33. **Who teaches what.** The Roll (a manuscript, or an NPC the slime
    rescues), Stretch Lash (which manuscript, where), Squash Slam (with the
    main story), Teleport, the Goo Bomb, the Lantern, and each shape.
    *2026-10-15 (review): Squash Slam is removed (question 45), and in Release
    1 NPCs teach and chests hold the finds (question 43). The rest is still
    open.*
    *2026-10-16 (owner): the Spear from Old Veteran Yoi (question 50), the Roll
    from young Burr (question 61), the Lantern from the smith (question 59),
    and the Hammer from the smith in Chapter 5 or 6 (question 51). Still
    open: Stretch Lash, Teleport, the Goo Bomb, the War Axe and the Bow.*
    *2026-10-16 (owner, question 94): the War Axe and Stretch Lash wait for the
    next release, and the Bow comes from Burr in Chapter 3. Still open: the
    Goo Bomb (question 95) and Teleport.*
34. ~~**Wearing skins.**~~ *2026-10-15 (owner): always on once learned, with
    no key. Each acts only where the place calls for it, has no downside and
    stacks with the others ([Direction](01-direction.md#the-skins)). Open:
    each skin's exact trigger and look.*
    *2026-10-15 (review, question 41): each skin acts in its own places and on
    its own move: one gate, and one change to a move the slime already has.
    Open: each skin's look while it works.*
35. **Manuscripts.** Whole, or in pieces to collect? How does the player
    track the pieces?
    *2026-10-15 (review, question 43): manuscript pieces wait until after
    Release 1, where NPCs teach and chests hold the finds.*
36. **The Slime Forge.** Where does it stand, when is it built, and what does
    an evolution cost?
    *2026-10-15 (review, question 43): Slime Forge evolutions wait until after
    Release 1 ("upgrades of skins and abilities come later in the game").*
37. ~~**Abilities tied to skins (idea).**~~ *2026-10-15 (owner): dropped. No
    ability is locked to a skin; skin × shape × ability combos give the
    variety instead.*
    *Changed 2026-10-15 (review, question 41): the combos go too ("depth from
    combos makes no sense to me, remove that"). Each skin has its gate and its
    change to a move instead.*
38. **Vaults.** Do all vaults share one storage?
39. ~~**Chapter 3's light.**~~ *2026-10-15: the Lantern, an ability, built in
    the rework mode. Where it is learned is question 33.*
    *2026-10-16 (owner, question 59): the smith gives it at his mine camp.*

## Review of the 2026-10-15 direction

Risks found when the new direction was reviewed (2026-10-15). Each has a
proposal for the owner to accept, change or drop. Chapter 2's key tool has its
proposal under question 31. The owner answered all ten the same day; each
answer is under its question.

40. ~~**The energy economy.**~~ Energy does not refill on its own. A Lantern candle
    puzzle costs 40 (four flames of 10), a Goo Bomb 20, a Squash Slam 35 and a
    charged attack 15 to 25 (Spear, Axe, Hammer), and a held Roll drains 12 a
    second.
    - A slime at 0 energy with no potions can be stuck at an energy puzzle, or
      locked in a boss chamber it cannot win.
    - Shards drop from one kill in five (+15), so the only way out is farming.
    - Players also tend to hoard a scarce resource and never use their powers.

    *Proposal:*
    - Refills that grow back (energy flowers or pots) through the world and
      the dungeons' rooms, not inside the boss chamber unless the boss creates
      minions you kill.
    - A full refill at the Wellspring and at save points.
    - The quick Roll is free.
    - No puzzle costs more than the starting max energy.
    - Before more is built, play one chapter's route and count the energy.

    *2026-10-15 (owner): "energy can recover but really slow, like 1 per
    second; in addition we will add more ways to recover energy." Energy
    refills by itself at 1 a second (in the rework mode
    `character.player.rework.energyRegenPerSecond` is 1 already). The more
    ways are the proposal above as he edited it: refills that grow back
    through the world and in the dungeons' rooms, but not inside a boss
    chamber unless the boss makes minions the slime kills, and a full refill
    at the Wellspring and at save points. The quick Roll stays free (it
    already is: `quickRollEnergy` 0), no puzzle costs more than the starting
    max energy, and one chapter's route is played and its energy counted
    before more is built.*
41. ~~**What each skin does in play.**~~ As written, Heavy and Silk are on/off
    gates: before the Pearl the slime cannot, after it can. They add no action
    of their own.
    - "Depth from combos" names only two examples: the Quake deeper with
      Heavy, the Roll through webs with Silk.
    - The first example clashes with "acts only where the place calls for it":
      if Heavy deepens the Quake, it acts in combat too.

    *Proposal:*
    - Each skin gets one gate and one change to a move the slime already has,
      written in its row of the skins table. For example: with Heavy, a Roll
      that hits an enemy knocks it over; with Silk, the Stretch Lash reaches
      farther.
    - Each skin's trigger is a place (a plate, a web) or an action (a Quake, a
      Roll), and the table says which.

    *2026-10-15 (owner): each skin has its gate plus a change to a move the
    slime already has. **Heavy** (Pearl 1) sinks heavy plates and moves
    statues, pedestals and blocks; its Roll pushes enemies away instead of
    stopping on them, and a Roll that hits a wall, a tree and so on shakes
    things loose, so objects fall. **Silk** (Pearl 2) passes web walls at
    −50%, webs no longer slow it, and weapons (shapes) can cut webs, but only
    once the Silk skin is learned. **Swim** (Pearl 3): deep water. "Depth from
    combos makes no sense to me, remove that": the rule and its examples are
    gone from [Direction](01-direction.md#the-skins), and a skin acts in its
    own places and on its own move. Open: Swim's change to a move
    (question 56).*
42. ~~**Switching abilities in a hurry.**~~ Every ability but the Roll shares one
    key, chosen in the bag. The bag pauses the game, so a combo like "a flame
    sets off a bomb at once" works, but it takes a trip to the bag inside the
    bomb's 3-second fuse.
    *Proposal:* the game pauses and the ability is chosen; no ability requires
    another ability.
    *2026-10-15 (owner): abilities are chosen in the bag, and the game pauses.
    No ability requires another ability. The Goo Bomb blows by itself: the
    Lantern's flame no longer sets it off (removed in code the same day).
    Open: whether a bomb caught in another bomb's blast still goes off
    (question 57).*
43. ~~**Release 1's scope.**~~ On top of skins, shapes and abilities, the
    2026-10-15 plan adds:
    - manuscripts, perhaps in pieces;
    - Slime Forge evolutions;
    - skins 3 to 8.

    That is on top of the bags, the vault, timed crafting and heart quarters,
    which makes many layers of progression for one release.
    *Proposal:* in Release 1, NPCs teach, chests hold the finds, and only the
    3 skins exist. Manuscript pieces and Forge evolutions wait for Release 2.
    *2026-10-15 (owner): Release 1 is Chapters 1 to 3, with 3 skins (Heavy,
    Silk, Swim). NPCs teach, and chests hold the finds. Manuscript pieces and
    Slime Forge evolutions wait: "upgrades of skins and abilities come later
    in the game". Open: where Release 1 ends and how long it plays
    (question 58).*
44. ~~**Webs at −80%.**~~ Chapter 2 is played without the Silk skin, and its
    spiders spread webs everywhere. The slime would crawl through much of the
    forest, and through the Matron's arena, where it is locked in.
    *Proposal:*
    - Webs slow the slime by 50%.
    - Play the Matron's fight with the slowdown before the number is fixed.

    *2026-10-15 (owner): webs slow the slime by 50%, not 80%, until the Silk
    skin. Web walls cannot be passed without it. Weapons cut webs only after
    the Silk skin, so the player has to deal with webs to defeat the Matron.
    Play the Matron's fight with the slowdown before the number is fixed.
    Open: Tom's web (question 54) and what the cutting is for (question 55).*
45. ~~**Squash Slam's job.**~~ The Goo Bomb now breaks cracked ground, which was
    the Slam's secret, so the Slam is only an attack around the slime.
    *Proposal:* I think it will disappear.
    *2026-10-15 (owner): Squash Slam is removed: it had no job left. The Goo
    Bomb breaks cracked ground (Planned: today it blows only cracked walls and
    rubble heaps). The One-Eyed Guardian's reward loses the Slam.*
46. ~~**What materials are for.**~~ Shapes replace crafted weapons and tools, but
    Chapter 2 still lists making iron gear, the Reinforced Pickaxe, the quest
    A Harder Pick, and the Iron Spear and Iron Axe. Without crafted gear, the
    wood, stone and iron that the Axe and the Hammer harvest buy nothing.
    *Proposal:* for Release 1 we only craft potions and food, maybe the vault.
    *2026-10-15 (owner): crafting in Release 1 is potions and food only
    ("maybe the vault"). There is no harvesting in Release 1: no wood, stone
    or iron from the Axe and the Hammer. Open: the quests built on crafting
    (question 50), the Forge and the Workshop (51), the ingredients (52), and
    the bags and the vault (53).*
47. ~~**Water before an aquatic skin.**~~ The Swim form came from a swallowed swim
    essence, and essences are marked for deletion. The water secrets (Dora's
    lake grotto, the old lakeside spot and the others) have no key until an
    aquatic skin exists, and none is placed yet (question 32).
    *Proposal:* the aquatic skin is Pearl 3's and the water secrets wait for
    it.
    *2026-10-15 (owner): Pearl 3, the Crystal Colossus's, grants the Swim
    skin, and the water secrets wait for it. Open: where water fits in the
    dark, dry caverns, and Swim's change to a move (question 56).*
    *Changed 2026-10-16 (owner, question 56): the Swim skin does not fit the
    Crystal Colossus. It moves to a later Pearl, the water secrets wait
    until after Release 1, and Pearl 3's skin is Open again.*
    *2026-10-16 (owner): the deep-water secrets become come-back secrets, and
    the swimming is not deleted: it stays in the code for the Swim skin
    (question 75). Pearl 3 grants the Feral skin (question 56). Later the same
    day the Swim form's mechanics, too, became the Swim skin's (question 75).*
48. ~~**One game, not two.**~~ The classic game still crafts weapons, swallows
    essences and refills energy, while the rework is the plan. Every new
    feature then needs both behaviours and both sets of tests, and the code
    marked for deletion stays in.
    *Proposal:* once the 3 skins are built, the rework becomes the only
    game. The classic mode, Swallow, essences and the forms are deleted.
    *2026-10-15 (owner): once the 3 skins are built, the rework becomes the
    only game. The old system goes with all its implementation: the classic
    mode, Swallow, essences, the forms, crafted weapons and tools,
    harvesting, Squash Slam and the classic number-key abilities. Their art
    moves to a holding folder for later deletion, kept "until we are sure we
    don't need it": `asset/to-delete/` at the repo root, outside the Godot
    project so it is no longer imported, each file keeping its relative
    path.*
    *Changed 2026-10-16 (owner): the swimming stays; only the Swim form and
    its essence go (question 75).* *Changed again 2026-10-16 (owner, question
    75): the Swim form is not dropped either; its mechanics become the later
    Swim skin's.*
49. ~~**The roadmap and the guidelines.**~~ They still describe the
    Gulp-and-essences game ([README](README.md)), so work planned from them
    builds the old game.
    *Proposal:* the 2026-10-15 decisions go into the roadmap as tasks, and the
    guidelines' Gulp section is marked as replaced.
    *2026-10-15 (owner): accepted. The same day the roadmap got
    [the 2026-10-15 decisions](../GAME_ROADMAP.md#the-2026-10-15-decisions)
    as tasks, and the guidelines marked their
    [Gulp section](../GAME_GUIDELINES.md#signature-mechanic-gulp) and the
    other parts these answers change as replaced.*

## Contradictions left after the review (2026-10-15)

What the answers to questions 40 to 51 still leave in conflict with the
chapters and the plan. Questions 59 to 61 come from the answers to 50 and 51,
and 62 to 67 from the docs pass that recorded the answers. Questions 68 to
76 come from the answers of 2026-10-16, and 77 to 83 from the docs pass that
recorded them. Questions 84 to 86 come from the answers to 68 to 83,
and 87 to 92 from the docs pass that recorded them. Questions 93 and 94 come from the answers to 84 to 92. Questions 95 and 96 come
from the answers to 93 and 94. Questions 97 to 100 come from the
owner's prologue idea. Questions 101 to 105 come from the docs pass for 84 to
94. Question 106 comes from the answer to 102. Question 107 is the
bestiary. Questions 108 and 109 come from the answers to 62 and 65. Questions 110 to 114 come
from the docs pass that recorded them.

50. ~~**Chapter 1 and 2 quests built on crafting and harvesting.**~~ With
    shapes, no crafted weapons or tools, and no harvesting in Release 1, these
    lose their point:
    - Stone Tools, which crafts the Stone Axe and the Stone Pickaxe, and
      teaches the Roll today;
    - Worm Trouble, which crafts a Wooden Spear;
    - A Home of Your Own, whose reason is a bag full of tools and wood;
    - A Harder Pick, which makes the Reinforced Pickaxe;
    - Chapter 2's goal, "make iron gear".

    *2026-10-15 (owner): "I don't think quests make sense any more. NPCs can
    give you info and tips; maybe a main quest like in Zelda: recover the 8
    Pearls." The Spear comes from the secret in town where the slime finds a
    war veteran who teaches it: **Old Veteran Yoi** in
    [Yoi's Hideout](../design/2026-10-11-release-1-dungeons-plan.md#4-yois-hideout)
    (the owner's decision of 2026-10-11). Lili tells of the hideouts slimes
    dug during Gorge's war. In her west yard the slime sucks away a heap of
    seven bricks and crates; the secret jingle plays and a hatch opens. Below
    is a water maze, where a thrown pot rings an old alarm bell that opens a
    gate. In his den Yoi of the Thorn Guard ("Gather all of yourself, and push
    it out to one point") teaches the Spear, and a bell that only the Spear
    rings opens the shortcut home. Open: what replaces the quests
    (question 60), and the Roll (question 61).*
51. ~~**The Forge and the Workshop in Release 1.**~~ Restoring them unlocks
    recipes, but Release 1 crafts only potions and food, and Slime Forge
    evolutions come later.
    *2026-10-15 (owner): the Workshop is where the smith teaches the Hammer
    shape, in Chapter 5 or 6, so not in Release 1. The Forge brews the potions
    until evolutions arrive. Open: what the Workshop does in Release 1, and
    the Crystal Colossus, who was weak to the Hammer (question 59).*
52. ~~**What potions and food are made from.**~~ With no harvesting, where do
    their ingredients come from?
    *Proposal:* pickups and drops: berries, mushrooms and herbs taken by hand,
    and enemy drops. No tool is needed.
    *2026-10-16 (owner): the proposal.*
53. ~~**Bags and the vault.**~~ With only potions, food and keys to carry, do
    Release 1 still need a 10-slot bag, a 20-slot bag and a 50-slot vault
    (question 46 says "maybe the vault")?
    *Proposal:* one bag, and the vault waits for a later release.
    *2026-10-16 (owner): the proposal. Open: the bag's size and who gives it
    (question 74).*
54. ~~**Tom in the Web.**~~ The slime frees Tom by cutting a web with its
    weapon, before the Matron, but weapons cut webs only once the Silk skin is
    learned.
    *2026-10-16 (owner): Tom hangs in a cocoon, which a weapon can tear. What
    he gives or teaches once freed is still question 31.*
55. ~~**What the Silk skin's cutting is for.**~~ With the Silk skin, webs no
    longer slow the slime, and web walls let it pass, so cutting a web does
    not change its way.
    *2026-10-16 (owner): accepted ("good"). With the Silk skin, a shape cuts a
    web wall open for good, and frees things wrapped in silk (a chest, a key,
    a trapped slime).*
56. ~~**The Crystal Colossus's Pearl.**~~ Pearl 3 was to grant Swim, but the
    Crystal Caverns are dark, dry caves, and the skin should open the region
    after Chapter 3.
    *2026-10-16 (owner): "you are right, the Colossus's maps do not fit [the
    Swim] skin. Give me ideas of the Colossus's Pearl and what power it has."
    Swim moves to a later Pearl, so the water secrets wait until after
    Release 1.*
    *2026-10-16 (owner, later): the ideas offered (Prism, Burrow, Echo, Shard)
    are declined. Pearl 3 grants the **Feral** skin:*
    - *Gate: the slime climbs some walls it could not climb before. That
      removes a real physical barrier and opens the world. Claws show while
      it climbs. To climb, the player holds W (interact); letting go midway
      drops the slime.*
    - *Change to a move: the Spear's attacks hit twice as fast.*

    *Open: which walls, the keys and the fall (question 68), and a beast's
    skin from a crystal golem (question 69).*

    Swim fits a water boss best: Old Gullet, the catfish of the Sticky Swamp
    in the [2026-10-11 power curve](../design/2026-10-11-world-power-curve.md).
57. ~~**Bombs setting off bombs.**~~ A bomb caught in another bomb's blast still
    goes off about 120 ms later. It is the same ability, so it does not break
    "no ability requires another ability".
    *Proposal:* keep the chain, or make a bomb blow only on its own fuse.
    *2026-10-16 (owner): keep the chain.*
58. ~~**Release 1 grows to three chapters.**~~ The roadmap's target is
    Chapters 1 and 2: 45 to 75 minutes, an end-of-Chapter-2 card, and the
    Crystal Caverns left out beyond a locked teaser.
    *Proposal:* Release 1 ends with an end card after the Crystal Colossus,
    and the play time is measured again once Chapter 3 is outlined.
    *2026-10-16 (owner): Release 1's content ends when the Crystal Colossus
    falls, but the game goes on. The player explores the map and uses the new
    powers, and the game tells them that from here on it is exploration and
    that more areas come in later releases. Open to explore: the first three
    chapters' regions, the West village and the Wilds that connect them.
    Open: what closes the ways to the regions that are not in Release 1
    (question 73).*
59. ~~**The Crystal Colossus without the Hammer.**~~ Chapter 3's boss is
    armoured, weak to the Hammer, and teaches switching shapes, but the Hammer
    now comes in Chapter 5 or 6 (question 51).
    *Proposal:* Chapter 3's own tool beats him, as the
    [2026-10-11 power curve](../design/2026-10-11-world-power-curve.md) has
    it. Four braziers ring his arena; a brazier lit by the Lantern bares the
    armour on his side for the Spear or the Axe, and his stomps blow the
    braziers out. The smith, found in Chapter 3, gives the Lantern there and
    teaches the Hammer later.
    *2026-10-16 (owner): the proposal, changed. Only when all four braziers
    burn is a weak spot on his armour bared, at a random place, for the Spear
    or the Axe; his stomps blow the braziers out one at a time. The smith runs
    the crystal mine, which the Colossus has blocked: the slime finds him safe
    at his mine camp. He gives it the Lantern, the Forge's ember, and goes
    home once the Colossus falls. Pip's story stays relighting the Forge. The
    smith teaches the Hammer later (question 51).*
60. ~~**What replaces the quests.**~~ Today every chapter beat is a quest: the
    journal, quest offers, and quest rewards that give the bag, the Roll,
    recipes and abilities, and restore Slimeshire's buildings. With NPCs giving
    info and tips, and perhaps one main quest for the Pearls (question 50):
    - Does the journal stay, for the main quest and the NPCs' tips?
    - How are the finds given: the bag, the home and the vault, the shapes and
      the abilities?
    - What restores Slimeshire's buildings?

    *Proposal:* the journal keeps one main quest, "Win back the Pearls", and a
    page of the tips NPCs give. An NPC hands over or teaches its find when the
    slime talks to it, and the other finds lie in chests, each with its
    ceremony. A building is restored when a Pearl comes home ("Return the
    Pearl: Slimeshire grows").
    *2026-10-16 (owner): accepted, and in the journal the Pearls' slots show
    empty and fill as they are won. Each one lights up its part of a picture,
    like a puzzle, and explains what the Pearl does: "a cool place to keep
    track of the progress".*
61. ~~**The Roll in Release 1.**~~ The Heavy skin changes the Roll, and Pearl 1
    comes at the end of Chapter 1. But Stone Tools, which teaches the Roll
    today, goes with the quests (question 50), and the 2026-10-11 dungeons
    plan had no Roll in Release 1.
    *Proposal:* the Roll is in Release 1, taught in Chapter 1 before Fatty One
    Eye, so the Heavy skin's Roll works as soon as the skin is won. It is the
    quick roll: the held, charged roll (the rework's `roll-charge` upgrade) is
    an upgrade, so it comes later with the others ("upgrades of skins and
    abilities come later in the game").
    *2026-10-16 (owner): yes, taught in Chapter 1 before Fatty One Eye. His
    story for it, polished, with his later answers:*
    1. After the Spear, Plop says the worms have shut their burrow with the
       old Thorn Guard gate, and only **Burr**, the gatekeeper in the West
       village, knew its trick.
    2. In the West village Burr's house is empty. His son, **young Burr**,
       says his father went to fight Fatty and never came back. He shows the
       trick his father taught him: curl up and roll (the Roll, with its
       ceremony). The slime promises to find his father.
    3. **The burrow's lock.** A worm lever lifts the gate, and the gate drops
       shut a moment later, too fast to walk. Behind it, **falling slabs**:
       loose slabs or bridges that fall too fast to cross walking, but slowly
       enough to cross rolling. They come back after 10 seconds. Under them
       are holes:
       - **lava:** damage over time until the slime walks out by a stair set
         there, so it can try again;
       - **spikes:** normal damage each time its invulnerability ends, until
         it steps off;
       - **the void:** damage, and the slime goes back to the start of the
         bridge.
    4. In the lair's first half Burr sits in a cell. A small key found in the
       lair frees him; he thanks the slime and asks it to visit him at home.
    5. The Spear on Fatty's eye beats him, and Pearl 1 gives the Heavy skin.
    6. Back home, Burr gives his thanks: an energy upgrade (max energy grows
       only through secrets and bosses, question 19) or a heart.

    *The Heavy skin's Roll (owner, 2026-10-16): it shakes things loose, and it
    breaks loose rocks, rubble heaps and old trunks it hits; its screen shake
    is strong. Without the Heavy skin a Roll's bonk shakes the screen much
    less. It does not push enemies away: that will be an upgrade later, from
    another skin. Rubble heaps now break under a Heavy Roll instead of a Goo
    Bomb, which keeps cracked walls and cracked ground.*

    *Resolved the same day:* two families (fix B), so the gatekeeper's family
    is Burr and young Burr, in the West village, and the smith is not a
    missing father (question 59). Part of the West village joins Release 1,
    with more NPCs, houses and things to do, like Zelda's town (question 73).
    The Roll opens the burrow, and the Spear's job in the lair is Fatty's eye.
    The cell's key is a small key from the planned dungeon kit. Open: the
    hazards and the slab timing (questions 70 and 71), and the rubble heaps
    the Goo Bomb opens today (question 72).
62. ~~**Save points.**~~ The full energy refill is planned "at the Wellspring and
    at save points" (question 40), but the game has no save points: it saves
    from the pause menu, and a bed sets where the slime wakes.
    *Proposal:* beds are the save points. Sleeping refills energy and life,
    and so does the Wellspring.
    *2026-10-16 (owner): "How does Zelda's saving work? I want something
    similar: he can save everywhere but inside dungeons." In A Link to the Past
    the player saves from the menu at any moment and comes back at home or at a
    dungeon's entrance; the newer Zeldas save anywhere outside special moments.
    So here the slime saves everywhere except inside dungeons, and there are no
    save points: the full energy refills come from beds, the Wellspring and the
    well. What happens on quitting or dying inside a dungeon is question 109.*
63. ~~**Places whose prize was a material.**~~ With no harvesting in Release 1,
    these hold nothing useful:
    - the iron hollow's iron;
    - the Gloop Cavern chest's iron ore and charcoal;
    - the weaver fangs, whose only use was the pickaxe recipe (Beyond the
      Verdant Gate asks for three).
    *Proposal:* those places hold heart quarters, potions or a piece of the
    story (the 2026-10-11 plan put a piece of Kiri's note in the iron hollow),
    and the weaver fangs go.
    *2026-10-16 (owner): the proposal; they can hold coins too.*
64. ~~**The Clod Stomper.**~~ It showed what a stone essence and a slam can do, and
    both go. Its own slam still breaks cracked ground, which is now the Goo
    Bomb's lock alone.
    *Proposal:* it stays as an enemy, and its slam no longer breaks cracked
    ground.
    *2026-10-16 (owner): it stays as it is: its slam still breaks cracked
    ground near it. It is an enemy, not a power, so the Goo Bomb stays the only
    power that opens cracked ground.*
65. ~~**Manuscripts and Stretch Lash in Release 1.**~~ Stretch Lash is "learned
    from manuscripts", but in Release 1 NPCs teach and chests hold the finds,
    and manuscript pieces wait. Mossy teaches the Lash in Chapter 2 today.
    *Proposal:* Release 1 has whole manuscripts, each found in a chest as one
    find; pieces come later. Whether the Lash is in Release 1 at all is Open.
    *2026-10-16 (owner, question 94): Stretch Lash waits for the next release,
    so Sunny's basket and the Lash's other uses become come-back secrets.
    Whether Release 1 has whole manuscripts is still open.*
    *2026-10-16 (owner): Release 1 has whole manuscripts. What they teach is
    question 108.*
66. ~~**Food without a kitchen.**~~ Release 1 crafts potions and food, but the
    Kitchen is not in Release 1, and only potions have a station (the Forge,
    question 51).
    *Proposal:* Release 1 crafts potions only, and food comes with the
    Kitchen; or a campfire cooks food.
    *2026-10-16 (owner): potions and food are both crafted at a campfire.*
67. ~~**What the Slime Forge upgrades.**~~ Direction says it evolves shapes and
    abilities; the answer to question 43 says "upgrades of skins and
    abilities". A skin is a pure addition with no downside, so an upgrade
    would give it levels.
    *Proposal:* shapes and abilities evolve at the Forge, and skins do not;
    all of it comes after Release 1.
    *2026-10-16 (owner): the proposal.*
68. ~~**Climbing: which walls, the keys and the fall.**~~ The Feral skin climbs
    "some walls" while W (interact) is held, and W held next to a heavy block
    grabs it.
    - How does the player tell a wall that can be climbed?
    - A climb goes up a cliff to the level above, like the stairs walk. Does
      it go down too, and what does a fall cost?

    *Proposal:* climbable faces are cliff walls with claw-scratched rock or
    thick roots, painted on the world like the stairs. Held W at a climbable
    face climbs, held W at a block grabs, and the two never stand together. A
    climb goes up and down, and letting go drops the slime to the foot with a
    small hit.
    *2026-10-16 (owner): a climbable wall looks different from the others:
    it has vines and irregularities. The slime climbs up and down, and a fall
    costs nothing. Open: vines are also the War Axe's lock (question 86).*
69. ~~**A beast's skin from a crystal golem.**~~ Feral is a beast's power, and the
    Colossus is a golem of crystal.
    *Proposal:* the Pearl in his chest made him part beast: between stomps he
    climbs his arena's walls on crystal claws, so the Pearl's power shows in
    the fight before the slime wins it.
    *2026-10-16 (owner): the proposal, and he climbs out of reach to throw
    some of his minions down. Killed, they can drop energy shards (the
    boss-chamber rule of question 40).*
70. ~~**The hazards under the slabs.**~~ Lava does not fit a worm burrow under a
    meadow, and falling slabs, lava, spikes and the void are all new pieces.
    *Proposal:* Chapter 1's slab bridges cross the void and spikes, and lava
    waits for a fire region. The slabs, the spikes and the lava share one
    hazard script, and the void works like the elevation's holes.
    *2026-10-16 (owner): the proposal.*
71. ~~**Slabs and the quick Roll.**~~ In Release 1 the Roll is the quick roll
    (165 px in 330 ms, then a short pause), and the charged roll comes later,
    so a bridge longer than one roll needs rolls in a row.
    *Proposal:* a slab falls a set time after the slime touches it (in
    game-constants.json), tuned in the playground so a bridge can be crossed
    with quick rolls in a row and never by walking.
    *2026-10-16 (owner): the proposal.*
72. ~~**Rubble heaps move to the Heavy Roll.**~~ The Goo Bomb blows rubble heaps
    today: in the playground's Bomb corner, the heap by the map's edge and the
    islet that only a thrown bomb reaches. The Heavy Roll also breaks old
    trunks, while old dry wood (rotten timbers, deadthorn) is the Lantern's.
    *Proposal:* the islet's prize sits behind a cracked rock face instead (the
    bomb's lock), and the heap by the edge waits for a Heavy Roll. A trunk the
    Roll breaks lies across a path; standing dry things burn.
    *2026-10-16 (owner): the proposal, and a combo: a Heavy Roll can knock an
    old tree down into dry wood, which the Lantern then burns. "We should not
    abuse combos, but used wisely they bring more depth to the game." Open: how
    this sits with "no ability requires another" and the Axe's trees
    (question 84).*
73. ~~**The West village and the borders of Release 1.**~~ Part of the West
    village joins Release 1, and after the Colossus the player explores the
    three chapters, the West village and the Wilds.
    - Which part of the West village, and what is there to do?
    - What closes the ways to the regions that are not in Release 1?

    *Proposal:* the West village's first chunk is a small town: Burr's house,
    three or four more houses, a shop and a game to play, like Kakariko. The
    ways to later regions are closed in the world (a fallen bridge, a
    landslide, a Thorn Guard post), and each says that more lies beyond.
    *2026-10-16 (owner): the proposal.*
74. ~~**The one bag.**~~ Plop gives a 10-slot bag at the start, and a 20-slot bag
    waits in a coffer in the Gloop Cavern. With one bag (question 53), which
    size, and who gives it?
    *Proposal:* Plop gives a 20-slot bag at the start, and the Gloop Cavern's
    coffer holds a heart quarter instead (question 63).
    *2026-10-16 (owner): "since we don't have many collectibles now", the
    20-slot bag waits for the next release. Release 1's one bag is Plop's
    10-slot bag. What the Gloop Cavern's coffer holds is question 63.*
75. ~~**The swimming kept for later.**~~ The deep-water secrets become come-back
    secrets, and the swimming stays in the code for the Swim skin (owner,
    2026-10-16), while the Swim form goes with the old system (question 48).
    *Proposal:* the playground keeps a dev switch that lends the swimming, so
    it can still be tried and its tests keep running.
    *2026-10-16 (owner): the Swim form is not dropped either. Its scene
    mechanics are refactored into a permanent power that works in deep water,
    the later Swim skin.*
76. ~~**The Bow (owner, 2026-10-16), learned later.**~~ "On press the slime aims
    in the direction it is moving; at release it shoots in that direction.
    The arrow does not change direction after it is shot."
    - Is it a shape (the slime's body bends into a bow, like the Spear) or an
      Ability Box power?
    - What does an arrow cost: energy, as every ability does, or arrows
      carried in the bag?
    - Where is it learned, and in which chapter?
    - What does it open that no other power does? The boomerang owns switches
      out of reach and around corners, and the Axe owns ropes.

    *Proposal:* an Ability Box power, each arrow costs energy, learned after
    Release 1. Its own locks are far targets in a straight line across gaps
    and water (eye switches on far walls, a target that must be hit while it
    passes), and it carries no fire or other power with it.
    *2026-10-16 (owner): the proposal. It also hits far enemies that cannot be
    reached otherwise, and some enemies open doors once they die, as in Zelda.
    Open: Burr gives the Bow (question 80), so when it comes (question 85).*
77. ~~**Heavy Roll, Hammer and Axe.**~~ The Heavy Roll breaks loose rocks, rubble
    heaps and old trunks (question 61). The Hammer's lock is boulders, and the
    War Axe's is "fell a dead tree": a dead tree on a riverbank falls across
    the water as a bridge.
    *Proposal:* a Heavy Roll breaks small loose things lying in the way: a
    loose rock, a rubble heap, a rotten trunk lying across a path. The Hammer
    keeps the big single boulders, and the Axe keeps standing trees, a dead
    one included, which fall where they are cut.
    *2026-10-16 (owner): the proposal. "It is important that each thing can be
    told apart. We don't want different things that look alike; we need to
    sacrifice options for clarity."*
78. ~~**The charged roll and "the Roll comes whole".**~~ On 2026-10-09 the owner
    said the Roll comes whole, with no upgrade (questions 16 and 26). The rework
    built a held, charged roll behind the `roll-charge` upgrade, and Release 1
    now has only the quick roll, the charged roll coming later as an upgrade.
    *Proposal:* the 2026-10-09 rule is replaced: the quick roll is the Roll,
    and the charged roll is a later upgrade, like the Roll's enemy push.
    *2026-10-16 (owner): the proposal.*
79. ~~**Which Pearl relights the Forge.**~~ A returned Pearl restores a building
    (question 60), and Pip's story is relighting the Forge. Today Pip's quest,
    Rekindle the Forge, does it, and it costs ore.
    *Proposal:* Pearl 2, the Matron's, relights the Forge: Pip and the slime
    light it when it comes home, and the Forge brews the potions from then on
    (question 51).
    *2026-10-16 (owner): the proposal.*
80. ~~**Burr's thanks.**~~ Burr gives the slime something when it visits him at
    home after Fatty's Lair: an energy upgrade or a heart?
    *Proposal:* an energy upgrade, the first one. Hearts come from heart
    quarters and bosses, and max energy then has its first source
    (question 19).
    *2026-10-16 (owner): the Bow. Open: the Bow was to come after Release 1
    (question 85).*
81. ~~**Chapter 2's end.**~~ Release 1 now ends at the Colossus. What do the
    end-of-Chapter-2 card after the Matron and the crystal that seals the way
    to the Caverns become?
    *Proposal:* the card goes, and the Matron's Pearl leads on to Chapter 3.
    The crystal seal opens with the Lantern's region, for example once the
    slime hears of the smith's mine, so the way to the Caverns opens on the
    story.
    *2026-10-16 (owner): the way to the Caverns is covered by web walls in a
    maze that only the Silk skin passes. The Silk skin then opens Chapter 3, as
    a skin opens the next region. The end-of-Chapter-2 card goes (the
    proposal), since Release 1 ends at the Colossus.*
82. ~~**Recipes in Release 1.**~~ With no quests and only potions and food
    crafted, what teaches a recipe (the guidelines' Recipe Discovery)?
    *Proposal:* the Forge knows the potion recipes once it is relit, and an
    NPC tip or a chest teaches each of the few others.
    *2026-10-16 (owner): the proposal. And with no quests, an NPC that has
    something to tell that matters to the story (a tip) shows the exclamation
    mark.*
83. ~~**Two bows.**~~ The roadmap's parking lot has an old "Bouncy Bow" whose
    arrows bounce off walls, and the new Bow's arrow never changes direction
    (question 76).
    *Proposal:* the Bouncy Bow goes, and the Bow is the one bow.
    *2026-10-16 (owner): the proposal.*

84. ~~**Combos, once more.**~~ Question 42 says no ability requires another, and
    question 41 dropped "depth from combos". Question 72's answer brings back a
    combo used wisely: a Heavy Roll knocks an old tree down, and the Lantern
    burns it. Question 77 also gives standing trees, dead ones included, to
    the War Axe.
    *Proposal:* the rule becomes "the main path never needs a combo; a few
    optional secrets may combine a skin and an ability, and each one looks
    clearly different". The old tree a Heavy Roll knocks down is its own
    thing: grey, leafless and leaning, and never a tree the Axe cuts. Once it
    lies on the ground it is dry wood, which burns.
    *2026-10-16 (owner): the proposal. The Heavy Roll is needed and the Axe
    cannot cut that tree because it is made of old material the Axe cannot cut,
    and the same may hold for other old things, such as old constructions.
    Open: old wooden constructions are also the Lantern's (question 93).*
85. ~~**When the Bow comes.**~~ Burr gives the Bow when the slime visits him after
    Fatty's Lair (question 80), in Chapter 1, but the Bow was to be learned
    after Release 1 (question 76).
    *Proposal:* in Release 1 Burr gives the Bow on that visit, so the Bow is
    in Release 1, and Chapters 1 to 3 hold a few far targets and the room
    doors that open when their enemies fall. Or, in Release 1 Burr only
    thanks the slime and the Bow waits for him in the next release.
    *2026-10-16 (owner): the Bow is in Release 1, from Burr. "Make a count of
    how many abilities we already have for Release 1; we may want to save some
    content." The count is question 94.*
86. ~~**Vines: climbing or cutting.**~~ A wall the Feral skin climbs has vines
    and irregularities (question 68), and vines are also the War Axe's lock (a
    curtain of vines hiding a cave).
    *Proposal:* climbable walls show thick roots and rocky handholds on the
    cliff face, and the Axe's vines are leafy curtains that hang in front of
    an opening, so the two never look alike (question 77).
    *2026-10-16 (owner): the proposal.*
87. ~~**Other ways into the Caverns and the forest.**~~ The map's openings let
    the slime walk from the Wilds into the Crystal Caverns, and from the Wilds
    into Gloop Forest, which skips the web-wall maze and the Verdant Gate.
    *Proposal:* until Chapter 3 those openings are closed in the world (a
    rockslide, thorn walls), and they open from the inside as shortcuts once
    the region is beaten, like Zelda's one-way doors.
    *2026-10-16 (owner): from the Wilds to the Crystal Caverns a hill must be
    climbed with the Feral skin, so that way opens only once Feral is won.
    From the Wilds to Gloop Forest there is also a web maze that only the Silk
    skin passes.*
88. ~~**The West village shop.**~~ The town's shop is in Release 1, but the
    guidelines' Coins section and the roadmap's "Coins get a use" put the
    first shop after Release 1, and what it sells is not decided.
    *Proposal:* a small shop that sells potions and food ingredients, so coins
    have a use in Release 1; anything bigger waits.
    *2026-10-16 (owner): the proposal.*
89. ~~**Potions before Pearl 2.**~~ The Forge knows the potion recipes only once
    Pearl 2 relights it, at the end of Chapter 2, but Lili's tonic, the
    portable Slime Tonic and the Berry Basket are crafted before that, and the
    rule "a fresh save never softlocks" needs a way to heal early.
    *Proposal:* before the Forge, potions are found (chests, drops, the shop),
    and the one or two simple recipes of Chapter 1 are made at a campfire.
    *2026-10-16 (owner): the proposal, and a secret in the West village teaches
    a simpler potion.*
90. ~~**Pearl 1's homecoming.**~~ Rekindle the Forge brought the slime home with
    Pearl 1. Now Pearl 2 relights the Forge, and which building Pearl 1
    restores is not decided.
    *Proposal:* Pearl 1 restores the Workshop's roof (it waits for the smith
    and the Hammer), or Slimeshire's well, which then refills energy.
    *2026-10-16 (owner): Slimeshire's well, which then refills energy.*
91. ~~**Climbing next to a heavy block.**~~ Held W climbs a climbable wall and
    grabs a heavy block (question 68).
    *Proposal:* the two never stand side by side in a level, and held W next to
    both does whichever the slime faces.
    *2026-10-16 (owner): the proposal.*
92. ~~**Wood that looks alike.**~~ The Lantern burns dead, dry things (rotten
    planks, mine timbers, deadthorn), the Heavy Roll breaks a rotten trunk
    lying across a path, and the War Axe fells standing trees, dead ones
    included. Under the clarity rule (question 77) these must not look alike.
    *Proposal:* three clear looks. Burnable things are grey-black and
    thorny or cracked planks; the Roll's trunk lies flat across the path, mossy
    and hollow; the Axe's trees stand, green or bare.
    *2026-10-16 (owner): the proposal. Open: the "bare" trees the Axe fells
    and the "grey, leafless" old tree a Heavy Roll knocks down can look alike
    (question 93).*
93. ~~**Who owns old wood.**~~ Three answers now overlap:
    - the Heavy Roll knocks down old trees made of material the Axe cannot cut,
      and the same may hold for old constructions (question 84);
    - the Lantern burns dry, dead things, rotten planks and mine timbers
      included (the plan's dry blockers);
    - the War Axe fells standing trees, green or bare (questions 77 and 92).

    A bare tree and a grey, leafless one look alike, and an old plank
    barricade could be the Roll's or the Lantern's.
    *Proposal:* one look per power, by what the thing is.
    - **The War Axe:** living, green things (trees in leaf, bushes, leafy
      vines, webs, tethers).
    - **The Heavy Roll:** old built or old dead wood and stone that lies or
      leans in the way (grey leaning old trees, rotten trunks across a path,
      old fences and plank barricades, loose rocks, rubble heaps).
    - **The Lantern:** dry plant growth (deadthorn, hay, dry roots, old
      banners), and what the Roll knocked down once it lies there as dry
      wood.
    *2026-10-16 (owner): the proposal. Plank barricades, old fences and rotten
    mine timbers move from the Lantern to the Heavy Roll.*
94. ~~**How many powers Release 1 holds.**~~ Counted from the answers so far:

    | Chapter | New powers | Where from |
    |---|---|---|
    | Start | The Gulp (suck and throw) | Built in |
    | 1 | Spear (shape), Roll, Heavy skin, Bow | Yoi; young Burr; Pearl 1; Burr |
    | 2 | Silk skin, plus Chapter 2's key tool: the Goo Bomb or the War Axe (question 31), and perhaps Stretch Lash (question 65) | Pearl 2; Open |
    | 3 | Lantern, Feral skin | The smith; Pearl 3 |

    That is 9 to 11 powers. Zelda: A Link to the Past gives about 8 items
    before its midpoint. Chapter 1 alone gives four, the most of any chapter.
    *Proposal:* keep about 8 and three per chapter:
    - **Chapter 1:** the Spear, the Roll, the Heavy skin;
    - **Chapter 2:** the Goo Bomb (its key tool) and the Silk skin;
    - **Chapter 3:** the Lantern, the Feral skin and the Bow. Burr gives it
      when the slime comes back to the West village after Chapter 2.

    Save for the next release: the War Axe and Stretch Lash. The Axe's
    locks (webs, vines, trees) then wait as come-back secrets, while the
    Silk skin's cut covers webs in Release 1.
    *2026-10-16 (owner): the proposal. Release 1 has eight powers besides the
    Gulp: the Spear, the Roll and the Heavy skin in Chapter 1; the Goo Bomb
    and the Silk skin in Chapter 2; the Lantern, the Feral skin and the Bow in
    Chapter 3. The War Axe and Stretch Lash wait for the next release. Open:
    where the Goo Bomb is found (question 95), and Release 1 with one shape
    (question 96).*
95. ~~**Where the Goo Bomb comes from, and Tom.**~~ The Goo Bomb is Chapter 2's key
    tool (question 94), but nothing gives it yet. Tom, freed from his cocoon,
    has nothing to teach since Swallow went (question 31). In the 2026-10-11
    plan the War Axe lay halfway through the Weaver Hollow, Chapter 2's
    dungeon, and the Axe now waits.
    *Proposal:* Tom teaches the Goo Bomb at Mossy's camp once he is freed: he
    is a slime who already knows how to build a bomb inside himself, so his
    beat stays and Chapter 2 has its tool before the Weaver Hollow and the
    Matron. The Weaver Hollow's big chest then holds a heart or the dungeon's
    big key instead.
    *2026-10-16 (owner): Tom teaches the Goo Bomb, but reaching him is not
    easy: the slime passes a maze with several secrets and tests to get to him.
    The maze is solved with the powers the slime has by then (the Spear, the
    Roll, the Heavy skin and the Gulp); its webs slow the slime and cannot be cut
    before the Silk skin.*
96. ~~**Release 1 with one shape.**~~ With the War Axe in the next release and the
    Hammer in Chapter 5 or 6, the Spear is Release 1's only shape. Switching
    shapes (E) then does nothing in Release 1, and the Colossus's weak spot is
    for the Spear alone.
    *Proposal:* accept it: Release 1 teaches one shape well, E stays hidden
    until a second shape is learned, and the Axe opens the next release with
    its come-back secrets (webs, vines and trees in the old maps).
    *2026-10-16 (owner): the proposal.*
97. ~~**The prologue (owner's idea, 2026-10-16).**~~ Like Zelda and Super Metroid,
    a short, closed opening before the big game: the slime is born at the
    Wellspring, learns to move and to gulp, sees the veteran fall to the
    worms, saves him by throwing things, and learns the Spear from him. It is
    written up, polished, in the
    [prologue design](../design/2026-10-16-prologue.md). The owner placed it
    in the south between chunks B4 and C4, ringed by forest, with the birth in
    B4 and the attack seen on walking into C4.
    - Is the polished version right?
    - C4 is Slimeshire's built chunk `level-1-c4`, so the glade would cut into
      its south-west corner.
    *Proposal:* the polished version, with both screens in B4's south-east
    corner (the West village's placeholder chunk), so nothing built in
    Slimeshire moves. The glade's barred gate opens east onto level-1-c4's
    west edge.
    *2026-10-16 (owner): the polished version. It goes between B4 and C4 as he
    placed it; things in the chunks may be moved to fit it, and if it does not fit
    naturally, the prologue can be an underground cavern instead.*
98. ~~**The Wellspring's place.**~~ Question 5 put it in "its own new map east of
    level-1", where Gloop Forest is now, and the Pearls come home to it, so it
    brightens with each one. The prologue puts it in a closed lake far from
    the town.
    *Proposal:* the prologue's lake is the Wellspring. After the prologue a
    short forest path from Slimeshire's south-west keeps it in reach, and each
    Pearl's homecoming is a short scene there.
    *2026-10-16 (owner): the proposal.*
99. ~~**Yoi's Hideout.**~~ The 2026-10-11 plan taught the Spear in a hideout under
    Lili's yard: her tip, a heap of bricks and crates, a water maze and its
    bells. The prologue now teaches it.
    *Proposal:* the hideout becomes Yoi's home: Lili's tip and the heap stay as
    an optional secret, and inside are a heart quarter, Yoi's tips, and later
    the Spear's upgrades.
    *2026-10-16 (owner): the proposal.*
100. ~~**Plop's first meeting.**~~ Plop greeted the slime at the Wellspring and
     gave the 10-slot bag with Slime Basics, a quest. Quests are going
     (question 60), and the prologue has no Plop.
     *Proposal:* Plop meets the slime at the town's edge as it comes out of
     the forest, gives it the 10-slot bag and its first tips (with the
     exclamation mark), and later sends it to Burr.
     *2026-10-16 (owner): the proposal.*
101. ~~**The War Axe's fallen-tree bridge.**~~ The Axe's lock "fell a dead tree":
     a leaning dead tree on a riverbank falls across the water as a log
     bridge. Question 93 gives grey, leaning old trees to the Heavy Roll, and
     the Axe owns living, green things.
     *Proposal:* the bridge becomes the Heavy Roll's: a Heavy Roll knocks the
     grey, leaning tree over the water. The Axe's bridge, a living tree cut to
     fall, comes back with the Axe in the next release if it is wanted.
     *2026-10-16 (owner): the proposal.*
102. ~~**Burr's visit before the Bow.**~~ Burr asks the slime to visit him at home
     after Fatty's Lair, but he gives the Bow only after Chapter 2.
     - What happens on a visit before then?
     - What counts as "after Chapter 2": Pearl 2 won, or the Matron's fall?
     - Does Chapter 3's main path or its boss need the Bow? A region's boss
       needs its tools.
     *Proposal:* before then Burr thanks the slime and gives a tip ("I am
     making you something, come back when the forest is free"). Pearl 2
     coming home counts. Chapter 3 uses the Bow on its main path at least
     once (a far eye switch across the mine's chasm), but the Colossus does
     not need it.
     *2026-10-16 (owner): the proposal, and Burr asks for silk and other things so
     he can build the slime something: the Bow. With the silk and Pearl 2 he can
     then teach the Bow. Open: what the silk is, with essences and materials gone
     (question 106).*
103. ~~**What brings the slime home with Pearl 1.**~~ Rekindle the Forge did. Pearl
     1 now restores Slimeshire's well (question 90), but nothing sends the
     slime home after Fatty One Eye.
     *Proposal:* after Fatty, Burr, freed, says the town must see the Pearl;
     the main quest's journal page (question 60) points home, and the well
     comes back when the slime brings the Pearl to it.
     *2026-10-16 (owner): the proposal.*
104. ~~**Campfire recipes.**~~ Early potions are made at a campfire (question 89),
     but the guidelines and the roadmap's Milestone 6 keep Slime Tonic and
     Berry Basket craftable anywhere, "so a fresh save cannot softlock".
     *Proposal:* the one or two Chapter 1 recipes are made at any campfire,
     and a campfire stands by the Wellspring, in the town and at each camp, so
     a fresh save can always heal.
     *2026-10-16 (owner): the proposal.*
105. ~~**How much the well refills.**~~ Pearl 1's well refills energy, and the
     Wellspring and beds give a full refill (questions 62 and 90).
     *Proposal:* the well gives a full refill too, as a drink in town, and
     beds also restore life.
     *2026-10-16 (owner): the proposal.*
106. ~~**Burr's silk.**~~ Burr needs silk and other things to build the Bow
     (question 102), but silk essences are going (question 48), and Release 1
     has no materials or harvesting (question 46).
     *Proposal:* the silk is one find, not a material: the **Matron's
     thread**, a spool the slime finds in her nest after she falls (with the
     Silk skin it can take it from her web). Burr's "other things" are already
     in his workshop. One find, one trip back, and no crafting.
     *2026-10-16 (owner): the proposal, the Matron's thread.*

107. ~~**The bestiary.**~~ The owner wants at least 20 different enemies, with
     some unique to each dungeon, not all of them walking at the slime, some
     following a strict pattern, and some easy with the right power. The
     [bestiary](../design/2026-10-16-bestiary.md) proposes 29 for Release 1:
     6 built, 5 planned, 18 new, each with a tell, a kind of its own and a
     right tool, and ideas from Zelda, Metroid, Mario and others.
     *Proposal:* the list as written. The owner strikes or changes any he does
     not want.
     *2026-10-16 (owner): the proposal: the 29 enemies as written. Each one is
     shown in the playground as it is built.*
108. **What Release 1's manuscripts teach.** Release 1 has whole manuscripts
     (question 65), but each of its eight powers already has a teacher: the
     Spear (Yoi), the Roll (young Burr), the Goo Bomb (Tom), the Lantern (the
     smith), the Bow (Burr), and the three skins from the Pearls.
     *Proposal:* Release 1's manuscripts teach recipes (the campfire potions
     and food) and lore: pages of the Thorn Guard's war journal, which tell
     the story of the war bit by bit. Manuscripts that teach powers start in
     the next release.
109. **Quitting or dying inside a dungeon.** The slime cannot save inside a
     dungeon (question 62). What happens when the player quits there, or the
     slime faints?
     *Proposal:* as in Zelda: the game resumes at the dungeon's entrance, and
     the dungeon keeps what the slime did (small keys found, doors opened, the
     map and the big key). The autosave also waits until the slime is out.

110. **Where a Pearl comes home.** Each Pearl's homecoming is a scene at the
     Wellspring (question 98), but the slime brings Pearl 1 to Slimeshire's
     well (question 103), and Pearl 2 relights the Forge in town (question 79).
     *Proposal:* every Pearl goes to the Wellspring first, which brightens,
     and its power then flows to the town: the well comes back with Pearl 1,
     the Forge lights with Pearl 2.
111. **Who upgrades the Spear.** Yoi gives the Spear's upgrades later
     (question 99), and the Slime Forge evolves shapes after Release 1
     (question 67).
     *Proposal:* Yoi teaches the Spear's new moves (a technique, like the
     charged Lunge), and the Forge makes the Spear stronger (more damage,
     reach). Both come after Release 1.
112. **Chunk B4 is booked twice.** The world map puts both the prologue's
     Wellspring and the West village's town in B4.
     *Proposal:* the prologue takes B4's south edge, sealed off by forest, and
     the town sits in B4's north and A4; the forest path to the Wellspring
     leaves Slimeshire, not the town.
113. **The prologue's loose ends.**
     - Can the prologue be saved? It is not a dungeon.
     - When does the HUD appear?
     - Where is Tom's maze, does he hang in his cocoon at its end, and where
       does he teach the bomb?
     - Does the Weaver Hollow's big chest hold the heart or the big key?
     - Does the well's refill grow back?

     *Proposal:* the prologue saves like the world (the autosave catches the
     Spear's ceremony); the HUD fades in when the slime first takes damage
     from a worm. Tom's maze is in Gloop Forest's south-west woods, Tom hangs
     at its heart, and he teaches the bomb there once freed. The big chest
     holds the dungeon's big key. The well never runs dry: it refills every
     visit.
114. **The Spear-only bell.** Yoi's Hideout had a bell only the Spear rings,
     which opened its shortcut home; the hideout's water maze is gone, and
     only the prologue's barred gate is left as the Spear's lock.
     *Proposal:* Spear-only bells come back across the world as a second kind
     of Spear lock next to "through bars": a bell on an islet, or behind a
     gap, that a thrown pot cannot ring but a Spear's reach can.

## Answered

- **2026-10-16 (sixth round, part 2):** the owner answered questions 62 to 67
  and 107. The slime saves everywhere except inside dungeons, and there are no
  save points. The places whose prize was a material hold heart quarters,
  potions, coins or story. The Clod Stomper stays as it is. Release 1 has
  whole manuscripts. Potions and food are crafted at a campfire. Shapes and
  abilities evolve at the Forge after Release 1, skins do not. The
  bestiary's 29 enemies are accepted, each shown in the playground as it is
  built. Questions 108 and 109 follow.
- **2026-10-16 (sixth round, part 1):** the owner answered questions 95 to 105. Tom
  teaches the Goo Bomb, at the end of a maze of secrets and tests. Release 1
  has one shape, the Spear. The prologue is the polished version, between B4
  and C4 (chunks may move, or it may be an underground cavern). Its lake is
  the Wellspring, reached later by a forest path, where each Pearl comes
  home. Yoi's Hideout becomes Yoi's home, an optional secret. Plop meets the
  slime at the town's edge with the 10-slot bag. A Heavy Roll knocks the
  grey tree over the river. Burr builds the Bow once the slime brings him
  silk, after Pearl 2. After Fatty, Burr and the journal send the slime home,
  where the well comes back. Campfires craft the first recipes, and the well
  gives a full refill. Question 106 follows.
- **2026-10-16 (fifth round):** the owner took the proposals of questions 93
  and 94. The War Axe owns living, green things; the Heavy Roll owns old,
  dead or built things lying or leaning in the way, plank barricades, old
  fences and mine timbers included; the Lantern owns dry plant growth and the
  wood the Roll knocks down. Release 1 has eight powers besides the Gulp,
  about three a chapter: the Spear, the Roll and the Heavy skin; the Goo Bomb
  and the Silk skin; the Lantern, the Feral skin and the Bow (from Burr, after
  Chapter 2). The War Axe and Stretch Lash wait for the next release.
  Questions 95 and 96 follow.
- **2026-10-16 (fourth round):** the owner answered questions 84 and 86 to
  92, and 85 in part. A few optional combos are welcome: a Heavy Roll knocks
  down an old tree whose old material the Axe cannot cut, and the Lantern
  burns it. The Bow is in Release 1, from Burr. Climbable walls show thick
  roots and handholds; the Axe's vines are leafy curtains. From the Wilds, the
  Caverns need a Feral climb and Gloop Forest a Silk web maze. The West
  village shop sells potions and ingredients. Early potions are found or
  made at a campfire, and a West village secret teaches a simpler one. Pearl 1
  restores Slimeshire's well, which refills energy. Climbable walls and heavy
  blocks never stand side by side. The three woods get three looks.
  Questions 93 and 94 follow.
- **2026-10-16 (third round):** the owner answered questions 68 to 83.
  Climbable walls have vines and irregularities; the slime climbs up and
  down, and a fall costs nothing. The Colossus climbs out of reach and
  throws minions down, which drop energy shards. Chapter 1's slabs cross the
  void and spikes, and a slab falls a set time after it is touched. A few
  combos used wisely are welcome (a Heavy Roll fells an old tree, the Lantern
  burns it). Release 1's part of the West village is a small town, and in-world
  barriers close the later regions. Release 1 has Plop's 10-slot bag; the
  20-slot bag waits. The Swim form's mechanics become the later Swim skin. The
  Bow also hits far enemies, and some enemies open doors when they die;
  Burr's thanks is the Bow. Each thing must be told apart: options are
  sacrificed for clarity. The quick roll is the Roll and the charged roll a
  later upgrade. Pearl 2 relights the Forge. A web-wall maze that only the
  Silk skin passes leads to the Caverns, and the end-of-Chapter-2 card goes.
  The relit Forge knows the potions, and an NPC with a tip shows the
  exclamation mark. The Bouncy Bow goes. Questions 84 to 86 follow.
- **2026-10-16 (later):** the owner answered questions 52, 53, 56 to 59 and
  61. Ingredients come from pickups and drops; one bag, and the vault waits.
  Pearl 3 grants the **Feral** skin: it climbs some walls while W is held,
  claws showing, and its Spear hits twice as fast. Bombs still chain.
  Release 1 ends when the Colossus falls, then the player explores the three
  chapters, the West village and the Wilds. All four braziers bare a random
  weak spot on the Colossus, and the smith, safe at his crystal mine, gives
  the Lantern. The Roll comes from young Burr in the West village, whose
  father Burr, the gatekeeper, waits in Fatty's Lair; the burrow is opened
  with a gate that shuts fast and falling slabs over lava, spikes or the
  void. The Heavy skin's Roll shakes things loose and breaks loose rocks,
  rubble heaps and old trunks, with no enemy push. Part of the West village
  joins Release 1. Deep water stays for later, and the swimming code stays.
  A **Bow** comes later. Questions 68 to 76 follow from these.
- **2026-10-16:** the owner answered questions 54, 55, 56, 60 and 61. Tom
  hangs in a cocoon a weapon can tear. With the Silk skin a shape cuts web
  walls open for good and frees what is wrapped in silk. Swim does not fit
  the Crystal Colossus, so Pearl 3's skin is Open again (ideas under 56). The
  journal keeps the main quest and the NPCs' tips, and its Pearl slots fill
  as the Pearls are won, lighting up a picture and saying what each one does.
  The Roll is taught in Chapter 1 before Fatty One Eye; the owner's story
  for it, polished, is under 61. Questions 52, 53, 57, 58 and 59 wait.
- **2026-10-15 (review):** the owner answered questions 40 to 49. Energy
  refills by itself, slowly (1 a second), and more refills are to come:
  refills that grow back, and a full refill at the Wellspring and at save
  points; the quick Roll stays free. Each skin has its gate and a change to a
  move: **Heavy** sinks heavy plates and moves heavy blocks, and its Roll
  pushes enemies away and shakes things loose; **Silk** passes web walls at
  −50%, webs no longer slow it, and only with it do shapes cut webs;
  **Swim**, Pearl 3's, from the Crystal Colossus, crosses deep water. "Depth
  from combos" is dropped. Abilities are chosen in the bag, which pauses the
  game, and no ability requires another: the Lantern no longer sets off a
  bomb. Release 1 is Chapters 1 to 3 with those three skins; NPCs teach and
  chests hold the finds, and manuscript pieces and Slime Forge evolutions
  come later. Webs slow the slime by 50% until the Silk skin. Squash Slam is
  removed, and the Goo Bomb breaks cracked ground. Release 1 crafts only
  potions and food ("maybe the vault"), with no harvesting. Once the three
  skins are built, the rework is the only game and the old system goes, its
  art held in `asset/to-delete/`. The roadmap carries these as
  [tasks](../GAME_ROADMAP.md#the-2026-10-15-decisions). Questions 50 to 61
  follow from these answers.
- **2026-10-15 (later):** skins are always on once learned (like Zelda's
  flippers or Super Metroid's suits): contextual, pure additions that stack,
  no keys. No ability is locked to a skin.
- **2026-10-15:** two systems for the slime's powers, plus abilities. Each
  Pearl grants a **skin** (Heavy from Fatty One Eye, Silk from the Matron),
  permanent, free, and never knocked off. **Shapes** (spear, axe, hammer, ...)
  replace crafted weapons and are taught by NPCs or old manuscripts.
  Abilities cost energy; the **Bomb** is one, and breaks cracked walls and
  ground. Swallow and essences are marked for deletion; the Gulp only grabs
  and throws. Energy does not regenerate. Webs slow the slime by 80% and web
  walls stop it without the Silk skin; with it, webs do not slow it and web
  walls slow it by 50%. No web wall blocks the way to the Matron. Bosses keep
  the slime in their chamber until beaten, and do not come back. See
  [Direction](01-direction.md). *Changed by the review the same day (above):
  energy refills slowly, at 1 a second, and webs slow the slime by 50%.*
- **2026-10-02:** each of the eight Pearls grants one unique permanent ability
  before returning to the Wellspring. Pearl 1 grants Jump; Pearl 2 grants
  Stretch Lash. Dodge remains basic training from Plop. Squash Slam belongs to
  a later Pearl; the other five Pearl abilities are Open. *Changed
  2026-10-08: the jump is removed and Pearl 1 grants Squash Slam (below).
  Since 2026-10-09 the Dodge is the Roll. Changed again 2026-10-15: the
  Pearls grant skins, not abilities.*
- **2026-10-02:** adventure first, with a little crafting. *2026-10-15
  (review): in Release 1 the crafting is potions and food only.*
- **2026-10-02:** heart quarters, four to a heart, and four quarters per map
  for now.
- **2026-10-02:** the vault has 50 slots, shares one storage across all vaults,
  holds weapons, and is found during a house quest that also teaches sleeping.
  *Changed 2026-10-15: shapes replace crafted weapons, and whether Release 1
  has the vault is question 53.*
- **2026-10-02:** sprint is a powerful mid-game ability, not available at the
  start.
- **2026-10-02:** webs trap the slime, and only the Silk Armor passes them,
  spending energy. A web door closes the Matron's camp. *Changed 2026-10-15:
  webs and web walls (above); no web door.*
- **2026-10-02:** the item ceremony, the timed crafting ideas, and the orb HUD
  ideas are accepted. See [Direction](01-direction.md).
- **2026-10-08:** the HUD console mockup's direction is approved
  ([mockup](../design/2026-10-07-hud-console-mockup.md#the-owners-answers-2026-10-08)):
  the orb numbers show only when a value changes; the slime starts with no
  hearts, the life orb's ring shows each heart quarter found, and only a whole
  heart adds max life; the minimap is never bigger than the orbs; one slot for
  the weapon in hand, with a weapon carousel on each scroll; E scrolls the
  weapon and the bag moves to B. Still open there: the menu buttons. The same
  day: B opens the bag and J the journal in every control scheme, E scrolls
  the weapon, and in the keys-only scheme only E cycles the belt.
- **2026-10-08:** the jump is removed from the game: its code stays, but no
  key, HUD slot or story beat uses it. Fatty One Eye's Pearl grants Squash
  Slam instead (until the Pearl is built, finishing The One-Eyed Guardian
  teaches it, and the Matron no longer does), and a Squash Slam in the Heavy
  form breaks cracked ground. See
  [Direction](01-direction.md#decisions-of-2026-10-08). *Changed 2026-10-15:
  the Pearls grant skins, Squash Slam is removed, and the Goo Bomb breaks
  cracked ground.*
- **2026-10-08:** Gulp is redesigned around essences instead of armors. The
  full design is in [Gulp](../GAME_GUIDELINES.md#signature-mechanic-gulp), and
  the table in [Direction](01-direction.md#decisions-of-2026-10-08)
  summarizes it. *Changed 2026-10-15: the Gulp only grabs and throws, and
  Swallow, essences, the forms and these keys go once the three skins are
  built (question 48).*
  - Q sucks in an essence or a light object and throws it.
  - Swallow (R; W in keys-only) turns a held essence into its form. Tom teaches
    it at Mossy's forest camp after the slime frees him from a web with its
    weapon (built 2026-10-09; Swallow is on 1 since that day's key change).
  - A hit pops the form out as a blob. Swallow with nothing held drops the
    essence out whole.
  - Essences: the Clod Stomper drops stone, spiders drop silk, and an aquatic
    monster will drop swim; some essences are placed in maps. The frog is
    decoration.
  - The Dodge becomes the Roll (built 2026-10-09). Keys (changed 2026-10-09): Q sucks and throws,
    1 swallows, 2 rolls, and Stretch Lash, Squash Slam and Teleport move to 3,
    4 and 5; interact stays where it was.
- **2026-10-09:** the Roll is a dash like Zelda's Pegasus Boots: straight, no
  steering, a bonk and a bounce back off walls, and the slime learns all of it
  at once (questions 16 and 26). Learning an ability gets a ceremony of the
  slime's own; it was built for abilities the same day (roadmap 4.13), and
  items still wait for theirs.
