"""Re-slice the generated interior sheets into clean, non-overlapping frame grids.

The generated sources in asset/Originals/interiors/generated-sheets/ are not laid
out on an exact grid: sprites drift across cell lines and some sheets hold more
sprites than a square grid. This tool detects every sprite as a connected alpha
component (splitting known touching pairs via CUT_OVERRIDES), keeps the source reading order (source row -> atlas row), and places
each sprite inside its own frame:

- one uniform scale per sheet, so directional sets and open/closed or lit/unlit
  states keep identical sizes and relative proportions;
- bottom-centre anchored (matches the manifest's render origin [0.5, 1]);
- a transparent safety margin, so no pixel ever reaches a neighbouring frame;
- structure floor/wall squares are fitted edge to edge so they tile.

Writes the normalized working atlases, the promoted copies in asset/MAPS/interiors/
and atlas-index.json. Requires Pillow and numpy.

Usage: python scripts/interiors/normalize-interior-sheets.py
"""

from __future__ import annotations

import json
import os
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ORIGINALS = ROOT / "asset" / "Originals" / "interiors"
SOURCES = ORIGINALS / "generated-sheets"
NORMALIZED = ORIGINALS / "normalized-sheets"
PROMOTED = ROOT / "asset" / "MAPS" / "interiors"

ALPHA_THRESHOLD = 32  # opaque enough to belong to a sprite silhouette
MIN_SPRITE_AREA = 150  # smaller islands are generation specks
PADDING = 4  # transparent margin kept inside every prop frame
TILE_SQUARE_TOLERANCE = 0.08  # structure pieces this close to square fill the frame

# Sprites the generator drew touching each other are one alpha component; these
# source-space cut lines separate them as (axis, coordinate, span start, span end):
# axis 0 is a horizontal line at y spanning x in [start, end), axis 1 a vertical
# line at x spanning y in [start, end). Only components inside the span are cut.
CUT_OVERRIDES = {
    # blue round bed rests on the canopy bed's leaf sprout; the leaf belongs below
    "interior-03-beds-directional": [(0, 309, 830, 1045)],
    # the fairy ring's glow touches the cuckoo clock in the row below
    "mushroom-04-decor-lighting": [(0, 1485, 1290, 1560)],
}

# Sheets generated on an exact source grid (cols, rows). Every alpha island is
# assigned to the cell holding its centre, so props drawn as several pieces
# (a table with separate stools, scattered petals) stay one sprite. Tiny specks
# sitting on a cell boundary are generation noise and are dropped.
GRID_LAYOUTS = {
    "mushroom-01-structure": (8, 8),
    "mushroom-02-large-furniture": (4, 4),
    "mushroom-03-furniture-props": (8, 8),
    "mushroom-04-decor-lighting": (8, 8),
    "mushroom-06-floor-decor": (8, 8),
}
GRID_SPECK_AREA = 1000
GRID_SPECK_EDGE = 32

SHEETS = [
    # (atlas id, source stem, output stem, promoted slug, frame, fixed cols or None, mode)
    ("interior.structure", "interior-01-structure", "interior-01-structure-128px", "structure", 128, 8, "tiles"),
    ("interior.seating.directional", "interior-02-seating-directional", "interior-02-seating-directional-128px", "seating-directional", 128, 8, "props"),
    ("interior.beds.directional", "interior-03-beds-directional", "interior-03-beds-directional-256px", "beds-directional", 256, None, "props"),
    ("interior.tables.directional", "interior-04-tables-directional", "interior-04-tables-directional-256px", "tables-directional", 256, None, "props"),
    ("interior.storage.states", "interior-05-storage-states", "interior-05-storage-states-128px", "storage-states", 128, 8, "props"),
    ("interior.kitchen-hearth", "interior-06-kitchen-hearth", "interior-06-kitchen-hearth-128px", "kitchen-hearth", 128, 8, "props"),
    ("interior.workshop-crafting", "interior-07-workshop-crafting", "interior-07-workshop-crafting-128px", "workshop-crafting", 128, 8, "props"),
    ("interior.decor-lighting-utility", "interior-08-decor-lighting-utility", "interior-08-decor-lighting-utility-128px", "decor-lighting-utility", 128, 8, "props"),
    ("interior.specialty-rooms", "interior-09-specialty-rooms", "interior-09-specialty-rooms-128px", "specialty-rooms", 128, 8, "props"),
    # mossy mushroom-cottage style
    ("interior.mushroom.structure", "mushroom-01-structure", "mushroom-01-structure-128px", "mushroom-structure", 128, 8, "tiles"),
    ("interior.mushroom.large-furniture", "mushroom-02-large-furniture", "mushroom-02-large-furniture-256px", "mushroom-large-furniture", 256, 4, "props"),
    ("interior.mushroom.furniture-props", "mushroom-03-furniture-props", "mushroom-03-furniture-props-192px", "mushroom-furniture-props", 192, 8, "props"),
    ("interior.mushroom.decor-lighting", "mushroom-04-decor-lighting", "mushroom-04-decor-lighting-192px", "mushroom-decor-lighting", 192, 8, "props"),
    ("interior.mushroom.floor-decor", "mushroom-06-floor-decor", "mushroom-06-floor-decor-128px", "mushroom-floor-decor", 128, 8, "props"),
]


def label_components(mask: np.ndarray) -> tuple[np.ndarray, list[tuple[int, int, int, int]]]:
    """4-connected labelling; returns the label image and per-label (x0, y0, x1, y1)."""
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    boxes: list[tuple[int, int, int, int]] = []
    for y in range(h):
        for x in np.nonzero(mask[y] & (labels[y] == 0))[0]:
            if labels[y, x]:
                continue
            n = len(boxes) + 1
            labels[y, x] = n
            queue = deque([(y, x)])
            x0 = x1 = x
            y0 = y1 = y
            while queue:
                cy, cx = queue.popleft()
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = n
                        queue.append((ny, nx))
            boxes.append((int(x0), int(y0), int(x1) + 1, int(y1) + 1))
    return labels, boxes


def tight_box(mask: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.nonzero(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def split_touching(own: np.ndarray, cuts) -> list[np.ndarray]:
    """Split a component that swallowed a touching neighbour along an override cut.

    Slivers of one sprite left on the wrong side of the straight cut (outline
    rows, leaf tips) are detached from that side's main body, so they are
    handed back to the other side.
    """
    x0, y0, x1, y1 = tight_box(own)
    for axis, at, start, end in cuts:
        lo, hi = (y0, y1) if axis == 0 else (x0, x1)
        span_lo, span_hi = (x0, x1) if axis == 0 else (y0, y1)
        if not (lo < at < hi and start <= span_lo and span_hi <= end):
            continue
        index = np.arange(own.shape[axis])
        before = index < at
        before = before[:, None] if axis == 0 else before[None, :]
        halves = [own & before, own & ~before]
        for i in (0, 1):
            labels, boxes = label_components(halves[i])
            if len(boxes) < 2:
                continue
            main = int(np.argmax(np.bincount(labels.ravel())[1:])) + 1
            stray = (labels > 0) & (labels != main)
            halves[i] &= ~stray
            halves[1 - i] |= stray
        return [half for half in halves if half.any()]
    return [own]


def detect_sprites(image: Image.Image, cuts=()) -> list[tuple[int, int, int, int, np.ndarray]]:
    alpha = np.array(image)[:, :, 3]
    labels, boxes = label_components(alpha > ALPHA_THRESHOLD)
    areas = np.bincount(labels.ravel(), minlength=len(boxes) + 1)
    sprites = []
    for label in range(1, len(boxes) + 1):
        if areas[label] < MIN_SPRITE_AREA:
            continue
        for own in split_touching(labels == label, cuts):
            sprites.append((*tight_box(own), own))
    return sprites


def group_rows(sprites):
    """Cluster sprites into source rows by vertical overlap, then order left to right."""
    ordered = sorted(sprites, key=lambda s: (s[1] + s[3]) / 2)
    rows: list[list] = []
    for sprite in ordered:
        cy = (sprite[1] + sprite[3]) / 2
        if rows:
            last = rows[-1]
            top = min(s[1] for s in last)
            bottom = max(s[3] for s in last)
            if top <= cy <= bottom:
                last.append(sprite)
                continue
        rows.append([sprite])
    return [sorted(row, key=lambda s: s[0]) for row in rows]


def group_grid(sprites, size: tuple[int, int], layout: tuple[int, int], stem: str):
    """Merge every island into the source grid cell holding its centre, row-major."""
    cols, rows = layout
    cell_w, cell_h = size[0] / cols, size[1] / rows
    cells: dict[tuple[int, int], np.ndarray] = {}
    for x0, y0, x1, y1, own in sprites:
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        edge = min(cx % cell_w, cell_w - cx % cell_w, cy % cell_h, cell_h - cy % cell_h)
        if own.sum() < GRID_SPECK_AREA and edge < GRID_SPECK_EDGE:
            continue
        key = (min(rows - 1, int(cy // cell_h)), min(cols - 1, int(cx // cell_w)))
        cells[key] = cells[key] | own if key in cells else own
    empty = [f"{r},{c}" for r in range(rows) for c in range(cols) if (r, c) not in cells]
    if empty:
        raise SystemExit(f"{stem}: empty grid cells {', '.join(empty)}")
    return [[(*tight_box(cells[r, c]), cells[r, c]) for c in range(cols)] for r in range(rows)]


def extract(rgba: np.ndarray, sprite) -> Image.Image:
    """Crop a sprite, keeping its soft edge but dropping pixels owned by neighbours."""
    x0, y0, x1, y1, own = sprite
    h, w = own.shape
    grow = 2
    ex0, ey0, ex1, ey1 = max(0, x0 - grow), max(0, y0 - grow), min(w, x1 + grow), min(h, y1 + grow)
    crop = rgba[ey0:ey1, ex0:ex1].copy()
    own_crop = own[ey0:ey1, ex0:ex1]
    # soft halo: pixels within `grow` px of this sprite's opaque silhouette
    halo = own_crop.copy()
    for _ in range(grow):
        shifted = halo.copy()
        shifted[1:] |= halo[:-1]
        shifted[:-1] |= halo[1:]
        shifted[:, 1:] |= halo[:, :-1]
        shifted[:, :-1] |= halo[:, 1:]
        halo = shifted
    region_rows = slice(y0 - ey0, y1 - ey0)
    region_cols = slice(x0 - ex0, x1 - ex0)
    keep = np.zeros_like(halo)
    keep[region_rows, region_cols] = halo[region_rows, region_cols]
    crop[:, :, 3] = np.where(keep, crop[:, :, 3], 0)
    crop[crop[:, :, 3] == 0] = 0
    out = Image.fromarray(crop, "RGBA")
    return out.crop(out.getbbox())


def resize(sprite: Image.Image, size: tuple[int, int]) -> Image.Image:
    if sprite.size == size:
        return sprite
    # premultiplied resample avoids dark fringes around transparent edges
    return sprite.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def is_tile_square(sprite: Image.Image, frame: int) -> bool:
    w, h = sprite.size
    return abs(w - h) <= max(w, h) * TILE_SQUARE_TOLERANCE and min(w, h) >= frame * 0.85


def normalize(entry) -> dict:
    atlas_id, source_stem, out_stem, slug, frame, fixed_cols, mode = entry
    image = Image.open(SOURCES / f"{source_stem}-source.png").convert("RGBA")
    rgba = np.array(image)
    sprites = detect_sprites(image, CUT_OVERRIDES.get(source_stem, ()))
    layout = GRID_LAYOUTS.get(source_stem)
    rows = group_grid(sprites, image.size, layout, source_stem) if layout else group_rows(sprites)
    crops = [[extract(rgba, s) for s in row] for row in rows]
    flat = [c for row in crops for c in row]

    cols = fixed_cols or max(len(row) for row in crops)
    if fixed_cols and any(len(row) > cols for row in crops):
        raise SystemExit(f"{source_stem}: a source row has more than {cols} sprites")
    if fixed_cols and len(crops) > cols:
        raise SystemExit(f"{source_stem}: found {len(crops)} rows, expected at most {cols}")
    grid_rows = fixed_cols or len(crops)

    inner = frame - 2 * PADDING
    if mode == "tiles":
        squares = [c for c in flat if is_tile_square(c, frame * 0.9)]
        reference = float(np.median([max(c.size) for c in squares]))
        scale = frame / reference
    else:
        scale = min(1.0, min(inner / max(c.size) for c in flat))

    sheet = Image.new("RGBA", (cols * frame, grid_rows * frame), (0, 0, 0, 0))
    for r, row in enumerate(crops):
        for c, sprite in enumerate(row):
            if mode == "tiles" and is_tile_square(sprite, frame * 0.9):
                size = (frame, frame)
            else:
                s = scale
                if mode == "tiles":
                    s = min(scale, inner / max(sprite.size))
                size = (max(1, round(sprite.width * s)), max(1, round(sprite.height * s)))
            placed = resize(sprite, size)
            bottom_pad = 0 if size == (frame, frame) else PADDING
            x = c * frame + (frame - placed.width) // 2
            y = r * frame + frame - bottom_pad - placed.height
            sheet.alpha_composite(placed, (x, y))

    NORMALIZED.mkdir(parents=True, exist_ok=True)
    PROMOTED.mkdir(parents=True, exist_ok=True)
    save_atomic(sheet, NORMALIZED / f"{out_stem}.png")
    promoted_name = f"{frame}x{frame}-tile_{cols}x{grid_rows}-interior-{slug}.png"
    save_atomic(sheet, PROMOTED / promoted_name)

    print(f"{atlas_id}: {len(flat)} sprites -> {cols}x{grid_rows} @ {frame}px (scale {scale:.3f}) -> {promoted_name}")
    return {
        "id": atlas_id,
        "file": f"normalized-sheets/{out_stem}.png",
        "promoted": f"MAPS/interiors/{promoted_name}",
        "columns": cols,
        "rows": grid_rows,
        "frameWidth": frame,
        "frameHeight": frame,
        "cellCount": len(flat),
        "rowCounts": [len(row) for row in crops],
        "sourceScale": round(scale, 4),
    }


# Terrain floor tiles cut from a structure atlas: (output name, atlas id, frame, trim, seamless).
# The frame's drawn outline is trimmed; organic textures are also cross-faded with
# a half-offset copy of themselves so their edges wrap without a visible grid.
FLOOR_TILES = [
    ("128x128-interior-floor-wood-a.png", "interior.structure", 3, 4, False),
    ("128x128-interior-floor-wood-b.png", "interior.structure", 59, 4, False),
    ("128x128-interior-floor-mushroom-earth-a.png", "interior.mushroom.structure", 0, 10, True),
    ("128x128-interior-floor-mushroom-earth-b.png", "interior.mushroom.structure", 56, 10, True),
    ("128x128-interior-floor-mushroom-clover-a.png", "interior.mushroom.structure", 1, 10, True),
    ("128x128-interior-floor-mushroom-clover-b.png", "interior.mushroom.structure", 57, 10, True),
]


def make_seamless(tile: Image.Image) -> Image.Image:
    """Blend in the tile rolled by half its size, weighted towards the edges."""
    pixels = np.asarray(tile, dtype=np.float32)
    size = pixels.shape[0]
    rolled = np.roll(pixels, (size // 2, size // 2), axis=(0, 1))
    ramp = np.abs(np.linspace(-1.0, 1.0, size))
    edge = np.clip((np.maximum(ramp[:, None], ramp[None, :]) - 0.55) / 0.45, 0.0, 1.0)[:, :, None]
    return Image.fromarray(np.round(pixels * (1 - edge) + rolled * edge).astype(np.uint8), "RGB")


def export_floor_tiles(atlases: list[dict]) -> None:
    by_id = {atlas["id"]: atlas for atlas in atlases}
    for name, atlas_id, index, trim, seamless in FLOOR_TILES:
        atlas = by_id[atlas_id]
        frame, cols = atlas["frameWidth"], atlas["columns"]
        sheet = Image.open(ROOT / "asset" / atlas["promoted"])
        x, y = (index % cols) * frame, (index // cols) * frame
        inner = sheet.crop((x + trim, y + trim, x + frame - trim, y + frame - trim))
        tile = inner.convert("RGB").resize((frame, frame), Image.LANCZOS)
        if seamless:
            tile = make_seamless(tile)
        save_atomic(tile, PROMOTED / name)
        print(f"floor tile: {atlas_id} frame {index} -> {name}")


# Plain floor textures generated whole: (output name, source stem, crop box, target RGB mean,
# contrast gain). The crop is recoloured to match the concept room's earth, then made seamless.
TEXTURE_TILES = [
    ("128x128-interior-floor-mushroom-plain.png", "mushroom-07-floor-earth", (384, 384, 640, 640), (148, 90, 42), 1.8),
]


def export_texture_tiles(frame: int = 128) -> None:
    for name, stem, box, target, gain in TEXTURE_TILES:
        crop = np.asarray(Image.open(SOURCES / f"{stem}-source.png").convert("RGB").crop(box), dtype=np.float32)
        mean = crop.reshape(-1, 3).mean(0)
        recoloured = np.clip(np.asarray(target, np.float32) + (crop - mean) * gain, 0, 255).astype(np.uint8)
        tile = Image.fromarray(recoloured, "RGB").resize((frame, frame), Image.LANCZOS)
        save_atomic(make_seamless(tile), PROMOTED / name)
        print(f"texture tile: {stem} -> {name}")


# A whole room shell (walls only, transparent floor) generated as one image and cut
# into a grid of world-aligned cells. Placing cell (col, row) at
# (col * CELL + CELL / 2, (row + 1) * CELL) rebuilds the room exactly. Pixels inside
# DOORWAY (world px) move to an extra row of walkable floor decals.
SHELL_VOID = (14, 10, 6, 255)
ROOM_SHELLS = [
    # (atlas id, source stem, out stem, promoted slug, world size, cell, doorway box)
    ("interior.mushroom.room-shell", "mushroom-05-room-shell", "mushroom-05-room-shell-128px", "mushroom-room-shell",
     (1024, 768), 128, (434, 672, 592, 768)),
]


def export_room_shell(entry) -> dict:
    atlas_id, stem, out_stem, slug, (width, height), cell, doorway = entry
    shell = resize(Image.open(SOURCES / f"{stem}-source.png").convert("RGBA"), (width, height))
    pixels = np.array(shell)
    door = np.zeros(pixels.shape[:2], bool)
    dx0, dy0, dx1, dy1 = doorway
    door[dy0:dy1, dx0:dx1] = True
    # Everything outside the wall ring is void: paint it opaque so the floor tiles
    # never show past the rounded corners. The doorway box stops the fill from
    # leaking in through the door gap.
    labels, _ = label_components((pixels[:, :, 3] <= ALPHA_THRESHOLD) & ~door)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    outside = np.isin(labels, list(border))
    pixels[outside] = SHELL_VOID
    walls, floor = pixels.copy(), pixels.copy()
    walls[door] = 0
    floor[~door] = 0
    cols, rows = width // cell, height // cell
    sheet = Image.new("RGBA", (cols * cell, (rows + 1) * cell), (0, 0, 0, 0))
    sheet.alpha_composite(Image.fromarray(walls, "RGBA"))
    for c in range(cols):
        part = Image.fromarray(floor[(rows - 1) * cell:rows * cell, c * cell:(c + 1) * cell], "RGBA")
        sheet.alpha_composite(part, (c * cell, rows * cell))
    # drop faint edge haze so empty interior cells stay truly empty
    cleaned = np.array(sheet)
    cleaned[cleaned[:, :, 3] < 8] = 0
    sheet = Image.fromarray(cleaned, "RGBA")
    save_atomic(sheet, NORMALIZED / f"{out_stem}.png")
    promoted_name = f"{cell}x{cell}-tile_{cols}x{rows + 1}-interior-{slug}.png"
    save_atomic(sheet, PROMOTED / promoted_name)
    filled = [i for i in range(cols * (rows + 1))
              if sheet.crop(((i % cols) * cell, (i // cols) * cell, (i % cols + 1) * cell, (i // cols + 1) * cell)).getbbox()]
    print(f"{atlas_id}: {len(filled)} cells -> {cols}x{rows + 1} @ {cell}px -> {promoted_name}; filled {filled}")
    return {
        "id": atlas_id,
        "file": f"normalized-sheets/{out_stem}.png",
        "promoted": f"MAPS/interiors/{promoted_name}",
        "columns": cols,
        "rows": rows + 1,
        "frameWidth": cell,
        "frameHeight": cell,
        "cellCount": len(filled),
        "layout": "room-shell-grid",
        "worldSize": [width, height],
        "doorway": list(doorway),
    }


WRITTEN: set[Path] = set()


def save_atomic(image: Image.Image, path: Path) -> None:
    """Write next to the target, then swap it in, so a running dev server or
    Scene Studio never sees a missing or half-written runtime texture."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    image.save(temporary, format="PNG", optimize=True)
    os.replace(temporary, path)
    WRITTEN.add(path.resolve())


def main() -> None:
    atlases = [normalize(entry) for entry in SHEETS]
    atlases += [export_room_shell(entry) for entry in ROOM_SHELLS]
    export_floor_tiles(atlases)
    export_texture_tiles()
    # Only after every texture is in place: drop runtime PNGs this run no longer produces.
    for stale in PROMOTED.glob("*.png"):
        if stale.resolve() not in WRITTEN:
            stale.unlink()
    index_path = ORIGINALS / "atlas-index.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    index["totalCells"] = sum(a["cellCount"] for a in atlases)
    index["anchor"] = "bottom-center"
    index["padding"] = PADDING
    index["atlases"] = atlases
    index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    print(f"total sprites: {index['totalCells']}")


if __name__ == "__main__":
    main()
