# Chapter 1 — The Clearing

| | |
|---|---|
| **Region** | Slimeshire Meadow (`level-1`, `slime-home`, `mushroom-home`) |
| **Goal** | Grow from a newborn puddle into a slime that can leave home, and open the Verdant Gate |
| **Boss** | Fatty One Eye |
| **Earned** | First bag, stone tools, Dodge, home and vault, spears, the green key; Planned: Pearl 1 with Jump, and a boss heart |
| **Status** | Built. The beats below mark each Planned change and Proposal. |

Quest IDs are in brackets. Their dialogue lives in
`godot/game/data/quests-chapter-1.json`. Lines quoted here that already
exist are marked *(in game)*; every other line is a draft.

---

## Beat 0 — Born from the Wellspring (Proposal)

**Where:** the Wellspring in the clearing (Open: or the plaza).

- The pool bubbles, and one drop rises, wobbles, and opens two eyes. The slime
  has nothing: no bag, no tools, no moves beyond walking.
- Elder Plop hurries over.
  - Plop: "Ah, a new slime in the clearing! Welcome, little one." *(in game)*
  - Plop: "No slime has come out of the Wellspring in years... and here you
    are."
- **The player learns:** movement.
- **Slime Basics** [`slime-basics`] starts here (Built). Planned change: drop
  its "Sprint" step, because sprinting is now a mid-game ability.

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

## Beat 2 — Stone Tools [`stone-tools`] (Built)

**Giver:** Elder Plop.

- **The player does:** crafts the Stone Axe and Stone Pickaxe, switches tools
  on the belt, chops 20 wood and mines 20 stone.
- **Planned change:** tools are made by staying at the bench and hammering. This
  is the first hammering moment, and each tool ends in the item ceremony.
- **Reward:** **Dodge** (ceremony), the Wooden Spear recipe, 20 coins, 10 wood.
  - Plop: "A slime that stands still gets squashed. When something swings at
    you, tuck in and roll away!" *(in game)*

## Beat 3 — A Home of Your Own (new, Planned)

**Giver:** Elder Plop (Proposal). **Where:** the slime's house, the red forge
house whose door leads to the Slime Home (Proposal; the mushroom house is the
alternative, Open).

- **Why here:** after Stone Tools, the 10-slot bag is full of tools, wood and
  stone, and the first fight comes next. This is the moment to learn to rest,
  and to get somewhere to store things.
- **The story:**
  - Plop: "A slime needs somewhere to rest its goo. The house by the forge yard
    has stood empty since the smith left. It is yours now."
  - Proposal: the door stays shut until now, and Plop's house key is a small
    ceremony.
- **The player does:**
  1. Explores the house.
  2. Sleeps in the bed. This teaches resting to recover, and that the slime
     wakes here after a defeat.
  3. Finds the **vault**: 50 slots, shared with every vault, and it holds
     weapons too. Full ceremony.
- **Proposal, why vaults are shared:** vaults are sealed with Wellspring goo,
  so everything put in one can be taken out of any other.
  - Plop: "Whatever you put in a vault, every vault remembers."
- **Open:** after this first one, can the slime craft more vaults, for
  example one at the forest camp?

## Side quests (Built)

- **A Tonic for Lili** [`a-tonic-for-lili`]: brew a Slime Tonic from three
  purple berries. Reward: 2 purple berries.
- **Snack for the Road** [`snack-for-the-road`], from Lily the Fishergirl: make a
  Berry Basket. Reward: 25 coins and a Slime Tonic.

## Beat 4 — Worm Trouble [`worm-trouble`] (Built)

**Giver:** Mossy.

- **The player does:** crafts a Wooden Spear (Planned: hammered), then clears
  the worm camp south-east of the clearing (3 worm swordsmen).
- **Reward:** the Stone Spear recipe and 30 coins.
- **Planned change:** remove Jump from this reward and replace Mossy's current
  jump lesson. Jump comes from Fatty One Eye's Pearl instead.
- **Proposal, a story hint:** the worms are not raiders, they are refugees.
  - Mossy: "Funny thing. They fight like something chased them out of their
    own burrows."

## Beat 5 — The One-Eyed Guardian [`the-one-eyed-guardian`] (Built)

**Giver:** Elder Plop.

- **The player does:** crafts a Stone Spear (Planned: hammered), then beats
  **Fatty One Eye** by aiming for his eye.
- Plop: "Beyond it lies Gloop Forest, and the rest of the world." *(in game)*
- **Proposal, Pearl 1:** Fatty's eye glows because a Pearl is lodged behind it.
  - Beaten, he shrinks and the Pearl pops free. This is the full ceremony and
    the first time the player sees a Pearl.
  - The Pearl transfers **Jump** permanently into the slime. The ability stays
    when the Pearl later returns to the Wellspring.
  - Plop explains what it is when the slime next returns to Slimeshire, which
    the Forge quest in Chapter 2 makes happen.
- **Proposal, boss heart:** Fatty also leaves one full heart (+20 max HP).
- **The player does next:** takes the green key from the chest and opens the
  Verdant Gate.
- **Reward:** 100 coins and the flag `chapter-1-complete`. Mossy moves to the
  forest camp.

## Secrets (Planned)

- **Four heart quarters** are hidden in Slimeshire Meadow. Their spots are
  Open.
- Today two Goo Hearts are placed in `level-1`. They become quarter spots, or
  move to harder ones.
- At least one quarter should need a later item (Silk Armor, the Stone Armor
  roll), so that coming back pays off.

## Chapter 1 checklist

| Item | Beat | Status |
|---|---|---|
| 10-slot bag | 1 | Planned |
| Stone Axe, Stone Pickaxe | 1–2 | Built (hammering Planned) |
| Dodge | 2 | Built |
| Home (bed) and vault | 3 | Planned |
| Wooden Spear, Stone Spear | 2–5 | Built (hammering Planned) |
| Jump | 5 | Built at Beat 4; relocation Planned |
| Green key | 5 | Built |
| Pearl 1 | 5 | Planned |
| Boss heart (Fatty) | 5 | Proposal |
| 4 heart quarters | Secrets | Planned |
