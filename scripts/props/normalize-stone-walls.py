"""Register every stone wall piece on one shared layout so runs, corners and
junctions line up into a single continuous wall.

Inside each 70x70 cell the wall band must sit at the same place:
  vertical band (and every corner/junction leg):  x = 9..61
  horizontal band (and every corner arm):         y = 7..63
The script measures each piece's band and shifts it into place; corner legs
that were painted narrower are stretched to the full width. Measuring first
makes it idempotent. Afterwards every wall scene's Visual sprite offset must be the
plain cell (godot/game/scenes/objects/wall-stone-solid*.tscn; set it in the Godot
editor, as this script did for the Phaser scenes before the cutover), and the
T-junctions are rebuilt from the corners (`python scripts/props/build-wall-junctions.py`).

  python scripts/props/normalize-stone-walls.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

WALLS = ROOT / "godot" / "asset" / "MAPS" / "walls"
CELL = 70
V_BAND = (9, 61)
H_BAND = (7, 63)

# sheet file, columns, rows, per-frame kind
SHEETS = {
    "70x70-8x1tiles_horizontals.webp": (8, 1, ["h"] * 8),
    "70x70-8x1tiles_verticals.webp": (1, 8, ["v"] * 8),
    # corners open toward: down-right x2, down-left x2, up-right x2, up-left x2
    "70x70-4x2tiles_corners.webp": (4, 2, ["DR", "DR", "DL", "DL", "UR", "UR", "UL", "UL"]),
}


def span(mask_line):
    idx = np.nonzero(mask_line)[0]
    return (int(idx.min()), int(idx.max())) if len(idx) else None


def measure(alpha, kind):
    """Return (x_span, y_span) of the bands to align, None where not applicable."""
    if kind == "h":
        return None, span(alpha[:, CELL // 2])
    if kind == "v":
        return span(alpha[CELL // 2]), None
    leg_row = alpha[CELL - 2] if kind[0] == "D" else alpha[1]
    arm_col = alpha[:, CELL - 2] if kind[1] == "R" else alpha[:, 1]
    return span(leg_row), span(arm_col)


def transform(cell, x_span, y_span):
    """Affine-map the measured spans onto the target bands (x may scale, y shifts)."""
    close = lambda got, want: got is None or (abs(got[0] - want[0]) <= 1 and abs(got[1] - want[1]) <= 1)
    if close(x_span, V_BAND) and close(y_span, H_BAND):
        return cell, False  # already registered (within resampling rounding)
    ax, bx = 1.0, 0.0
    if x_span:
        ax = (V_BAND[1] - V_BAND[0]) / max(1, x_span[1] - x_span[0])
        if abs(ax - 1) < 0.04:
            ax = 1.0
        bx = V_BAND[0] - ax * x_span[0]
    by = (H_BAND[0] - y_span[0]) if y_span else 0.0
    if ax == 1.0 and abs(bx) < 0.5 and abs(by) < 0.5:
        return cell, False
    # PIL wants the inverse map: source = (x - bx) / ax, y - by
    rgba = cell.astype(np.float64)
    premult = np.concatenate([rgba[..., :3] * rgba[..., 3:4] / 255, rgba[..., 3:4]], -1).astype(np.uint8)
    img = Image.fromarray(premult, "RGBA")
    resample = Image.NEAREST if ax == 1.0 and float(bx).is_integer() and float(by).is_integer() else Image.BICUBIC
    out = np.array(img.transform((CELL, CELL), Image.AFFINE, (1 / ax, 0, -bx / ax, 0, 1, -by), resample=resample)).astype(np.float64)
    alpha = out[..., 3:4]
    rgb = np.where(alpha > 0, out[..., :3] * 255 / np.maximum(alpha, 1), 0)
    result = np.concatenate([rgb, np.where(alpha > 127, 255, 0)], -1)
    result[result[..., 3] == 0, :3] = 0
    return np.clip(result, 0, 255).astype(np.uint8), True


def main():
    for name, (cols, rows, kinds) in SHEETS.items():
        path = WALLS / name
        sheet = np.array(Image.open(path).convert("RGBA"))
        changed = 0
        for index, kind in enumerate(kinds):
            x0, y0 = (index % cols) * CELL, (index // cols) * CELL
            cell = sheet[y0:y0 + CELL, x0:x0 + CELL]
            x_span, y_span = measure(cell[..., 3] > 0, kind)
            fixed, did = transform(cell, x_span, y_span)
            if did:
                sheet[y0:y0 + CELL, x0:x0 + CELL] = fixed
                changed += 1
                print(f"  {name} frame {index}: x {x_span} y {y_span} -> x {V_BAND if x_span else '-'} y {H_BAND if y_span else '-'}")
        if changed:
            save_game_webp(Image.fromarray(sheet, "RGBA"), path)
        print(f"{name}: {changed} frame(s) re-registered")


if __name__ == "__main__":
    main()
