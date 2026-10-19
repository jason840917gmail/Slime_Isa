# Audio credits

## Synthesized (`sfx/synth/`)
Generated in-house by `pnpm audio:bake` from `scripts/audio/cues.mjs` (deterministic; no third-party material).

## Library (`sfx/library/`)
Each cue ships the flavour picked in `scripts/audio/picks.json`. The third-party packs are released under
Creative Commons Zero (CC0 1.0, http://creativecommons.org/publicdomain/zero/1.0/); credit is appreciated but not
required. The `magnific` pack was generated for this project.

| Pack folder (for `--library`) | Pack | Author | Source |
|---|---|---|---|
| `rpg-audio` | RPG Audio 1.0 | Kenney | https://kenney.nl/assets/rpg-audio |
| `impact-sounds` | Impact Sounds 1.0 | Kenney | https://kenney.nl/assets/impact-sounds |
| `interface-sounds` | Interface Sounds 1.0 | Kenney | https://kenney.nl/assets/interface-sounds |
| `music-jingles` | Music Jingles | Kenney | https://kenney.nl/assets/music-jingles |
| `rubberduck-creature-1` | 80 CC0 creature SFX | rubberduck | https://opengameart.org/content/80-cc0-creature-sfx |
| `rubberduck-creature-2` | 80 CC0 creature SFX #2 | rubberduck | https://opengameart.org/content/80-cc0-creture-sfx-2 |
| `rubberduck-slime` | 40 CC0 water/splash/slime SFX | rubberduck | https://opengameart.org/content/40-cc0-water-splash-slime-sfx |
| `artisticdude-swishes` | Swishes Sound Pack | artisticdude | https://opengameart.org/content/swishes-sound-pack |
| `magnific` | Generated for Slime Isa with Magnific (ElevenLabs sound effects), trimmed and normalized: the Workshop restoration, the 20 sounds replaced after the owner's picks, and the round-3 steps, water and action sounds (2026-10-06; steps cut from generated walks by `scripts/audio/slice-steps.py`) | the project | `asset/Originals/audio/magnific/` (copy this folder in as `magnific`) |

### The owner's own sounds

Sound Picker round 7 (applied 2026-10-17; [audio spec §12](../../../docs/godot/specs/audio.md#12-round-7-the-gulps-suck-catch-and-throw))
ships four of the owner's own sounds, not generated ones. They are in the `magnific` folder only because
`stage-round.py` keeps every shipped take there.

| Shipped take | Kept as | Original | Source and licence |
|---|---|---|---|
| `sfx/library/player/gulp-suck.wav` (the Gulp's suck) | `magnific/player-gulp-suck-r7-1.wav` | `asset/Originals/audio/sounds/suck1.mp3` | to be recorded by the owner |
| `sfx/library/player/gulp-spit-1.wav` (the throw) | `magnific/player-gulp-spit-r7-1.wav` | `asset/Originals/audio/sounds/throwing.mp3` | to be recorded by the owner |
| `sfx/library/player/gulp-spit-2.wav` (the throw) | `magnific/player-gulp-spit-r7-2.wav` | `asset/Originals/audio/sounds/throwing2.mp3` | to be recorded by the owner |
| `sfx/library/player/gulp-spit-3.wav` (the throw) | `magnific/player-gulp-spit-r7-3.wav` | `asset/Originals/audio/sounds/throwing3.mp3` | to be recorded by the owner |

The round's catch (`sfx/library/player/gulp-catch.wav`, kept as `magnific/player-gulp-catch-r7-1.wav`) was
generated with Magnific, as the rest of that folder.

`scripts/audio/cues.mjs` lists the original file for every library take (the `library` field; `<pack-folder>/<name>`
where a name exists in more than one pack). To re-import, unpack each zip into a folder named as above inside one
parent folder and run:

```bash
pnpm audio:bake --library <unpacked-folder>
```

## Music (`music/`)
Hand-authored manifest entries (`audio.music.*`, bundle `music`); `pnpm audio:bake` never touches them.

| File | Track | Author | License | Source |
|---|---|---|---|---|
| `level-1-home-town.ogg` | Home Town (JRPG Pack 2: Towns) | Juhani Junkala | CC0 1.0 | https://archive.org/details/JuhaniJunkala-JRPGpack2Town |
| `gloop-forest.mp3` | Gloop Forest (120 s loop) | generated for Slime Isa with Magnific (ElevenLabs music v2) | the project | Magnific, 2026-10-01 |
| `gloop-forest-ambience.mp3` | Gloop Forest ambience bed (20 s loop) | generated for Slime Isa with Magnific (ElevenLabs sound effects) | the project | Magnific, 2026-10-01 |
| `dungeon.wav` | Dungeon (72 s loop; Fatty's Lair, the Weaver Hollow, the Crystal Mine) | generated for Slime Isa with Magnific (Google Lyria) | the project | Magnific, 2026-10-18; loop cut from `asset/Originals/audio/music/dungeon/loops/dungeon-loop.wav` |
| `boss-fight.wav` | Boss fight (41 s loop; `audio.global` `Music/BossMusic`) | generated for Slime Isa with Magnific (Google Lyria) | the project | Magnific, 2026-10-18; `dungeon/loops/boss-fight-loop.wav` |
| `cave-a.wav` | Cave C, bass and drops (loop) | generated for Slime Isa with Magnific (Google Lyria) | the project | Magnific, 2026-10-18; `loops/cave-c-bass-and-drops.wav` |
| `cave-b.wav` | Cave D, chiptune bass (loop) | generated for Slime Isa with Magnific (Google Lyria) | the project | Magnific, 2026-10-18; `loops/cave-d-chiptune-bass.wav` |
| `interior-a.wav` | Interior C, solo piano (loop) | generated for Slime Isa with Magnific (Google Lyria) | the project | Magnific, 2026-10-18; `loops/interior-c-solo-piano.wav` |
| `interior-b.wav` | Interior D, chiptune two voices (loop) | generated for Slime Isa with Magnific (Google Lyria) | the project | Magnific, 2026-10-18; `loops/interior-d-chiptune-two-voices.wav` |

## One flavour per cue
Each cue ships only the flavour picked in `scripts/audio/picks.json` (library sample or synthesized take); there is
no runtime switch between them.
