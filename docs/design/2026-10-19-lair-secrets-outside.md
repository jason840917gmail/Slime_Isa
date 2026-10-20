# The Lair caves in; its come-back secrets move outside (2026-10-19)

**Status:** Planned, owner, 2026-10-19. Built one piece at a time; each piece is marked here when
it is built.

## Why

Once Fatty One Eye falls, the Lair caves in and cannot be entered again, as a Zelda dungeon is done
for good. Three of its secrets were come-backs for powers won later (the sally port for the Goo
Bomb, the Old Armoury and the Glow-moss Burrow for the Lantern), so inside a closed Lair they could
never be taken. They move into Slimeshire's outdoor chunks, near the Lair, keeping their rooms and
prizes. The map nook, R1's store and the Weigh House's pouch open during the Lair and stay inside.

## The collapse

- When Fatty falls, the tunnels shake; the slime leaves by R14 the Postern and the bolt-hole into D4
  (the way out the Lair already has).
- After that the gate in Fatty's Hollow (D5) lies buried under rubble: no way back in.
- A faint or a quit after the win never wakes the slime inside the Lair: it wakes outside.

## The three secrets

| Secret | Where | Tell and way in | Lock | Prize |
|---|---|---|---|---|
| **Sally port** | C4, below the town's stone wall (west of the banners) | A pen of fences around a patch of cracked ground. No gate: the slime gets in only by dropping off the ledge above (a raised level behind the wall, its rim over the pen; the jump is gone, so the drop is the elevation's one-way hop) | Goo Bomb (Chapter 2) breaks the cracked ground; the slime falls into the sally port room | A campfire recipe (manuscript) |
| **Glow-moss Burrow** | D4, inside a dark-forest maze with a few enemies | A hole in the ground covered by an old dry trunk, glow-moss specks at its lip | The Lantern (Chapter 3) burns the trunk and bares the hole; inside, the shadow path over the void to the islet needs the Lantern's light too | A heart quarter (one of Slimeshire's four) |
| **Old Armoury** | D4's north edge, on new raised ground (elevation) where the doorway hides | A black doorway between two cold sconces, a glint inside | The Lantern lights its four sconces (as before) | A war journal page |

The rooms stay the scenes already built (`rooms/fatty-lair/sally-port.tscn`, `glow-moss-burrow.tscn`,
`old-armoury.tscn`), made standalone: no fatty-lair Dungeon node (no Lair map, no save block, no
respawn at R1), off the Lair's `layout.tscn`, their doors pointing at the outdoor chunks. The Lair's
doorways to them (R5's crack, R6's tunnel, R8's doorway) become plain wall.

## Order of work

1. The sally port in C4. *Built 2026-10-19:* C4 cells 4-6, rows 7-10 fenced (wood), the cracked
   ground at (352, 576); the room is `slimeshire-sally-port` with a ladder back up to
   `sally-port-way-out` (352, 744); R5's crack walled, the room off the Lair's layout.
   *Changed 2026-10-19 (owner):* no Goo Bomb: the pen holds an **open hole** (`object.open-hole`,
   352, 548) the slime falls through by stepping in; the room is a winding 26x16 tunnel (a landing
   chamber with the chest, an S-bend, an exit chamber) whose ladder climbs to a **hatch** on the town's
   east side (`object.hatch-exit` at 1735, 940 in C4's flower garden), which opens as the slime comes
   out and slams shut behind it. The owner painted the pen's fences himself (a cracked fence post
   along the wall's top).
2. The Glow-moss Burrow and D4's dark-forest maze. *Built 2026-10-19:* the maze on D4's forest layer
   (cells 2-13, rows 15-31; in at the top, out south to D5), the clearing (cells 3-6, rows 22-26) with
   `object.dry-trunk-hole` (a generated dry trunk and its burnt ring), the room
   `slimeshire-glow-moss-burrow` with a ladder back up. D4's forest layer was hidden (its trees
   collided but did not draw); it shows again.
3. The Old Armoury on D4's new north elevation. *Built 2026-10-19:* the hill (level 1, cells 23-30,
   rows 1-3) in place of the north-east woods, the doorway (`object.hill-doorway`) in its south face
   behind the trees, through a gap at cells 27-28 from the garden; the room `slimeshire-old-armoury`,
   its east doorway the way back. *Changed the same day (owner):* the hill is level 2 and its way in
   a cracked wall for the Goo Bomb, its crack toned to the rock so it hardly shows.
4. The Lair's three doorways walled; the collapse (buried gate, wake outside after the win). *Built
   2026-10-19* (DUNGEONS.md "The cave-in").
