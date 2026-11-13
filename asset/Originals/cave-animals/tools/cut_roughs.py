# Cut each cave animal rough sheet into its figures (grid cells cut along the emptiest lines,
# trimmed to alpha) -> <out>/<sheet>-<n>.png
#   python asset/Originals/cave-animals/tools/cut_roughs.py asset/Originals/cave-animals/roughs <out dir>
import sys
from pathlib import Path

import numpy as np
from PIL import Image

R, OUT = Path(sys.argv[1]), Path(sys.argv[2])
GRIDS = {"cave-animals-1": (4, 2), "cave-animals-2": (4, 2)}
# The glow the generator paints round a figure is faint: a figure is what is more solid than this.
SOLID = 96


def splits(counts: np.ndarray, parts: int) -> list[int]:
    length, cuts = len(counts), [0]
    for index in range(1, parts):
        centre, half = index * length / parts, length / parts * 0.4
        lo, hi = int(centre - half), int(centre + half)
        window = counts[lo:hi]
        lines = np.nonzero(window == window.min())[0]
        runs = np.split(lines, np.nonzero(np.diff(lines) > 1)[0] + 1)
        run = min(runs, key=lambda r: abs(lo + (r[0] + r[-1]) / 2 - centre))
        cuts.append(lo + int((run[0] + run[-1]) // 2))
    return cuts + [length]


OUT.mkdir(parents=True, exist_ok=True)
for name, (cols, rows) in GRIDS.items():
    im = Image.open(R / f"{name}.png").convert("RGBA")
    solid = np.asarray(im)[..., 3] > SOLID
    n = 0
    row_cuts = splits(solid.sum(axis=1), rows)
    for top, bottom in zip(row_cuts, row_cuts[1:]):
        col_cuts = splits(solid[top:bottom].sum(axis=0), cols)
        for left, right in zip(col_cuts, col_cuts[1:]):
            cell = im.crop((left, top, right, bottom))
            ys, xs = np.nonzero(np.asarray(cell)[..., 3] > 24)
            cell = cell.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
            cell.save(OUT / f"{name}-{n}.png")
            print(name, n, cell.size)
            n += 1
