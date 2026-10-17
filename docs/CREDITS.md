# Credits And Licenses

Everything Slime Isa ships that someone else made, or that a tool generated,
and what the in-game credits screen (`godot/game/shell/credits_menu.gd`,
roadmap 4.7) must say about it. Roadmap task: 10.3.

Status: first draft, 2026-09-30; engine and fonts updated for the Godot build on 2026-10-05.
The origin of each image family was traced from the Phaser asset manifest's notes (retired at the
cutover), the sources in `asset/Originals/` (most still
carry C2PA "Content Credentials" metadata naming the generator) and git
history. The older art with no recorded source was made by the owner with AI
image tools (confirmed 2026-09-30); those rows say "owner, with AI".

## What the credits screen must show

| Must show | Why |
|---|---|
| Godot Engine (MIT) and the third-party components it bundles | MIT asks for the copyright and permission notice to ship with the game; Godot's own notice and its third-party licences (`Engine.get_license_info()`, `get_copyright_info()`) belong in a notices screen or file (see [Still to do](#still-to-do)). |
| Source Sans 3 and Noto Sans Symbols 2 (SIL OFL 1.1) | The UI fonts; OFL asks for the licence to ship with the font (`OFL.txt` beside each font in `godot/game/ui/theme/fonts/`). |
| "Art made by the Slime Isa team with AI image tools (ChatGPT, Magnific and others)" | Honest disclosure of AI-generated art: part was made in the ChatGPT app, part with Magnific, and the older art by the owner with AI tools. |
| "Sound effects generated with Magnific (ElevenLabs), made for Slime Isa" | 35 generated takes ship across 22 cues (the 20 replaced sounds, the Workshop restoration, the bell). This line was missing. |

Credit that is not required but kept, because the authors ask for it kindly:
the CC0 audio packs (Kenney, rubberduck, artisticdude) and the CC0 music
(Juhani Junkala).

Not needed on the screen: Python, Pillow, numpy, Node and Playwright are art and test tools;
none of their code ships in the game. The Phaser build (until 2026-10-05) shipped Phaser 3,
eventemitter3, ajv and fast-deep-equal (all MIT); the Godot build ships none of them.

## Code shipped in the build

| Component | Version | License | How it ships |
|---|---|---|---|
| Godot Engine | 4.7.2 | MIT | the web export's engine (`index.wasm`, `index.js`) |
| Godot's bundled third-party libraries (FreeType, HarfBuzz, ...) | with the engine | various permissive (listed by `Engine.get_license_info()`) | inside the engine |

## Fonts

| Font | Author | License | Where |
|---|---|---|---|
| Source Sans 3 (variable) | Adobe | SIL OFL 1.1 (Reserved Font Name "Source": shipped unmodified) | `godot/game/ui/theme/fonts/source-sans-3/` |
| Noto Sans Symbols 2 | The Noto Project Authors | SIL OFL 1.1 (no Reserved Font Name; line metrics fitted by `scripts/godot/fit-symbol-font-metrics.py`) | `godot/game/ui/theme/fonts/noto-sans-symbols-2/` |

The debug FPS readout uses system monospace fonts (never bundled).

## Audio

Details and re-import steps: [godot/asset/audio/CREDITS.md](../godot/asset/audio/CREDITS.md).
Which flavour each cue ships is in `scripts/audio/picks.json`.

| What | Author | License | Source |
|---|---|---|---|
| RPG Audio, Impact Sounds, Interface Sounds, Music Jingles | Kenney | CC0 1.0 | https://kenney.nl/assets |
| 80 CC0 creature SFX (#1 and #2), 40 CC0 water/splash/slime SFX | rubberduck | CC0 1.0 | https://opengameart.org/users/rubberduck |
| Swishes Sound Pack | artisticdude | CC0 1.0 | https://opengameart.org/content/swishes-sound-pack |
| Home Town (JRPG Pack 2: Towns), the Slimeshire music | Juhani Junkala | CC0 1.0 | https://archive.org/details/JuhaniJunkala-JRPGpack2Town |
| Generated sound effects (22 cues) | Magnific (ElevenLabs sound effects), for Slime Isa | generated | `asset/Originals/audio/magnific/` |
| The Gulp's suck and throw (Sound Picker round 7, 2026-10-17) | the owner's own sounds | to be recorded by the owner | `asset/Originals/audio/sounds/` ([details](../godot/asset/audio/CREDITS.md#the-owners-own-sounds)) |
| Gloop Forest music and ambience | Magnific (ElevenLabs music and sound effects), for Slime Isa | generated | `godot/asset/audio/music/gloop-forest*.mp3` |
| Synthesized effects and ambience (42 cues) | made for Slime Isa | own | `scripts/audio/cues.mjs`, `pnpm audio:bake` |

## Art

All runtime images are WebP under `godot/asset/` (10.1); their sources stay in
`asset/Originals/`. "OpenAI image model" means the source carries OpenAI's
C2PA metadata ("OpenAI Media Service API … gpt-image"); Magnific calls the same
API for its GPT-2 model. "ChatGPT" means the metadata also names the ChatGPT app.

| Family | Runtime files | Made with | Evidence |
|---|---|---|---|
| Player slime (the old side-view sheet) and its Gulp form skins | none: `characters/slime_normalized`, `slime-form-{heavy,sticky}` wait in `asset/to-delete/characters/`, no longer shipped (2026-10-17) | the sheet: owner, with AI; the skins: that sheet re-textured with Magnific GPT-2 stone and silk textures | the sheet in the first commit (2026-04-25), no source or metadata; the skins' builder (`build-gulp-form-skins.py`) is in git history |
| NPCs: Elder Plop, Mossy Scout | `characters/authored/npcs/` | OpenAI image model | C2PA on their first versions |
| NPCs: Lili, Red Slime Boy, Yellow-Blond Slime Girl, Fisherman | `characters/authored/npcs/` | owner, with AI | no source or metadata |
| Worm enemies (swordsman, archer, brawler, prologue worm, Popworm), their arrow and the brawler's hit | `MAPS/enemies/256x256-tile_*-worm-*`, `-prologue-worm`, `-popworm`, `64x64-worm-arrow`, `64x64-tile_3x1-worm-brawler-hit` | Magnific GPT 2.5, 2026-10-16 | sources and prompts in `Originals/enemies/bestiary/` (the old 64 px worm sheets, hits and arrows, owner with AI and ChatGPT, wait in `asset/to-delete/`, no longer shipped) |
| Slime Spider and Orb-weaver, their web and web cover | `MAPS/enemies/256x256-tile_13x1-slime-spider`, `-orb-weaver`, `64x64-tile_3x1-spider-web`, `128x128-spider-web-cover` | Magnific GPT 2.5, 2026-10-16 | sources and prompts in `Originals/enemies/bestiary/` (the old spider sheet and web projectile wait in `asset/to-delete/`, no longer shipped) |
| The Matron's web patch (the old web cover) | `MAPS/enemies/64x64-4x1-spider-web-cover` | ChatGPT | C2PA on `Originals/weapon/webs.png` |
| The Orb-Weaver Matron (the old orb-weaver sheet) | `MAPS/enemies/64x64-8x10-forest-orb-weaver-slime` | concept from ChatGPT; sheet unverified | `Originals/concepts/spider-slime-examples/README.md` |
| The Matron's cocoon fight: her cocoon (whole and torn), her four poses, Pearl 2, her thread's spool and its bag icon | `MAPS/enemies/256x416-tile_2x1-matron-cocoon`, `384x384-tile_4x1-matron`, `MAPS/props/256x256-pearl-silk`, `128x128-matron-spool`, `MAPS/items/64x64-matron-thread` | Magnific GPT 2.5, 2026-10-17 (the Lili sheet as style reference; the poses also the cocoon sheet); the thread, the shadow, the eyes' glow and the respin's threads are code | sources and prompts in `Originals/enemies/matron/`, packed by `scripts/art/pack-matron-art.py` |
| Fatty One Eye, ground-crack effect, chest, keys, potions | `bosses/`, `effects/boss-ground-crack-4x1`, `objects/chest-wooden-2x1`, `items/keys-5x4`, `items/potions-5x2` | OpenAI image model | C2PA on `Originals/milestone-2/*` |
| Trees (region sets) | `MAPS/trees/sets/` | Magnific GPT 2.5, 2026-10-12 | renders in `Originals/trees/<set>/generated/` |
| The Weaver Hollow's bomb pieces: blast keg, cracked winch post, blown floor hole | `abilities/goo-bomb/blast-keg-2x1`, `winch-post-2x1`, `floor-hole` | Magnific GPT 2.5, 2026-10-17 (the Lili sheet as style reference); the crack mark is the cracked wall's decal, laid on by the packer | sources and prompts in `Originals/weaver-hollow/bomb-pieces/`, packed by `scripts/art/pack-weaver-bomb-art.py` |
| The Weaver Hollow's webs: floor webs and their palette, web walls (across and side, intact and cut), the silk parcel | `MAPS/webs/floor-webs-6x1`, `palette`, `web-wall-across-2x1`, `web-wall-side-2x1`, `silk-parcel-3x1` | Magnific GPT 2.5, 2026-10-17 (the Lili sheet as style reference); the parcel's glint star and the palette frames painted by the packer | sources and prompts in `Originals/weaver-hollow/webs/`, packed by `scripts/art/pack-web-art.py` |
| The Watch Oak (the Weaver Hollow's forecourt: the oak's foot and its bricked arch) | `MAPS/landmarks/watch-oak` | Magnific GPT 2.5, 2026-10-17 (the Lili sheet as style reference; two takes, 200 credits); its upper trunk faded and its soft halo cut by hand (Pillow) | source and prompt in `Originals/weaver-hollow/watch-oak/` |
| The Crystal Mine: the Crystal Colossus's eight poses, the mine's props (cart, ore lift, ore crate, rotten timbers, crystal lens, crystal veil, root wall, miner's lantern, buffer stop, Pearl 3, mine gate, rock stump, ore heap) and the smith | `MAPS/enemies/384x384-tile_8x1-crystal-colossus`, `MAPS/props/mine/`, `characters/authored/npcs/smith` | Magnific GPT 2.5, 2026-10-17 (the Lili sheet as style reference); the rails, the vein glows and the smashed timbers' frame are code or drawn by the packer | sources and prompts in `Originals/mine/`, packed by `scripts/art/pack-mine-art.py` |
| Fatty's Lair: the old Thorn Guard drop gate in its mound and its leaf, the worm lever, the gatehouse winch, the stone eye latch (open and shut), the stone door, the plank barricade (whole and smashed), the Inner Stair's hatch (shut and open), the Pearl and its altar, Gorge's war banner, a worm bunk, and Burr (three poses) | `MAPS/objects/fattys-lair/`, `characters/authored/npcs/burr` | Magnific GPT 2.5 (`gpt-2-mini`), 2026-10-17 (transparent background, the Lili creation `XmsSFu2Bfo` as style reference; 12 generations, 1,200 credits, one take each; the mud clod's was not used); cut into frames and the gate's leaf and the stone door's slab cut out by the packer | sources in `Originals/fattys-lair/generated/`, packed by `scripts/art/pack-fattys-lair-art.py` |
| The prologue: the Wellspring's pool, the barred gate and its lever, Old Veteran Yoi, Plop's satchel | `MAPS/landmarks/wellspring-pool`, `MAPS/objects/barred-gate/`, `characters/authored/npcs/yoi`, `UI/items/plops-satchel` | Magnific GPT 2.5, 2026-10-16 (the Lili sheet as style reference) | renders in `Originals/prologue/generated/`, packed by `scripts/art/pack-prologue-art.py` |
| Rocks (3x1, 8x3) | `MAPS/rocks/` | owner, with AI | no source |
| Crystal clusters | `MAPS/rocks/128x128-tile_8x2-crystal-clusters` | OpenAI image model | C2PA on `Originals/props/crystal-clusters-*` |
| Stone walls | `MAPS/walls/` | OpenAI image model | C2PA on `Originals/walls/stone-wall-networks-source.png` |
| Houses (the old 3x1 sheet) | `MAPS/Houses/320-3x1` | owner, with AI | no source |
| Mushroom houses, the Workshop, the Forge | `MAPS/Houses/320-mushroom-2x1`, `320-workshop-2x1`, `256-forge-2x1` | Magnific GPT-2 | manifest notes, C2PA |
| Chapter 2 icons, iron ore node, iron weapons | `MAPS/items/chapter-2-5x2`, `MAPS/rocks/128x128-tile_2x1-iron-ore`, `MAPS/weapons/128x128-tile_4x1-iron-tools` | Magnific GPT-2 (cut out of a white background) | manifest notes, sources in `Originals/items/chapter-2/`, `Originals/props/iron-ore/`, `Originals/weapon/iron-tools/` |
| Stone-and-oak interiors | `MAPS/interiors/*-interior-{structure,seating,beds,tables,storage,kitchen,workshop,decor,specialty}*` | ChatGPT | C2PA on `Originals/interiors/generated-sheets/interior-0*` |
| Mushroom-cottage interiors | `MAPS/interiors/*-interior-mushroom-*` | Magnific GPT-2 | manifest notes, C2PA |
| Decorations (8x3) | `MAPS/decorations/128x128-tile_8x3` | owner, with AI | no source |
| Ambient decorations (8x5) | `MAPS/decorations/128x128-tile_8x5-decorations-ambient` | built from the 8x3 sheet; fire from a Magnific (Seedance) video | [AMBIENT_ANIMATION.md](assets/AMBIENT_ANIMATION.md) |
| Gulp props, landmarks, bell post, training dummy, Stretch Lash | `MAPS/props/`, `MAPS/landmarks/`, `MAPS/objects/*lash-bell-post`, `MAPS/objects/*training-dummy`, `MAPS/effects/*stretch-lash` | Magnific GPT-2 (the dummy cut out with Magnific's background removal) | manifest notes, C2PA (the pressure-plate frames have no metadata) |
| Resource piles (4x2) | `MAPS/resources/128x128-tile_4x2-resource-piles` | owner, with AI | no source |
| Starter materials | `MAPS/resources/128x128-tile_2x1-starter-materials` | OpenAI image model | inferred from `Originals/weapon/stone_stools and resourses.png` |
| Items: gems, materials, forage | `MAPS/items/` | OpenAI image model | C2PA on `Originals/items/` |
| Weapons: sword tiles, hit sprites, stone tools, starter spears | `MAPS/weapons/` | OpenAI image model (partly verified) | C2PA on some sources; prompts in `prompts/` |
| Weapons: hammer and spear, wooden axe, pickaxe, resource and stone impacts | `MAPS/weapons/` | owner, with AI | no source |
| UI minimap frame | `UI/ui-organic-minimap-frame` | OpenAI image model | C2PA on `Originals/ui/` (the other seven Phaser-era frames and backplates of this family, and the crafting workbench backplate, owner with AI, wait in `asset/to-delete/UI/`, no longer shipped: 2026-10-17) |
| Logo, game-over art, Gulp form badges | `UI/ui-slime-isa-logo`, `ui-game-over-puddle`, `ui-gulp-form-icons-3x1` | Magnific GPT-2 | manifest notes, roadmap |
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
- [ ] Ship Godot's MIT notice and its third-party licences with the build
      (a notices screen from `Engine.get_license_info()`, or a
      `THIRD_PARTY_NOTICES.txt` next to the web export, linked from the
      credits screen).
- [x] Credits screen: the art line names both ChatGPT and Magnific, the
      generated sound effects have their own line, and the shipped libraries
      are listed (2026-09-30).
