# Slime Interior Art Library

This folder contains the approved stone-and-oak slime interior direction and the generated source atlases derived from it.

## Folders

- `approved-concept/` — the approved artisan-house room mockup used as the visual master.
- `generated-sheets/` — untouched 1254×1254 transparent source generations.
- `normalized-sheets/` — exact-grid, transparent working atlases ready for deterministic frame slicing. Regenerate with `python scripts/interiors/normalize-interior-sheets.py` (also rewrites `asset/MAPS/interiors/` and `atlas-index.json`).

## Normalized atlases

| Atlas | Grid | Frame | Sprites | Coverage |
| --- | ---: | ---: | ---: | --- |
| `interior-01-structure-128px.png` | 8×8 | 128×128 | 64 | Floors, walls, corners, doors, windows, stairs, hatches |
| `interior-02-seating-directional-128px.png` | 8×8 | 128×128 | 64 | Chairs, stools, benches, cushions in directional sets |
| `interior-03-beds-directional-256px.png` | 6×8 | 256×256 | 43 | Bed and privacy-screen families; source rows preserved (short rows leave empty cells) |
| `interior-04-tables-directional-256px.png` | 5×9 | 256×256 | 37 | Table and desk families; source rows preserved (short rows leave empty cells) |
| `interior-05-storage-states-128px.png` | 8×8 | 128×128 | 64 | Chests, vaults, cabinets, shelves, barrels, crates, sacks |
| `interior-06-kitchen-hearth-128px.png` | 8×8 | 128×128 | 64 | Fireplaces, fire frames, cooking, washing, food, pantry props |
| `interior-07-workshop-crafting-128px.png` | 8×8 | 128×128 | 64 | Smithing, carpentry, textiles, books, herbs, equipment, trades |
| `interior-08-decor-lighting-utility-128px.png` | 8×8 | 128×128 | 64 | Lights, rugs, banners, curtains, plants, cleaning and wash props |
| `interior-09-specialty-rooms-128px.png` | 8×8 | 128×128 | 64 | Tavern, shop, shrine, cellar, nursery, music and railings |

### Mossy mushroom-cottage style

A second style generated with Magnific GPT-2 (see `docs/assets/magnific-mcp-guide.md`) from `mushroom-gpt2.png`, the approved concept blending `roky.png` and `woody.png`. Sources are 2048×2048 transparent grid sheets (`generated-sheets/mushroom-0*-source.png`); the normalizer slices them by grid cell (`GRID_LAYOUTS`) so multi-piece props stay whole.

| Atlas | Grid | Frame | Sprites | Coverage |
| --- | ---: | ---: | ---: | --- |
| `mushroom-01-structure-128px.png` | 8×8 | 128×128 | 64 | Earth/moss/root floors, root-timber walls, corners, beams, round doors, windows, hatches, eaves, fences |
| `mushroom-02-large-furniture-256px.png` | 4×4 | 256×256 | 16 | Mushroom-cap and nest beds, hammock, dining/stump tables, root hearths, shelves, wardrobe, basin, counter |
| `mushroom-03-furniture-props-192px.png` | 8×8 | 192×192 | 64 | Stools, root chairs, leaf armchairs, benches, chests, storage, cauldrons, ovens, food, washing |
| `mushroom-04-decor-lighting-192px.png` | 8×8 | 192×192 | 64 | Glow mushrooms, lanterns, banners, rugs, plants, curios, clutter, curtains, wall hangings |
| `mushroom-05-room-shell-128px.png` | 8×7 | 128×128 | 40 | One 1024×768 room shell (root walls, mushroom-cap eave, doorway) cut into world-aligned cells; row 6 holds the walkable doorway floor |
| `mushroom-06-floor-decor-128px.png` | 8×8 | 128×128 | 64 | Flat floor decals: stepping stones, clover, flowers, moss, pebbles, surface roots, leaf litter, tiny mushrooms |

The room shell is generated whole so its walls line up exactly: place cell `(col, row)` (frame `row * 8 + col`) at `(col * 128 + 64, (row + 1) * 128)`. Back/side cells draw under actors (`backdrop`), front-wall cells sort with actors (`block`); both block their full visible area. Outside the wall ring is filled with opaque void.

Floors: `mushroom-plain-floor` (plain packed earth from `mushroom-07-floor-earth-source.png`, recoloured to the concept and made seamless) is the intended base, decorated with the floor-decor decals. The earth and clover squares are also exported (`mushroom-earth-floor`, `mushroom-clover-floor`). The sample room using this set is `world.mushroom-home` (16×12 tiles).

Total working library: **840 sprites** (including the 40 room-shell cells).

## Conventions

- Directional sets use north, east, south, west order unless a row is explicitly state-based.
- Open/closed and lit/unlit pairs share the same intended ground anchor.
- Large beds and tables use 256-pixel frames so silhouettes and curtains are not clipped.
- Every sprite sits inside its own frame, bottom-centre anchored with a 4 px transparent margin, so no pixel bleeds into a neighbouring frame.
- Each sheet uses one uniform scale (never upscaled), so directional sets and state pairs stay identical in size. Structure floor/wall squares instead fill their 128 px frame edge to edge so they tile.
- All normalized sheets use real alpha transparency and contain no modern objects.
- The untouched generated sheets are retained so individual sprites can be repainted or re-sliced without generation loss.

## Runtime pipeline

- The normalizer also writes the promoted copies to `asset/MAPS/interiors/` (`<frame>x<frame>-tile_<cols>x<rows>-interior-*.png`); they are registered as `sheet.interiors.*` in the `interiors` bundle of `asset/assets.json` (add or update entries there by hand).
- `pnpm interiors:scenes` writes one `object.interior-<category>-<name>` scene per sprite listed in `scripts/interiors/interior_catalog.py` to `src/game/content/scenes/authored/objects/interiors/<category>/`; `pnpm interiors:check` fails when the scenes drift from the catalog. Re-running overwrites catalog-owned scenes.
- Both tools need Python with Pillow (the normalizer also needs numpy).
- Collision, depth, and behavior live in those scenes, never in the manifest.
