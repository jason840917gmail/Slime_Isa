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
| **Webs** | A web blocks the path and traps the slime in place. Only the **Silk Armor** passes a web, and passing costs energy when there is no more energy and the armor avility activate it should remove the armor at that moment. The Matron's special-attack webs work the same way, as do some webs in spider camps. A **web door** closes the Matron's camp. | A web holds the slime 0.9 s and pushes it back; the Sticky form is a one-minute consumable |
| **Gulp armors** | Gulp forms become armors the slime keeps: Silk, Stone, and more later. They are hard to get, and using them costs energy. | One-minute forms eaten from materials |
| **Sprint** | Not available at the start. An Open Pearl grants it mid-game as a powerful milestone, and it is a fast roll. It combines with armors: rolling in the Stone Armor breaks cracked walls. | Hold Shift from the start, free |
| **Energy** | Every ability costs energy. Some cost it per use (dodge, Squash Slam), others over time (rolling). Energy is not too easy to recover, so cooldowns get shorter. Max energy grows over the game. | Only Lash, Slam and Teleport cost energy; max 100, refills 8 per second |
| **Life and energy display** | Two goo orbs, one on each side of the weapon belt, in slime-styled frames (Diablo-like). The life orb shows its number and a ring of pips for the hearts found. The boss bar moves to the top of the screen. A mockup comes before the build. | Two bars, top left |
| **Hearts** | **Heart quarters:** four quarters make one heart, worth **+20 max HP**. For now each map hides four quarters. Secrets are spread across the whole game. | Five Goo Hearts of +10 each |
| **Boss reset** | A boss heals to full after 60 s with the slime outside its arena (Built). Its bar also hides while the slime is outside and comes back on return (Planned). | Heal Built; bar stays on screen |
| **The Weaver (Matron)** | New art. Her normal attack uses Stretch Lash in three directions. A hit deals damage, pulls the slime toward her and traps it unless the Silk Armor is active. Her Pearl grants Stretch Lash after the fight. | One web spit; placeholder art; Stretch Lash comes from Mossy |

Ideas from the same planning talk that the owner has not answered yet (energy
details, merging dodge and roll on one button, where each armor is earned)
are in [Open questions](./06-open-questions.md).
