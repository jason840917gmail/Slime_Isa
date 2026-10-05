# Handoff: Chapter 2 built (roadmap 8.3–8.11), 2026-10-01

Supersedes [the 2026-09-30 iron-path handoff](2026-09-30-chapter-2-iron-path-handoff.md).
Read `AGENTS.md`, then this, then the milestone 8 entries in
`docs/GAME_ROADMAP.md` (each says what was built, what was played headless and
what is open).

## Where things stand

Chapter 2 plays from the Verdant Gate to the end card. Every 8.x task is built
and played headless; they stay `[~]` until the owner accepts them on a fresh
save (the roadmap's rule). Nothing is committed: the tree holds this session's
work and the 2026-09-30 session's (listed in the old handoff). Commit only when
the owner asks. Never push.

All checks and every Node test suite pass, the production build works, and
`pnpm test:scene-browser` (Brave) passes 44/44.

## What was built

- **8.3** weaver fang (`weaver-fang`, 60 % from orb-weavers). Enemy drops now
  count as collected for quests, and drop pop-ups use the icon frame.
- **8.4** iron nodes (`object.resource-iron-node`, tier 2 `iron`) and the
  Reinforced Pickaxe. The quest waypoint finds a node by the item its piles
  give. Dev panel: "Learn all recipes".
- **8.5** the Forge: an outdoor furnace in the forge yard beside the home
  (`object.forge`, `forge.restored`). **The red forge house is the player's
  home** (its door leads to the Slime Home), so it stays as it was. New item
  `iron-bar`; Smelt Charcoal and Smelt Iron Bar.
- **8.6** Iron Spear and Iron Axe with their own art
  (`weapon.player.iron-tools-tiles`, which also gives the Reinforced Pickaxe its
  art).
- **8.7** the Orb-Weaver Matron
  ([spec](../../../../design/2026-10-01-orb-weaver-matron.md)): `MatronScript`,
  `WebPatchScript`, `effect.matron-web-patch`, `encounter.gloop-matron-nest`.
- **8.8** the hut: the camp's blue cottage has a door to `world.gloop-hut` (one
  bed). Recipe in [Adding an interior](../../knowledge/adding-an-interior.md).
- **8.9** the iron hollow (Heavy plate gate), the silk nook (Sticky, Goo
  Heart), the cracked clearing (Heavy, sinkhole to `world.gloop-cavern` with
  the second heart), Sunny's moat at the north edge, a third orb-weaver
  thicket, and a camp workbench and campfire.
- **8.10** `chapterTwo.ts`: six quests. Mossy and Sunny leave Slimeshire once
  Chapter 1 is done (a story variant in level-1). Red Slime Boy is Pip, the
  Yellow-Blond Slime Girl is Sunny.
- **8.11** the Crystal Caverns exit is locked by `crystal-key` (never given in
  Release 1), and `chapter-2-complete` shows the End of Chapter 2 card.
- Gloop Forest music and ambience (Magnific), wired into the world.
- Fixes: a story variant that takes an NPC out of the world no longer breaks
  the quest waypoint or its name tag.

## Open for the owner

- Play Chapter 2 on a fresh save and accept (or redirect) 8.3–8.11.
- The Matron's own art and voice, a web-volley sound, and arena dressing. She
  is the orb-weaver sheet, 2.6× and purple, today. Tuning: standing still in
  her volleys is deadly.
- The iron node's rubble frame is unused (broken nodes vanish, as stone nodes
  do).
- The hut room was scripted from the Slime Home's scene, not furnished in
  Scene Studio.

## Practical notes

- Gloop Forest's Chapter 2 content was added by a scratch script; the world
  scene is the source of truth now (edit it in Scene Studio). Its instances use
  the `gloop-ch2-` prefix and the groups `camp`, `iron-hollow`, `silk-nook`,
  `cracked-clearing`, `sunny-stream` and `matron-nest`. After moving stone walls,
  run `node scripts/maps/autotile-stone-walls.mjs gloop-forest --write` and
  `pnpm audio:wire`.
- New maps go through the converter (`map:<id>` in `scripts/convert-scenes.mjs`),
  then the furnished scene is laid over it. The steps are in the interior note.
- Headless play (Brave + Playwright) gotchas: right-click interacts, E opens the
  bag, Escape opens the pause menu (the world stops), an NPC conversation and
  the end card pause the world too. Raise the page's resource-timing buffer
  before looking up module URLs from `performance`.
- Magnific this session: 3,300 credits (8 images, the music at 2,400, the
  ambience at 100). `gpt-2` with `transparentBackground` still fails; cut art
  out of a white background with `scripts/lib/white_cutout.py`.
