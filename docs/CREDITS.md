# Credits And Licenses

Everything Slime Isa ships that someone else made, or that a tool generated,
and what the in-game credits screen (`src/game/content/credits/credits.json`,
roadmap 4.7) must say about it. Roadmap task: 10.3.

Status: first draft, 2026-09-30. The origin of each image family was traced
from `asset/assets.json` notes, the sources in `asset/Originals/` (most still
carry C2PA "Content Credentials" metadata naming the generator) and git
history. The older art with no recorded source was made by the owner with AI
image tools (confirmed 2026-09-30); those rows say "owner, with AI".

## What the credits screen must show

| Must show | Why |
|---|---|
| Phaser 3 (MIT), eventemitter3 (MIT, bundled inside Phaser), ajv (MIT) and fast-deep-equal (MIT) | MIT asks for the copyright and permission notice to ship with the game. Only Phaser's `@license` comment survives in `dist/`, so the build also needs a third-party notices file (see [Still to do](#still-to-do)). |
| "Art made by the Slime Isa team with AI image tools (ChatGPT, Magnific and others)" | Honest disclosure of AI-generated art: part was made in the ChatGPT app, part with Magnific, and the older art by the owner with AI tools. |
| "Sound effects generated with Magnific (ElevenLabs), made for Slime Isa" | 35 generated takes ship across 22 cues (the 20 replaced sounds, the Workshop restoration, the bell). This line was missing. |

Credit that is not required but kept, because the authors ask for it kindly:
the CC0 audio packs (Kenney, rubberduck, artisticdude) and the CC0 music
(Juhani Junkala).

Not needed on the screen: TypeScript, Vite, esbuild and Playwright are build
and test tools; none of their code ships in the game.

## Code shipped in the build

| Package | Version | License | How it ships |
|---|---|---|---|
| phaser | 3.90.0 | MIT | the `phaser-*.js` vendor chunk |
| eventemitter3 | 5.0.4 | MIT | bundled inside Phaser's ESM build |
| ajv | 8.20.0 | MIT | only `ajv/dist/runtime/equal.js`, used by the generated game-constants validator |
| fast-deep-equal | 3.1.3 | MIT | wrapped by that ajv runtime file |

## Fonts

None ship. The game uses system font stacks only (Trebuchet MS, Segoe UI
Variable, Aptos, Bahnschrift, Palatino Linotype, Georgia, Arial, Courier New
and monospace for the debug overlay); there are no web fonts or font files.

## Audio

Details and re-import steps: [asset/audio/CREDITS.md](../asset/audio/CREDITS.md).
Which flavour each cue ships is in `scripts/audio/picks.json`.

| What | Author | License | Source |
|---|---|---|---|
| RPG Audio, Impact Sounds, Interface Sounds, Music Jingles | Kenney | CC0 1.0 | https://kenney.nl/assets |
| 80 CC0 creature SFX (#1 and #2), 40 CC0 water/splash/slime SFX | rubberduck | CC0 1.0 | https://opengameart.org/users/rubberduck |
| Swishes Sound Pack | artisticdude | CC0 1.0 | https://opengameart.org/content/swishes-sound-pack |
| Home Town (JRPG Pack 2: Towns), the Slimeshire music | Juhani Junkala | CC0 1.0 | https://archive.org/details/JuhaniJunkala-JRPGpack2Town |
| Generated sound effects (22 cues) | Magnific (ElevenLabs sound effects), for Slime Isa | generated | `asset/Originals/audio/magnific/` |
| Synthesized effects and ambience (50 cues) | made for Slime Isa | own | `scripts/audio/cues.mjs`, `pnpm audio:bake` |

## Art

All runtime images are WebP under `asset/` (10.1); their sources stay in
`asset/Originals/`. "OpenAI image model" means the source carries OpenAI's
C2PA metadata ("OpenAI Media Service API … gpt-image"); Magnific calls the same
API for its GPT-2 model. "ChatGPT" means the metadata also names the ChatGPT app.

| Family | Runtime files | Made with | Evidence |
|---|---|---|---|
| Player slime | `characters/slime_normalized` | owner, with AI | in the first commit (2026-04-25), no source or metadata |
| NPCs: Elder Plop, Mossy Scout | `characters/authored/npcs/` | OpenAI image model | C2PA on their first versions |
| NPCs: Lili, Red Slime Boy, Yellow-Blond Slime Girl, Fisherman | `characters/authored/npcs/` | owner, with AI | no source or metadata |
| Worm enemies and hit sprites | `MAPS/enemies/64x64-*-worm-*`, `16x20-1x3-worm-brawler_hits` | owner, with AI | sources in `Originals/enemies/` have no metadata |
| Worm arrows, spider web projectile and web cover | `MAPS/enemies/40x40-*`, `64x64-4x1-spider-web-cover` | ChatGPT | C2PA on `Originals/weapon/arrows.png`, `webs.png` |
| Spider and orb-weaver sheet | `MAPS/enemies/64x64-8x10-forest-orb-weaver-slime` | concept from ChatGPT; sheet unverified | `Originals/concepts/spider-slime-examples/README.md` |
| Fatty One Eye, ground-crack effect, chest, keys, potions | `bosses/`, `effects/boss-ground-crack-4x1`, `objects/chest-wooden-2x1`, `items/keys-5x4`, `items/potions-5x2` | OpenAI image model | C2PA on `Originals/milestone-2/*` |
| Trees (8x6, 3x1, autumn leaf fall) | `MAPS/trees/` | owner, with AI | added with ChatGPT forest images that were later deleted |
| Rocks (3x1, 8x3) | `MAPS/rocks/` | owner, with AI | no source |
| Crystal clusters | `MAPS/rocks/128x128-tile_8x2-crystal-clusters` | OpenAI image model | C2PA on `Originals/props/crystal-clusters-*` |
| Stone walls | `MAPS/walls/` | OpenAI image model | C2PA on `Originals/walls/stone-wall-networks-source.png` |
| Houses (the old 3x1 sheet) | `MAPS/Houses/320-3x1` | owner, with AI | no source |
| Mushroom houses, the Workshop | `MAPS/Houses/320-mushroom-2x1`, `320-workshop-2x1` | Magnific GPT-2 | manifest notes, C2PA |
| Stone-and-oak interiors | `MAPS/interiors/*-interior-{structure,seating,beds,tables,storage,kitchen,workshop,decor,specialty}*` | ChatGPT | C2PA on `Originals/interiors/generated-sheets/interior-0*` |
| Mushroom-cottage interiors | `MAPS/interiors/*-interior-mushroom-*` | Magnific GPT-2 | manifest notes, C2PA |
| Decorations (8x3) | `MAPS/decorations/128x128-tile_8x3` | owner, with AI | no source |
| Ambient decorations (8x5) | `MAPS/decorations/128x128-tile_8x5-decorations-ambient` | built from the 8x3 sheet; fire from a Magnific (Seedance) video | [AMBIENT_ANIMATION.md](./assets/AMBIENT_ANIMATION.md) |
| Gulp props, landmarks, bell post, training dummy, Stretch Lash | `MAPS/props/`, `MAPS/landmarks/`, `MAPS/objects/*lash-bell-post`, `MAPS/objects/*training-dummy`, `MAPS/effects/*stretch-lash` | Magnific GPT-2 (the dummy cut out with Magnific's background removal) | manifest notes, C2PA (the pressure-plate frames have no metadata) |
| Resource piles (4x2) | `MAPS/resources/128x128-tile_4x2-resource-piles` | owner, with AI | no source |
| Starter materials | `MAPS/resources/128x128-tile_2x1-starter-materials` | OpenAI image model | inferred from `Originals/weapon/stone_stools and resourses.png` |
| Items: gems, materials, forage | `MAPS/items/` | OpenAI image model | C2PA on `Originals/items/` |
| Weapons: sword tiles, hit sprites, stone tools, starter spears | `MAPS/weapons/` | OpenAI image model (partly verified) | C2PA on some sources; prompts in `prompts/` |
| Weapons: hammer and spear, wooden axe, pickaxe, resource and stone impacts | `MAPS/weapons/` | owner, with AI | no source |
| UI frames and backplates (8 files) | `UI/` | OpenAI image model | C2PA on `Originals/ui/` |
| UI crafting workbench backplate | `UI/ui-crafting-detail-workbench-backplate` | owner, with AI | no metadata |
| Logo, game-over art, Gulp form badges | `UI/ui-slime-isa-logo`, `ui-game-over-puddle`, `ui-gulp-form-icons-2x1` | Magnific GPT-2 | manifest notes, roadmap |
| Grounds (highland, amberleaf, frozen, desert) | `MAPS/grounds/` legacy sheets | probably OpenAI; direct source unverified | the named biome sources carry C2PA, the packed legacy sheets do not |
| Grounds (forest floor, moss, cavern, crystal, water, cobble) | `MAPS/grounds/` | OpenAI image model; town cobble Magnific GPT-2 | C2PA on `Originals/grounds/generated/`, manifest note |

## Still to do

- [x] The owner confirmed the older art without a recorded source (player
      slime, four NPC sheets, worms, trees, rocks, old houses, decorations,
      resource piles, five weapon sheets, the crafting backplate): made by the
      owner with AI image tools (2026-09-30).
- [ ] Check the terms of use of OpenAI (ChatGPT and API), Magnific and
      ElevenLabs for redistributing generated images and sounds in a free
      web game.
- [ ] Ship the MIT notices of Phaser, eventemitter3, ajv and fast-deep-equal
      in the build (a `THIRD_PARTY_NOTICES.txt` next to `index.html`, linked
      from the credits screen).
- [x] Credits screen: the art line names both ChatGPT and Magnific, the
      generated sound effects have their own line, and the shipped libraries
      are listed (2026-09-30).
