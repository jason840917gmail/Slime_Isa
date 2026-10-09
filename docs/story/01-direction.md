# Direction

## The game in one line

Slime Isa is a top-down adventure in the spirit of Zelda. The last born slime, just before the final boss Gorge had stollen the Wellspring's scattered Pearls that power new slime creations,
explores a growing world, earns items and abilities that open new places, and
beats the bosses that guard them. Crafting stays, but it is small: it makes
gear and supplies, and it is not a survival game. The owner decided this on
2026-10-02, calling it "the adventure version, with a little bit of crafting".

## The rule behind every chapter

> **Permanent things are earned and celebrated. Consumable things are crafted
> and farmed.**

| Permanent: earned once, kept forever, celebrated | Consumable: crafted or farmed, used up |
|---|---|
| Weapons and tools | Potions and food |
| Abilities | Charcoal, iron bars and other materials |
| Gulp armors | Anything that stacks in the bag |
| Bags and vaults | |
| Heart quarters, hearts, energy upgrades | |
| Keys and story items | |

Weapons and tools are crafted, but each one is made once and kept. Forging a
weapon is the moment the player earns it, so it gets the same celebration as
a weapon found in a chest.

## How it borrows from Zelda

- **A big world.** It has many regions, and each region can span several maps.
  A chapter can also span several maps while remaining within one region. Some
  maps have no boss; each region has one boss, placed on whichever map best
  suits the adventure. For example, Fatty One Eye could move to his own cavern
  map. Release 1 (Chapters 1 and 2) is only the opening of that world.
- **One key item per region.** The region's boss requires that item, and the
  item also reveals secrets in previously visited places, rewarding the player
  for returning.
- **Growth through exploration.** Max health and max energy grow through
  secrets and bosses, never through levels.
- **Movement in order.** Basic moves come early and powerful ones mid-game.
  The fast roll (sprint) is a mid-game milestone.
- **Secrets spread over the whole game.** They are not packed into the first
  maps.

## Decisions of 2026-10-02 (Planned, not built)

| Topic | Decision | The game today |
|---|---|---|
| **Getting an item** | The game pauses, the item rises out of the slime with light rays and a fanfare, and a card shows the name, one line of text and how to use it. Permanent items get the full ceremony the first time. New recipes get a smaller sting, and materials get nothing. New player animations are welcome when they improve the game. | A banner for abilities; floating text for everything else |
| **Bags** | The slime starts with no bag. Elder Plop gives a **10-slot bag** when the player accepts the first quest. A **20-slot bag** waits in a coffer in the Gloop Cavern. A new bag replaces the old one. | 20 slots from the start |
| **Vault** | Found inside a house during a quest that also teaches sleeping to recover. **50 slots.** All vaults share one storage, and weapons can be stored. The vault screen shows the vault on the right and the bag on the left, with drag and drop both ways. | Chests are take-only |
| **Dropping weapons** | Removed from the plan. Weapons go into the vault instead. | Roadmap parking lot item UX.3 |
| **Crafting time** | Forge materials such as charcoal and iron bars cook in the background with a progress bar on the Forge, and the player claims them later. Weapons and tools are made by staying at the bench and hammering: a few timed strikes and a new hammering animation, ending in the item ceremony. Quick recipes stay instant. | Every recipe is instant |
| **Webs** | A web blocks the path and traps the slime in place. Only the **Silk Armor** (since 2026-10-08: the Silk form, which costs no energy) passes a web, and passing costs energy when there is no more energy and the armor avility activate it should remove the armor at that moment. The Matron's special-attack webs work the same way, as do some webs in spider camps. A **web door** closes the Matron's camp. | A web holds the slime 0.9 s and pushes it back; the Sticky form is a one-minute consumable |
| **Gulp armors** | Gulp forms become armors the slime keeps: Silk, Stone, and more later. They are hard to get, and using them costs energy. **Replaced on 2026-10-08** by essences: see below. | One-minute forms eaten from materials |
| **Sprint** | Not available at the start. An Open Pearl grants it mid-game as a powerful milestone, and it is a fast roll. It combines with armors: rolling in the Stone Armor breaks cracked walls. **2026-10-08:** sprint is gone, and the Dodge becomes the Roll (below). | Shift no longer sprints (2026-10-08); the Roll is built (2026-10-09) |
| **Energy** | Every ability costs energy. Some cost it per use (dodge, Squash Slam), others over time (rolling). Energy is not too easy to recover, so cooldowns get shorter. Max energy grows over the game. | Lash, Slam and Teleport cost energy per use, and holding the Roll drains 12 per second (2026-10-09); max 100, refills 8 per second |
| **Life and energy display** | Two goo orbs, one on each side of the weapon belt, in slime-styled frames (Diablo-like). The life orb shows its number and a ring of pips for the hearts found. The boss bar moves to the top of the screen. A mockup comes before the build. **2026-10-08:** the [mockup](../design/2026-10-07-hud-console-mockup.md) is approved: a bottom console; the numbers show only when a value changes; the ring shows each heart quarter. | Two bars, top left |
| **Hearts** | **Heart quarters:** four quarters make one heart, worth **+20 max HP**; a quarter adds nothing on its own, and the slime starts with no hearts (2026-10-08). For now each map hides four quarters. Secrets are spread across the whole game. | Five Goo Hearts of +10 each |
| **Boss reset** | A boss heals to full after 60 s with the slime outside its arena (Built). Its bar also hides while the slime is outside and comes back on return (Planned). | Heal Built; bar stays on screen |
| **The Weaver (Matron)** | New art. Her normal attack uses Stretch Lash in three directions. A hit deals damage, pulls the slime toward her and traps it unless the Silk Armor is active. Her Pearl grants Stretch Lash after the fight. | One web spit; placeholder art; Stretch Lash comes from Mossy |

Since 2026-10-07 the [roadmap](../GAME_ROADMAP.md#the-2026-10-02-decisions) carries every row above as a Release 1 task, with a table that maps each decision to its task numbers.

Ideas from the same planning talk that the owner has not answered yet (energy
details, merging dodge and roll on one button, where each armor is earned)
are in [Open questions](06-open-questions.md).

## Decisions of 2026-10-08

| Topic | Decision | The game today |
|---|---|---|
| **Jump** | Removed from the game. It was stronger than the other abilities (it hopped over walls and gates), it did not fit, its only use was the Heavy landing on cracked ground, and it misbehaved around hills. The code stays, but nothing teaches it and no key or HUD slot runs it. | Built 2026-10-08 |
| **Pearl 1** | Fatty One Eye's Pearl grants **Squash Slam**: his fight is a leap that lands hard, and his Pearl gives the slime that landing. | Built as a quest reward: finishing The One-Eyed Guardian teaches the slam; the Matron no longer does. The Pearl itself is Planned |
| **Cracked ground** | A **Squash Slam in the Heavy form** breaks it. Standing on it in the Heavy form makes it creak, and the hint names the slam once it is learned. | Built 2026-10-08 |
| **Gulp** | Redesigned around **essences**, replacing the armors (full design: [Gulp](../GAME_GUIDELINES.md#signature-mechanic-gulp)). Holding Q sucks in an essence or a light object (pots and 60-odd other things for every kind of place, drawn in the game's own style rather than copied from Zelda; owner, 2026-10-09), never a live enemy; the slime swells up and waddles, and can only throw it (Q) or swallow it. **Swallow** turns an essence into its form: one form at a time, no timer, no energy. A hit pops the form out as a blob that can be taken back. Some enemies drop essences, some maps hold them, and the bag can keep them. A new form gets no ceremony; the challenge is finding essences. Two later upgrades suck heavy rocks, each celebrated. | Built 2026-10-09 as a playground prototype, with its art (roadmap 7.5); the lift upgrades are Planned |
| **Swallow** | Taught by **Tom**, with the full ceremony, at Mossy's forest camp, after the slime frees him from a spider web with its weapon (Chapter 2, before the iron hollow). It is Chapter 2's key item. | Built 2026-10-09 (Tom in the Web); a banner until the ceremony is built |
| **Essences and their enemies** | Stone from the new **Clod Stomper**, a small stomping golem; silk from spiders; swim from an aquatic monster still to design, and placed by hand meanwhile. The frog becomes decoration. | Built 2026-10-09: the Clod Stomper drops stone and spiders drop silk; swim essences are placed by hand |
| **Roll** | The Dodge becomes the **Roll** on key 2: a curled ball that spins in place like screeching tires, then shoots off, and keeps rolling while held. Details later. | Built 2026-10-09 as a Zelda Pegasus-boots dash (owner): it goes straight, never steers, and bonks off walls and bounces back with a screen shake; holding drains energy; it comes whole with its lesson |
| **Keys** | Changed 2026-10-09: Q sucks and throws; 1 swallows; 2 rolls; Stretch Lash, Squash Slam and Teleport on 3, 4 and 5; interact stays on right-click (W in the keys-only scheme). | Built 2026-10-09 |

The [roadmap](../GAME_ROADMAP.md#the-2026-10-08-decisions) lists the tasks
each row changes.
