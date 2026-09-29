# Audio credits

## Synthesized (`sfx/synth/`)
Generated in-house by `pnpm audio:bake` from `scripts/audio/cues.mjs` (deterministic; no third-party material).

## Library (`sfx/library/`) — shipping default
All packs are released under Creative Commons Zero (CC0 1.0,
http://creativecommons.org/publicdomain/zero/1.0/). Credit is appreciated but not required.

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

## A/B flavour
Library samples play by default. Open the game with `?sfx=synth` to hear the synthesized takes instead;
the few cues without a library take always play the synthesized one.
