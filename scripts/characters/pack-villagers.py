"""Packs the West town's villagers and animals (docs/godot/VILLAGERS.md "Art").

Each character's generated sheets (`asset/Originals/town/villagers/generated/<id>-<sheet>.png`,
Magnific GPT 2.5 on a transparent background, a grid of frames each) are cut along their emptiest
rows and columns, trimmed, and drawn at one scale into one runtime sheet,
`godot/asset/characters/villagers/<cell>x<cell>-tile_<cols>x<rows>-<id>.webp`: one row per source
sheet in the order of its `SHEETS` entry, its frames left to right, each frame standing on the
cell's bottom (`FOOT` px up) and centred on its mass. The scale puts the first frame at the
character's `height` world units, 2 px a unit (128 px per 64-unit cell); a later sheet (a walk) is
matched to it by the height of its own first frame, which the prompts draw standing at rest.

The layout of every packed sheet goes to `asset/Originals/town/villagers/packed.json` (cell, rows,
frames per row), which `tools/build_villager_scenes.gd` reads to make the scenes.

    python scripts/characters/pack-villagers.py            # every character with sources
    python scripts/characters/pack-villagers.py penny pig  # only these
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = REPO / "asset" / "Originals" / "town" / "villagers" / "generated"
MANIFEST = REPO / "asset" / "Originals" / "town" / "villagers" / "packed.json"
OUTPUT = REPO / "godot" / "asset" / "characters" / "villagers"
PX_PER_UNIT = 2.0
ALPHA_CUT = 24
# Faint haze the generator leaves around the art is cleared below this alpha.
HAZE_ALPHA = 12
# Free px around the widest and tallest frame; the cell is rounded up to a multiple of CELL_STEP.
MARGIN = 6
CELL_STEP = 16
# The frames stand this many px above the cell's bottom edge.
FOOT = 4

# The sheets a character's art is made of, with their grids (columns, rows), in row order.
POSES = ("poses", (2, 2))
WALKS = [("walk-side", (2, 2)), ("walk-down", (2, 2)), ("walk-up", (2, 2))]
# id -> {"height": world units of the first frame, "sheets": [(sheet, (columns, rows)), ...]}
CHARACTERS: dict[str, dict] = {
    # villagers: a pose sheet (idle, blink, talk, laugh); the walkers also walk. A height counts
    # what the first frame holds above the head (Bram's spear, Gramps Reel's rod, a chef's hat).
    "penny": {"height": 70, "sheets": [POSES] + WALKS},
    "dollop": {"height": 70, "sheets": [POSES]},
    "burble": {"height": 76, "sheets": [POSES]},
    "crumb": {"height": 78, "sheets": [POSES]},
    "mayor-wobbleton": {"height": 74, "sheets": [POSES]},
    "bobbin": {"height": 72, "sheets": [POSES]},
    "auntie-suds": {"height": 70, "sheets": [POSES]},
    "dune": {"height": 72, "sheets": [POSES]},
    "granny-thistle": {"height": 64, "sheets": [POSES]},
    "sprig": {"height": 72, "sheets": [POSES]},
    "dot": {"height": 66, "sheets": [POSES]},
    "dab": {"height": 66, "sheets": [POSES]},
    "bram": {"height": 88, "sheets": [POSES]},
    "zing": {"height": 72, "sheets": [POSES]},
    "plum": {"height": 70, "sheets": [POSES]},
    "gramps-reel": {"height": 76, "sheets": [POSES]},
    "young-burr": {"height": 50, "sheets": [POSES]},
    "old-sedge": {"height": 68, "sheets": [POSES] + WALKS},
    "wick": {"height": 76, "sheets": [POSES] + WALKS},
    "tansy": {"height": 70, "sheets": [POSES] + WALKS},
    "fizz": {"height": 48, "sheets": [POSES] + WALKS},
    "tad": {"height": 46, "sheets": [POSES] + WALKS},
    # the three sisters and their parents (owner, 2026-11-01)
    "isa": {"height": 62, "sheets": [POSES] + WALKS},
    "dany": {"height": 54, "sheets": [POSES] + WALKS},
    "gavy": {"height": 44, "sheets": [POSES] + WALKS},
    "dan": {"height": 80, "sheets": [POSES] + WALKS},
    "may": {"height": 76, "sheets": [POSES]},
    # animals: a pose sheet (idle, two rest poses, a blink) and walks; `match` scales a walk whose
    # first frame stands lower than the first pose (a sitting cat or squirrel against its walk)
    "pig": {"height": 46, "sheets": [POSES] + WALKS},
    "biscuit": {"height": 30, "sheets": [POSES] + WALKS},
    "cat": {"height": 30, "sheets": [POSES] + WALKS, "match": {"walk-side": 0.78, "walk-down": 0.95, "walk-up": 0.95}},
    "hen": {"height": 30, "sheets": [POSES] + WALKS},
    "sheep": {"height": 42, "sheets": [POSES] + WALKS},
    "hedgehog": {"height": 20, "sheets": [POSES] + WALKS},
    "squirrel": {"height": 26, "sheets": [POSES] + WALKS, "match": {"walk-side": 0.6, "walk-down": 0.9, "walk-up": 0.9}},
    # one 3 x 2 sheet each (birds: stand, peck, hop, wings up, wings down, front)
    "robin": {"height": 17, "sheets": [("poses", (3, 2))]},
    "dove": {"height": 20, "sheets": [("poses", (3, 2))]},
    "bluebird": {"height": 17, "sheets": [("poses", (3, 2))]},
    "goldfinch": {"height": 16, "sheets": [("poses", (3, 2))]},
    "swallow": {"height": 15, "sheets": [("poses", (3, 2))]},
    "chick": {"height": 12, "sheets": [("poses", (3, 2))]},
    "duck": {"height": 26, "sheets": [("poses", (3, 2))]},
    "duckling": {"height": 12, "sheets": [("poses", (3, 2))]},
    "snail": {"height": 12, "sheets": [("poses", (3, 2))]},
    "butterflies": {"height": 14, "sheets": [("poses", (3, 2))]},
}


def splits(counts: np.ndarray, parts: int) -> list[int]:
    """Where to cut `counts` (opaque pixels per line) into `parts`: the emptiest line near each
    expected boundary (the middle of an empty run when there is one)."""
    length = len(counts)
    cuts = [0]
    for index in range(1, parts):
        centre = index * length / parts
        half = length / parts * 0.4
        lo, hi = int(centre - half), int(centre + half)
        window = counts[lo:hi]
        best = window.min()
        lines = np.nonzero(window == best)[0]
        # the middle of the run of emptiest lines closest to the expected boundary
        runs = np.split(lines, np.nonzero(np.diff(lines) > 1)[0] + 1)
        run = min(runs, key=lambda r: abs(lo + (r[0] + r[-1]) / 2 - centre))
        cuts.append(lo + int((run[0] + run[-1]) // 2))
    cuts.append(length)
    return cuts


def trimmed(image: Image.Image) -> Image.Image:
    alpha = np.asarray(image)[..., 3]
    ys, xs = np.nonzero(alpha > ALPHA_CUT)
    if xs.size == 0:
        raise SystemExit("an empty frame")
    return image.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def cut_frames(path: Path, grid: tuple[int, int]) -> list[Image.Image]:
    """The sheet's frames in reading order, trimmed."""
    pixels = np.asarray(Image.open(path).convert("RGBA")).copy()
    pixels[pixels[..., 3] < HAZE_ALPHA] = 0
    sheet = Image.fromarray(pixels, "RGBA")
    mask = pixels[..., 3] > ALPHA_CUT
    columns, rows = grid
    row_cuts = splits(mask.sum(axis=1), rows)
    frames: list[Image.Image] = []
    for top, bottom in zip(row_cuts, row_cuts[1:]):
        column_cuts = splits(mask[top:bottom].sum(axis=0), columns)
        for left, right in zip(column_cuts, column_cuts[1:]):
            frames.append(trimmed(sheet.crop((left, top, right, bottom))))
    return frames


def mass_x(frame: Image.Image) -> float:
    alpha = np.asarray(frame)[..., 3].astype(np.float64)
    columns = alpha.sum(axis=0)
    return float((columns * np.arange(len(columns))).sum() / max(1.0, columns.sum()))


def pack(character: str) -> dict:
    spec = CHARACTERS[character]
    rows: list[tuple[str, list[Image.Image]]] = []
    for sheet, grid in spec["sheets"]:
        path = SOURCES / f"{character}-{sheet}.png"
        if not path.exists():
            raise SystemExit(f"{character}: missing {path.relative_to(REPO)}")
        rows.append((sheet, cut_frames(path, grid)))
    first = rows[0][1][0]
    scale = spec["height"] * PX_PER_UNIT / first.height
    scaled: list[tuple[str, list[Image.Image]]] = []
    match = spec.get("match", {})
    for index, (sheet, frames) in enumerate(rows):
        factor = scale if index == 0 else scale * first.height * match.get(sheet, 1.0) / frames[0].height
        scaled.append((sheet, [frame.resize((max(1, round(frame.width * factor)),
            max(1, round(frame.height * factor))), Image.LANCZOS) for frame in frames]))
    widest = max(frame.width for _, frames in scaled for frame in frames)
    tallest = max(frame.height for _, frames in scaled for frame in frames)
    cell = -(-(max(widest, tallest + FOOT) + 2 * MARGIN) // CELL_STEP) * CELL_STEP
    columns = max(len(frames) for _, frames in scaled)
    out = Image.new("RGBA", (cell * columns, cell * len(scaled)), (0, 0, 0, 0))
    for row, (sheet, frames) in enumerate(scaled):
        for column, frame in enumerate(frames):
            left = column * cell + cell // 2 - round(mass_x(frame))
            top = row * cell + cell - FOOT - frame.height
            out.alpha_composite(frame, (left, top))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    path = OUTPUT / f"{cell}x{cell}-tile_{columns}x{len(scaled)}-{character}.webp"
    for old in OUTPUT.glob(f"*-tile_*-{character}.webp"):
        if old != path:
            old.unlink()
    save_game_webp(out, path)
    print(f"wrote {path.relative_to(REPO)} (cell {cell}, scale {scale:.4f})")
    return {
        "sheet": "res://" + path.relative_to(REPO / "godot").as_posix(),
        "cell": cell,
        "foot": FOOT,
        "columns": columns,
        "rows": {sheet: {"row": row, "frames": len(frames)} for row, (sheet, frames) in enumerate(scaled)},
        "height": spec["height"],
    }


def main() -> None:
    wanted = sys.argv[1:] or [c for c in CHARACTERS if (SOURCES / f"{c}-{CHARACTERS[c]['sheets'][0][0]}.png").exists()]
    unknown = [c for c in wanted if c not in CHARACTERS]
    if unknown:
        raise SystemExit(f"unknown: {', '.join(unknown)}")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {}
    for character in wanted:
        manifest[character] = pack(character)
    MANIFEST.write_text(json.dumps(dict(sorted(manifest.items())), indent="\t") + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
