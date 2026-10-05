"""Packs page 1 of the three-quarter top-down player slime (v2): idle and walk facing down, up and side.

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

Writes asset/characters/256x256-tile_8x8-slime-v2-page-1.webp (8 x 8 cells of 256 px; rows 0-5 are
idle down/up/side and walk down/up/side, rows 6-7 free) and slime-v2/page-1.json (loop choice and
playback fps per row, which the Godot player scene's clips use).

usage: python scripts/characters/pack-slime-v2-page.py [--preview preview.gif]
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
OUTPUT = REPO / "asset" / "characters" / "256x256-tile_8x8-slime-v2-page-1.webp"
EXTRACTOR = REPO / "scripts" / "characters" / "extract-video-frames.mjs"

CELL = 256
COLUMNS = 8
SOURCE_FPS = 24
EXTRACT_SIZE = 512
TARGET_WIDTH = 186
BOTTOM = 251
CENTRE_X = 128
ROWS = ["idle-down", "idle-up", "idle-side", "walk-down", "walk-up", "walk-side"]
LOOP_RANGE = {"idle": (24, 72), "walk": (10, 24)}  # loop length, in source frames
# Source frames a row's loop may use: the side walk turns toward the viewer before frame 58.
WINDOWS = {"walk-side": (58, 97)}


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


def extract(frames_dir: Path) -> None:
    clips = [f"{row}={SOURCES / 'videos' / f'{row}.mp4'}" for row in ROWS]
    subprocess.run(["node", str(EXTRACTOR), str(frames_dir), str(SOURCE_FPS), str(EXTRACT_SIZE), *clips], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", type=Path, help="also write an animated GIF of the six loops")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="slime-v2-frames-") as tmp:
        frames_dir = Path(tmp)
        extract(frames_dir)
        clips = {row: [keyed(p) for p in sorted((frames_dir / row).glob("f*.png"))] for row in ROWS}

    x0, _, x1, _ = bbox(clips["idle-down"][0][..., 3])
    scale = TARGET_WIDTH / (x1 - x0)
    page = Image.new("RGBA", (CELL * COLUMNS, CELL * COLUMNS), (0, 0, 0, 0))
    manifest = {"cell": CELL, "columns": COLUMNS, "source_fps": SOURCE_FPS, "scale": round(scale, 4), "rows": {}}
    previews: dict[str, tuple[list[Image.Image], float]] = {}
    for row, name in enumerate(ROWS):
        frames = clips[name]
        start, length, score = best_loop(frames, name.split("-")[0], WINDOWS.get(name))
        picks = [start + round(i * length / COLUMNS) for i in range(COLUMNS)]
        fx0, _, fx1, fy1 = bbox(frames[start][..., 3])
        offset = (round(CENTRE_X - (fx0 + fx1) / 2 * scale), round(BOTTOM - fy1 * scale))
        cells = []
        for column, index in enumerate(picks):
            frame = Image.fromarray((frames[index] * 255).astype(np.uint8), "RGBA")
            frame = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.LANCZOS)
            cell = place(frame, offset)
            cells.append(cell)
            page.alpha_composite(cell, (column * CELL, row * CELL))
        touches_edge = any(np.asarray(c)[[0, -1], :, 3].max() > 0 or np.asarray(c)[:, [0, -1], 3].max() > 0 for c in cells)
        fps = round(COLUMNS * SOURCE_FPS / length, 2)
        manifest["rows"][name] = {
            "row": row, "first_frame": row * COLUMNS, "fps": fps, "loop_start": start,
            "loop_length": length, "source_frames": picks, "loop_score": round(score, 4), "touches_cell_edge": bool(touches_edge),
        }
        previews[name] = (cells, fps)
        print(f"{name:10s} loop {start}+{length} ({length / SOURCE_FPS:.2f} s) -> {fps} fps, score {score:.4f}{', TOUCHES CELL EDGE' if touches_edge else ''}")

    save_game_webp(page, OUTPUT)
    (SOURCES / "page-1.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(REPO)} and {(SOURCES / 'page-1.json').relative_to(REPO)}")

    if args.preview:
        ticks = []
        for tick in range(72):  # 3 s at 24 fps, six loops in a 3 x 2 grid on the meadow green
            canvas = Image.new("RGBA", (CELL * 3, CELL * 2), (58, 74, 52, 255))
            for slot, name in enumerate(ROWS):
                cells, fps = previews[name]
                canvas.alpha_composite(cells[int(tick / 24 * fps) % COLUMNS], ((slot % 3) * CELL, (slot // 3) * CELL))
            ticks.append(canvas.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT))
        ticks[0].save(args.preview, save_all=True, append_images=ticks[1:], duration=42, loop=0)


if __name__ == "__main__":
    main()
