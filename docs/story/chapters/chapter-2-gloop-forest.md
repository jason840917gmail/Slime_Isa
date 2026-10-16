# Chapter 2 — Gloop Forest

| | |
|---|---|
| **Region** | Gloop Forest (`gloop-forest`, `gloop-hut`, `gloop-cavern`), plus Slimeshire for the Forge |
| **Goal** | Make iron gear, learn the chapter's key tool, and break the Matron's hold on the forest |
| **Boss** | Orb-Weaver Matron |
| **Earned** | Reinforced Pickaxe, the Forge, iron gear and the 20-slot bag; Rework: the Goo Bomb and the Lantern (candidates for the key tool); Planned: Pearl 2 with the **Silk skin**, and a boss heart. Swallow (from Tom, Built 2026-10-09) is marked for deletion. |
| **Status** | Built and in progress (roadmap 8.3–8.13). The beats below mark each Planned change and Proposal. |

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
- **Reward:** the Reinforced Pickaxe recipe and 30 coins.
- **Planned change:** remove Stretch Lash from this reward (it teaches it
  today). Stretch Lash is learned from manuscripts; where is Open.
- **Changed 2026-10-09:** this reward no longer teaches **Swallow** (it was a
  stand-in); Tom does (Beat 3).
- **Proposal, the trail:** Mossy has been following something. "The webs got
  thick about the same time the ground started shaking. Strange, isn't it?"

## Beat 2 — Sunny's Basket [`sunnys-basket`] (Built; its place follows Stretch Lash)

**Giver:** Sunny, at the forest camp.

- **The player does:** once the slime knows Stretch Lash, pulls Sunny's
  basket across the north stream.
- **Reward:** 2 purple berries and 20 coins.

## Beat 3 — Tom in the Web [`tom-in-the-web`] (Built, 2026-10-09)

**Giver:** Mossy, at the forest camp, after Beyond the Verdant Gate.

> **2026-10-15: Swallow and essences are marked for deletion.** The code
> stays, but the game will not use it. The slime already has the Heavy skin
> from Fatty One Eye's Pearl, so nothing here needs swallowing. **Open:** Tom
> teaches the chapter's new key tool instead (the Goo Bomb, the Lantern, or
> something new), or this beat goes. The text below is the beat as built.

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
- **Reward:** back at the camp Tom teaches **Swallow** and gives 20 coins. It
  is the chapter's key item: the Matron and the web secrets need the forms it
  opens. The full ceremony marks it (built 2026-10-09).
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

## Beat 4 — A Harder Pick [`a-harder-pick`] (Built)

**Giver:** Mossy, after Tom in the Web (since 2026-10-09; before that, after
Beyond the Verdant Gate).

- **The player does:**
  1. Crafts the Reinforced Pickaxe (Planned: hammered).
  2. Opens the iron hollow by standing on its plate in the Heavy skin
     (Planned; today in the Stone form from a swallowed stone essence).
  3. Mines 6 iron ore.
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
- **Reward:** the Iron Spear recipe and 40 coins.
  - Pip: "Look at it glow! Dad would be so proud." *(in game)*
- **Proposal, Pearl 1 comes home:**
  - Back in Slimeshire with Fatty's Pearl, the slime meets Plop at the
    Wellspring. The Pearl sinks in, and the pool brightens for the first time
    in years.
  - Plop tells the first piece of the story: the Wellspring, the Pearls, and a
    name nobody says aloud, Gorge.
  - Slimeshire's first visible change follows; which one is Open.

## Beat 6 — Iron Gear [`iron-gear`] (Built)

**Giver:** Elder Plop.

- **The player does:** forges an Iron Spear (10 wood, 4 iron bars). Planned:
  the first real hammering session, ending in the full ceremony.
- **Reward:** the Iron Axe recipe and 40 coins.
  - Plop: "Something big is nesting in the north-east. Find Mossy when you are
    ready." *(in game)*

## Beat 7 — The Gloop Cavern (Built secret)

**Where:** the cracked clearing, south-west of the camp.

- **The player does:** breaks the cracked ground and drops into the Gloop
  Cavern. Today a Squash Slam in the Stone form breaks it (Built 2026-10-08);
  Planned: the **Goo Bomb** (it blows cracked walls in the rework, not cracked
  ground yet).
- **Planned change: the 20-slot bag.** A coffer in the cavern holds a **20-slot
  bag**, which replaces the 10-slot one. Full ceremony.
- **The cavern today:** a chest with iron ore, charcoal and a tonic, plus a Goo
  Heart and crystal shards.
  - Planned: the Goo Heart becomes one of the region's heart quarters.
  - Proposal: the shards glow faintly, a hint of Chapter 3.

## Beat 8 — Webs (Planned)

The forest has two kinds of web (2026-10-15):

| | Webs | Web walls |
|---|---|---|
| **Without the Silk skin** | Speed −80% | Cannot pass |
| **With the Silk skin** | Full speed | Pass at −50% speed |

- Before the Matron the slime has no Silk skin: webs slow it down, and web
  walls keep it out of secrets. **No web wall blocks the way to her.**
- After the Matron, her Pearl grants the Silk skin, and the web walls open:
  the **silk nook** in the north-west and the other web secrets in the forest
  and in Chapter 1's map.
- Today spiders drop **silk essences** that give a Silk form when swallowed
  (built 2026-10-09). They are marked for deletion.
- **Open:** the Weaver Hollow, once proposed as the place to earn silk. Keep
  it as a small dungeon (for example, where the key tool or a manuscript is
  found), or drop it.

## Beat 9 — The Matron's Nest [`the-matrons-nest`] (Built)

**Giver:** Mossy.

- **The way in:** no web wall blocks the nest (the web door of 2026-10-02 is
  dropped).
- **Planned: the fight.**
  - **New art** for the Matron.
  - Her **normal attack is Stretch Lash in three directions**, spread wide
    enough to dodge between. A hit deals damage, pulls the slime toward her
    and traps it. The slime has no Silk skin yet, so it always takes the full
    effect.
  - Her **web volley** marks four circles. The webs it leaves slow the slime
    like every web.
  - She rests after each volley, and that is the opening to hit her.
- **Boss rules (Planned):** once the slime enters her chamber it cannot leave
  until she is beaten. Today she heals to full after 60 s with the slime
  outside her arena.
- **Reward:**
  - 100 coins and `chapter-2-complete`.
  - The end card, then the Crystal Caverns exit, still sealed with crystal.
  - Today a Goo Heart appears in the nest. Proposal: it becomes a full heart
    (+20), the boss's own reward on top of the map's four quarters.
- **Proposal, Pearl 2:** her nest was woven around a Pearl. Beaten, she shrinks
  back into an ordinary (big) orb-weaver and scuttles off. The Pearl lies in
  the silk.
  - The Pearl transfers the **Silk skin** permanently into the slime during
    its ceremony. The slime keeps it after returning the Pearl.
  - Mossy: "Two of them now. And the shaking is worse. Whatever is under that
    mountain is waking up."

## Secrets (Planned)

- **Four heart quarters** in Gloop Forest. Their spots are Open, and so is
  whether the Gloop Cavern counts as its own map.
- Today's Goo Hearts in the forest (one is in the silk nook) and in the cavern
  become quarter spots.
- Some secrets sit behind web walls (the Silk skin) or cracked walls (the
  Bomb), which sends the slime back through Chapter 1's map as well.

## Chapter 2 checklist

| Item | Beat | Status |
|---|---|---|
| Stretch Lash | Open (manuscripts) | Built at Beat 1 |
| Reinforced Pickaxe | 1, 4 | Built (hammering Planned) |
| Swallow (from Tom) | 3 | Built 2026-10-09; marked for deletion |
| Chapter key tool (the Goo Bomb, the Lantern, the War Axe or new) | Open | Goo Bomb, Lantern and War Axe in the rework |
| Clod Stomper | 3–4 | Built 2026-10-09 (its essence drop marked for deletion) |
| Forge, smelting with a timer | 5 | Built (timer Planned) |
| Iron Spear, Iron Axe | 5–6 | Built (the shapes in the rework) |
| 20-slot bag | 7 | Planned |
| Webs and web walls | 8 | Planned |
| Pearl 2 and the Silk skin | 9 | Planned |
| Boss heart (Matron) | 9 | Built as a Goo Heart; full heart is a Proposal |
| 4 heart quarters | Secrets | Planned |
