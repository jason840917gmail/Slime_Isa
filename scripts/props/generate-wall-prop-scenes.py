"""Generate the wall prop object scenes used to build cave and forest walls.

Each prop is a real object scene (like interior furniture and rock walls): a
StaticBody2D with a collision footprint, and a world-sorted Sprite2D whose
occlusion bounds are measured from the art. Worlds place one instance per
former wall cell (scripts/maps/convert-wall-tiles.mjs).

The footprint is deliberately wider/deeper than the visible base: bodies sit on
the 64px cell grid, so neighbouring footprints (48x44) leave gaps smaller than
the player's 30x26 body and a mass of props stays a solid barrier. Visual
variety comes from per-instance visualOffset/scale overrides, never from moving
the body.

Writes src/game/content/scenes/authored/objects/<family>--<variant>.scene.json.
Requires Pillow and numpy.

Usage: python scripts/props/generate-wall-prop-scenes.py
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OBJECTS = ROOT / "src" / "game" / "content" / "scenes" / "authored" / "objects"
MANIFEST = json.loads((ROOT / "asset" / "assets.json").read_text(encoding="utf8"))

FOOTPRINT = {"shape": "rectangle", "width": 48, "height": 44}
ALPHA_THRESHOLD = 32

# family -> (asset id, {variant: frame})
FAMILIES: dict[str, tuple[str, dict[str, int]]] = {
    "crystal-cluster-wall": ("sheet.rocks.crystal-clusters.8x2", {f"{index + 1:02d}": index for index in range(16)}),
    "tree-forest-wall": ("sheet.trees.8x6", {
        "pine-02": 18, "pine-03": 19, "pine-04": 20, "pine-06": 22, "pine-07": 23,
        "green-tree-05": 29, "green-tree-06": 30, "green-tree-07": 31,
    }),
}


def occlusion_bounds(sheet: np.ndarray, frame: int, width: int, height: int, columns: int) -> dict[str, int]:
    x0, y0 = (frame % columns) * width, (frame // columns) * height
    alpha = sheet[y0:y0 + height, x0:x0 + width, 3] > ALPHA_THRESHOLD
    ys, xs = np.nonzero(alpha)
    return {"width": int(xs.max() - xs.min() + 1), "height": int(ys.max() - ys.min() + 1), "offsetX": int(xs.min()), "offsetY": int(ys.min())}


def scene(family: str, variant: str, asset_id: str, frame: int, frame_size: tuple[int, int], bounds: dict[str, int]) -> dict:
    prefix = f"{family}.{variant}"
    return {
        "version": 1,
        "sceneId": f"object.{family}.{variant}",
        "rootNodeId": "body",
        "nodes": [
            {"id": "body", "name": "Body", "type": "StaticBody2D", "parentId": None, "order": 0,
             "properties": {"collisionLayer": 1, "collisionMask": 0, "position": [0, 0]}},
            {"id": "body-shape", "name": "BodyShape", "type": "CollisionShape2D", "parentId": "body", "order": 0,
             "properties": {"shape": {"resourceId": f"{prefix}.shape"}, "position": [0, -FOOTPRINT["height"] // 2]}},
            {"id": "visual", "name": "Visual", "type": "Sprite2D", "parentId": "body", "order": 1,
             "properties": {"texture": {"resourceId": f"{prefix}.sprite"}, "frame": frame, "origin": [0.5, 1], "scale": [1, 1],
                            "visualOffset": [0, 0], "depthMode": "world-sorted", "depthBand": "world-entities", "occlusionBounds": bounds}},
        ],
        "instances": [],
        "subresources": [
            {"version": 1, "resourceId": f"{prefix}.sprite", "kind": "sprite-sheet", "assetId": asset_id,
             "frameWidth": frame_size[0], "frameHeight": frame_size[1]},
            {"version": 1, "resourceId": f"{prefix}.shape", "kind": "collision-shape", "value": FOOTPRINT},
        ],
    }


def main() -> None:
    written = 0
    for family, (asset_id, variants) in FAMILIES.items():
        source = MANIFEST["assets"][asset_id]["source"]
        frame = source["frame"]
        sheet = np.asarray(Image.open(ROOT / "asset" / source["path"]).convert("RGBA"))
        for variant, index in variants.items():
            bounds = occlusion_bounds(sheet, index, frame["w"], frame["h"], frame["cols"])
            document = scene(family, variant, asset_id, index, (frame["w"], frame["h"]), bounds)
            path = OBJECTS / f"{family}--{variant}.scene.json"
            path.write_bytes((json.dumps(document, indent=2) + "\n").replace("\n", "\r\n").encode())
            written += 1
    print(f"wrote {written} wall prop scenes")


if __name__ == "__main__":
    main()
