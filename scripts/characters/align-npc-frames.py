"""Aligns the frames of the first village's NPC sheets, so a clip no longer jumps from frame to frame
(owner, 2026-11-12: "their animations are not so good, some of them looks like jumping tiles not
perfectly align").

The six sheets (godot/asset/characters/authored/npcs/<name>.webp, 6 columns x 5 rows: idle, walk
down, up, left, right) were cut so that a figure sat at a different place in each cell: the
fisherman drifted 37 px sideways along a row, the elder and the scout stood on a different ground
line in each walk direction, the others wobbled sideways. This tool moves each frame inside its cell
(whole pixels, nothing is redrawn or scaled):

- **Ground line:** every frame's lowest pixel goes to the idle row's ground line (the median of its
  frames' lowest rows), so the feet stay put through a clip and from one clip to the next.
- **Centre:** a row's first frame is centred by the middle of its lower body (the lowest 45% of its
  height: hats, rods and waving arms do not pull it), and each other frame of the row is slid
  sideways to where its lower body covers that frame's best.
- **Room above:** a sheet whose figures are taller than the room over the ground line gets taller
  cells (rows added at the top) and its scene's Visual offset follows, so the feet stay where they
  were in the world.
- Loose specks away from the figure (slivers of a neighbouring cell) are removed.

Running it again on an aligned sheet moves nothing. The originals are in git.

    python scripts/characters/align-npc-frames.py [--preview=<dir>] [name ...]

--preview writes before/after GIFs of every row there instead of changing the game.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SHEETS = ROOT / "godot/asset/characters/authored/npcs"
SCENES = ROOT / "godot/game/scenes/characters"
NPCS = ["village-elder-plop", "lili", "red-slime-boy", "fisherman-slime", "yellow-blond-slime-girl", "mossy-scout"]
COLS, ROWS = 6, 5
ROW_NAMES = ["idle", "walk-down", "walk-up", "walk-left", "walk-right"]
ALPHA_CUT = 40
## the share of a figure's height, from its feet, that centres it
LOWER_BODY = 0.45
## how far a frame may be slid to match its row's first (pixels)
SEARCH = 60
## a part this far outside the figure's box is a stray speck (pixels)
SPECK_REACH = 12
## empty rows kept above the tallest figure
HEADROOM = 2


def parts(mask: np.ndarray) -> list[np.ndarray]:
	"""The 8-connected parts of a mask, each an array of (y, x), biggest first."""
	seen = np.zeros_like(mask, dtype=bool)
	height, width = mask.shape
	out = []
	for y0, x0 in zip(*np.nonzero(mask)):
		if seen[y0, x0]:
			continue
		stack = [(y0, x0)]
		seen[y0, x0] = True
		part = []
		while stack:
			y, x = stack.pop()
			part.append((y, x))
			for ny in (y - 1, y, y + 1):
				for nx in (x - 1, x, x + 1):
					if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
						seen[ny, nx] = True
						stack.append((ny, nx))
		out.append(np.array(part))
	out.sort(key=len, reverse=True)
	return out


def cleaned(frame: np.ndarray) -> np.ndarray:
	"""The frame without the specks that stand away from its figure."""
	found = parts(frame[..., 3] > ALPHA_CUT)
	if len(found) < 2:
		return frame
	body = found[0]
	top, left = body.min(axis=0)
	bottom, right = body.max(axis=0)
	out = frame.copy()
	for part in found[1:]:
		ys, xs = part[:, 0], part[:, 1]
		if xs.max() < left - SPECK_REACH or xs.min() > right + SPECK_REACH or ys.max() < top - SPECK_REACH or ys.min() > bottom + SPECK_REACH:
			out[ys, xs] = 0
	return out


def box(frame: np.ndarray) -> tuple[int, int, int, int]:
	ys, xs = np.nonzero(frame[..., 3] > ALPHA_CUT)
	return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def lower_body(frame: np.ndarray) -> np.ndarray:
	"""The mask of the figure's lowest LOWER_BODY, on a canvas whose last row is the figure's feet."""
	mask = frame[..., 3] > ALPHA_CUT
	left, top, right, bottom = box(frame)
	band = int(round((bottom - top + 1) * LOWER_BODY))
	out = np.zeros((band, mask.shape[1]), dtype=bool)
	out[:] = mask[bottom - band + 1:bottom + 1]
	return out


def slide_to(reference: np.ndarray, band: np.ndarray) -> int:
	"""How far right `band` must slide to cover `reference` best (both lower bodies; the shorter
	one's rows are compared, from the feet up)."""
	rows = min(reference.shape[0], band.shape[0])
	a, b = reference[-rows:], band[-rows:]
	best, best_score = 0, -1.0
	for dx in range(-SEARCH, SEARCH + 1):
		moved = np.zeros_like(b)
		if dx >= 0:
			moved[:, dx:] = b[:, :b.shape[1] - dx]
		else:
			moved[:, :dx] = b[:, -dx:]
		union = (a | moved).sum()
		score = (a & moved).sum() / union if union else 0.0
		if score > best_score + 1e-9 or (abs(score - best_score) <= 1e-9 and abs(dx) < abs(best)):
			best, best_score = dx, score
	return best


def aligned(sheet: Image.Image, name: str) -> tuple[Image.Image, int, list[str]]:
	"""The sheet with every frame on one ground line and centre, the rows added above each cell,
	and what was moved (a line per row)."""
	array = np.asarray(sheet.convert("RGBA"))
	cell_w, cell_h = array.shape[1] // COLS, array.shape[0] // ROWS
	frames = [[cleaned(array[r * cell_h:(r + 1) * cell_h, c * cell_w:(c + 1) * cell_w]) for c in range(COLS)] for r in range(ROWS)]
	ground = int(np.median([box(frame)[3] for frame in frames[0]]))
	tallest = max(box(frame)[3] - box(frame)[1] + 1 for row in frames for frame in row)
	extra = max(0, tallest + HEADROOM - (ground + 1))
	new_h = cell_h + extra
	out = np.zeros((new_h * ROWS, cell_w * COLS, 4), dtype=np.uint8)
	notes = []
	for r, row in enumerate(frames):
		first = lower_body(row[0])
		xs = np.nonzero(first)[1]
		centre = int(round((cell_w - 1) / 2 - xs.mean()))
		moves = []
		for c, frame in enumerate(row):
			left, top, right, bottom = box(frame)
			dx = centre + (slide_to(first, lower_body(frame)) if c else 0)
			dx = max(-left, min(cell_w - 1 - right, dx))  # the figure stays inside its cell
			dy = ground + extra - bottom
			moves.append((dx, dy - extra))
			ys, xs = np.nonzero(frame[..., 3] > 0)
			keep = (xs + dx >= 0) & (xs + dx < cell_w) & (ys + dy >= 0) & (ys + dy < new_h)
			out[r * new_h + ys[keep] + dy, c * cell_w + xs[keep] + dx] = frame[ys[keep], xs[keep]]
		notes.append("  %-10s moved (right, down): %s" % (ROW_NAMES[r], " ".join("(%d,%d)" % move for move in moves)))
	return Image.fromarray(out, "RGBA"), extra, notes


def gif(sheet: Image.Image, cell_h: int, path: Path, scale: float = 1.0) -> None:
	"""Every row of the sheet playing side by side, on grass, with the ground line drawn."""
	cell_w = sheet.width // COLS
	shots = []
	for c in range(COLS):
		shot = Image.new("RGBA", (cell_w * ROWS, cell_h), (96, 148, 72, 255))
		for r in range(ROWS):
			shot.alpha_composite(sheet.crop((c * cell_w, r * cell_h, (c + 1) * cell_w, (r + 1) * cell_h)), (r * cell_w, 0))
		shots.append(shot.convert("RGB"))
	shots[0].save(path, save_all=True, append_images=shots[1:], duration=125, loop=0)


def main() -> None:
	preview = [arg.split("=", 1)[1] for arg in sys.argv[1:] if arg.startswith("--preview=")]
	wanted = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
	for name in NPCS:
		if wanted and name not in wanted:
			continue
		path = SHEETS / f"{name}.webp"
		sheet = Image.open(path).convert("RGBA")
		cell_h = sheet.height // ROWS
		result, extra, notes = aligned(sheet, name)
		print(f"{name}: cells {sheet.width // COLS} x {cell_h}" + (f", {extra} rows added above each" if extra else ""))
		print("\n".join(notes))
		if preview:
			out = Path(preview[0])
			out.mkdir(parents=True, exist_ok=True)
			gif(sheet, cell_h, out / f"{name}-before.gif")
			gif(result, cell_h + extra, out / f"{name}-after.gif")
			result.save(out / f"{name}-after.png")
			continue
		save_game_webp(result, path)
		if extra:
			scene = SCENES / f"{name}.tscn"
			text = scene.read_text(encoding="utf-8")
			newline = "\r\n" if "\r\n" in text else "\n"
			found = re.search(r'(\[node name="Visual"[^\[]*?offset = Vector2\(-?[\d.]+, )(-?[\d.]+)\)', text, re.S)
			if found is None:
				raise RuntimeError(f"{scene}: no Visual offset to move")
			text = text[:found.start(2)] + f"{float(found.group(2)) - extra:g}" + text[found.end(2):]
			scene.write_text(text, encoding="utf-8", newline="")
			print(f"  {scene.name}: Visual offset y {found.group(2)} -> {float(found.group(2)) - extra:g}")


if __name__ == "__main__":
	main()
