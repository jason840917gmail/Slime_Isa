# asset/to-delete/

The owner's holding folder for runtime art and sound that the game no longer uses, kept "until we
are sure we don't need it" (roadmap 7.11). It sits outside the Godot project, so nothing here is
imported or shipped. Each file keeps its path under `godot/asset/` and its `.import` file, so it can
go straight back. Delete the folder only when the owner says so.

## What is here

| Folder | Files | Why | Moved |
|---|---|---|---|
| `MAPS/enemies/` | the old 64 px worm sheets (swordsman, archer, brawler), the brawler's hits, the worm arrows, the meadow spider slime and its web | replaced by the 256 px bestiary sheets ([BESTIARY.md](../../docs/godot/BESTIARY.md)) | 2026-10-16 |
| `MAPS/enemies/` | `384x384-tile_8x1-crystal-colossus` (the Colossus's eight poses) | replaced by `384x384-tile_9x1-crystal-colossus` (the same eight and his stun, the Pearl mid-dungeon rework, [DUNGEONS.md](../../docs/godot/DUNGEONS.md#the-crystal-colossus-roadmap-124)) | 2026-10-17 |
| `UI/` | eight Phaser-era window backplates and frames: `ui-area-title-banner`, `ui-boss-health-frame`, `ui-crafting-detail-workbench-backplate`, `ui-inventory-backplate`, `ui-map-journal-paper`, `ui-organic-compact-frame`, `ui-quest-journal-backplate`, `ui-quest-offer-scroll-frame` | the Godot UI draws its windows from `slime_theme.tres` and code | 2026-10-17, clean-out wave 1 |
| `characters/` | `slime_normalized` (the old side-view player sheet) and its Gulp form skins `slime-form-heavy`, `slime-form-sticky` | the player draws the slime-v2 pages; the forms are painted by `form_skin.gdshader` | 2026-10-17, clean-out wave 1 |
| `abilities/goo-bomb/` | `cracked-wall-2x1` (a painted cracked wall) | cracked walls are the crack and hole overlays drawn over real walls | 2026-10-17, clean-out wave 1 |
| `audio/sfx/library/` | `boss/fatty-step-1/2`, `enemy/arrow-hit`, `ui/ability-ready`, `ui/cancel`, `ui/confirm`, `world/interact` | no scene plays them; their cues left `scripts/audio/cues.mjs` and `picks.json` | 2026-10-17, clean-out wave 1 |
| `audio/sfx/synth/` | `enemy/telegraph`, `ui/error`, `ui/hotbar-switch`, `weapon/combo-1/2/3`, `weapon/combo-finisher`, `world/area-title` | the same | 2026-10-17, clean-out wave 1 |
| `MAPS/elevation/` | the front-only cliff look's art (40 files, 3.0 MB): each ground's `<ground>-lip.png` and `-foot.png` (nine grounds and `storybook-grass`) and each wall style's `<style>-wall-end-left.png` / `-right.png` (ten styles) | every world draws side walls, whose edges and feet come from the grounds' sheets ([ELEVATION.md](../../docs/godot/ELEVATION.md#side-walls)); their Magnific sources stay in `asset/Originals/elevation/generated/` | 2026-10-17, the front-only cliff removal |
| `MAPS/cliffs/` | `256x256-8x8-clif.png` (8.7 MB), the hand-painted cliff sheet of the experiments removed on 2026-10-12, and the `.import` files of the cliff kits `kit-h2.png` / `kit-h3.png` (the kits themselves moved to `asset/Originals/elevation/cliff-kit/`: art-tool inputs, not runtime art), and `cliff_paint_tiles.png`, an old copy of the `cliffs` layer's paint tiles (the live atlas is `game/world/elevation/cliffs/cliff_paint_tiles.png`) | nothing reads them | 2026-10-17, the front-only cliff removal |

The art's sources stay in `asset/Originals/`. The library sounds come from the packs named in
`godot/asset/audio/CREDITS.md` (the arrow hit from `asset/Originals/audio/magnific/`); the synth
takes' recipes are in git history (`scripts/audio/cues.mjs` before 2026-10-17), as is the form
skins' builder (`scripts/characters/build-gulp-form-skins.py`).
