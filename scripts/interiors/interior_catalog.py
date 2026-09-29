"""Catalog of every sprite in the normalized interior atlases.

One row per scene: which atlas frame it shows, how it is named, how the player
interacts with it physically, and the world scale it is drawn at. The scene
generator (generate-interior-scenes.py) turns every row into
`object.interior-<category>-<name>` under
src/game/content/scenes/authored/objects/interiors/<category>/.

Kinds:
  solid  - StaticBody2D with a footprint collider; sorts with actors
  free   - non-blocking, sorts with actors (small props, open doorways)
  decal  - non-blocking floor art drawn under actors (rugs, floors, hatches)
  wall   - non-blocking art hung on a back wall; place it at the wall's base
           and raise it with an instance `visualOffset`
  block  - StaticBody2D whose collider covers the whole visible sprite (room-shell
           wall slices, so a run of slices blocks without gaps); sorts with actors
  backdrop - like block, but drawn under actors (back and side walls of a room
           shell, so furniture placed against them stays in front)

Directional sets follow the atlas column order south, east, north, west.
Scales are per family so directional sets and state pairs stay identical.
"""

from __future__ import annotations

SHEETS = {
    "structure": "sheet.interiors.structure.8x8",
    "seating": "sheet.interiors.seating-directional.8x8",
    "beds": "sheet.interiors.beds-directional.6x8",
    "tables": "sheet.interiors.tables-directional.5x9",
    "storage": "sheet.interiors.storage-states.8x8",
    "kitchen": "sheet.interiors.kitchen-hearth.8x8",
    "workshop": "sheet.interiors.workshop-crafting.8x8",
    "decor": "sheet.interiors.decor-lighting-utility.8x8",
    "specialty": "sheet.interiors.specialty-rooms.8x8",
    "mushroom-structure": "sheet.interiors.mushroom-structure.8x8",
    "mushroom-large": "sheet.interiors.mushroom-large-furniture.4x4",
    "mushroom-furniture": "sheet.interiors.mushroom-furniture-props.8x8",
    "mushroom-decor": "sheet.interiors.mushroom-decor-lighting.8x8",
    "mushroom-floor": "sheet.interiors.mushroom-floor-decor.8x8",
    "mushroom-shell": "sheet.interiors.mushroom-room-shell.8x7",
}

DIRECTIONS = ("s", "e", "n", "w")

# (category, frame) -> (name, kind, scale)
ROWS: dict[tuple[str, int], tuple[str, str, float]] = {}
# Extra rows derived from an atlas frame: name -> (category, frame, kind, scale, rotation radians)
DERIVED: dict[str, tuple[str, int, str, float, float]] = {}


def add(category: str, frame: int, name: str, kind: str, scale: float) -> None:
    key = (category, frame)
    if key in ROWS:
        raise ValueError(f"duplicate catalog row {key}")
    ROWS[key] = (name, kind, scale)


def family(category: str, start: int, name: str, kind: str, scale: float, suffixes=DIRECTIONS) -> None:
    for offset, suffix in enumerate(suffixes):
        add(category, start + offset, f"{name}-{suffix}", kind, scale)


def singles(category: str, start: int, names: list[str], kind: str, scale: float) -> None:
    for offset, name in enumerate(names):
        add(category, start + offset, name, kind, scale)


# ---------------------------------------------------------------- structure
S = "structure"
singles(S, 0, ["floor-stone-large", "floor-stone-cracked", "floor-stone-mossy", "floor-wood-planks",
               "floor-wood-vertical", "floor-stone-wood-edged", "floor-stone-wood-framed", "floor-stone-small-framed"], "decal", 1.0)
singles(S, 8, ["wall-plaster-post", "wall-stone-post", "wall-plaster-center-post", "wall-stone-center-post",
               "wall-plaster-beams", "wall-stone-beams", "wall-plaster-post-short", "wall-stone-post-short"], "solid", 1.0)
singles(S, 16, ["corner-plaster-inner", "corner-stone-inner", "corner-plaster-outer", "corner-stone-outer",
                "wall-plaster-cross", "wall-stone-cross", "wall-plaster-cross-narrow", "wall-stone-cross-narrow"], "solid", 1.0)
singles(S, 24, ["wall-plaster-end", "wall-stone-end"], "solid", 1.0)
add(S, 26, "post-wood", "solid", 0.8)
add(S, 27, "pillar-stone", "solid", 0.8)
singles(S, 28, ["beam-wood", "beam-stone"], "solid", 1.0)
singles(S, 30, ["wall-plaster-end-right", "wall-stone-end-right"], "solid", 1.0)
singles(S, 32, ["archway-wood", "archway-stone", "door-frame-plaster-left", "door-frame-plaster-right"], "free", 1.0)
add(S, 36, "door-wood-closed", "solid", 1.0)
add(S, 37, "door-wood-open", "free", 1.0)
add(S, 38, "door-stone-closed", "solid", 1.0)
add(S, 39, "door-stone-open", "free", 1.0)
singles(S, 40, ["window-plaster", "window-stone", "window-plaster-angled-left", "window-plaster-angled-right",
                "window-plaster-angled-left-b", "window-stone-angled", "window-shuttered-stone", "window-shuttered-stone-b"], "solid", 1.0)
add(S, 48, "fireplace-niche", "solid", 1.0)
singles(S, 49, ["stairs-wood-down", "stairs-stone-down", "hatch-closed", "hatch-open", "hatch-ladder",
                "cellar-grate", "trapdoor-wood"], "decal", 1.0)
singles(S, 56, ["floor-stone-large-b", "floor-stone-cracked-b", "floor-stone-mossy-b", "floor-wood-planks-b",
                "floor-wood-stone-mix", "floor-stone-wood-edged-b", "floor-stone-wood-framed-b", "floor-stone-plain"], "decal", 1.0)
# A horizontal beam turned upright: the side walls of a room seen from above.
DERIVED["beam-wood-vertical"] = (S, 28, "solid", 1.0, 1.570796)

# ---------------------------------------------------------------- seating
C = "seating"
for start, name in [(0, "chair-plain"), (4, "chair-heart"), (8, "chair-green-cushion"), (12, "chair-blue-cushion"),
                    (16, "stool-log"), (20, "stool-plank"), (24, "armchair-green"), (28, "throne-blue"),
                    (32, "bench-green"), (36, "loveseat-green"), (40, "floor-cushion-straw"), (44, "floor-cushion-blue"),
                    (48, "chair-plank"), (52, "chair-iron-banded"), (56, "chair-slime-back"), (60, "ottoman-green")]:
    family(C, start, name, "solid", 0.75)

# ---------------------------------------------------------------- beds
B = "beds"
# Source rows are preserved (6 columns), so short rows leave empty cells.
BED_FRAMES = {
    0: "straw-nest-s", 1: "straw-nest-e", 2: "straw-nest-n", 3: "straw-nest-w",
    4: "round-green-s", 5: "round-green-e",
    6: "round-green-w", 7: "round-green-n", 8: "round-green-e-b", 9: "round-blue-s", 10: "round-blue-e",
    12: "round-blue-w", 13: "round-blue-n", 14: "round-blue-e-b", 15: "canopy-s", 16: "canopy-e",
    18: "canopy-w", 19: "canopy-n", 20: "canopy-e-b", 21: "four-poster-s", 22: "four-poster-e",
    24: "four-poster-end", 25: "four-poster-w", 26: "four-poster-end-b", 27: "double-round-s", 28: "double-round-e",
    30: "double-round-w", 31: "double-round-n", 32: "double-round-e-b", 33: "cradle-s", 34: "cradle-e",
    36: "cradle-n", 37: "cradle-w", 38: "basket-dome-s", 39: "basket-dome-e", 40: "basket-dome-n", 41: "basket-dome-w",
    42: "screen-green-wide", 43: "screen-green-folded", 44: "screen-wood-wide", 45: "screen-green-angled",
    46: "screen-wood-folded", 47: "screen-green-angled-b",
}
for frame, name in BED_FRAMES.items():
    add(B, frame, name, "solid", 0.75)

# ---------------------------------------------------------------- tables (5 columns, row-preserving)
T = "tables"
singles(T, 0, ["round-emblem", "round-half-e", "round-plain", "round-half-w", "round-plain-b"], "solid", 0.9)
family(T, 5, "dining-blue-runner", "solid", 0.9)
family(T, 10, "banquet-green-runner", "solid", 0.9)
family(T, 15, "work-iron-banded", "solid", 0.9)
family(T, 20, "desk-with-chair", "solid", 0.9)
singles(T, 25, ["low-round-emblem", "low-round-small", "low-oval", "low-round-small-b"], "solid", 0.45)
singles(T, 30, ["nightstand-ring-s", "nightstand-e", "nightstand-n", "nightstand-ring-w"], "solid", 0.6)
singles(T, 35, ["bench-carved-s", "bench-carved-end", "bench-plain-s", "bench-plain-end"], "solid", 0.9)
singles(T, 40, ["trestle-bench-s", "trestle-bench-end", "trestle-bench-n", "trestle-bench-end-b"], "solid", 0.9)

# ---------------------------------------------------------------- storage
K = "storage"
family(K, 0, "chest-wood-closed", "solid", 0.75)
family(K, 4, "chest-wood-open", "solid", 0.75)
family(K, 8, "chest-banded-closed", "solid", 0.75)
family(K, 12, "chest-banded-open", "solid", 0.75)
family(K, 16, "vault-closed", "solid", 0.75)
family(K, 20, "vault-open", "solid", 0.75)
family(K, 24, "wardrobe-closed", "solid", 0.8)
family(K, 28, "wardrobe-open", "solid", 0.8)
family(K, 32, "dresser", "solid", 0.8)
family(K, 36, "dish-cabinet", "solid", 0.8)
singles(K, 40, ["bookshelf-books-s", "bookshelf-books-e", "bookshelf-back-n", "bookshelf-vines-w"], "solid", 0.8)
family(K, 44, "shelf-empty", "solid", 0.8)
singles(K, 48, ["barrel", "barrel-open", "barrel-lidded", "barrel-tap-e", "barrel-tap-w", "keg-stand",
                "keg-small"], "solid", 0.7)
add(K, 55, "washtub-towel", "solid", 0.7)
singles(K, 56, ["crate", "crate-banded", "crate-open", "basket-vegetables", "basket-laundry", "sack-grain",
                "sacks-bundled", "strongbox"], "solid", 0.7)

# ---------------------------------------------------------------- kitchen
H = "kitchen"
family(H, 0, "hearth-unlit", "solid", 1.45)
family(H, 4, "hearth-lit", "solid", 1.45)
singles(H, 8, ["firepit-ash", "firepit-small", "firepit-medium", "firepit-large", "firepit-roaring"], "solid", 0.8)
singles(H, 13, ["clay-oven-closed", "clay-oven-baking"], "solid", 0.9)
add(H, 15, "coal-pile", "free", 0.6)
singles(H, 16, ["cauldron-empty", "cauldron-water", "cauldron-stew", "cauldron-stew-b", "cauldron-stew-c",
                "cauldron-stew-d", "cauldron-stew-e", "cauldron-hanging"], "solid", 0.7)
singles(H, 24, ["prep-table", "butcher-block", "dough-board", "spit-empty", "spit-roast", "utensil-rack",
                "butter-churn", "grain-mill"], "solid", 0.8)
add(H, 32, "dish-shelf", "solid", 0.95)
singles(H, 33, ["plates-stacked", "bowls-stacked", "mugs", "clay-jug", "kettle", "pots-stacked", "utensil-jar"], "free", 0.5)
singles(H, 40, ["tub-empty", "tub-water", "basin-stone", "bucket", "bucket-water", "yoke-buckets",
                "washtub-towel", "towels-folded"], "solid", 0.6)
singles(H, 48, ["basket-bread", "basket-vegetables", "basket-fruit"], "solid", 0.6)
singles(H, 51, ["herb-bundle", "cheese-board", "fish-hanging", "sack-grain", "cloche"], "free", 0.6)
add(H, 56, "pantry-shelf", "solid", 0.8)
singles(H, 57, ["herb-rack", "pan-rack", "pan-rack-angled", "pan-rack-angled-b"], "wall", 0.8)
singles(H, 61, ["spice-box", "mortar", "wine-crate"], "solid", 0.6)

# ---------------------------------------------------------------- workshop
W = "workshop"
singles(W, 0, ["forge-unlit", "forge-lit"], "solid", 1.0)
singles(W, 2, ["anvil", "anvil-angled", "quench-tub", "bellows", "hammer-rack", "ore-basket"], "solid", 0.75)
singles(W, 8, ["workbench", "workbench-vise", "sawhorse", "sawhorse-angled", "saw-rack", "lumber-stack"], "solid", 0.85)
add(W, 14, "wood-shavings", "decal", 0.6)
add(W, 15, "toolbox", "solid", 0.6)
singles(W, 16, ["spinning-wheel-s", "spinning-wheel-e", "spinning-wheel-w", "spinning-wheel-n", "loom", "loom-side"], "solid", 0.85)
singles(W, 22, ["basket-wool", "basket-yarn"], "solid", 0.6)
singles(W, 24, ["lectern", "lectern-book", "writing-desk"], "solid", 0.85)
singles(W, 27, ["paper-stack", "ink-quill", "books-stacked", "book-open"], "free", 0.5)
add(W, 31, "scroll-rack", "solid", 0.8)
add(W, 32, "herb-drying-rack", "solid", 0.8)
add(W, 33, "mortar", "free", 0.55)
add(W, 34, "potion-jars", "free", 0.55)
singles(W, 35, ["herb-planter", "herb-press", "herb-cutting-board"], "solid", 0.75)
add(W, 38, "poultice-bowl", "free", 0.55)
add(W, 39, "roots-hanging", "wall", 0.7)
singles(W, 40, ["sword-rack", "spear-rack", "shield-display", "tool-rack", "armor-stand", "helmet-stand",
                "bow-rack", "safe"], "solid", 0.85)
singles(W, 48, ["grindstone", "potters-wheel", "pottery-table", "hide-frame", "cobbler-bench",
                "basket-weaving-frame", "chopping-stump", "candle-rack"], "solid", 0.8)
singles(W, 56, ["scales", "coin-tray"], "free", 0.6)
singles(W, 58, ["strongbox", "treasure-chest-open"], "solid", 0.7)
singles(W, 60, ["cloth-bolt-rack", "display-shelf", "wheelbarrow", "trade-goods"], "solid", 0.8)

# ---------------------------------------------------------------- decor
D = "decor"
singles(D, 0, ["candle-unlit", "candle-lit", "candles-triple-unlit", "candles-triple-lit"], "free", 0.45)
singles(D, 4, ["candlestick-unlit", "candlestick-lit", "lantern-unlit", "lantern-lit"], "solid", 0.6)
singles(D, 8, ["sconce-unlit", "sconce-lit", "sconce-double-unlit", "sconce-double-lit",
               "sconce-iron-unlit", "sconce-iron-lit", "sconce-side-unlit", "sconce-side-lit"], "wall", 0.6)
singles(D, 16, ["rug-green-small", "rug-blue-small", "runner-red", "runner-red-vertical",
                "rug-round-blue", "rug-round-green", "rug-green-large", "mat-woven"], "decal", 1.0)
singles(D, 24, ["banner-green", "banner-blue", "banner-red-narrow", "tapestry",
                "curtain-left", "curtain-narrow", "curtain-drape", "curtain-right"], "wall", 0.8)
singles(D, 32, ["plant-potted-small", "plant-potted-large"], "solid", 0.6)
add(D, 34, "planter-hanging", "wall", 0.6)
singles(D, 35, ["planter-flowers", "vase-clay", "flower-pot", "urn-tall", "planter-box"], "solid", 0.6)
singles(D, 40, ["broom", "hand-broom", "dustpan", "mop"], "free", 0.6)
singles(D, 44, ["bucket-metal", "firewood-basket", "fireplace-tools", "coal-bucket"], "solid", 0.6)
add(D, 48, "wash-stand", "solid", 0.8)
add(D, 49, "hand-mirror", "free", 0.5)
singles(D, 50, ["towel-rack", "towel-rack-side"], "solid", 0.7)
add(D, 52, "towels-folded", "free", 0.55)
add(D, 53, "chamber-pot", "solid", 0.55)
add(D, 54, "folding-screen", "solid", 0.8)
add(D, 55, "wash-basin-soap", "solid", 0.6)
singles(D, 56, ["hourglass", "keys", "coin-purse", "dice-cup", "scroll", "books-stacked"], "free", 0.45)
add(D, 62, "picture-framed", "wall", 0.6)
add(D, 63, "sprout-pot", "free", 0.5)

# ---------------------------------------------------------------- specialty
P = "specialty"
singles(P, 0, ["bar-counter", "bar-counter-side", "bar-corner-left", "bar-corner-angled", "bar-corner-right",
               "bar-corner-right-b"], "solid", 0.9)
singles(P, 6, ["saloon-doors-closed", "saloon-doors-open"], "free", 0.9)
add(P, 8, "keg-stand", "solid", 0.75)
singles(P, 9, ["mug-tray", "bread-cheese-platter"], "free", 0.55)
add(P, 11, "tavern-sign", "wall", 0.7)
add(P, 12, "potion-shelf", "wall", 0.7)
singles(P, 13, ["counter-shop", "dice-table"], "solid", 0.85)
add(P, 15, "key-rack", "wall", 0.6)
singles(P, 16, ["counter-shop-green", "counter-shop-side", "merchant-table", "market-stall", "merchant-scale",
                "shelves-empty"], "solid", 0.85)
add(P, 22, "banner-sign", "wall", 0.7)
add(P, 23, "parcels", "solid", 0.6)
singles(P, 24, ["shrine-altar", "altar-table", "shrine-alcove"], "solid", 0.85)
singles(P, 27, ["offering-bowl", "offering-bowl-fruit"], "solid", 0.6)
add(P, 29, "prayer-cushion", "free", 0.6)
add(P, 30, "candle-cluster", "free", 0.55)
add(P, 31, "sigil-stone", "solid", 0.75)
singles(P, 32, ["wine-rack", "bottle-rack", "grape-press", "cheese-shelf", "root-crate"], "solid", 0.8)
add(P, 37, "chain-hanging", "wall", 0.6)
add(P, 38, "ladder", "free", 0.8)
add(P, 39, "grain-chest", "solid", 0.75)
singles(P, 40, ["toy-slime", "rocking-horse", "ball", "toy-blocks"], "free", 0.5)
add(P, 44, "cradle-basket", "solid", 0.65)
singles(P, 45, ["toy-chest-closed", "toy-chest-open"], "solid", 0.65)
add(P, 47, "rug-round-green", "decal", 1.0)
singles(P, 48, ["lute", "harp", "drum", "pan-flute-stand", "chimes", "music-stand", "ribbon-pole"], "solid", 0.7)
add(P, 55, "cushion-blue", "free", 0.6)
singles(P, 56, ["railing", "railing-post", "railing-corner", "rope-barrier"], "solid", 0.8)
singles(P, 60, ["ladder-tall", "step-ladder"], "free", 0.8)
add(P, 62, "folding-screen", "solid", 0.8)
add(P, 63, "bell-hanging", "wall", 0.6)

# ================================================================ mushroom cottage
# Mossy mushroom-cottage style (GPT-2 generated, grid-normalized). The mushroom
# sets are drawn from their own atlases and scaled to match the classic set:
# structure tiles fill 128 px, furniture lands at the same world size.

# ---------------------------------------------------------------- mushroom structure
MS = "mushroom-structure"
singles(MS, 0, ["floor-earth", "floor-clover", "floor-moss", "floor-stepping-stones", "floor-root-planks",
                "floor-mossy-flagstones", "floor-gill-planks", "floor-earth-pebbles"], "decal", 1.0)
singles(MS, 8, ["wall-plain", "wall-root-post", "wall-glow-mushrooms", "wall-round-window", "wall-hanging-roots",
                "wall-shelf-niche", "wall-end-left", "wall-end-right"], "solid", 1.0)
singles(MS, 16, ["corner-inner-left", "corner-inner-right", "corner-outer", "post-root", "pillar-mushroom-stem",
                 "beam-root-long", "beam-root-short", "beam-log-mossy"], "solid", 1.0)
add(MS, 24, "door-round-closed", "solid", 1.0)
add(MS, 25, "door-round-open", "free", 1.0)
add(MS, 26, "archway-root", "free", 1.0)
add(MS, 27, "door-leaf-curtain-closed", "solid", 1.0)
singles(MS, 28, ["door-leaf-curtain-open", "door-frame-left", "door-frame-right"], "free", 1.0)
add(MS, 31, "doorstep-stone", "decal", 1.0)
singles(MS, 32, ["window-round", "window-round-shutters-open", "window-round-shutters-closed", "window-flower-box",
                 "window-oval-vines", "window-crystal-glow"], "wall", 0.8)
singles(MS, 38, ["wall-window-angled-left", "wall-window-angled-right"], "solid", 1.0)
singles(MS, 40, ["trapdoor-closed", "trapdoor-open", "hatch-ladder", "stairs-earth-down"], "decal", 1.0)
add(MS, 44, "burrow-hole", "solid", 1.0)
add(MS, 45, "puddle-glow", "decal", 1.0)
add(MS, 46, "root-hump", "solid", 1.0)
add(MS, 47, "moss-patch", "decal", 1.0)
singles(MS, 48, ["eave-cap", "eave-cap-end-left", "eave-cap-end-right", "roots-hanging", "garland-vine-beam",
                 "moss-overhang"], "wall", 1.0)
singles(MS, 54, ["fence-twig", "fence-post-lantern"], "solid", 1.0)
singles(MS, 56, ["floor-earth-b", "floor-clover-b", "floor-moss-b", "floor-stepping-stones-b", "floor-root-planks-b",
                 "floor-mossy-flagstones-b", "floor-gill-planks-b", "floor-moss-earth-mix"], "decal", 1.0)
# The long root beam turned upright: the side walls of a room seen from above.
DERIVED["beam-root-vertical"] = (MS, 21, "solid", 1.0, 1.570796)

# ---------------------------------------------------------------- mushroom large furniture (256 px frames)
ML = "mushroom-large"
singles(ML, 0, ["bed-mushroom-cap-s", "bed-mushroom-cap-e", "bed-moss-nest", "hammock-leaf"], "solid", 0.78)
singles(ML, 4, ["table-toadstool-dining", "table-root-slab", "table-stump-round", "alchemy-workbench"], "solid", 0.82)
singles(ML, 8, ["hearth-root-lit", "hearth-root-unlit", "bookshelf-hollow-stump", "wardrobe-mushroom"], "solid", 0.82)
singles(ML, 12, ["potion-shelf-tall", "herb-drying-rack", "water-basin-stump", "counter-root"], "solid", 0.82)

# ---------------------------------------------------------------- mushroom furniture & props (192 px frames)
MF = "mushroom-furniture"
singles(MF, 0, ["stool-toadstool-red", "stool-mushroom-brown", "stool-stump", "stool-log"], "solid", 0.5)
add(MF, 4, "cushion-moss", "free", 0.5)
add(MF, 5, "beanbag-leaf", "solid", 0.5)
singles(MF, 6, ["chair-root-s", "chair-root-e"], "solid", 0.55)
singles(MF, 8, ["chair-root-n", "chair-root-w"], "solid", 0.55)
family(MF, 10, "armchair-leaf", "solid", 0.55)
singles(MF, 14, ["bench-log-s", "bench-log-e"], "solid", 0.6)
singles(MF, 16, ["table-stump-small", "table-toadstool-side", "nightstand-mushroom-candle", "table-leaf-low"], "solid", 0.5)
singles(MF, 20, ["chest-vine-closed", "chest-vine-open", "chest-acorn-closed", "chest-acorn-open"], "solid", 0.5)
singles(MF, 24, ["basket-lidded", "basket-mushrooms", "barrel-log", "barrel-log-lidded", "crate-mushrooms",
                 "sack-seeds", "gourds-stacked", "pots-clay-stacked"], "solid", 0.45)
singles(MF, 32, ["shelf-jars-small", "pantry-shelf", "seed-drawers", "tool-rack-root"], "solid", 0.55)
singles(MF, 36, ["broom-twig", "watering-can"], "free", 0.45)
singles(MF, 38, ["bucket-water", "bucket-empty"], "solid", 0.4)
singles(MF, 40, ["cauldron-empty", "cauldron-soup", "cauldron-potion", "oven-clay-unlit", "oven-clay-lit"], "solid", 0.5)
add(MF, 45, "mortar-pestle", "free", 0.4)
singles(MF, 46, ["cutting-stump", "spice-rack"], "solid", 0.5)
singles(MF, 48, ["basket-bread", "basket-berries"], "solid", 0.4)
singles(MF, 50, ["plates-leaf-stacked", "cups-acorn", "teapot", "honey-jar", "cheese-board", "carrots-bundle"], "free", 0.4)
singles(MF, 56, ["wash-basin-stump", "water-trough", "towel-rack-twig"], "solid", 0.5)
singles(MF, 59, ["mop-moss", "soap-leaf"], "free", 0.4)
singles(MF, 61, ["basket-laundry", "butter-churn", "grain-mill"], "solid", 0.5)

# ---------------------------------------------------------------- mushroom decor & lighting (192 px frames)
MD = "mushroom-decor"
add(MD, 0, "glow-mushroom-small", "free", 0.5)
add(MD, 1, "glow-mushroom-tall", "solid", 0.55)
singles(MD, 2, ["glow-mushroom-cluster", "firefly-jar-lit", "firefly-jar-dark", "toadstool-candle-unlit",
                "toadstool-candle-lit"], "free", 0.5)
add(MD, 7, "lantern-acorn-hanging", "wall", 0.55)
singles(MD, 8, ["banner-leaf-green", "banner-leaf-teal", "garland-vine", "herb-bundle-hanging", "planter-glow-hanging",
                "wreath-leaf", "picture-slime", "sconce-glow-mushroom"], "wall", 0.7)
singles(MD, 16, ["rug-round-sprout", "rug-moss-oval", "rug-clover", "runner-leaf", "runner-leaf-vertical",
                 "mat-lily-pad", "doormat-sprout", "rug-mushroom"], "decal", 1.1)
singles(MD, 24, ["plant-fern-pot", "plant-flower-pot"], "solid", 0.6)
add(MD, 26, "plant-succulent", "free", 0.5)
add(MD, 27, "planter-vine-hanging", "wall", 0.6)
add(MD, 28, "toadstool-cluster-small", "free", 0.5)
add(MD, 29, "toadstool-tall-red", "solid", 0.6)
add(MD, 30, "bonsai", "free", 0.5)
add(MD, 31, "fern-basket-large", "solid", 0.6)
add(MD, 32, "potion-bottles", "free", 0.45)
singles(MD, 33, ["crystal-ball-stump", "spellbook-stand"], "solid", 0.55)
singles(MD, 35, ["books-stacked", "scroll-rolled", "quill-ink", "snail-shell", "hourglass"], "free", 0.45)
singles(MD, 40, ["pebble-pile", "acorn-pile"], "free", 0.5)
add(MD, 42, "basket-pinecones", "solid", 0.5)
add(MD, 43, "twig-bundle", "free", 0.5)
add(MD, 44, "firewood-logs", "solid", 0.55)
singles(MD, 45, ["fairy-ring-glow", "petals-scattered"], "decal", 0.8)
add(MD, 47, "rock-mossy", "solid", 0.55)
singles(MD, 48, ["plush-slime", "flute"], "free", 0.45)
add(MD, 50, "wind-chimes-seedpod", "wall", 0.6)
singles(MD, 51, ["bird-nest-eggs", "terrarium-snail"], "free", 0.45)
singles(MD, 53, ["cuckoo-clock", "mirror-root-frame"], "wall", 0.6)
add(MD, 55, "music-box", "free", 0.45)
singles(MD, 56, ["curtain-leaf-left", "curtain-leaf-right", "root-tassel", "wreath-dried-flowers",
                 "charm-horseshoe-mushroom", "shelf-wall-jars", "pans-copper-hanging", "key-hooks"], "wall", 0.65)


# ---------------------------------------------------------------- mushroom floor decor (flat ground decals)
MG = "mushroom-floor"
singles(MG, 0, [f"stepping-stone-{i}" for i in range(1, 9)], "decal", 0.6)
singles(MG, 8, [f"clover-{i}" for i in range(1, 9)], "decal", 0.6)
singles(MG, 16, ["flowers-daisy", "flowers-forget-me-not", "flowers-buttercup", "flowers-violet", "flowers-mixed",
                 "flowers-white-clover", "flowers-pink", "daisy-single"], "decal", 0.55)
singles(MG, 24, ["moss-1", "grass-tuft-1", "moss-2", "grass-moss-1", "moss-3", "grass-moss-2", "grass-tuft-2",
                 "moss-4"], "decal", 0.6)
singles(MG, 32, ["pebbles-1", "rock-mossy-small", "rock-half-buried", "pebbles-2", "pebbles-mossy", "rock-small",
                 "pebbles-3", "rock-mossy"], "decal", 0.55)
singles(MG, 40, [f"root-{i}" for i in range(1, 9)], "decal", 0.7)
singles(MG, 48, ["leaves-fallen", "leaf-big", "acorns-leaves", "petals", "twigs", "pinecone", "fern-frond", "seeds"],
        "decal", 0.5)
singles(MG, 56, ["mushrooms-brown", "mushrooms-red", "mushrooms-cream", "mushrooms-glow", "toadstool-tiny",
                 "mushrooms-ring", "chanterelles", "mushrooms-mixed"], "decal", 0.5)

# ---------------------------------------------------------------- mushroom room shell (world-aligned cells)
# One 1024x768 room shell cut into 128 px cells; frame = row * 8 + col. Place cell
# (col, row) at (col * 128 + 64, (row + 1) * 128) to rebuild the room. Back and side
# walls draw under actors, the front wall sorts with them, and the doorway floor
# (row 6, under the front-wall cells 3 and 4) is walkable.
SHELL_CELLS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 22, 23, 24, 31,
               32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47]
for frame in SHELL_CELLS:
    row, col = divmod(frame, 8)
    add("mushroom-shell", frame, f"cell-r{row}-c{col}", "backdrop" if row < 4 else "block", 1.0)
singles("mushroom-shell", 51, ["doorway-floor-left", "doorway-floor-right"], "decal", 1.0)


def is_workbench(category: str, name: str) -> bool:
    """Sprites that get a `game.workbench` script (crafting station for 'workbench' recipes)."""
    return category == "workshop" and name in ("workbench", "workbench-vise")


def is_bed(category: str, name: str) -> bool:
    """Sprites that get a `game.bed` script so the player can sleep in them."""
    if category == "mushroom-large":
        return name.startswith(("bed-", "hammock-"))
    return category == "beds" and not name.startswith(("screen-", "cradle-"))


# Old hand-built room scene ids -> catalog names, used once to migrate the
# Slime Home instances. Rugs that were drawn at other sizes keep that size via
# an instance scale override (decals have no collider to disagree with).
LEGACY_RENAMES = {
    "back-wall": ("structure", "wall-plaster-post", None),
    "back-wall-end": ("structure", "wall-plaster-end", None),
    "side-beam": ("structure", "beam-wood-vertical", None),
    "front-beam": ("structure", "beam-wood", None),
    "door-post": ("structure", "post-wood", None),
    "hearth": ("kitchen", "hearth-lit-s", None),
    "dish-cabinet": ("kitchen", "dish-shelf", None),
    "barrel": ("storage", "barrel", None),
    "apple-basket": ("kitchen", "basket-fruit", None),
    "firewood": ("decor", "firewood-basket", None),
    "pan-rack": ("kitchen", "herb-rack", None),
    "leaf-banner": ("decor", "banner-green", None),
    "nest-bed": ("beds", "straw-nest-s", None),
    "round-rug": ("decor", "rug-round-green", None),
    "green-rug": ("decor", "rug-green-large", 1.5),
    "hearth-rug": ("decor", "rug-green-small", 1.1),
    "doormat": ("decor", "rug-green-small", 0.8),
    "dining-table": ("tables", "banquet-green-runner-s", None),
    "side-table": ("tables", "low-round-emblem", None),
    "candle": ("decor", "candle-lit", None),
    "banded-chest": ("storage", "chest-banded-closed-s", None),
    "pantry-shelf": ("storage", "dish-cabinet-s", None),
    "wash-stand": ("decor", "wash-stand", None),
    "water-bucket": ("kitchen", "bucket", None),
    "potted-plant": ("decor", "plant-potted-large", None),
}
