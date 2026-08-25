# Station-aware crafting, food, and starter farming

## Status

Open — a crafting popup and a small recipe list already exist. The roadmap also
defines Workbench, Forge, Kitchen, and Alchemy milestones. This task connects
those pieces through one recipe workflow and adds the food lifecycle.

## Goal

Use one crafting interface and one recipe catalog for portable crafting and all
workstations, then progress food from foraging to farming to cooking.

## Recipe and station contract

Each recipe owns stable content data for:

- ingredients and output;
- required context: `portable`, `workbench`, `forge`, `kitchen`, or `alchemy`;
- required station tier;
- discovery/unlock rule;
- optional progression tags used for filtering and objectives.

The existing crafting popup is refactored instead of replaced. Opening it from
the field shows unlocked portable recipes. Interacting with a workstation opens
the same component filtered to that station and tier. Locked recipes explain
whether the missing requirement is discovery, station, tier, or ingredients.

Official station names are **Workbench**, **Forge**, **Kitchen**, and **Alchemy
Table**. “Work table” and “foundry” are treated as earlier names, not additional
station types.

## Food progression

1. **Forage:** collect edible berries or plants and distinguish edible items
   from crafting-only materials.
2. **Farm:** author one persistent plot, one seed, planting, growth, harvesting,
   and reload-safe growth state. Watering and seasons are deferred until the
   first crop loop is proven.
3. **Cook:** use the Kitchen to turn raw ingredients into one healing food and
   one temporary buff food.
4. **Upgrade:** improve the Kitchen once and unlock one stronger recipe.

## Craft transaction requirements

- Validate unlock, station, tier, ingredients, and output capacity before
  consuming anything.
- Consume ingredients and add output atomically; failures cannot lose items.
- Save recipe discoveries, station tiers, crop state, and crafted inventory.
- Keep recipe selection usable with pointer and keyboard input.

## Acceptance criteria

- Portable and station recipes use the same popup and recipe authority.
- The popup only shows recipes valid for its current context, with useful locked
  explanations.
- Failed crafts never consume ingredients.
- One crop can be planted, grown, harvested, saved, and cooked.
- Workbench, Forge, Kitchen, and Alchemy recipes cannot be crafted from the
  wrong station.
- The first food loop works as forage/farm → cook → consume → visible effect.

