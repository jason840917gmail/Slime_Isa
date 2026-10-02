# Story — Index

> **Status: first draft, started 2026-10-02.** This folder is the story script
> of Slime Isa: what happens, why it happens, and where the slime earns every
> permanent item. It is written to be argued with. Most of the plot is still a
> proposal; the owner's answers in [Open questions](./06-open-questions.md)
> turn proposals into decisions.

## Index

1. [Direction](./01-direction.md): adventure first with a little crafting, the
   rules every chapter follows, and the decisions of 2026-10-02.
2. [Premise](./02-premise.md): the story on one page, covering the
   Wellspring, the newborn slime, the goal and the ending.
3. [World](./03-world.md): the regions in order, what has gone wrong in each,
   and where dungeons go.
4. [Characters](./04-characters.md): the slime, the people of Slimeshire, the
   bosses and the villain.
5. Chapters, one file each:
   - [Chapter 1 — The Clearing](./chapters/chapter-1-the-clearing.md)
   - [Chapter 2 — Gloop Forest](./chapters/chapter-2-gloop-forest.md)
   - [Chapter 3 — Crystal Caverns (sketch)](./chapters/chapter-3-crystal-caverns.md)
6. [Unlock map](./05-unlock-map.md): every permanent item, where and how it
   is earned, and what it opens.
7. [Open questions](./06-open-questions.md): the decisions waiting on the owner.

## Status tags

Every beat, item and idea carries one tag:

| Tag | Meaning |
|---|---|
| **Built** | In the game today. Quest text in code is the source for its dialogue. |
| **Planned** | Decided by the owner, not built yet. |
| **Proposal** | A suggestion in this draft. It needs the owner's yes. |
| **Open** | Undecided. It is listed in [Open questions](./06-open-questions.md). |
| **Idea** | From the roadmap's parking lot. Kept for reference, not committed. |

## How this folder relates to the other docs

- [Game Guidelines](../GAME_GUIDELINES.md) describe the game as it is designed
  today. The [Game Roadmap](../GAME_ROADMAP.md) owns task order. Anything
  tagged Planned here changes those docs only once the work is scheduled. Until
  then, both still describe the current build.
- Two Planned decisions already contradict the guidelines:
  - The guidelines' Gulp forms last one minute; the plan replaces them with
    armors the slime keeps.
  - The guidelines let the slime sprint from the start; the plan makes it a
    mid-game ability.
- Dialogue already in the game lives in
  `src/game/content/quests/quests/chapterOne.ts`, `chapterTwo.ts` and
  `src/game/content/npcs/NpcDefinitions.ts`. When a chapter file and the game
  disagree about something tagged Built, the game is right; fix the chapter
  file, or plan the change.

## Writing rules

- One chapter is one file. Each beat says where it happens, who is involved,
  what the player does, what they get, and its status tag.
- Every permanent item appears in the [unlock map](./05-unlock-map.md).
- Dialogue stays short: one to three lines per page. Quest text never names
  keys, because the HUD shows the controls.
- Keep the tone cozy storybook. There is danger, but no gore, and bosses are
  beaten, not killed (see [Premise](./02-premise.md#tone)).
