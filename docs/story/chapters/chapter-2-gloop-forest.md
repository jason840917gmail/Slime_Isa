# Chapter 2 — Gloop Forest

| | |
|---|---|
| **Region** | Gloop Forest (`gloop-forest`, `gloop-hut`; `gloop-cavern`, a small secret cave: owner, 2026-10-16, question 18), its dungeon the Weaver Hollow (Planned, questions 25 and 133), plus Slimeshire for the Forge |
| **Goal** | ~~Make iron gear,~~ learn the chapter's key tool (the Goo Bomb, owner, 2026-10-16, question 94), and break the Matron's hold on the forest. Iron gear left the plan on 2026-10-15: no crafted gear in Release 1 (question 50). Her Pearl's Silk skin opens the way on to Chapter 3 (owner, 2026-10-16, question 81) |
| **Boss** | Orb-Weaver Matron |
| **Earned** | Today: the Reinforced Pickaxe, the Forge, iron gear, Stretch Lash (Beyond the Verdant Gate) and Swallow (from Tom, Built 2026-10-09). Rework: the Goo Bomb and the Lantern (Chapter 3's since 2026-10-16: the smith gives it, question 59). Planned: the **Goo Bomb**, the chapter's key tool (owner, 2026-10-16, question 94; where it comes from is question 95), Pearl 2 with the **Silk skin** and a boss heart. Stretch Lash waits for the next release (question 94). Release 1 has one bag, Plop's 10-slot bag, so the 20-slot bag waits for the next release (owner, 2026-10-16, questions 53 and 74). The pickaxe and the iron gear go with the crafted gear, Swallow is marked for deletion, and the Forge, relit when Pearl 2 comes home, brews the potions (questions 51 and 79). *Changed 2026-10-16 (sixth round): Tom teaches the Goo Bomb at the end of a maze (question 95, Beat 3), the Weaver Hollow's big chest holds a heart or the dungeon's big key (question 95, Beat 8), and the Matron's thread, taken from her web, goes to Burr for the Bow (question 106, Beat 9).* *Changed 2026-10-16 (seventh round, question 113): Tom teaches the Goo Bomb at the end of his maze, as soon as he is freed, and the Weaver Hollow's big chest holds a heart quarter.* *Changed 2026-11-17 (owner, question 146): shapes are dropped as a concept, and the Spear is an ability.* *As built (2026-11-14): nobody teaches the Goo Bomb (only dev runs have it), and the Weaver Hollow's root gate needs it, so the Hollow cannot be entered in play; Pearl 2 and the Silk skin are built inside it, in the Hoard.* *Changed 2026-11-20 (owner): Pearl 2's homecoming raises Pip's Workshop, and the Forge waits for Pearl 3 (Chapter 3); the Matron's thread goes to Pip for the Bow's rune.* |
| **Status** | Built and in progress (roadmap 8.3–8.13). The beats below mark each Planned change and Proposal. Every beat is a quest as built; quests no longer make sense (owner, 2026-10-15, question 50). In their place the journal keeps one main quest and the NPCs' tips, and an NPC hands over or teaches its find when the slime talks to it (owner, 2026-10-16, question 60). *As built (2026-11-14): the quests in the data are still the old chain (they reward Stretch Lash and Swallow), and they cannot be finished: no story chunk has any wood.* *Built 2026-11-19: the old quests are retired; Mossy and Tom give tips at the camp, Tom's web tears under the Spear with no quest, and the Matron's fall sets `chapter-2-complete`; the Chapter 2 end card is gone ([quests spec §14](../../godot/specs/quests.md#14-the-main-quest-talks-and-tips-2026-11-19)).* |

Quest IDs are in brackets. Their dialogue lives in
`godot/game/data/quests-chapter-2.json`. The older design is in
[the Chapter 2 outline](../../design/2026-09-30-chapter-2-outline.md)
and [the Matron spec](../../design/2026-10-01-orb-weaver-matron.md).

---

## Beat 1 — Beyond the Verdant Gate [`beyond-the-verdant-gate`] (Built)

**Giver:** Mossy, at the forest camp.

- Mossy: "I set up camp here, behind these old walls. The hut is ours to use:
  sleep in its bed and you will wake here, not back home." *(in game)*
- **The player does:** defeats 5 orb-weavers and picks up 3 weaver fangs.
  *2026-10-16 (owner, question 63): the weaver fangs go.* *2026-10-16
  (owner): enemies in the world are placed, not spawned. Today the forest's
  orb-weaver camps spawn from enemy-spawn areas and refill on a timer;
  Planned: a fixed number of placed orb-weavers per chunk, each with its own
  wandering area, back when the chunk is reloaded
  ([World](../03-world.md#enemies-in-the-world-planned)).*
- **Reward:** the Reinforced Pickaxe recipe and 30 coins. The pickaxe goes
  with the crafted tools (2026-10-15: no harvesting in Release 1).
- **Planned change:** remove Stretch Lash from this reward (it teaches it
  today). Stretch Lash is learned from manuscripts; where is Open
  (question 33). *2026-10-16 (owner, question 94): Stretch Lash waits for the
  next release, so Release 1 does not teach it.*
- **Changed 2026-10-09:** this reward no longer teaches **Swallow** (it was a
  stand-in); Tom does (Beat 3).
- **Proposal, the trail:** Mossy has been following something. "The webs got
  thick about the same time the ground started shaking. Strange, isn't it?"

## Beat 2 — Sunny's Basket [`sunnys-basket`] (Built; its place follows Stretch Lash)

**Giver:** Sunny, at the forest camp.

- **The player does:** once the slime knows Stretch Lash, pulls Sunny's
  basket across the north stream.
- **Reward:** 2 purple berries and 20 coins.
- **2026-10-16 (owner, question 94):** Stretch Lash waits for the next
  release, so Sunny's basket becomes a come-back secret (question 65).

## Beat 3 — Tom in the Web [`tom-in-the-web`] (Built, 2026-10-09)

**Giver:** Mossy, at the forest camp, after Beyond the Verdant Gate.

> **2026-10-15: Swallow and essences are marked for deletion.** The code
> stays, but the game will not use it. The slime already has the Heavy skin
> from Fatty One Eye's Pearl, so nothing here needs swallowing. **Open:** Tom
> teaches the chapter's new key tool instead (the Goo Bomb or something new;
> the Lantern is Chapter 3's since 2026-10-16, question 59), or this beat
> goes (question 31). **2026-10-16 (owner,
> question 54):** Tom hangs in a cocoon, which a weapon can tear, so freeing
> him needs no Silk skin. **2026-10-16 (owner, question 94):** the key tool is
> the Goo Bomb, and whether Tom teaches it is question 95. In Release 1 the
> Spear, the only shape, tears his cocoon. **2026-10-16 (owner, question
> 95):** Tom teaches the **Goo Bomb**, with the full ceremony. Reaching him is
> not easy: the slime passes a maze with several secrets and tests to get to
> him, solved with the powers it has by then (the Spear, the Roll, the Heavy
> skin and the Gulp). The maze's webs slow the slime and cannot be cut before
> the Silk skin. **2026-10-16 (owner, seventh round, question 113):** Tom
> hangs in his cocoon at the end of the maze and teaches the Goo Bomb right
> there, as soon as he is freed, no longer at Mossy's camp. Where in the
> forest the maze lies is not decided. Not built. The text below is the beat
> as built until 2026-11-19.
>
> **As built 2026-11-19 (question 117: E5's south-west woods; Tom first, his
> maze later):** the quest is retired and Tom's web hangs in a small clearing
> at the end of a short path cut into the forest band west of the trail
> (gloop-forest-e5). Three Spear hits tear it, any time (Mossy's tip sends
> the slime there). Torn, Tom calls "I'm free!", and his lesson plays right
> there: he got caught studying the webs, the Matron's brood wrapped him up,
> thanks; he teaches the **Goo Bomb** with its ceremony, points at the cracked
> rock in the ledge beside his clearing and goes off to Mossy's camp, where he
> waits with his tip about the Watch Oak's root gate. The cracked rock is the
> Goo Bomb's first lock: blown (the secret jingle), it opens a short tunnel
> back north to the trail, and the loop closes. A run that freed him before
> (an old save) learns the Goo Bomb from him at the camp. He no longer teaches
> Swallow.

The iron hollow's gate and the cracked clearing both need something heavy, and
from now on heavy comes from swallowing a stone essence. Swallowing is taught
here. This beat replaces the Stone Armor of 2026-10-02.

- **The story:** Tom, a slime who already knows how to swallow, went into a
  spider thicket to swallow some silk and got caught in a web. Mossy asks the
  slime to bring him back. The owner may add more to this story later.
  - Mossy: "He went into the spider thicket south-west of here to swallow some
    silk, the fool, and he has not come back." *(in game)*
- **Tom:** a round blue jelly slime with a moss-green scarf and a small bottle
  of glowing essence.
- **The player does:** fights through the spiders and frees Tom by hitting the
  web around him with a weapon. The slime cannot swallow yet, and a path web
  would trap it.
  - The web hangs in the south-west spider thicket. Three weapon hits tear it;
    thrown things and abilities only shake it. It tears only while the quest
    is active; before that, Tom just mumbles.
  - Torn, Tom calls "I'm free! Thank you! Meet me at Mossy's camp!" *(in
    game)*. The torn web stays, and Tom waits by the camp fire.
  - *Since 2026-10-16 (eighth round, questions 129 and 132): in the plan his
    cocoon hangs by a thread with his face showing, and the Goo Bomb's first
    lock is a cracked wall by him, his maze's way back to its start: he
    teaches, the slime blows the wall, the jingle plays, the loop closes.*
- **Reward:** back at the camp Tom teaches **Swallow** and gives 20 coins. It
  is the chapter's key item: the Matron and the web secrets need the forms it
  opens. The full ceremony marks it (built 2026-10-09). *As built
  (2026-11-14): still so in the data; his Goo Bomb lesson and his maze are not
  built (question 117).*
  - Tom: "Phew! I thought I'd be a weaver's snack. You pulled me out, so here
    is how it is done." *(in game)*
- **Then:** Clod Stompers, squat golems that stomp the ground, live by the iron
  hollow. Beaten, they drop **stone essences**: swallowed, they give the Stone
  form.
  - Built 2026-10-09: two camps, one south of the iron hollow's plate and one
    east of the cracked clearing. A Clod Stomper crouches behind a ring, hops
    and slams; its slam breaks cracked ground near its feet. The clearing's
    camp keeps it away from the cracks, so they break only for a slime that
    lures it over. It always drops a stone essence.
  - *2026-10-16 (owner, question 64): the Clod Stomper stays as it is, and
    its slam still breaks cracked ground near it: it is an enemy, not a
    power. Its stone essence goes with the essences.*

## Beat 4 — A Harder Pick [`a-harder-pick`] (Built)

**Giver:** Mossy, after Tom in the Web (since 2026-10-09; before that, after
Beyond the Verdant Gate).

- **The player does:**
  1. Crafts the Reinforced Pickaxe (its hammering was dropped 2026-10-15).
  2. Opens the iron hollow by standing on its plate in the Heavy skin
     (Planned; today in the Stone form from a swallowed stone essence).
  3. Mines 6 iron ore.
- **Question 60:** with no harvesting and no crafted tools in Release 1, this
  quest loses its point, and the quests go. What the iron hollow holds
  instead is not decided yet (question 63). *Answered 2026-10-16 (owner):
  heart quarters, potions, coins or a piece of the story, such as a piece of
  Kiri's note (the 2026-10-11 plan's).*
- **Reward:** 20 coins. Mossy sends the slime home to Pip: "Slimeshire had a
  Forge, once." *(in game)*

## Beat 5 — Rekindle the Forge [`rekindle-the-forge`] (Built)

**Giver:** Pip, in Slimeshire.

- **The player does:** restores the Forge (40 stone, 20 wood, 6 iron ore),
  then smelts 2 charcoal and 3 iron bars.
- **Planned change: smelting takes time.**
  - The Forge shows a progress bar while the charcoal and bars cook, and the
    slime can walk away and come back to claim them.
  - Pip: "It needs a while to get hot. Go on, I will watch it!"
- **2026-10-15:** Release 1 has no harvesting and crafts only potions and
  food, so the smelting and its timer leave Release 1: the Forge brews the
  potions until evolutions arrive (owner, question 51).
- **2026-10-16 (owner):** Pip's story stays relighting the Forge, and is no
  longer about finding his dad (question 59). A building is restored when a
  Pearl comes home (question 60); which Pearl relights the Forge is not
  decided. *Changed 2026-10-16 (owner, question 79): Pearl 2, the Matron's,
  relights it when it comes home (Beat 9), and Pip and the slime light it.
  This replaces the quest and its ore cost. From then on the Forge brews the
  potions and knows their recipes (question 82).* *Changed 2026-10-16
  (seventh round, question 110): Pearl 2 goes home to the Wellspring, and its
  power flows into the town and lights the Forge.* *Changed 2026-11-20
  (owner): Pearl 2 raises Pip's Workshop instead, and Pearl 3 lights the
  Forge, at the end of Chapter 3. Pip's quest is now Pip's Workshop
  ([Chapter 3](chapter-3-crystal-caverns.md#beats), beat 1). The quest
  Rekindle the Forge is retired (2026-11-19).*
- **Reward:** the Iron Spear recipe and 40 coins. The Iron Spear goes with
  the crafted weapons (2026-10-15).
  - Pip: "Look at it glow! Dad would be so proud." *(in game)*
- **Proposal, Pearl 1 comes home:**
  - Back in Slimeshire with Fatty's Pearl, the slime meets Plop at the
    Wellspring. The Pearl sinks in, and the pool brightens for the first time
    in years.
  - Plop tells the first piece of the story: the Wellspring, the Pearls, and a
    name nobody says aloud, Gorge.
  - Slimeshire's first visible change follows; which one is Open.
  - *2026-10-16: the Forge quest that brought the slime home goes
    (question 79). What brings it home with Pearl 1 is not decided yet.*
    *2026-10-16 (owner, question 90): Slimeshire's first visible change is
    its well, which Pearl 1 restores and which then refills energy.*
    *Changed 2026-10-16 (sixth round, questions 98, 100 and 103): Pearl 1
    comes home at the end of Chapter 1. After Fatty, the freed Burr says the
    town must see the Pearl, the journal's main quest points home, and the
    well comes back when the slime brings the Pearl to it
    ([Chapter 1](chapter-1-the-clearing.md), Beat 5). Each homecoming is a
    short scene at the Wellspring, the prologue's lake, which a short forest
    path from Slimeshire's south-west reaches; Plop no longer meets the slime
    there.* *Changed 2026-10-16 (seventh round, question 110): the slime
    takes Pearl 1 home to the Wellspring, not to the well; the Wellspring
    brightens, and its power flows into the town and brings the well back.*

## Beat 6 — Iron Gear [`iron-gear`] (Built)

**Giver:** Elder Plop.

- **The player does:** forges an Iron Spear (10 wood, 4 iron bars). Planned:
  the first real hammering session, ending in the full ceremony.
- **2026-10-15:** no crafted gear in Release 1, so the iron gear, its
  hammering and this quest go (question 50). In place of the quests, NPCs
  give tips and the journal keeps the main quest (owner, 2026-10-16,
  question 60).
- **Reward:** the Iron Axe recipe and 40 coins.
  - Plop: "Something big is nesting in the north-east. Find Mossy when you are
    ready." *(in game)*

## Beat 7 — The Gloop Cavern (Built secret)

> **2026-10-16 (owner, tenth round, question 18): the Gloop Cavern stays as a
> small secret cave**, the Goo Bomb's come-back secret, holding one of Gloop
> Forest's four heart quarters (today's Goo Heart), with no four of its own.
> Its coffer stays gone (questions 63 and 74). In the eighth round the owner
> first said there is no Gloop Cavern; told that the small cave is built, he
> kept it. The text below is the beat as built.

**Where:** the cracked clearing, south-west of the camp.

- **The player does:** breaks the cracked ground and drops into the Gloop
  Cavern. Today a Squash Slam in the Stone form breaks it (Built 2026-10-08);
  Planned: the **Goo Bomb** (it blows cracked walls in the rework, not cracked
  ground yet), since Squash Slam is removed (owner, 2026-10-15).
- **Planned change: the 20-slot bag.** A coffer in the cavern holds a **20-slot
  bag**, which replaces the 10-slot one. Full ceremony. *Changed 2026-10-16:
  Release 1 has one bag (question 53), so what the coffer holds is
  question 74. Changed again the same day: the one bag is Plop's 10-slot
  bag, the 20-slot bag waits for the next release, and the coffer's prize is
  question 63 (question 74).* *Answered 2026-10-16 (owner, question 63): the
  coffer holds heart quarters, potions, coins or a piece of the story.*
- *As built (2026-11-14): the cracked ground breaks under the Goo Bomb, and
  the cave's Goo Heart is a heart quarter since 2026-10-26.*
- **The cavern today:** a chest with iron ore, charcoal and a tonic, plus a Goo
  Heart and crystal shards. *Since 2026-11-20 (owner) its hidden chest
  (`gloop-cavern-hidden-chest`) also holds a **Roll Fragment**, Gloop Forest's
  one of the four that make the Charged Roll (Burr's in Fatty's Lair, Yoi's,
  the A4 barn's in Glimmerhill; the fourth found teaches it).*
  - Planned: the Goo Heart becomes one of the region's heart quarters.
  - Proposal: the shards glow faintly, a hint of Chapter 3.

## Beat 8 — Webs (Planned)

The forest has two kinds of web (2026-10-15):

| | Webs | Web walls |
|---|---|---|
| **Without the Silk skin** | Speed −50% | Cannot pass |
| **With the Silk skin** | Full speed | Pass at −50% speed |

- The slowdown was 80% until the review of 2026-10-15. The Matron's fight is
  played with it before the number is fixed.
- Before the Matron the slime has no Silk skin: webs slow it down, and web
  walls keep it out of secrets. **No web wall blocks the way to her.**
- The shapes cut webs only once the Silk skin is learned, so the player has
  to deal with the webs to defeat the Matron (owner, 2026-10-15). With the
  skin, a cut opens a web wall for good and frees things wrapped in silk
  (owner, 2026-10-16, question 55). In Release 1 the Spear, the only shape,
  does the cutting (question 94). *Changed 2026-11-17 (owner, question 146):
  shapes are gone; the Spear, an ability, does the cutting.*
- After the Matron, her Pearl grants the Silk skin, and the web walls open:
  the **silk nook** in the north-west and the other web secrets in the forest
  and in Chapter 1's map.
- *Changed 2026-10-17 (owner): her Pearl lies in the Weaver Hollow, before
  her, so the slime meets her with the Silk skin. The Hollow's second half
  teaches the skin on its webs and web walls, and her fight is its exam. The
  two bullets above ("before the Matron the slime has no Silk skin", "the
  player has to deal with the webs to defeat the Matron") hold only up to the
  Pearl.*
- **The way to Chapter 3** (Planned, owner, 2026-10-16, question 81): a maze
  of web walls on the forest's east side, which only the Silk skin passes,
  leads to the Crystal Caverns. The Silk skin opens Chapter 3, as a skin
  opens the next region. *Built 2026-11-20: three web walls stand across the
  web lane in F4 before the Caverns (the lane is entered by its ford), so only
  the Silk skin passes; the maze itself is designed with the owner later.*
- **The way in from the Wilds** (Planned, owner, 2026-10-16, question 87): a
  second web maze, which only the Silk skin passes, so the Wilds never skip
  the Verdant Gate. *As built (2026-11-14): the North Wilds' link into the
  forest was closed on 2026-10-31, and the South Wilds' opening is a plain
  one; question 164.* *Changed 2026-11-19 (owner, question 164): the Wilds are
  walled off for all of Release 1, so this maze waits for the release that
  opens them. Built 2026-11-20: E5's trail south into the South Wilds is
  planted shut, its exit gone.*
- Today spiders drop **silk essences** that give a Silk form when swallowed
  (built 2026-10-09). They are marked for deletion.
- **Open until 2026-10-16:** the Weaver Hollow, once proposed as the place to earn silk. Keep
  it as a small dungeon (for example, where the key tool or a manuscript is
  found), or drop it. *2026-10-16: in the
  [2026-10-11 dungeons plan](../../design/2026-10-11-release-1-dungeons-plan.md)
  its big chest held the War Axe, which now waits for the next release
  (question 94). What it holds instead is part of question 95.* *Answered
  2026-10-16 (sixth round, owner, question 95): the big chest holds a heart
  or the dungeon's big key instead of the Axe.* *Changed 2026-10-16 (seventh
  round, owner, question 113): it holds a heart quarter.* Like every dungeon,
  quitting or fainting inside it resumes at its entrance, with what the slime
  did there kept (question 109). *Closed 2026-10-16 (eighth round,
  questions 25 and 133): the Weaver Hollow is Chapter 2's dungeon. Its
  entrance is the Matron's old nest, and she lives at its top (Beat 9). Its
  own enemies are the Broodling and the Cocoon Mimic, with the Brood Warden as
  mini-boss ([bestiary](../../design/2026-10-16-bestiary.md)); where its big
  key lies is [question 116](../06-open-questions.md#open-after-the-seventh-round-2026-10-16).*
- **A Roll sticks in a floor web** (Planned, owner, 2026-10-16, question 131):
  walking through one slows the slime until the Silk skin, and web walls block
  until the Silk skin; with it, a web no longer sticks. The War Axe, in the
  next release, cuts webs without it (question 135).
- **Tom's maze** (Planned, owner, 2026-10-16, question 95): its webs slow the
  slime and cannot be cut before the Silk skin (Beat 3). Tom hangs at its end
  and teaches the Goo Bomb there once freed (question 113).

## Beat 9 — The Matron's Nest [`the-matrons-nest`] (Built)

**Giver:** Mossy.

*As built (2026-10-17): the Matron lives at the top of the Weaver Hollow, in
the Crown (C2); her old nest in the open forest is placed nowhere, and the
quest's text still tells the old nest fight.*

- **The way in:** no web wall blocks the nest (the web door of 2026-10-02 is
  dropped).
- **Planned (owner, 2026-10-16, eighth round, question 133): the Weaver
  Hollow.** The Matron lives at the top of the Hollow, Chapter 2's dungeon,
  and her nest in the open world becomes its entrance. Her fight needs the
  Goo Bomb, the chapter's tool: she shields herself in a web cocoon that only
  a blast tears open, then the Spear hurts her.
- **Planned: the fight.**
  - **New art** for the Matron.
  - Her **normal attack is Stretch Lash in three directions**, spread wide
    enough to dodge between. A hit deals damage, pulls the slime toward her
    and traps it. The slime has no Silk skin yet, so it always takes the full
    effect.
  - Her **web volley** marks four circles. The webs it leaves slow the slime
    like every web.
  - The slime's shapes cannot cut her webs before the Silk skin, so it has to
    deal with them (owner, 2026-10-15).
  - She rests after each volley, and that is the opening to hit her.
  - *Changed 2026-10-17 (owner): the slime comes to her with the Silk skin,
    won from Pearl 2 in the Hollow before her, and her fight is the skin's
    exam. What the skin changes in her lash, her volley and her cocoon is not
    decided ([the rework plan](../../design/2026-10-17-pearl-mid-dungeon.md)).*
  - *Changed 2026-11-17 (owner, question 146): bosses are hurt by throws, or
    by something the slime throws into a mechanism; her fight is redone when
    the bosses are revisited (question 166).*
- **Boss rules (Planned):** once the slime enters her chamber it cannot leave
  until she is beaten. Today she heals to full after 60 s with the slime
  outside her arena. *Since 2026-10-17 (owner): taking Pearl 2 enrages her
  (her strength stays the same) and seals the Hollow's exits until she is
  beaten; fainting or quitting after it resumes at the entrance, inside, with
  the doors to the outside sealed.*
- **Reward:**
  - 100 coins and `chapter-2-complete`.
  - The end card, then the Crystal Caverns exit, still sealed with crystal.
    That was Release 1's end; Release 1 now goes on into Chapter 3 (owner,
    2026-10-15), so the card and the seal are Open (question 58). *Changed
    2026-10-16: Release 1's content ends when the Crystal Colossus falls
    (question 58), so the Matron's fall leads on into Chapter 3. Changed
    again the same day (question 81): the end card and the crystal seal go,
    and the web-wall maze that only the Silk skin passes leads to the
    Caverns (Beat 8).* *As built (2026-11-14): the end card still says
    Chapter 3 is still to come.*
  - Today a Goo Heart appears in the nest. Proposal: it becomes a full heart
    (+20), the boss's own reward on top of the map's four quarters.
    *Planned since 2026-10-16 (owner, question 17): each boss also gives a
    full heart, and beating her raises max energy (question 19).* *As built
    (2026-10-17): a full heart, +20 max HP and +20 max energy.*
- **Proposal, Pearl 2:** her nest was woven around a Pearl. Beaten, she shrinks
  back into an ordinary (big) orb-weaver and scuttles off. The Pearl lies in
  the silk.
  - The Pearl transfers the **Silk skin** permanently into the slime during
    its ceremony. The slime keeps it after returning the Pearl.
  - *Changed 2026-10-17 (owner): the Pearl is not in her nest's silk after
    the fight: she hides it in the Weaver Hollow, before her chamber, and the
    slime takes it there, with its ceremony. Whether she still shrinks back
    when beaten is not decided.*
  - **Planned (owner, 2026-10-16, question 79):** when Pearl 2 comes home it
    relights the Forge. Pip and the slime light it, and from then on it
    brews the potions. *Changed 2026-10-16 (seventh round, question 110):
    the Pearl goes home to the Wellspring, and its power flows into the town
    and lights the Forge.* *Changed 2026-11-17 (owner, question 149): its
    power also fills Glimmerhill's next fountain and wakes the next part of
    town. Which part is question 159 (Proposal: West Hill, A4), and so is
    whether it still lights the Forge (Proposal: it does).* *Settled
    2026-11-19 (question 159): the proposal. Built 2026-11-20: its homecoming
    wakes West Hill and sets `forge.restored`, which lights the Forge.*
    *Changed later on 2026-11-20 (owner): its homecoming wakes West Hill and
    raises Slimeshire's old Workshop (`workshop.restored`; the card: "Far off
    in Slimeshire, the old Workshop rises from its boards."), where Pip then
    carves the Bow's rune; Pearl 3 lights the Forge. Built the same day.*
  - **Planned (owner, 2026-10-16, question 94):** when the slime comes back
    to the West village after this chapter, Burr gives it the Bow
    ([Chapter 3](chapter-3-crystal-caverns.md#beats)). *Changed 2026-11-17
    (owner, question 150): Burr's house is in Slimeshire's C4, so he gives it
    there.* *Changed 2026-11-20 (owner): Pip carves its rune at the raised
    Workshop instead.*
  - **Planned (owner, 2026-10-16, questions 102 and 106): the Matron's
    thread.** After she falls, the slime finds a spool of her thread in the
    nest (her web at the top of the Weaver Hollow since question 133) and,
    with the Silk skin, takes it from her web. It is the silk Burr
    needs to build the Bow; his other things are already in his workshop. With
    the thread and Pearl 2 home, he teaches the Bow: one find, one trip back,
    and no crafting. *As built (2026-11-14): the thread drops in her fight
    and has no use yet, as the Bow is not built.* *Changed 2026-11-20 (owner):
    the Bow is the slime's own body, so Burr builds nothing: the thread
    becomes its string. Built 2026-11-20: Burr takes the thread at his lesson.*
    *Changed later on 2026-11-20 (owner): the thread is the string of Pip's
    bow rune, brought to him with 5 wood and the smith's crystal; Burr no
    longer takes it. Built the same day.*
  - **Planned (owner, 2026-10-16, question 98):** Pearl 2's homecoming is a
    short scene at the Wellspring. *Built 2026-11-20
    ([PROLOGUE.md](../../godot/PROLOGUE.md#the-homecoming-2026-11-20)).*
  - Mossy: "Two of them now. And the shaking is worse. Whatever is under that
    mountain is waking up."

## Secrets (Planned)

- **Four heart quarters** in Gloop Forest. Their spots are Open, and so is
  whether the Gloop Cavern counts as its own map. *2026-10-16 (owner,
  question 18): it does not; the small cave holds one of the forest's four.
  Every quarter can be reached with Release 1's powers (question 135).* *Since 2026-10-16 (seventh
  round, question 113): the Weaver Hollow's big chest holds one; whether it
  is one of the forest's four is not decided.*
- Today's Goo Hearts in the forest (one is in the silk nook) and in the cavern
  become quarter spots.
- Some secrets sit behind web walls (the Silk skin), cracked walls (the
  Bomb), old dead or built things lying or leaning in the way (the Heavy
  skin's Roll: rubble heaps, rotten trunks across paths, grey leaning old
  trees, old fences, plank barricades; question 93) or walls with thick roots
  and rocky handholds to climb (the Feral skin, question 86), which sends the
  slime back through Chapter 1's map as well. A few optional secrets may
  combine a skin and an ability, each clearly different (question 84). The
  War Axe's and Stretch Lash's locks (leafy vines, bushes, trees in leaf;
  Sunny's basket) are come-back secrets for the next release (question 94). The water secrets wait for the Swim skin from a later Pearl, after
  Release 1 (owner, 2026-10-16, question 56): the deep-water secrets are
  come-back secrets (question 75).

## Chapter 2 checklist

| Item | Beat | Status |
|---|---|---|
| Stretch Lash | The next release (question 94; manuscripts, question 33) | Built at Beat 1 |
| Reinforced Pickaxe | 1, 4 | Built; goes with the crafted tools (2026-10-15) |
| Swallow (from Tom) | 3 | Built 2026-10-09; marked for deletion; Tom no longer teaches it (2026-11-19) |
| Chapter key tool: the Goo Bomb (owner, 2026-10-16, question 94; the War Axe waits for the next release, and the Lantern is Chapter 3's) | 3, from Tom (question 95) | Built: Tom's lesson as his web tears, and its first lock, the cracked rock by his clearing (2026-11-19) |
| Tom's maze (secrets and tests, webs that slow; Tom at its end) | 3 | Planned (questions 95 and 113) |
| The Weaver Hollow's big chest: a heart quarter (a heart or the big key until the seventh round) | 8 | Planned (questions 95 and 113) |
| Clod Stomper | 3–4 | Built 2026-10-09 (its essence drop marked for deletion); it stays as it is, slam included (question 64) |
| Forge | 5 today, 9 in the plan | Built (smelting); Planned: Pearl 2 relights it, and it brews the potions (questions 51 and 79); the smelting timer leaves Release 1. *Changed 2026-11-20 (owner): Pearl 3 lights it, in Chapter 3 (built)* |
| The Workshop | 9 | Built 2026-11-20 (owner, the same day): Pearl 2's homecoming raises it, Pip's place, where he carves the Bow's rune in Chapter 3 |
| Iron Spear, Iron Axe | 5–6 | Built; they go with the crafted gear (2026-10-15) |
| 20-slot bag | 7 | Waits for the next release (question 74); the coffer held heart quarters, potions, coins or a piece of the story (question 63) until the coffer went (question 18) |
| The Gloop Cavern's heart quarter, one of the forest's four | 7 | Planned (question 18; the Goo Bomb opens the cracked clearing) |
| A Roll Fragment (one of four) | 7, the Gloop Cavern's hidden chest | Built 2026-11-20 (owner, the same day) |
| Webs and web walls | 8 | Built 2026-10-17 ([WEBS.md](../../godot/WEBS.md)); −50% without the Silk skin |
| The web-wall maze to the Crystal Caverns | 8 | Built 2026-11-20 as three web walls across the web lane (question 81); the maze itself is designed with the owner later |
| The second web maze, from the Wilds | 8 | Waits for a later release: the Wilds are walled off in Release 1 (owner, 2026-11-19, question 164); E5's way south planted shut 2026-11-20 |
| Pearl 2 and the Silk skin | 9; the Weaver Hollow, before the Matron, since 2026-10-17 | Built 2026-10-17 in the Hoard; its homecoming, which wakes West Hill (question 159) and raises Slimeshire's Workshop (owner, 2026-11-20; it lit the Forge until then), built 2026-11-20 |
| The Matron's thread (for the Bow's string) | 9 | Built: it drops in her fight; Pip takes it for the bow rune's string (built 2026-11-20, Burr's lesson until the owner's change the same day; question 106) |
| Boss heart (Matron) | 9 | Built: a full heart, +20 max HP and +20 max energy (questions 17 and 19) |
| The Weaver Hollow, the Matron at its top, her cocoon phase | 8, 9 | Built 2026-10-17 ([DUNGEONS.md](../../godot/DUNGEONS.md)); her fight is redone in the boss pass (question 166) |
| 4 heart quarters | Secrets | Two placed (the Gloop Cavern, the silk nook), and the Hollow's in its Pillar room (B6) |
