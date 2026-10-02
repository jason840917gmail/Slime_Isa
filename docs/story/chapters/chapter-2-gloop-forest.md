# Chapter 2 — Gloop Forest

| | |
|---|---|
| **Region** | Gloop Forest (`gloop-forest`, `gloop-hut`, `gloop-cavern`), plus Slimeshire for the Forge |
| **Goal** | Make iron gear, earn the Silk Armor, and break the Matron's hold on the forest |
| **Boss** | Orb-Weaver Matron |
| **Earned** | Stretch Lash, Reinforced Pickaxe, Stone Armor, the Forge, iron gear, 20-slot bag, Silk Armor, Squash Slam; Proposal: Pearl 2 and a boss heart |
| **Status** | Built and in progress (roadmap 8.3–8.11). The beats below mark each Planned change and Proposal. |

Quest IDs are in brackets. Their dialogue lives in
`src/game/content/quests/quests/chapterTwo.ts`. The older design is in
[the Chapter 2 outline](../../superpowers/specs/2026-09-30-chapter-2-outline.md)
and [the Matron spec](../../superpowers/specs/2026-10-01-orb-weaver-matron.md).

---

## Beat 1 — Beyond the Verdant Gate [`beyond-the-verdant-gate`] (Built)

**Giver:** Mossy, at the forest camp.

- Mossy: "I set up camp here, behind these old walls. The hut is ours to use:
  sleep in its bed and you will wake here, not back home." *(in game)*
- **The player does:** defeats 5 orb-weavers and picks up 3 weaver fangs.
- **Reward:** **Stretch Lash** (ceremony), the Reinforced Pickaxe recipe, 30
  coins.
- **Proposal, the trail:** Mossy has been following something. "The webs got
  thick about the same time the ground started shaking. Strange, isn't it?"

## Beat 2 — Sunny's Basket [`sunnys-basket`] (Built, optional)

**Giver:** Sunny, at the forest camp.

- **The player does:** pulls her basket back across the north stream with the
  Stretch Lash.
- **Reward:** 2 purple berries and 20 coins.

## Beat 3 — The Stone Armor (Planned; where is Open)

The iron hollow's gate and the cracked clearing both need something heavy.
Today any stone Gulp spot gives the one-minute Heavy form. In the plan, the
Heavy form becomes the **Stone Armor**: kept forever, worn at will, costing
energy, and **hard to get**.

**Where it is earned is Open.** Two proposals:

- **A. A stone shrine in the forest.** This is a short trial early in the
  chapter: a small puzzle-and-fight room around a mossy boulder. Gulping the
  boulder at its end teaches the Stone Armor for good. It keeps the Gulp as
  the way armors are learned.
- **B. Fatty One Eye's reward** at the end of Chapter 1. A boss reward is very
  Zelda, but it puts a lot on one boss: a Pearl, a heart and an armor.

**Either way:** the slime must have the Stone Armor before A Harder Pick sends
it into the iron hollow.

## Beat 4 — A Harder Pick [`a-harder-pick`] (Built)

**Giver:** Mossy.

- **The player does:**
  1. Crafts the Reinforced Pickaxe (Planned: hammered).
  2. Opens the iron hollow by standing in the Stone Armor on its plate.
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

- **The player does:** breaks the cracked ground with the Stone Armor and drops
  into the Gloop Cavern.
- **Planned change: the 20-slot bag.** A coffer in the cavern holds a **20-slot
  bag**, which replaces the 10-slot one. Full ceremony.
- **The cavern today:** a chest with iron ore, charcoal and a tonic, plus a Goo
  Heart and crystal shards.
  - Planned: the Goo Heart becomes one of the region's heart quarters.
  - Proposal: the shards glow faintly, a hint of Chapter 3.

## Beat 8 — The Silk Armor (Planned; where is Open)

The Silk Armor is the region's key item: the boss needs it, and it opens the
web secrets all over the forest. **It must be hard to get.**

**Proposal: the Weaver Hollow, the game's first small dungeon.** It is a
web-choked den inside the largest thicket:

1. **Getting in.** The way in has no webs; it is a fight through weaver waves.
   Its puzzles use what the slime already has: the Stretch Lash, Jump and the
   Stone Armor.
2. **The cocoon.** At its heart hangs a giant silk cocoon. Gulping it teaches
   the **Silk Armor** for good. Full ceremony.
3. **Getting out.** The way back out goes *through* webs, so the new armor is
   used at once.

**A new quest** from Mossy between Iron Gear and The Matron's Nest:

- Mossy: "You cannot walk through her webs, and her nest is wrapped in them.
  But the weavers spin from a great cocoon in the big thicket. If a slime ate
  that..."

**The web rules (Planned)** apply from here on:

- A web blocks the path and traps the slime in place.
- Only the Silk Armor passes a web, and passing costs energy.
- The **silk nook** in the north-west, and its secret, open now.

**Open:** what happens to today's silk cocoon Gulp spots? They could be
removed, or become energy refills for the Silk Armor.

## Beat 9 — The Matron's Nest [`the-matrons-nest`] (Built)

**Giver:** Mossy.

- **Planned: the web door.** A web door closes the nest's only entrance. The
  slime passes it in the Silk Armor, and the passage costs energy.
- **Planned: the fight.**
  - **New art** for the Matron.
  - Her **normal attack** throws **three webs at different angles**, spread
    wide enough to dodge between.
  - Her **web volley** marks four circles. The webs it leaves trap the slime the
    same way all webs do: only the Silk Armor passes them, and passing costs
    energy.
  - She rests after each volley, and that is the opening to hit her.
- **Boss rules:**
  - Built: she heals to full after 60 s with the slime outside her arena.
  - Planned: her bar also hides while the slime is outside and comes back on
    return.
- **Reward:**
  - **Squash Slam** (ceremony), 100 coins and `chapter-2-complete`.
  - The end card, then the Crystal Caverns exit, still sealed with crystal.
  - Today a Goo Heart appears in the nest. Proposal: it becomes a full heart
    (+20), the boss's own reward on top of the map's four quarters.
- **Proposal, Pearl 2:** her nest was woven around a Pearl. Beaten, she shrinks
  back into an ordinary (big) orb-weaver and scuttles off. The Pearl lies in
  the silk.
  - Mossy: "Two of them now. And the shaking is worse. Whatever is under that
    mountain is waking up."

## Secrets (Planned)

- **Four heart quarters** in Gloop Forest. Their spots are Open, and so is
  whether the Gloop Cavern counts as its own map.
- Today's Goo Hearts in the forest (one is in the silk nook) and in the cavern
  become quarter spots.
- Some secrets need the Silk Armor, which sends the slime back through
  Chapter 1's map as well.

## Chapter 2 checklist

| Item | Beat | Status |
|---|---|---|
| Stretch Lash | 1 | Built |
| Reinforced Pickaxe | 1, 4 | Built (hammering Planned) |
| Stone Armor | 3 | Planned (where is Open) |
| Forge, smelting with a timer | 5 | Built (timer Planned) |
| Iron Spear, Iron Axe | 5–6 | Built (hammering Planned) |
| 20-slot bag | 7 | Planned |
| Silk Armor | 8 | Planned (where is Open) |
| Squash Slam | 9 | Built |
| Pearl 2 | 9 | Proposal |
| Boss heart (Matron) | 9 | Built as a Goo Heart; full heart is a Proposal |
| 4 heart quarters | Secrets | Planned |
