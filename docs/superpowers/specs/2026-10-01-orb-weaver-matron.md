# The Orb-Weaver Matron (roadmap 8.7)

Short spec, 2026-10-01. Chapter 2's boss, on the Fatty One Eye model (a boss
camp with an arena leash, a boss bar, a guarded chest and a persisted defeat),
built around the Sticky form as the outline asks.

## Where

The Matron's nest in Gloop Forest's north-east, east of the north-east weaver
thicket: `encounter.gloop-matron-nest`, activation radius 460 px, arena radius
320 px. A silk cocoon Gulp spot stands just inside the arena's west edge, so the
fight is solvable without carried silk. The guarded chest sits at the arena's
north edge.

## How she fights

A bigger, darker orb-weaver (the orb-weaver sheet drawn 2.6 times larger and
tinted purple until she has her own art). 300 HP (about 20 Iron Spear hits); knockback does not move her.
Every attack telegraphs for at least half a second.

| Attack | Telegraph | Effect |
|---|---|---|
| Web spit (every 2.2 s) | 0.7 s wind-up (the orb-weaver's) | one web projectile: 18 damage, sticks the slime for 0.9 s |
| **Web volley** (every 6.5 s, first after 3.5 s) | 0.9 s: she stops and four red circles mark the ground, one under the slime and three around it | 20 damage to a slime inside a circle; each circle becomes a **web patch** for 6 s |
| Contact | none (she keeps her distance) | 30 damage if the slime walks into her |

**Web patches** catch a normal slime that walks onto them (stuck 0.9 s and set
back outside, like the 7.2 web barrier) but the Sticky form walks through and
tears them. After a volley she rests for 1.3 s (no spit), the opening to hit
her. Patches pile up during the fight, so the arena slowly fills with webs:
the Sticky form is the way to keep moving.

## Win, lose, leave

- **Defeat:** the boss camp marks `orb-weaver-matron` defeated (the
  `boss:orb-weaver-matron` fact, `boss.defeated` for quests), unguards the
  chest (3 iron bars, 2 Slime Tonics) and respawns her after 5 minutes like
  Fatty. Quest 6, **The Matron's Nest** (Mossy, after Iron Gear), completes on
  her defeat: 100 coins, **Squash Slam**, and the story flag
  `chapter-2-complete`, which shows the end card (8.11) and makes a Goo Heart
  appear in the nest (a story variant). Quest rewards and the heart's flag make
  both happen exactly once.
- **Player defeat:** the slime wakes at its last bed; the fight resets (the camp
  removes the live boss), as with Fatty.
- **Leaving the arena:** she returns to the nest centre (the arena leash) and
  heals to full after 60 s with the slime outside it (`arenaRecoveryMs`); leaving the map unmounts her, and she comes back at full
  health.
- **Save and load:** her defeat and the respawn timer are saved by the boss
  camp; a fight in progress is not (it restarts).

## Art and sound

Placeholder until the owner asks for new art: the orb-weaver sheet scaled and
tinted, the web-cover effect as the ground patch, the spider's voice pitched
down. Open: her own sprite sheet, a web-volley sound, arena dressing.
