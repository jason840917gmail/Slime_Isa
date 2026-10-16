# Story — Index

> **Status: first draft, started 2026-10-02.** This folder is the story script
> of Slime Isa: what happens, why it happens, and where the slime earns every
> permanent item. It is written to be argued with. Most of the plot is still a
> proposal; the owner's answers in [Open questions](06-open-questions.md)
> turn proposals into decisions.

## Index

1. [Direction](01-direction.md): adventure first with a little crafting, the
   slime's three kinds of power (skins, shapes, abilities), how a region
   plays, and the decisions in effect.
2. [Premise](02-premise.md): the story on one page, covering the
   Wellspring, the newborn slime, the goal and the ending.
3. [World](03-world.md): the regions in order, the world size and screen
   rules (8 × 8 chunks of 32 × 32 tiles, 16 × 14 tiles on screen), what has
   gone wrong in each region, where dungeons go, and the world map sketch.
   The sketch is drawn with `pnpm story:map` and saved as the game's world
   layout, `godot/game/data/world-map.json`; its picture,
   `world-map.png`, stays in this folder.
4. [Characters](04-characters.md): the slime, the people of Slimeshire, the
   bosses and the villain.
5. Chapters, one file each:
   - [Chapter 1 — The Clearing](chapters/chapter-1-the-clearing.md)
   - [Chapter 2 — Gloop Forest](chapters/chapter-2-gloop-forest.md)
   - [Chapter 3 — Crystal Caverns (sketch)](chapters/chapter-3-crystal-caverns.md)
6. [Unlock map](05-unlock-map.md): every permanent item, where and how it
   is earned, and what it opens.
7. [Open questions](06-open-questions.md): the decisions waiting on the owner.

## Status tags

Every beat, item and idea carries one tag:

| Tag | Meaning |
|---|---|
| **Built** | In the game today. Quest text in code is the source for its dialogue. |
| **Rework** | Built in the rework mode: on in the playground, and in any world with `?shapes` ([BODY_SHAPES.md](../godot/BODY_SHAPES.md)). |
| **Planned** | Decided by the owner, not built yet. |
| **Proposal** | A suggestion in this draft. It needs the owner's yes. |
| **Open** | Undecided. It is listed in [Open questions](06-open-questions.md). |
| **Idea** | From the roadmap's parking lot. Kept for reference, not committed. |

## How this folder relates to the other docs

- [Game Guidelines](../GAME_GUIDELINES.md) describe the game as it is designed
  today. The [Game Roadmap](../GAME_ROADMAP.md) owns task order. Anything
  tagged Planned here changes those docs only once the work is scheduled. Until
  then, both still describe the current build.
- The decisions of 2026-10-15 (skins from the Pearls, shapes instead of
  crafted weapons, the Goo Bomb, Swallow and essences marked for deletion, no
  energy regeneration) are not in the guidelines or the roadmap yet. Until
  they are, those docs describe the Gulp-and-essences build.
- Dialogue already in the game lives in
  `godot/game/data/quests-chapter-1.json`, `quests-chapter-2.json` and
  `godot/game/data/npc-definitions.json`. When a chapter file and the game
  disagree about something tagged Built, the game is right; fix the chapter
  file, or plan the change.

## Writing rules

- One chapter is one file. Each beat says where it happens, who is involved,
  what the player does, what they get, and its status tag.
- Every permanent item appears in the [unlock map](05-unlock-map.md).
- Dialogue stays short: one to three lines per page. Quest text never names
  keys, because the HUD shows the controls.
- Keep the tone cozy storybook. There is danger, but no gore, and bosses are
  beaten, not killed (see [Premise](02-premise.md#tone)).
