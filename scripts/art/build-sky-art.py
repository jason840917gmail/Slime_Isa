"""Packs the sky floor's art (docs/godot/SKY_FLOOR.md) into godot/asset/MAPS/sky/.

    python scripts/art/build-sky-art.py

Sources: asset/Originals/sky/generated/ (Magnific GPT 2.5, 2026-11-01). Writes (through
scripts/lib/game_webp.py), at 128 px a cell:

- far-forest.webp     the far ground: the forest seen from very high, made seamless (wrap blend);
- clouds-big-a.webp, clouds-big-b.webp, clouds-wisps.webp
                      cloud layers on transparency (no cloud touches an edge, so they tile);
- cloud-sea.webp      the cloud bank round the islands' feet, made seamless;
- rope-bridge-ew-{west,mid,east}.webp, rope-bridge-ns-{north,mid,south}.webp
                      the rope bridge cut into its two ends and one repeating stretch (from one
                      railing post's middle to the next), 192 px (96 units) across the deck.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SRC = ROOT / "asset" / "Originals" / "sky" / "generated"
OUT = ROOT / "godot" / "asset" / "MAPS" / "sky"
BRIDGE_ACROSS = 192


def seamless(path: Path) -> Image.Image:
    """The picture blended with itself rolled by half, so its edges wrap (opaque)."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    h, w, _ = im.shape
    rolled = np.roll(np.roll(im, h // 2, 0), w // 2, 1)

    def ramp(n: int) -> np.ndarray:
        d = np.minimum(np.arange(n), n - 1 - np.arange(n)).astype(np.float32)
        t = np.clip(d / (n * 0.22), 0, 1)
        return t * t * (3 - 2 * t)

    m = np.minimum(ramp(h)[:, None], ramp(w)[None, :])[..., None]
    out = im * m + rolled * (1 - m)
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGB")


def clean_edges(path: Path) -> Image.Image:
    """A cloud layer with its border forced clear (the model leaves a 1-2 alpha haze)."""
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).copy()
    a[..., 3] = np.where(a[..., 3] < 4, 0, a[..., 3])
    a[:2, :, 3] = 0
    a[-2:, :, 3] = 0
    a[:, :2, 3] = 0
    a[:, -2:, 3] = 0
    return Image.fromarray(a, "RGBA")


def band(im: Image.Image, vertical: bool) -> Image.Image:
    """The bridge cropped to its solid band, scaled to BRIDGE_ACROSS across."""
    a = np.asarray(im)[..., 3]
    rows = np.where(a.max(1) > 128)[0]
    cols = np.where(a.max(0) > 128)[0]
    im = im.crop((int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1))
    if vertical:
        return im.resize((BRIDGE_ACROSS, round(im.height * BRIDGE_ACROSS / im.width)), Image.LANCZOS)
    return im.resize((round(im.width * BRIDGE_ACROSS / im.height), BRIDGE_ACROSS), Image.LANCZOS)


def period(profile: np.ndarray, shortest: int) -> int:
    """The railing's repeat along the bridge: the first peak of the profile's autocorrelation."""
    p = profile - profile.mean()
    corr = np.correlate(p, p, "full")[len(p) - 1:]
    corr /= corr[0]
    longest = len(corr) // 3
    if longest <= shortest:
        raise SystemExit("the bridge is too short to find its repeat")
    return shortest + int(np.argmax(corr[shortest:longest]))


def cut_bridge(im: Image.Image, vertical: bool, names: tuple[str, str, str]) -> None:
    """Cuts the bridge into its start end, one repeat of its railing (from between two posts to the
    next) and its far end, the cuts a whole number of repeats apart so the pieces join."""
    rgba = np.asarray(im).astype(np.float32)
    lum = rgba[..., :3].mean(-1) * rgba[..., 3] / 255.0
    # the railing's posts along one side carry the repeat
    side = lum[:, : BRIDGE_ACROSS // 5] if vertical else lum[: BRIDGE_ACROSS // 5, :]
    profile = side.mean(1) if vertical else side.mean(0)
    length = len(profile)
    step = period(profile, BRIDGE_ACROSS // 4)
    # a cut between two posts near the bridge's middle: the darkest point of the railing within one
    # repeat of it (rope and planks join there; a cut through a post shows)
    centre = length // 2
    a0 = centre - step // 2 + int(np.argmin(profile[centre - step // 2: centre + step // 2]))
    a1 = a0 + step
    # the ends: the anchors plus whole repeats, at least an eighth of the bridge each
    first = a0
    while first - step >= length // 8:
        first -= step
    last = a1
    while last + step <= length - length // 8:
        last += step

    def part(p0: int, p1: int) -> Image.Image:
        return im.crop((0, p0, im.width, p1)) if vertical else im.crop((p0, 0, p1, im.height))

    for name, piece in zip(names, (part(0, first), part(a0, a1), part(last, length))):
        save_game_webp(piece, OUT / name)
        print(f"{name}: {piece.size}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    save_game_webp(seamless(SRC / "far-ground-a.png"), OUT / "far-forest.webp")
    save_game_webp(seamless(SRC / "cloud-sea-b.png"), OUT / "cloud-sea.webp")
    for src, name in (("clouds-big-a", "clouds-big-a"), ("clouds-big-b", "clouds-big-b"),
                      ("clouds-wisps-a", "clouds-wisps")):
        save_game_webp(clean_edges(SRC / f"{src}.png"), OUT / f"{name}.webp")
    ew = band(Image.open(SRC / "rope-bridge-a.png").convert("RGBA"), False)
    cut_bridge(ew, False, ("rope-bridge-ew-west.webp", "rope-bridge-ew-mid.webp", "rope-bridge-ew-east.webp"))
    ns = band(Image.open(SRC / "rope-bridge-ns-b.png").convert("RGBA"), True)
    cut_bridge(ns, True, ("rope-bridge-ns-north.webp", "rope-bridge-ns-mid.webp", "rope-bridge-ns-south.webp"))
    print("sky art packed into", OUT)


if __name__ == "__main__":
    main()
