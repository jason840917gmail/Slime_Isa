"""Generate one object scene per interior atlas sprite from interior_catalog.py.

Each scene is `object.interior-<category>-<name>` written to
src/game/content/scenes/authored/objects/interiors/<category>/. Solid sprites
get a StaticBody2D whose footprint collider is derived from the sprite's alpha
bounds; the rest are plain Node2D roots. Every visual is bottom-centre anchored
and world-sorted, matching the rest of the object library.

Generated scenes are ordinary authored scenes: tweak them in Scene Studio, but
re-running this tool overwrites catalog-owned files and deletes scenes in the
interiors folder that the catalog no longer lists.

Usage: python scripts/interiors/generate-interior-scenes.py [--check]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from interior_catalog import DERIVED, ROWS, SHEETS, footprint_share, is_bed, is_workbench  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = json.loads((ROOT / "asset" / "assets.json").read_text(encoding="utf-8"))
OUT = ROOT / "src" / "game" / "content" / "scenes" / "authored" / "objects" / "interiors"

FOOTPRINT_WIDTH = 0.88  # share of the visible width that blocks movement
FOOTPRINT_DEPTH = 0.42  # share of the visible height used as footprint depth
FOOTPRINT_MIN, FOOTPRINT_MAX = 12.0, 44.0
SLEEP_HEIGHT = 0.55  # the sleeping slime sits this far up the visible bed art
WAKE_DEPTH = 16      # wake/respawn point: just in front of the bed's footprint
BADGE_GAP = 8        # key badge floats this far above the bed art


class Atlas:
    def __init__(self, asset_id: str):
        source = MANIFEST["assets"][asset_id]["source"]
        self.asset_id = asset_id
        self.image = Image.open(ROOT / "asset" / source["path"]).convert("RGBA")
        self.frame = source["frame"]["w"]
        self.cols = source["frame"]["cols"]
        self.count = source["frame"].get("count", self.cols * source["frame"]["rows"])

    def bounds(self, index: int):
        x, y = (index % self.cols) * self.frame, (index // self.cols) * self.frame
        return self.image.crop((x, y, x + self.frame, y + self.frame)).getbbox()


def number(value: float):
    rounded = round(value, 4)
    return int(rounded) if float(rounded).is_integer() else rounded


def scene_document(category: str, name: str, atlas: Atlas, frame: int, kind: str, scale: float, rotation: float):
    bounds = atlas.bounds(frame)
    if bounds is None:
        raise SystemExit(f"{category}/{name}: atlas frame {frame} is empty")
    x0, y0, x1, y1 = bounds
    fw = atlas.frame
    scene_slug = f"interior-{category}-{name}"
    sprite_res, shape_res = f"{scene_slug}.sprite", f"{scene_slug}.shape"
    solid = kind in ("solid", "block", "backdrop")
    root = "body" if solid else "root"
    visual = {
        "texture": {"resourceId": sprite_res},
        "frame": frame,
        "origin": [0.5, 1],
        "scale": [number(scale), number(scale)],
        "visualOffset": [0, 0],
        "depthMode": "world-sorted",
        "depthBand": "ground-decals" if kind in ("decal", "backdrop") else "world-entities",
    }
    if kind in ("block", "backdrop"):
        # Room-shell slices block their whole visible rectangle so wall runs have no gaps.
        shape = {"shape": "rectangle", "width": number((x1 - x0) * scale), "height": number((y1 - y0) * scale)}
        shape_position = [number(((x0 + x1) / 2 - fw / 2) * scale), number(-(fw - (y0 + y1) / 2) * scale)]
    elif rotation:
        # Turn the art about its own centre so the node sits in the middle of it.
        visual["origin"] = [0.5, number((y0 + y1) / 2 / fw)]
        visual["rotation"] = number(rotation)
        shape = {"shape": "rectangle", "width": number((y1 - y0) * scale * 0.9), "height": number((x1 - x0) * scale)}
        shape_position = [0, 0]
    else:
        share = footprint_share(category, name)
        depth = ((y1 - y0) * scale * share if share is not None
                 else max(FOOTPRINT_MIN, min((y1 - y0) * scale * FOOTPRINT_DEPTH, FOOTPRINT_MAX)))
        shape = {"shape": "rectangle", "width": number((x1 - x0) * scale * FOOTPRINT_WIDTH), "height": number(depth)}
        shape_position = [number(((x0 + x1) / 2 - fw / 2) * scale), number(-(fw - y1) * scale - depth / 2)]

    root_properties = {"collisionLayer": 1, "collisionMask": 0, "position": [0, 0]} if solid else {"position": [0, 0]}
    nodes = [{"id": root, "name": name, "type": "StaticBody2D" if solid else "Node2D", "parentId": None, "order": 0,
              "properties": root_properties}]
    subresources = [{"version": 1, "resourceId": sprite_res, "kind": "sprite-sheet", "assetId": atlas.asset_id,
                     "frameWidth": fw, "frameHeight": fw}]
    if solid:
        nodes.append({"id": "body-shape", "name": "BodyShape", "type": "CollisionShape2D", "parentId": root, "order": 0,
                      "properties": {"shape": {"resourceId": shape_res}, "position": shape_position}})
        subresources.append({"version": 1, "resourceId": shape_res, "kind": "collision-shape", "value": shape})
    nodes.append({"id": "visual", "name": "Visual", "type": "Sprite2D", "parentId": root, "order": len(nodes) - 1,
                  "properties": visual})
    if is_bed(category, name):
        top, bottom = -(fw - y0) * scale, -(fw - y1) * scale
        centre_x = ((x0 + x1) / 2 - fw / 2) * scale
        nodes.append({"id": "script", "name": "BedScript", "type": "ScriptNode", "scriptId": "game.bed", "parentId": root,
                      "order": len(nodes) - 1, "properties": {
                          "prompt": "Sleep",
                          "interactRadius": number(max(90, (x1 - x0) * scale / 2 + 40)),
                          "badgeRise": number(-top + BADGE_GAP),
                          "sleepPoint": [number(centre_x), number(bottom + (top - bottom) * SLEEP_HEIGHT)],
                          "wakePoint": [number(centre_x), WAKE_DEPTH],
                      }})
    if is_workbench(category, name):
        top = -(fw - y0) * scale
        nodes.append({"id": "script", "name": "WorkbenchScript", "type": "ScriptNode", "scriptId": "game.workbench",
                      "parentId": root, "order": len(nodes) - 1, "properties": {
                          "prompt": "Use workbench",
                          "recipeContext": "workbench",
                          "interactRadius": number(max(90, (x1 - x0) * scale / 2 + 40)),
                          "badgeRise": number(-top + BADGE_GAP),
                      }})
    return {"version": 1, "sceneId": f"object.{scene_slug}", "rootNodeId": root, "nodes": nodes,
            "instances": [], "subresources": subresources}


def main() -> None:
    check = "--check" in sys.argv
    atlases = {category: Atlas(asset_id) for category, asset_id in SHEETS.items()}

    uncovered = [f"{category}:{index}" for category, atlas in atlases.items() for index in range(atlas.count)
                 if atlas.bounds(index) is not None and (category, index) not in ROWS]
    if uncovered:
        raise SystemExit(f"atlas sprites missing from the catalog: {', '.join(uncovered)}")

    rows = [(category, name, frame, kind, scale, 0.0) for (category, frame), (name, kind, scale) in ROWS.items()]
    rows += [(category, name, frame, kind, scale, rotation) for name, (category, frame, kind, scale, rotation) in DERIVED.items()]

    expected: dict[Path, str] = {}
    for category, name, frame, kind, scale, rotation in rows:
        path = OUT / category / f"interior-{category}-{name}.scene.json"
        if path in expected:
            raise SystemExit(f"duplicate scene name {category}/{name}")
        document = scene_document(category, name, atlases[category], frame, kind, scale, rotation)
        expected[path] = json.dumps(document, indent=2, ensure_ascii=False) + "\n"

    existing = set(OUT.rglob("*.scene.json")) if OUT.exists() else set()
    stale = sorted(existing - set(expected))
    changed = [path for path, text in expected.items()
               if not path.exists() or path.read_text(encoding="utf-8").replace("\r\n", "\n") != text]
    if check:
        if stale or changed:
            raise SystemExit(f"interior scenes out of date: {len(changed)} changed, {len(stale)} stale")
        print(f"interior scenes OK - {len(expected)} scene(s)")
        return
    for path in stale:
        path.unlink()
    for path in changed:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected[path], encoding="utf-8", newline="\n")
    print(f"interior scenes: {len(expected)} total, {len(changed)} written, {len(stale)} removed")


if __name__ == "__main__":
    main()
