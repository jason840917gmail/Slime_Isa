"""Packs a page of the three-quarter top-down player slime (v2) from its Seedance clips.

Sources (asset/Originals/characters/slime-v2/): `videos/<row>.mp4`, one Seedance 1.5 Pro clip per
row, each made with the same start and end frame (`start-<direction>.png`, cut from the approved
turnaround `turnaround-e.png`) on a flat #FF00FF screen; see the README there.

For each clip:
1. extract every frame at 24 fps with headless Brave (scripts/characters/extract-video-frames.mjs);
2. key the background against each frame's own border colour (it drifts from #FF00FF to a duller
   pink), drop painted drop shadows by hue, un-mix the edge colour, and keep only the shape
   connected to the slime;
3. pick the loop whose end best matches its start relative to how much it moves (only loops that
   move at least half as much as the liveliest candidate), and sample 8 frames over it
   (playback fps = 8 * 24 / loop length);
4. scale every clip by ONE factor (idle-down's first frame is 186 px wide, the width of the old
   slime sheet's frame 0) and align each clip by its first frame: centred at x 128, bottom at y 251
   of a 256 px cell, so the motion inside the clip is kept.

Pages (PAGES below): 1 = idle and walk (each facing down, up and side), then doze and sleep
(facing down); 2 = roll and the stretch lash (down, up, side), then the defeat (facing down).
Looping rows (idle, walk, sleep) play at 8 * 24 / loop length fps; one-shot rows (roll, stretch,
doze, die) cut one action and are timed to their gameplay duration (ONE_SHOT_MS). Rows in PICKS use
hand-picked frames (the lash, the doze and the defeat), and some sit shifted in their cells
(SHIFTS) so the reach fits. A page is always packed whole from its clips: the sheet is a lossy
WebP, so redrawing rows into an existing sheet would re-encode (and degrade) the others.
Writes asset/characters/256x256-tile_8x8-slime-v2-page-<n>.webp (8 x 8 cells of 256 px, one row per
clip, unused rows empty) and slime-v2/page-<n>.json (loop choice, fps and looping per row, which
godot/tools/build_player_clips.gd turns into the player scene's clips).

usage: python scripts/characters/pack-slime-v2-page.py [--page N] [--preview preview.gif]
Needs Pillow, numpy, Node and Brave (BRAVE_PATH to override its path).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = REPO / "asset" / "Originals" / "characters" / "slime-v2"
EXTRACTOR = REPO / "scripts" / "characters" / "extract-video-frames.mjs"

CELL = 256
COLUMNS = 8
SOURCE_FPS = 24
EXTRACT_SIZE = 512
START_FRAME_SIZE = 1024  # the start-<direction>.png canvases the clips begin from
TARGET_WIDTH = 186
BOTTOM = 251
CENTRE_X = 128
PAGES = {
    1: ["idle-down", "idle-up", "idle-side", "walk-down", "walk-up", "walk-side", "doze-down", "sleep-down"],
    2: ["roll-down", "roll-up", "roll-side", "stretch-down", "stretch-up", "stretch-side", "die-down"],
}
# Loop (or one-shot action) length range in source frames, by clip (the row name minus its direction).
LOOP_RANGE = {"idle": (24, 72), "walk": (10, 24), "roll": (8, 30), "attack-1": (8, 30), "sleep": (30, 72)}
# One-shot clips are timed to gameplay: the dodge roll lasts 500 ms (player spec 5.2), a sword
# swing 416.67 ms (the basic sword's attack plans), and the stretch lash's reach 270 ms (a lash that
# catches nothing is done at 270 ms, abilities spec 8); the doze and the defeat keep Phaser's 1 s
# clips (the sleep controller dozes for the doze clip's length).
ONE_SHOT_MS = {"roll": 500.0, "attack-1": 416.67, "stretch": 270.0, "doze": 1000.0, "die": 1000.0}
# Source frames a row's loop may use: the side walk turns toward the viewer before frame 58; the
# down and up rolls tumble only in these stretches; the sleeper perks its sprout up after frame 72.
WINDOWS = {"walk-side": (58, 97), "roll-down": (25, 46), "roll-up": (30, 66), "sleep-down": (0, 72)}
# Rows whose clip drifts sideways (the rolls): each frame is centred and stood on the baseline on
# its own (in play the body moves during a dodge anyway). They keep the page scale: a tumble changes
# the slime's shape, not its size.
RECENTRED = {"roll-down", "roll-up"}
# Rows baked from a still instead of a clip: the side roll is the side pose spun clockwise in 45°
# steps (a right-facing profile rolling right; mirrored, it rolls left), tucked to fit the cell.
SPINS = {"roll-side": "start-side.png"}
SPIN_TUCK = 0.88
# Rows whose 8 source frames are picked by hand: the lash takes reach twice and wobble in between, so
# no neutral-to-neutral stretch is a clean single lash. Each runs neutral, reach, hold, back to
# neutral (the side pulls back through its reach frames reversed), and leaves out frames that would
# not fit a cell or point the wrong way (README, page 2).
PICKS = {
    "stretch-down": [22, 37, 43, 44, 44, 43, 80, 81],
    "stretch-up": [2, 40, 44, 48, 54, 58, 60, 88],
    "stretch-side": [4, 18, 20, 22, 24, 22, 18, 96],
    # Awake, a blink, heavy eyes, closed, the yawn, settling, the leaves drooping, asleep (the sleep
    # still the sleep row loops on).
    "doze-down": [4, 12, 34, 38, 56, 70, 80, 96],
    # The take opens with a hand poking the slime (frames 2-20), so the defeat starts at frame 56:
    # the flinch, the squeezed > < eyes, the melt and the puddle it ends on.
    "die-down": [56, 62, 66, 68, 70, 72, 76, 96],
}
# Rows drawn smaller than the page scale: the defeat's puddle (276 px at page scale) must fit a cell.
ROW_SCALES = {"die-down": 0.9}
# Rows drawn shifted in their cells by (x, y) px so the reach fits: the down lash's arm hangs below
# the baseline and the side lash's arm reaches past the cell's right edge. The manifest records the
# shift; build_player_clips.gd keys Visual:offset back by it, so the slime stays where it stands.
SHIFTS = {"stretch-down": (0, -37), "stretch-side": (-26, -3)}


def keyed(path: Path) -> np.ndarray:
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    ring = np.concatenate([rgb[:12].reshape(-1, 3), rgb[-12:].reshape(-1, 3), rgb[:, :12].reshape(-1, 3), rgb[:, -12:].reshape(-1, 3)])
    background = np.median(ring, axis=0).astype(np.float32)
    distance = np.linalg.norm(rgb - background, axis=2)
    alpha = np.clip((distance - 0.16) / (0.42 - 0.16), 0.0, 1.0)

    # Painted drop shadows are the background darkened: same hue, lower brightness. Keying on
    # chromaticity removes them; the slime's green, its brown outline, white highlights and red
    # mouth sit far from the pink. Near-black pupils have no reliable hue, so only pixels whose
    # brightest channel clears them are judged.
    def chroma(values: np.ndarray) -> np.ndarray:
        return values / np.maximum(values.sum(axis=-1, keepdims=True), 1e-3)

    chroma_alpha = np.clip((np.linalg.norm(chroma(rgb) - chroma(background), axis=2) - 0.06) / 0.10, 0.0, 1.0)
    alpha = np.minimum(alpha, np.where(rgb.max(axis=2) > 0.35, chroma_alpha, 1.0))

    colour = np.clip((rgb - (1.0 - alpha[..., None]) * background) / np.maximum(alpha, 1e-3)[..., None], 0.0, 1.0)
    excess = np.clip(np.minimum(colour[..., 0], colour[..., 2]) - colour[..., 1], 0.0, None)  # leftover spill
    colour[..., 0] -= excess
    colour[..., 2] -= excess
    alpha[alpha < 0.04] = 0.0
    return keep_main_blob(np.dstack([colour, alpha]))


def keep_main_blob(frame: np.ndarray) -> np.ndarray:
    """Keeps only the shape connected to the slime (drops shadow remnants and stray specks): a flood
    fill on a firm outline from the opaque point nearest the centroid, grown 3 px for the soft edge."""
    alpha = frame[..., 3]
    ys, xs = np.nonzero(alpha > 0.5)
    if xs.size == 0:
        return frame
    nearest = np.argmin((ys - ys.mean()) ** 2 + (xs - xs.mean()) ** 2)
    # .copy(): an image made by fromarray shares the array's memory and silently ignores the fill.
    mask = Image.fromarray(np.where(alpha > 0.35, 255, 0).astype(np.uint8), "L").copy()
    ImageDraw.floodfill(mask, (int(xs[nearest]), int(ys[nearest])), 128)
    core = Image.fromarray(np.where(np.asarray(mask) == 128, 255, 0).astype(np.uint8), "L")
    keep = np.asarray(core.filter(ImageFilter.MaxFilter(7))) > 0
    out = frame.copy()
    out[..., 3] = np.where(keep, alpha, 0.0)
    return out


def signature(frame: np.ndarray) -> np.ndarray:
    image = Image.fromarray((frame * 255).astype(np.uint8), "RGBA").resize((64, 64), Image.BILINEAR)
    return np.asarray(image, dtype=np.float32) / 255.0


def best_loop(frames: list[np.ndarray], kind: str, window: tuple[int, int] | None) -> tuple[int, int, float]:
    signatures = [signature(f) for f in frames]
    low, high = LOOP_RANGE[kind]
    first, last = window or (0, len(frames))
    candidates = []
    for start in range(first, last - low):
        for length in range(low, min(high, last - 1 - start) + 1):
            closure = float(np.abs(signatures[start] - signatures[start + length]).mean())
            amplitude = max(float(np.abs(signatures[start] - signatures[start + k]).mean()) for k in range(1, length))
            candidates.append((start, length, closure, amplitude))
    liveliest = max(c[3] for c in candidates)
    start, length, closure, amplitude = min((c for c in candidates if c[3] >= 0.5 * liveliest), key=lambda c: c[2] / (c[3] + 1e-4))
    return start, length, closure / (amplitude + 1e-4)


def bbox(alpha: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(alpha > 0.1)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def place(frame: Image.Image, offset: tuple[int, int]) -> Image.Image:
    """The cell-sized window of `frame` drawn at `offset` (which may be negative)."""
    pad = max(abs(offset[0]), abs(offset[1]), 0) + CELL
    canvas = Image.new("RGBA", (frame.width + 2 * pad, frame.height + 2 * pad), (0, 0, 0, 0))
    canvas.alpha_composite(frame, (pad, pad))
    return canvas.crop((pad - offset[0], pad - offset[1], pad - offset[0] + CELL, pad - offset[1] + CELL))


def clip_of(row: str) -> str:
    """The clip a row belongs to: its name without the direction suffix ("attack-1-side" -> "attack-1")."""
    return row.rsplit("-", 1)[0]


def spin_cells(still: np.ndarray, scale: float) -> list[Image.Image]:
    """Eight cells of `still` (a keyed frame) rotated clockwise by 0, 45, ... 315 degrees about its
    body centre, scaled by `scale` and SPIN_TUCK, the body centre at the neutral pose's centre."""
    x0, y0, x1, y1 = bbox(still[..., 3])
    body = Image.fromarray((still * 255).astype(np.uint8), "RGBA").crop((x0, y0, x1, y1))
    size = (round(body.width * scale * SPIN_TUCK), round(body.height * scale * SPIN_TUCK))
    body = body.resize(size, Image.LANCZOS)
    centre = (CENTRE_X, BOTTOM - round((y1 - y0) * scale) / 2)
    cells = []
    for step in range(COLUMNS):
        turned = body.rotate(-45 * step, resample=Image.BICUBIC, expand=True)
        cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        cell.alpha_composite(place(turned, (round(centre[0] - turned.width / 2), round(centre[1] - turned.height / 2))))
        cells.append(cell)
    return cells


def extract(frames_dir: Path, rows: list[str]) -> None:
    clips = [f"{row}={SOURCES / 'videos' / f'{row}.mp4'}" for row in rows if row not in SPINS]
    subprocess.run(["node", str(EXTRACTOR), str(frames_dir), str(SOURCE_FPS), str(EXTRACT_SIZE), *clips], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--page", type=int, default=1, choices=sorted(PAGES), help="page to pack (default 1)")
    parser.add_argument("--preview", type=Path, help="also write an animated GIF of the page's clips")
    args = parser.parse_args()
    rows = PAGES[args.page]
    output = REPO / "asset" / "characters" / f"256x256-tile_8x8-slime-v2-page-{args.page}.webp"
    manifest_path = SOURCES / f"page-{args.page}.json"

    with tempfile.TemporaryDirectory(prefix="slime-v2-frames-") as tmp:
        frames_dir = Path(tmp)
        extract(frames_dir, rows)
        clips = {row: [keyed(p) for p in sorted((frames_dir / row).glob("f*.png"))] for row in rows if row not in SPINS}
    for row in rows:
        if row in SPINS:
            clips[row] = [keyed(SOURCES / SPINS[row])]

    # Every clip starts on the same start image (turnaround E's view), so the first frame of the
    # page's first clip sets one scale for every page: 186 px wide, the old sheet's frame 0. Spin rows
    # use the start stills themselves (START_FRAME_SIZE px canvases, twice the extracted frames).
    first_clip = next((r for r in rows if r not in SPINS), None)
    if first_clip is not None:
        x0, _, x1, _ = bbox(clips[first_clip][0][..., 3])
        scale = TARGET_WIDTH / (x1 - x0)
        still_scale = scale * EXTRACT_SIZE / START_FRAME_SIZE
    else:
        x0, _, x1, _ = bbox(keyed(SOURCES / "start-down.png")[..., 3])
        still_scale = scale = TARGET_WIDTH / (x1 - x0)
    page = Image.new("RGBA", (CELL * COLUMNS, CELL * COLUMNS), (0, 0, 0, 0))
    manifest = {"cell": CELL, "columns": COLUMNS, "source_fps": SOURCE_FPS, "scale": round(scale, 4), "rows": {}}
    previews: dict[str, tuple[list[Image.Image], float]] = {}
    for row, name in enumerate(rows):
        frames = clips[name]
        if name in SPINS:
            start, length, score, picks = 0, COLUMNS, 0.0, [0] * COLUMNS
            cells = spin_cells(frames[0], still_scale)
        else:
            if name in PICKS:
                picks = PICKS[name]
                start, length, score = picks[0], picks[-1] - picks[0], 0.0
            else:
                start, length, score = best_loop(frames, clip_of(name), WINDOWS.get(name))
                picks = [start + round(i * length / COLUMNS) for i in range(COLUMNS)]
            row_scale = scale * ROW_SCALES.get(name, 1.0)
            shift = SHIFTS.get(name, (0, 0))
            fx0, _, fx1, fy1 = bbox(frames[start][..., 3])
            offset = (round(CENTRE_X - (fx0 + fx1) / 2 * row_scale) + shift[0], round(BOTTOM - fy1 * row_scale) + shift[1])
            cells = []
            for index in picks:
                if name in RECENTRED:
                    gx0, _, gx1, gy1 = bbox(frames[index][..., 3])
                    offset = (round(CENTRE_X - (gx0 + gx1) / 2 * row_scale), round(BOTTOM - gy1 * row_scale))
                frame = Image.fromarray((frames[index] * 255).astype(np.uint8), "RGBA")
                frame = frame.resize((round(frame.width * row_scale), round(frame.height * row_scale)), Image.LANCZOS)
                cells.append(place(frame, offset))
        for column, cell in enumerate(cells):
            page.alpha_composite(cell, (column * CELL, row * CELL))
        touches_edge = any(np.asarray(c)[[0, -1], :, 3].max() > 0 or np.asarray(c)[:, [0, -1], 3].max() > 0 for c in cells)
        one_shot_ms = ONE_SHOT_MS.get(clip_of(name))
        fps = round(COLUMNS * 1000.0 / one_shot_ms, 2) if one_shot_ms else round(COLUMNS * SOURCE_FPS / length, 2)
        manifest["rows"][name] = {
            "row": row, "first_frame": row * COLUMNS, "fps": fps, "loop": one_shot_ms is None, "loop_start": start,
            "loop_length": length, "source_frames": picks, "loop_score": round(score, 4), "touches_cell_edge": bool(touches_edge),
        }
        if name in SHIFTS:
            manifest["rows"][name]["shift"] = list(SHIFTS[name])
        if name in ROW_SCALES:
            manifest["rows"][name]["row_scale"] = ROW_SCALES[name]
        previews[name] = (cells, fps)
        print(f"{name:10s} loop {start}+{length} ({length / SOURCE_FPS:.2f} s) -> {fps} fps, score {score:.4f}{', TOUCHES CELL EDGE' if touches_edge else ''}")

    save_game_webp(page, output)
    manifest_path.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {output.relative_to(REPO)} and {manifest_path.relative_to(REPO)}")

    if args.preview:
        ticks = []
        for tick in range(72):  # 3 s at 24 fps, the clips three to a row on the meadow green
            canvas = Image.new("RGBA", (CELL * 3, CELL * ((len(rows) + 2) // 3)), (58, 74, 52, 255))
            for slot, name in enumerate(rows):
                cells, fps = previews[name]
                cells_shown = int(tick / 24 * fps)
                column = cells_shown % COLUMNS if manifest["rows"][name]["loop"] else min(cells_shown, COLUMNS - 1)
                canvas.alpha_composite(cells[column], ((slot % 3) * CELL, (slot // 3) * CELL))
            ticks.append(canvas.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT))
        ticks[0].save(args.preview, save_all=True, append_images=ticks[1:], duration=42, loop=0)


if __name__ == "__main__":
    main()
