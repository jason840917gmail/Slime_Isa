# Game Guidelines

> **Status: incomplete living draft — resume later.**
>
> This document records agreed direction for the first version. It is not a
> complete production specification; unresolved topics remain open below.
> Task status lives in the [Game Roadmap](./GAME_ROADMAP.md).

## Core Loop

Explore and gather resources. Fight enemies for drops and access to dangerous
areas. Build up home and its crafting buildings. Craft stronger tools and
weapons, then tackle tougher enemies to obtain rarer materials.

Chapter 1 ("The Clearing", in Slimeshire Meadow, map `level-1`) is the
playable version of this loop today: gather loose wood, craft and place a
workbench, craft stone tools, clear the worm camp with a spear, defeat Fatty
One Eye for the green key, and open the Verdant Gate into Gloop Forest. Quests
guide each step and teach the next recipe.

## Home

There is no single authored home instance. Any bed the player sleeps in
becomes the respawn point, doors can be placed anywhere and link to any
interior, and placed furniture (starting with the workbench) persists per map.
Home is not automatically safe: map conditions and nearby enemies determine
whether it is safe to use.

## Crafting And Buildings

Simple survival recipes may be portable. Weapons, advanced tools, building
pieces, and other progression recipes require the correct crafting building.
Today the only station is the placeable **workbench**: the workbench itself is
craftable anywhere, and every wood and stone tool or weapon recipe needs a
placed one.

Each building owns a clear recipe family, and upgrading it unlocks the next
recipe tier in that family. Buildings unlock gradually:

- **Workshop:** weapons, tools, bombs, storage, building parts, and repairs.
- **Forge:** smelts ore into metal bars (later alloys); it never outputs
  weapons. Metal gear goes ore → Forge (bars) → Workshop.
- **Kitchen:** food, healing and buff meals, potions, and antidotes.
- **Builder’s table:** home upgrades, furniture, and defenses.

The separate Alchemy table is retired: potions belong to the Kitchen and bombs
to the Workshop. Future possibilities such as a loom or enchanting station are
examples only and are not committed direction.

## Resource Progression

Tool-gated and enemy-gated progression work together. The player starts
unarmed, gathers loose wood and stone, and crafts basic harvesting tools; tree
and stone nodes need the matching stone tool. Improved tools will harvest iron
and later rarer materials in tougher regions. Enemies provide special
ingredients for high-tier weapons, potions, and upgrades.

## Recipe Discovery

Chapter 1 teaches recipes as quest rewards (`learnedByQuest` recipes stay
visible but locked until learned). Whether later recipes come from building
tiers, exploration, drops, or more quests is still open.

## Open Questions

- Should the home (or its buildings) still be movable and upgradable, now that
  beds and doors replace a single home instance?
- What are the safety, recovery, and storage rules?
- What are the exact material tiers and biome distributions?
- Which enemy drops exist, and at what progression points?
- How many recipes should each family contain, and how are they balanced?
- How are recipes discovered after Chapter 1?
- What is the scope of building and defenses?
- How fast should progression advance?
