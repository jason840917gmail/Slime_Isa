"""Packs the first batch of the bestiary's new enemies (docs/godot/BESTIARY.md) from their Magnific
pose sheets.

Sources (asset/Originals/enemies/bestiary/, GPT 2.5 with a transparent background, one 1024 px
sheet per enemy with four poses in a 2 x 2 grid; prompts in the README there):
`prologue-worm-sheet.png`, `popworm-sheet.png`, `spitcap-sheet.png`, `hopper-sheet.png`,
`bramble-boar-sheet.png`, `thorn-guard-sheet.png`, `rook-thief-sheet.png`; Chapter 2's
`silk-lurker-sheet.png`, `thornball-sheet.png`, `broodling-sheet.png`, `brood-props-sheet.png`
(the egg sac and the real cocoon), `cocoon-mimic-sheet.png`, `brood-warden-sheet.png`; Fatty's
Lair's `squint-sheet.png`, `pipe-worm-sheet.png`, `dung-roller-sheet.png`, `big-squint-sheet.png`
and the single picture `mud-glob.png` (SINGLES: 64x64-mud-glob.webp); every dungeon's skeletons'
`bone-leaper-sheet.png`, `bone-thrower-sheet.png`, `bone-marcher-sheet.png` and
`skeleton-props-sheet.png` (the bone, the skull, the helmeted skull and the bone pile: PROP_SHEETS).
Gorge's worm soldiers (rows 1 to 3, repainted 2026-10-16) have more poses, from several sheets:
`worm-swordsman-sheet.png` and `worm-swordsman-sheet-2.png` (the second sheet's four follow the
first's), the same for `worm-brawler`, and `worm-archer-sheet.png` to `-sheet-3.png`; their arrow
and the brawler's hit come from `worm-army-props-sheet.png` (PROP_SHEETS). The Gloop Forest's
spiders (rows 15 and 16, repainted 2026-10-16): `slime-spider-sheet.png` to `-sheet-3.png` and
`orb-weaver-sheet.png` to `-sheet-3.png` (BODY_ANCHORED), and their webs from
`spider-webs-sheet.png` (PROP_SHEETS). The Crystal Caverns' (rows 23 to 29) and the Watcher Eye
(row 33): `gloomling-sheet.png`, `glint-bat-sheet.png`, `crystal-crawler-sheet.png` (CENTRED),
`prism-eye-sheet.png`, `pick-mole-sheet.png`, `shardback-sheet.png`, `crystal-mite-sheet.png`,
`watcher-eye-sheet.png`, and `caverns-props-sheet.png` (the crystal pillar and the brazier into
godot/asset/MAPS/props/caverns/, the pickaxe into 64x64-pickaxe.webp: PROP_SHEETS).

Each sheet is cut along its empty rows and columns into its four poses (top left, top right,
bottom left, bottom right), each trimmed to its opaque pixels. The poses of one enemy are drawn at
ONE scale (the largest that fits every pose in CELL x BOTTOM), centred at x CELL / 2 and standing
on y BOTTOM of a CELL px cell, so they keep their sizes relative to each other. Frames, left to
right, are the sheet's reading order (see POSES).

The Spitcap's fourth image is its spore seed (the projectile): it goes to its own SEED_CELL px
picture, centred, instead of a frame.

Writes godot/asset/MAPS/enemies/256x256-tile_4x1-<enemy>.webp (and 64x64-spore-seed.webp).

usage: python scripts/characters/pack-bestiary-enemies.py [enemy ...]  (none: every enemy)
Needs Pillow and numpy.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = REPO / "asset" / "Originals" / "enemies" / "bestiary"
OUTPUT = REPO / "godot" / "asset" / "MAPS" / "enemies"
CELL = 256
BOTTOM = 248
CENTRE_X = 128
# The widest / tallest a pose may be drawn in its cell.
FIT = 240
ALPHA_CUT = 24
# Where the grid's empty lines are looked for (the sheet's middle band).
GAP_FROM = 360
GAP_TO = 664
SEED_CELL = 64
SEED_FIT = 56

# A walk cycle's poses (2026-10-19): three more sheets after an enemy's first, four steps each,
# facing right, walking toward the viewer and walking away (WALK_MATCHED; the scenes' `walk_frame`).
WALK = [f"walk-{facing}-{step}" for facing in ("side", "down", "up") for step in "abcd"]
# enemy -> the four poses in reading order (top left, top right, bottom left, bottom right).
POSES = {
    "prologue-worm": ["idle", "walk", "attack", "dazed"] + WALK,
    "popworm": ["mound", "tail", "bite", "dazed"],
    "spitcap": ["hidden", "up", "spit", "seed"],
    "hopper": ["stand", "crouch", "air", "flipped"],
    "bramble-boar": ["stand", "scrape", "charge", "stunned"] + WALK,
    "thorn-guard": ["asleep", "march-a", "march-b", "rubble"] + WALK,
    "rook-thief": ["glide", "swoop", "away", "down"],
    # Fatty's Lair (rows 11 to 14). The Pipe Worm's first three poses hang in their pipe (HUNG); the
    # Dung Roller's fourth is its mud ball, which its scene draws as a sprite of its own.
    # The Squint's walk (2026-10-19, sheets 2 to 4: WALK): four steps facing right, toward the
    # viewer and away from it (WALK_MATCHED).
    "squint": ["stand", "rear", "open", "flipped"] + WALK,
    "pipe-worm": ["hole", "up", "spit", "dazed"],
    "dung-roller": ["push-a", "push-b", "flipped", "ball"],
    "big-squint": ["stand", "rear", "open", "flipped"] + WALK,
    # Chapter 2 (rows 18 to 22). brood-props: the egg sac's three states and the real silk cocoon
    # (the Cocoon Mimic's look-alike), at one scale.
    "silk-lurker": ["hang", "drop", "spin", "down"],
    "thornball": ["stand", "curl", "ball", "flipped"] + WALK,
    "broodling": ["scuttle-a", "scuttle-b", "leap", "popped"] + WALK,
    "brood-props": ["sac", "hatching", "burst", "cocoon"],
    "cocoon-mimic": ["disguised", "burst", "hold", "dazed"] + WALK,
    "brood-warden": ["guard", "windup", "sweep", "planted"] + WALK,
    # Chapter 3 (rows 23 to 29).
    "gloomling": ["rest", "flinch", "scuttle", "fade"],
    "glint-bat": ["asleep", "woken", "swoop", "down"],
    "crystal-crawler": ["crawl-a", "crawl-b", "turn", "flipped"],
    "prism-eye": ["watch", "charge", "shut", "shattered"],
    "pick-mole": ["ducked", "raise", "throw", "out"],
    "shardback": ["walk", "rear", "slam", "broken"] + WALK,
    "crystal-mite": ["ready", "run", "ball", "shards"] + WALK,
    # Every dungeon (row 33): the eye's front (a blank eyeball: the code draws its iris), charging,
    # its back (looking away), broken.
    "watcher-eye": ["front", "charge", "back", "broken"],
    # Every dungeon: the skeletons (rows 30 to 32). The Bone Marcher's front views march down and to
    # the side, its back views march up.
    "bone-leaper": ["watch", "cast", "air", "stuck"] + WALK,
    # The Bone Thrower walks armed (sheets 2 to 4), then empty-handed (5 to 7).
    "bone-thrower": ["armed", "windup", "thrown", "unarmed"] + WALK + [f"bare-{name}" for name in WALK],
    "bone-marcher": ["front-a", "front-b", "back-a", "back-b"] + WALK,
    # Gorge's worm soldiers (rows 1 to 3): eight poses from two sheets (SHEET_POSES a sheet), all
    # facing right but the back views (walking up, striking up). The archer shoots along four lines
    # only (owner, 2026-10-16), so its third sheet draws and shoots down (facing the viewer), shoots
    # up (from behind) and runs.
    "worm-swordsman": ["idle", "walk", "windup", "slash", "hurt", "down", "back", "back-slash"],
    "worm-archer": ["idle", "walk", "draw", "loose", "hurt", "down", "back", "back-draw",
        "front-draw", "front-loose", "back-loose", "run"],
    "worm-brawler": ["guard", "walk", "coil", "punch", "hurt", "down", "back", "back-punch"],
    # The Gloop Forest's spiders (rows 15 and 16): twelve poses from three sheets: facing the viewer
    # (idle, scuttle, rearing to spit, spitting down), facing right (the same four), from behind
    # (idle, spitting up), hurt and defeated. They spit along four lines only (owner, 2026-10-16).
    "slime-spider": ["idle", "scuttle", "rear", "spit", "side", "side-scuttle", "side-rear",
        "side-spit", "back", "back-spit", "hurt", "down"],
    "orb-weaver": ["idle", "scuttle", "rear", "spit", "side", "side-scuttle", "side-rear",
        "side-spit", "back", "back-spit", "hurt", "down"],
}
# Poses on one source sheet: an enemy with more is drawn from `<enemy>-sheet.png`, then
# `<enemy>-sheet-2.png`, ... in order.
SHEET_POSES = 4
# Enemies whose walk sheets (every sheet after the first) were generated later, at their own
# size: each such sheet's poses are first resized so their mean opaque area matches the first
# pose's, so the walk draws the creature as big as its other poses whatever size the model drew it.
WALK_MATCHED = {"squint", "big-squint", "bramble-boar", "thornball", "brood-warden", "shardback",
    "bone-marcher", "bone-thrower", "prologue-worm", "thorn-guard", "broodling", "cocoon-mimic",
    "crystal-mite", "bone-leaper"}
# Enemies whose poses stand with their weight (the middle of their opaque pixels) at x CENTRE_X
# instead of their box's middle, so a sword, a bow or a fist thrust out to one side does not push
# the body back; their scale keeps every pose inside FIT from that middle.
MASS_CENTRED = {"prologue-worm", "worm-swordsman", "worm-archer", "worm-brawler"}
# Enemies whose poses are centred in their cell instead of standing on BOTTOM: the Crystal Crawler
# turns round its middle as it crawls round its pillar.
CENTRED = {"crystal-crawler"}
# Enemies whose poses are placed by their body instead of their box: the middle of the body (the
# biggest blob left once BODY_CORE_PX is eroded off the opaque pixels, so legs, drips and spat goo
# are gone) sits at the cell's centre (x CENTRE_X, y CELL / 2), so the body stays put as the legs
# rear up or a spray shoots out on any side (the spiders spit up, down and sideways); their scale
# keeps every pose inside FIT / 2 of that middle. No pose reaches more than BODY_FLOOR_PX below the
# first pose's bottom (one reaching lower is lifted that much): the ground hides a body's pixels
# more than 12 px below its feet as a ghost (elevation_occlusion.gdshaderinc), so legs striding
# toward the viewer may not hang lower than the idle pose's.
BODY_ANCHORED = {"slime-spider", "orb-weaver"}
BODY_CORE_PX = 48
BODY_FLOOR_PX = 6
# Poses also packed mirrored, as extra frames after the sheet's (`<pose>-mirrored`): the spiders'
# front scuttle, whose mirror is the other stride (a walk cycle with no flip_h, which the facing
# code owns).
MIRRORED = {"slime-spider": ["scuttle"], "orb-weaver": ["scuttle"]}
# Sheets of props cut into pictures of their own (the Caverns' pens, rows 23 to 29): sheet ->
# [(picture, its poses (one scale), cell px, centred, output folder under godot/asset/MAPS)].
PROP_SHEETS = {
    "caverns-props": [
        ("crystal-pillar", ["pillar"], 256, False, "props/caverns"),
        ("pickaxe", ["pickaxe"], 64, True, "enemies"),
        ("brazier", ["brazier-unlit", "brazier-lit"], 256, False, "props/caverns"),
    ],
    # The skeletons' remains (rows 30 to 32): the Bone Thrower's thrown bone, the skull the Gulp
    # takes from a bone pile (the Bone Marcher's in its helmet), and the pile without its skull.
    "skeleton-props": [
        ("bone", ["bone"], 64, True, "enemies"),
        ("skull", ["skull"], 64, True, "enemies"),
        ("helmet-skull", ["helmet-skull"], 64, True, "enemies"),
        ("bone-pile", ["pile"], 128, True, "enemies"),
    ],
    # The worm soldiers' (rows 1 to 3): the archer's arrow (pointing right) and the three frames of
    # the brawler's punch hit.
    "worm-army-props": [
        ("worm-arrow", ["arrow"], 64, True, "enemies"),
        ("worm-brawler-hit", ["hit-a", "hit-b", "hit-c"], 64, True, "enemies"),
    ],
    # The spiders' webs (rows 15 and 16, and the Matron's volley): the spat web (the glob flying
    # right, bursting, the open net) and the web wrapped over the slime when one hits.
    "spider-webs": [
        ("spider-web", ["glob", "burst", "net"], 64, True, "enemies"),
        ("spider-web-cover", ["cover"], 128, True, "enemies"),
    ],
}
SEED_POSE = ("spitcap", "seed")
# Poses that hang from their top instead of standing on BOTTOM: the Pipe Worm's pipe is the same
# in each, so they line up by the pipe (their tops at the same y, the centre of their top HUNG_BAND
# rows at x CENTRE_X) and the pipe stays put as the worm comes out.
HUNG = {("pipe-worm", "hole"), ("pipe-worm", "up"), ("pipe-worm", "spit")}
HUNG_BAND = 0.3
# Single pictures (one image each, not a sheet): source name -> (cell px, fit px), centred, into
# godot/asset/MAPS/enemies/<cell>x<cell>-<name>.webp. The Pipe Worm's mud glob (a projectile).
SINGLES = {"mud-glob": (64, 56)}
# Sheets generated with a faint haze over the whole transparent background (alpha 2 or 3): alpha
# under HAZE_ALPHA is cleared before the cut, or each pose's box shows as a pale square.
HAZY = {"brood-props", "bone-leaper", "bone-thrower", "bone-marcher", "skeleton-props"}
HAZE_ALPHA = 12
# On a hazy sheet each pose keeps only the opaque parts within this many px of its main body.
MERGE_PX = 15
# Sheets (by the name before `-sheet`) with a fainter haze (alpha 16 at most, far from the art): it
# is cleared the same way, but their stray goo drops and sprays are kept (no main-body pass).
FAINT_HAZE = {"slime-spider", "orb-weaver", "spider-webs"}


def gap(mask: np.ndarray, axis: int) -> int:
    """The emptiest line (fewest opaque pixels) in the middle band, along `axis` (0: a column)."""
    counts = mask.sum(axis=axis)
    band = counts[GAP_FROM:GAP_TO]
    return GAP_FROM + int(np.argmin(band))


def trimmed(image: Image.Image) -> Image.Image:
    alpha = np.asarray(image)[..., 3]
    ys, xs = np.nonzero(alpha > ALPHA_CUT)
    if xs.size == 0:
        raise SystemExit("an empty pose")
    return image.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def cut_poses(path: Path) -> list[Image.Image]:
    """The sheet's four poses in reading order, trimmed."""
    sheet = Image.open(path).convert("RGBA")
    if path.name.removesuffix("-sheet.png") in HAZY or path.name.split("-sheet")[0] in FAINT_HAZE:
        pixels = np.asarray(sheet).copy()
        pixels[pixels[..., 3] < HAZE_ALPHA] = 0
        sheet = Image.fromarray(pixels, "RGBA")
    mask = np.asarray(sheet)[..., 3] > ALPHA_CUT
    split_y = gap(mask, 1)
    hazy = path.name.removesuffix("-sheet.png") in HAZY
    boxes: list[tuple[int, int, int, int]] = []
    split_x = gap(mask, 0)
    if mask[split_y].any() and not mask[:, split_x].any():
        # No empty row across the sheet but an empty column (a pose reaching into the other row's
        # band, as the Worm Brawler's punch up): the columns first, then each column's rows.
        rows = [gap(mask[:, left:right], 1) for left, right in ((0, split_x), (split_x, sheet.width))]
        boxes = [(0, 0, split_x, rows[0]), (split_x, 0, sheet.width, rows[1]),
            (0, rows[0], split_x, sheet.height), (split_x, rows[1], sheet.width, sheet.height)]
    else:
        for top, bottom in ((0, split_y), (split_y, sheet.height)):
            split_x = gap(mask[top:bottom], 0)
            boxes += [(0, top, split_x, bottom), (split_x, top, sheet.width, bottom)]
    poses: list[Image.Image] = []
    for box in boxes:
        pose = sheet.crop(box)
        poses.append(trimmed(main_body(pose) if hazy else pose))
    return poses


def main_body(image: Image.Image) -> Image.Image:
    """`image` with only its main body: the opaque pixels joined (within MERGE_PX) to the one
    nearest its middle; stray specks of the haze elsewhere are cleared."""
    from PIL import ImageDraw, ImageFilter

    alpha = np.asarray(image)[..., 3]
    solid = Image.fromarray(np.where(alpha > ALPHA_CUT, 255, 0).astype(np.uint8), "L")
    grown = solid.filter(ImageFilter.MaxFilter(MERGE_PX))
    ys, xs = np.nonzero(np.asarray(grown) > 0)
    if xs.size == 0:
        return image
    middle = np.array([image.width / 2, image.height / 2])
    nearest = int(np.argmin((xs - middle[0]) ** 2 + (ys - middle[1]) ** 2))
    ImageDraw.floodfill(grown, (int(xs[nearest]), int(ys[nearest])), 128)
    keep = np.asarray(grown) == 128
    pixels = np.asarray(image).copy()
    pixels[~keep] = 0
    return Image.fromarray(pixels, "RGBA")


def pack(enemy: str, names: list[str]) -> None:
    sheets = [f"{enemy}-sheet.png"] + [f"{enemy}-sheet-{index}.png"
        for index in range(2, (len(names) + SHEET_POSES - 1) // SHEET_POSES + 1)]
    cut = [cut_poses(SOURCES / name) for name in sheets]
    if enemy in WALK_MATCHED:
        cut = [cut[0]] + [matched(poses, cut[0][0]) for poses in cut[1:]]
    stills = [still for poses in cut for still in poses]
    frames = [(name, still) for name, still in zip(names, stills) if (enemy, name) != SEED_POSE]
    frames += [(f"{name}-mirrored", still.transpose(Image.Transpose.FLIP_LEFT_RIGHT))
        for name, still in list(frames) if name in MIRRORED.get(enemy, [])]
    scale = min(min(FIT / still.width, FIT / still.height) for _, still in frames)
    if enemy in MASS_CENTRED:
        scale = min([scale] + [FIT / 2 / max(mass_x(still), still.width - mass_x(still))
            for _, still in frames])
    cores = {name: body_core(still) for name, still in frames} if enemy in BODY_ANCHORED else {}
    if cores:
        scale = FIT / 2 / max(max(x, still.width - x, y, still.height - y)
            for (x, y), (_, still) in zip(cores.values(), frames))
    sheet = Image.new("RGBA", (CELL * len(frames), CELL), (0, 0, 0, 0))
    hung_heights = [round(still.height * scale) for name, still in frames if (enemy, name) in HUNG]
    hung_top = BOTTOM - max(hung_heights) if hung_heights else 0
    for column, (name, still) in enumerate(frames):
        size = (round(still.width * scale), round(still.height * scale))
        art = still.resize(size, Image.LANCZOS)
        left = CENTRE_X - size[0] // 2
        if enemy in MASS_CENTRED:
            left = CENTRE_X - round(mass_x(still) * scale)
        top = CELL // 2 - size[1] // 2 if enemy in CENTRED else BOTTOM - size[1]
        if (enemy, name) in HUNG:
            left, top = CENTRE_X - round(band_centre(still) * scale), hung_top
        if name in cores:
            left = CENTRE_X - round(cores[name][0] * scale)
            top = CELL // 2 - round(cores[name][1] * scale)
            first_core, first = cores[frames[0][0]], frames[0][1]
            floor = CELL // 2 - round(first_core[1] * scale) + round(first.height * scale) + BODY_FLOOR_PX
            top -= max(0, top + size[1] - floor)
            if top < 0:
                raise SystemExit(f"{enemy} {name}: lifted out of its cell")
        sheet.alpha_composite(art, (column * CELL + left, top))
        print(f"  {name:9s} {size[0]} x {size[1]}")
    out = OUTPUT / f"{CELL}x{CELL}-tile_{len(frames)}x1-{enemy}.webp"
    save_game_webp(sheet, out)
    print(f"wrote {out.relative_to(REPO)} (scale {scale:.4f})")
    for name, still in zip(names, stills):
        if (enemy, name) == SEED_POSE:
            seed_scale = min(SEED_FIT / still.width, SEED_FIT / still.height)
            size = (round(still.width * seed_scale), round(still.height * seed_scale))
            picture = Image.new("RGBA", (SEED_CELL, SEED_CELL), (0, 0, 0, 0))
            picture.alpha_composite(still.resize(size, Image.LANCZOS),
                ((SEED_CELL - size[0]) // 2, (SEED_CELL - size[1]) // 2))
            seed_out = OUTPUT / f"{SEED_CELL}x{SEED_CELL}-spore-seed.webp"
            save_game_webp(picture, seed_out)
            print(f"wrote {seed_out.relative_to(REPO)} ({size[0]} x {size[1]})")


def opaque_area(still: Image.Image) -> int:
    return int((np.asarray(still)[..., 3] > ALPHA_CUT).sum())


def matched(poses: list[Image.Image], first: Image.Image) -> list[Image.Image]:
    """`poses` (one later sheet, WALK_MATCHED) resized by one factor so their mean opaque area is
    `first`'s."""
    mean = sum(opaque_area(pose) for pose in poses) / len(poses)
    factor = (opaque_area(first) / max(1.0, mean)) ** 0.5
    return [pose.resize((max(1, round(pose.width * factor)), max(1, round(pose.height * factor))),
        Image.LANCZOS) for pose in poses]


def band_centre(still: Image.Image) -> float:
    """The x middle of the opaque pixels in the top HUNG_BAND of `still` (a hung pose's pipe)."""
    alpha = np.asarray(still)[: max(1, round(still.height * HUNG_BAND)), :, 3]
    xs = np.nonzero((alpha > ALPHA_CUT).any(axis=0))[0]
    return (xs.min() + xs.max() + 1) / 2 if xs.size else still.width / 2


def mass_x(still: Image.Image) -> float:
    """The x middle of `still`'s weight: the mean x of its opaque pixels (MASS_CENTRED)."""
    columns = (np.asarray(still)[..., 3] > ALPHA_CUT).sum(axis=0)
    return float((columns * (np.arange(columns.size) + 0.5)).sum() / max(1, columns.sum()))


def body_core(still: Image.Image) -> tuple[float, float]:
    """The middle (x, y) of `still`'s body (BODY_ANCHORED): the centroid of the biggest blob left
    after eroding BODY_CORE_PX off its opaque pixels (worked on a quarter-size mask)."""
    from PIL import ImageDraw, ImageFilter

    factor = 4
    alpha = np.asarray(still)[..., 3] > ALPHA_CUT
    size = (-(-still.width // factor), -(-still.height // factor))
    small = Image.fromarray(np.where(alpha, 255, 0).astype(np.uint8), "L").resize(size, Image.BOX)
    small = small.point(lambda value: 255 if value >= 128 else 0)
    for _ in range(BODY_CORE_PX // factor):
        small = small.filter(ImageFilter.MinFilter(3))
    label = 0
    while label < 254:
        ys, xs = np.nonzero(np.asarray(small) == 255)
        if xs.size == 0:
            break
        label += 1
        ImageDraw.floodfill(small, (int(xs[0]), int(ys[0])), label)
    labels = np.asarray(small)
    if label == 0:
        raise SystemExit("a pose with no body left after the erosion")
    biggest = 1 + int(np.argmax([(labels == value).sum() for value in range(1, label + 1)]))
    ys, xs = np.nonzero(labels == biggest)
    return (float(xs.mean()) + 0.5) * factor, (float(ys.mean()) + 0.5) * factor


def pack_single(name: str, cell: int, fit: int) -> None:
    """A one-image source (`<name>.png`), trimmed, scaled to fit `fit` px and centred in `cell`."""
    still = trimmed(Image.open(SOURCES / f"{name}.png").convert("RGBA"))
    scale = min(fit / still.width, fit / still.height)
    size = (round(still.width * scale), round(still.height * scale))
    picture = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    picture.alpha_composite(still.resize(size, Image.LANCZOS), ((cell - size[0]) // 2, (cell - size[1]) // 2))
    out = OUTPUT / f"{cell}x{cell}-{name}.webp"
    save_game_webp(picture, out)
    print(f"wrote {out.relative_to(REPO)} ({size[0]} x {size[1]})")


def pack_props(sheet_name: str, pictures: list) -> None:
    """A props sheet's poses (reading order) into pictures of their own, each picture's poses at one
    scale (the largest that fits them in its cell, 6 % margin), side by side, standing on its
    bottom (or centred)."""
    order = [name for _, names, _, _, _ in pictures for name in names]
    stills = dict(zip(order, cut_poses(SOURCES / f"{sheet_name}-sheet.png")))
    for picture, names, cell, centred, folder in pictures:
        fit = cell * 0.94
        scale = min(min(fit / stills[name].width, fit / stills[name].height) for name in names)
        sheet = Image.new("RGBA", (cell * len(names), cell), (0, 0, 0, 0))
        for column, name in enumerate(names):
            size = (round(stills[name].width * scale), round(stills[name].height * scale))
            top = (cell - size[1]) // 2 if centred else cell - round(cell * 0.03) - size[1]
            sheet.alpha_composite(stills[name].resize(size, Image.LANCZOS),
                (column * cell + (cell - size[0]) // 2, top))
            print(f"  {name:13s} {size[0]} x {size[1]}")
        tile = f"-tile_{len(names)}x1" if len(names) > 1 else ""
        out = REPO / "godot" / "asset" / "MAPS" / folder / f"{cell}x{cell}{tile}-{picture}.webp"
        out.parent.mkdir(parents=True, exist_ok=True)
        save_game_webp(sheet, out)
        print(f"wrote {out.relative_to(REPO)} (scale {scale:.4f})")


def main() -> None:
    # Optional arguments: only these enemies (e.g. `thornball broodling`); none: all of them.
    wanted = set(sys.argv[1:])
    unknown = wanted - set(POSES) - set(PROP_SHEETS) - set(SINGLES)
    if unknown:
        raise SystemExit(f"unknown: {', '.join(sorted(unknown))}")
    for enemy, names in POSES.items():
        if wanted and enemy not in wanted:
            continue
        print(enemy)
        pack(enemy, names)
    for sheet_name, pictures in PROP_SHEETS.items():
        if wanted and sheet_name not in wanted:
            continue
        print(sheet_name)
        pack_props(sheet_name, pictures)
    for name, (cell, fit) in SINGLES.items():
        if wanted and name not in wanted:
            continue
        print(name)
        pack_single(name, cell, fit)


if __name__ == "__main__":
    main()
