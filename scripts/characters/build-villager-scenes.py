"""Writes the scenes of the West town's villagers and animals (docs/godot/VILLAGERS.md "Scenes").

For each character packed by `pack-villagers.py` (its layout in
`asset/Originals/town/villagers/packed.json`) and listed in `CAST` below, writes
`godot/game/scenes/characters/villagers/<id>.tscn` (a villager: an NPC with VillagerScript) or
`godot/game/scenes/objects/animals/<id>.tscn` (an animal: Critter), the script on the scene's root
(so a placed one's settings are its own, in the Inspector), with its AnimationPlayer clips:

- villagers: `idle` (the first pose, a blink every 4 s, a soft jelly breath on the Visual's scale),
  `talk` (talk and laugh poses), and for walkers `walk-left/-right/-down/-up` (4 steps, the side row
  mirrored for left) and `idle-left/-right/-up` (a walk's first frame, breathing);
- animals: the clips named in their entry (frames by row and column).

A scene that exists is left alone (the owner may have edited it in Godot); `--force` rewrites the
named ones. Run it with the Godot editor closed or reload the scenes there after.

    python scripts/characters/build-villager-scenes.py            # every missing scene
    python scripts/characters/build-villager-scenes.py --force penny
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MANIFEST = REPO / "asset" / "Originals" / "town" / "villagers" / "packed.json"
VILLAGER_DIR = REPO / "godot" / "game" / "scenes" / "characters" / "villagers"
ANIMAL_DIR = REPO / "godot" / "game" / "scenes" / "objects" / "animals"
SCALE = 0.5  # 2 px per world unit
STEP_S = 0.12  # a walk step
BREATH = (1.012, 0.985)  # the Visual's scale at the top of a breath, x and y, times its own
BLINK_AT, BLINK_S, IDLE_S = 2.8, 0.15, 4.0

# The villagers: definition id = scene id. walk: speed px/s, pauses ms; route: a default loop of
# points (the owner drags them); radius: its own wander circle; size: a kid's scale against the
# packed height (their sheets are packed at adult height).
VILLAGER = "villager"
ANIMAL = "animal"
CAST: dict[str, dict] = {
    "penny": {"kind": VILLAGER, "walk": (34, 1200, 2600), "route": [(0, 0), (192, 0), (192, 128), (0, 128)]},
    "dollop": {"kind": VILLAGER},
    "burble": {"kind": VILLAGER},
    "crumb": {"kind": VILLAGER},
    "mayor-wobbleton": {"kind": VILLAGER},
    "bobbin": {"kind": VILLAGER},
    "auntie-suds": {"kind": VILLAGER},
    "dune": {"kind": VILLAGER},
    "granny-thistle": {"kind": VILLAGER},
    "sprig": {"kind": VILLAGER},
    "dot": {"kind": VILLAGER},
    "dab": {"kind": VILLAGER},
    "bram": {"kind": VILLAGER},
    "zing": {"kind": VILLAGER},
    "plum": {"kind": VILLAGER},
    "gramps-reel": {"kind": VILLAGER},
    "young-burr": {"kind": VILLAGER, "body": (20, 10)},
    "old-sedge": {"kind": VILLAGER, "walk": (24, 2000, 4500), "route": [(0, 0), (256, 0), (256, 96), (0, 96)]},
    "wick": {"kind": VILLAGER, "walk": (30, 2500, 4000), "route": [(0, 0), (224, 0), (224, 160), (0, 160)]},
    "tansy": {"kind": VILLAGER, "walk": (30, 1500, 3500), "radius": 160},
    "fizz": {"kind": VILLAGER, "walk": (52, 300, 900), "radius": 96, "body": (20, 10)},
    "tad": {"kind": VILLAGER, "walk": (48, 300, 900), "radius": 96, "body": (20, 10)},
    # the family: Dany follows Isa and Dan runs after Gavy (`follow`, set where they are placed);
    # until then they wander their own circles. Gavy and Dan climb over fences and walls (`climb`).
    "isa": {"kind": VILLAGER, "walk": (36, 2500, 6000), "radius": 240, "body": (18, 10)},
    "dany": {"kind": VILLAGER, "walk": (40, 300, 1200), "radius": 64, "body": (18, 10), "follow_radius": 40},
    "gavy": {"kind": VILLAGER, "walk": (64, 200, 700), "radius": 280, "body": (16, 8),
        "climb": {"climb_speed": 150.0, "climb_reach": 128.0, "climb_step": 16.0, "climb_height": 22.0,
            "climb_head_on": 0.5, "climb_rest_ms": 1500.0}},
    "dan": {"kind": VILLAGER, "walk": (60, 400, 1200), "radius": 96, "follow_radius": 56,
        "climb": {"climb_speed": 130.0, "climb_reach": 128.0, "climb_step": 16.0, "climb_height": 18.0,
            "climb_head_on": 0.5, "climb_rest_ms": 1500.0}},
    "may": {"kind": VILLAGER},
}


def quad(rest_a: str, rest_b: str) -> dict:
    """An animal's 2 x 2 pose sheet (idle, rest A, rest B, blink) and its walks."""
    return {
        "idle": {"frames": [("poses", 0, 0.0), ("poses", 3, BLINK_AT), ("poses", 0, BLINK_AT + BLINK_S)],
            "length": IDLE_S, "breath": True},
        rest_a: {"frames": [("poses", 1, 0.0)], "length": 0.6, "bob": [(0.0, 0), (0.3, 1)]},
        rest_b: {"frames": [("poses", 2, 0.0)], "length": 3.0, "breath": True},
        "walk": True, "bob": True,
    }


def bird(fly: list[int]) -> dict:
    """A 3 x 2 bird sheet: stand (side), peck, hop, wings up, wings down, front; `fly`: the flight's
    frames, in order."""
    flap = [("poses", f, i * 0.08) for i, f in enumerate(fly)]
    return {
        "idle": {"frames": [("poses", 5, 0.0)], "length": 1.6, "breath": True},
        "idle-right": {"frames": [("poses", 0, 0.0)], "length": 1.6, "breath": True},
        "idle-left": {"frames": [("poses", 0, 0.0)], "length": 1.6, "flip": True, "breath": True},
        "peck": {"frames": [("poses", 1, 0.0), ("poses", 0, 0.22), ("poses", 1, 0.5), ("poses", 0, 0.72)],
            "length": 1.3},
        "walk-right": {"frames": [("poses", 2, 0.0), ("poses", 0, 0.14)], "length": 0.28},
        "walk-left": {"frames": [("poses", 2, 0.0), ("poses", 0, 0.14)], "length": 0.28, "flip": True},
        "fly-right": {"frames": flap, "length": len(fly) * 0.08, "free": True},
        "fly-left": {"frames": flap, "length": len(fly) * 0.08, "flip": True, "free": True},
    }


def swimmer() -> dict:
    """A 3 x 2 swimming sheet: side, side bobbing, dabbling, toward, away, side blinking."""
    return {
        "idle": {"frames": [("poses", 0, 0.0), ("poses", 5, BLINK_AT), ("poses", 0, BLINK_AT + BLINK_S)],
            "length": IDLE_S, "bob": [(0.0, 0), (1.0, 1), (2.0, 0), (3.0, 1)]},
        "idle-left": {"frames": [("poses", 0, 0.0)], "length": 2.0, "flip": True, "bob": [(0.0, 0), (1.0, 1)]},
        "dabble": {"frames": [("poses", 2, 0.0), ("poses", 0, 1.2)], "length": 2.0},
        "walk-right": {"frames": [("poses", 0, 0.0), ("poses", 1, 0.3)], "length": 0.6},
        "walk-left": {"frames": [("poses", 0, 0.0), ("poses", 1, 0.3)], "length": 0.6, "flip": True},
        "walk-down": {"frames": [("poses", 3, 0.0)], "length": 0.6, "bob": [(0.0, 0), (0.3, 1)]},
        "walk-up": {"frames": [("poses", 4, 0.0)], "length": 0.6, "bob": [(0.0, 0), (0.3, 1)]},
    }


def butterfly(colour: int) -> dict:
    """One butterfly of the 3 x 2 sheet (top row open, bottom row closed): it flaps all the time."""
    flap = {"frames": [("poses", colour, 0.0), ("poses", colour + 3, 0.09)], "length": 0.18, "free": True}
    return {"idle": flap, "fly-right": flap, "fly-left": dict(flap, flip=True)}


SMALL = {"layer": 0, "mask": 1025}
BIRD_PROPS = {"pause_min_ms": 800.0, "pause_max_ms": 2600.0, "wander_radius": 96.0, "rest_clips": ["peck"],
    "rest_clip_chance": 0.6, "reaction": "fly", "notice_px": 76.0, "fly_px": 220.0, "fly_ms": 600.0,
    "gone_ms": 9000.0, "flight_chance": 0.3, "flight_height": 40.0, "flight_speed": 90.0}
CAST.update({
    "pig": {"kind": ANIMAL, "body": (40, 16), "layer": 128, "mask": 1027, "clips": quad("snuffle", "sleep"),
        "props": {"walk_speed": 18.0, "pause_min_ms": 1500.0, "pause_max_ms": 4500.0, "wander_radius": 96.0,
            "rest_clips": ["snuffle", "sleep"], "rest_clip_chance": 0.5, "reaction": "none"}},
    "piglet": {"kind": ANIMAL, "sheet": "pig", "size": 0.55, "body": (20, 10), **SMALL, "clips": "pig",
        "props": {"walk_speed": 22.0, "pause_min_ms": 600.0, "pause_max_ms": 2000.0, "wander_radius": 64.0,
            "follow_radius": 40.0, "catch_up_speed": 44.0, "rest_clips": ["snuffle"], "rest_clip_chance": 0.4,
            "reaction": "flee", "notice_px": 48.0, "flee_speed": 70.0, "flee_ms": 600.0}},
    "biscuit": {"kind": ANIMAL, "body": (22, 10), **SMALL, "clips": quad("sit", "bark"),
        "props": {"walk_speed": 40.0, "pause_min_ms": 600.0, "pause_max_ms": 2500.0, "wander_radius": 96.0,
            "follow_radius": 40.0, "catch_up_speed": 80.0, "rest_clips": ["sit", "bark"], "rest_clip_chance": 0.5,
            "reaction": "none"}},
    "cat": {"kind": ANIMAL, "body": (22, 10), **SMALL, "clips": quad("sleep", "stretch"),
        "props": {"walk_speed": 20.0, "pause_min_ms": 3000.0, "pause_max_ms": 9000.0, "wander_radius": 64.0,
            "rest_clips": ["sleep", "stretch"], "rest_clip_chance": 0.7, "reaction": "flee", "notice_px": 56.0,
            "flee_speed": 70.0, "flee_ms": 900.0}},
    "hen": {"kind": ANIMAL, "body": (18, 10), **SMALL, "clips": quad("peck", "nest"),
        "props": {"walk_speed": 22.0, "pause_min_ms": 800.0, "pause_max_ms": 2500.0, "wander_radius": 96.0,
            "rest_clips": ["peck", "nest"], "rest_clip_chance": 0.6, "reaction": "flee", "notice_px": 64.0,
            "flee_speed": 90.0, "flee_ms": 700.0}},
    "chick": {"kind": ANIMAL, "body": (8, 6), **SMALL,
        "clips": dict(bird([3, 4]), **{"walk-right": {"frames": [("poses", 3, 0.0), ("poses", 4, 0.1)], "length": 0.2},
            "walk-left": {"frames": [("poses", 3, 0.0), ("poses", 4, 0.1)], "length": 0.2, "flip": True}}),
        "props": {"walk_speed": 26.0, "pause_min_ms": 400.0, "pause_max_ms": 1500.0, "wander_radius": 48.0,
            "follow_radius": 36.0, "catch_up_speed": 60.0, "rest_clips": ["peck"], "rest_clip_chance": 0.6,
            "reaction": "flee", "notice_px": 48.0, "flee_speed": 80.0, "flee_ms": 500.0}},
    "sheep": {"kind": ANIMAL, "body": (34, 14), "layer": 128, "mask": 1027, "clips": quad("graze", "lie"),
        "props": {"walk_speed": 14.0, "pause_min_ms": 2000.0, "pause_max_ms": 6000.0, "wander_radius": 112.0,
            "rest_clips": ["graze", "lie"], "rest_clip_chance": 0.6, "reaction": "none"}},
    "duck": {"kind": ANIMAL, "body": (20, 10), "layer": 0, "mask": 0, "clips": swimmer(),
        "route": [(0, 0), (128, -24), (192, 40), (64, 72)],
        "props": {"walk_speed": 16.0, "pause_min_ms": 1500.0, "pause_max_ms": 4000.0, "rest_clips": ["dabble"],
            "rest_clip_chance": 0.3, "reaction": "none"}},
    "duckling": {"kind": ANIMAL, "body": (8, 6), "layer": 0, "mask": 0, "clips": swimmer(),
        "props": {"walk_speed": 18.0, "pause_min_ms": 300.0, "pause_max_ms": 1200.0, "follow_radius": 28.0,
            "catch_up_speed": 34.0, "rest_clips": ["dabble"], "rest_clip_chance": 0.2, "reaction": "none"}},
    "hedgehog": {"kind": ANIMAL, "body": (14, 8), **SMALL, "clips": quad("snuffle", "curl"),
        "props": {"walk_speed": 12.0, "pause_min_ms": 1500.0, "pause_max_ms": 4000.0, "wander_radius": 80.0,
            "rest_clips": ["snuffle"], "rest_clip_chance": 0.5, "reaction": "curl", "notice_px": 56.0,
            "calm_ms": 2500.0}},
    "squirrel": {"kind": ANIMAL, "body": (14, 8), **SMALL, "clips": quad("nibble", "alert"),
        "props": {"walk_speed": 50.0, "pause_min_ms": 1500.0, "pause_max_ms": 5000.0, "wander_radius": 160.0,
            "rest_clips": ["nibble", "alert"], "rest_clip_chance": 0.6, "reaction": "flee", "notice_px": 80.0,
            "flee_speed": 120.0, "flee_ms": 900.0}},
    "snail": {"kind": ANIMAL, "body": (10, 6), **SMALL,
        "clips": {
            "idle": {"frames": [("poses", 5, 0.0)], "length": 2.0, "breath": True},
            "idle-right": {"frames": [("poses", 0, 0.0)], "length": 2.0, "breath": True},
            "idle-left": {"frames": [("poses", 0, 0.0)], "length": 2.0, "flip": True, "breath": True},
            "walk-right": {"frames": [("poses", 0, 0.0), ("poses", 2, 0.3), ("poses", 1, 0.6), ("poses", 2, 0.9)],
                "length": 1.2},
            "walk-left": {"frames": [("poses", 0, 0.0), ("poses", 2, 0.3), ("poses", 1, 0.6), ("poses", 2, 0.9)],
                "length": 1.2, "flip": True},
            "hide": {"frames": [("poses", 3, 0.0)], "length": 1.0},
        },
        "props": {"walk_speed": 4.0, "pause_min_ms": 2000.0, "pause_max_ms": 6000.0, "wander_radius": 48.0,
            "reaction": "hide", "notice_px": 28.0, "calm_ms": 3000.0}},
    "robin": {"kind": ANIMAL, "body": (8, 6), **SMALL, "clips": bird([3, 4]),
        "props": dict(BIRD_PROPS, walk_speed=26.0)},
    "dove": {"kind": ANIMAL, "body": (10, 6), **SMALL, "clips": bird([3, 4]),
        "props": dict(BIRD_PROPS, walk_speed=20.0, flight_chance=0.2, flight_height=44.0, flight_speed=80.0,
            gone_ms=10000.0)},
    "bluebird": {"kind": ANIMAL, "body": (8, 6), **SMALL, "clips": bird([3, 4]),
        "props": dict(BIRD_PROPS, walk_speed=26.0)},
    "goldfinch": {"kind": ANIMAL, "body": (8, 6), **SMALL, "clips": bird([3, 4]),
        "props": dict(BIRD_PROPS, walk_speed=28.0, flight_chance=0.35)},
    "swallow": {"kind": ANIMAL, "body": (8, 6), "layer": 0, "mask": 0, "clips": bird([3, 4, 3, 4, 1, 1]),
        "props": dict(BIRD_PROPS, walk_speed=0.0, wander_radius=220.0, reaction="none", always_flying=True,
            flight_height=56.0, flight_speed=110.0)},
})
for _index, _colour in enumerate(("orange", "blue", "yellow")):
    CAST[f"butterfly-{_colour}"] = {"kind": ANIMAL, "sheet": "butterflies", "body": (6, 4), "layer": 0, "mask": 0,
        "clips": butterfly(_index),
        "props": {"wander_radius": 64.0, "always_flying": True, "flight_height": 18.0, "flight_speed": 30.0,
            "fly_ms": 400.0, "reaction": "none"}}


def fmt(value: float) -> str:
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return text if text not in ("", "-0") else "0"


class Scene:
    def __init__(self) -> None:
        self.ext: list[str] = []
        self.sub: list[str] = []
        self.nodes: list[str] = []

    def add_ext(self, kind: str, path: str) -> str:
        rid = f"{len(self.ext) + 1}"
        self.ext.append(f'[ext_resource type="{kind}" path="{path}" id="{rid}"]')
        return rid

    def add_sub(self, kind: str, rid: str, body: list[str]) -> str:
        self.sub.append("\n".join([f'[sub_resource type="{kind}" id="{rid}"]'] + body))
        return rid

    def text(self) -> str:
        return "\n\n".join(["[gd_scene format=3]", "\n".join(self.ext)] + self.sub + self.nodes) + "\n"


def track(index: int, path: str, times: list[float], values: list[str], update: int, interp: int = 1) -> list[str]:
    return [
        f'tracks/{index}/type = "value"',
        f"tracks/{index}/imported = false",
        f"tracks/{index}/enabled = true",
        f'tracks/{index}/path = NodePath("{path}")',
        f"tracks/{index}/interp = {interp}",
        f"tracks/{index}/loop_wrap = true",
        f"tracks/{index}/keys = {{",
        f'"times": PackedFloat32Array({", ".join(fmt(t) for t in times)}),',
        f'"transitions": PackedFloat32Array({", ".join("1" for _ in times)}),',
        f'"update": {update},',
        f'"values": [{", ".join(values)}]',
        "}",
    ]


def clip(scene: Scene, name: str, spec: dict, layout: dict, scale: float) -> str:
    """One Animation sub-resource: frames (row name, column, time), `length`, `flip`, `breath`
    (the Visual's scale breathing), `bob` [(time, px up)], `free` (no position track: code moves
    the picture, a bird's flight)."""
    columns = layout["columns"]
    times = [t for _, _, t in spec["frames"]]
    frames = [str(layout["rows"][row]["row"] * columns + column) for row, column, _ in spec["frames"]]
    body = [f'resource_name = "{name}"', f"length = {fmt(spec['length'])}", "loop_mode = 1", "step = 0.01"]
    body += track(0, "Visual:frame", times, frames, 1)
    body += track(1, "Visual:flip_h", [0.0], ["true" if spec.get("flip") else "false"], 1)
    base = f"Vector2({fmt(scale)}, {fmt(scale)})"
    if spec.get("breath"):
        top = f"Vector2({fmt(scale * BREATH[0])}, {fmt(scale * BREATH[1])})"
        half = spec["length"] / 4
        body += track(2, "Visual:scale", [0.0, half, half * 2, half * 3], [base, top, base, top], 0, 2)
    else:
        body += track(2, "Visual:scale", [0.0], [base], 1)
    if not spec.get("free"):
        bob = spec.get("bob", [(0.0, 0)])
        body += track(3, "Visual:position", [t for t, _ in bob], [f"Vector2(0, {fmt(-px)})" for _, px in bob], 1)
    rid = f"Animation_{name.replace('-', '_')}"
    return scene.add_sub("Animation", rid, body)


def villager_clips(layout: dict) -> dict:
    rows = layout["rows"]
    clips = {
        "idle": {"frames": [("poses", 0, 0.0), ("poses", 1, BLINK_AT), ("poses", 0, BLINK_AT + BLINK_S)],
            "length": IDLE_S, "breath": True},
        "talk": {"frames": [("poses", 2, 0.0), ("poses", 0, 0.3), ("poses", 2, 0.45), ("poses", 3, 0.75),
            ("poses", 0, 1.0)], "length": 1.2},
    }
    clips.update(walk_clips(rows, False))
    return clips


def walk_clips(rows: dict, bob: bool) -> dict:
    clips: dict = {}
    for facing, row, flip in (("right", "walk-side", False), ("left", "walk-side", True),
            ("down", "walk-down", False), ("up", "walk-up", False)):
        if row not in rows:
            continue
        steps = rows[row]["frames"]
        clips[f"walk-{facing}"] = {"frames": [(row, i, i * STEP_S) for i in range(steps)],
            "length": steps * STEP_S, "flip": flip,
            "bob": [(i * STEP_S, i % 2) for i in range(steps)] if bob else [(0.0, 0)]}
        clips[f"idle-{facing}"] = {"frames": [(row, 0, 0.0)], "length": IDLE_S, "flip": flip, "breath": True}
    clips.pop("idle-down", None)
    return clips


def build(cid: str, manifest: dict) -> Path:
    spec = CAST[cid]
    sheet_id = spec.get("sheet", cid)
    layout = manifest[sheet_id]
    scale = SCALE * spec.get("size", 1.0)
    scene = Scene()
    sheet_script = scene.add_ext("Script", "res://game/runtime/sheet_sprite.gd")
    anim_script = scene.add_ext("Script", "res://game/runtime/animation_player.gd")
    glow_script = scene.add_ext("Script", "res://game/prologue/soft_glow.gd")
    guide_script = scene.add_ext("Script", "res://game/world/villagers/wander_guide.gd")
    villager = spec["kind"] == VILLAGER
    main_script = scene.add_ext("Script", "res://game/world/villagers/villager_script.gd" if villager
        else "res://game/world/villagers/critter.gd")
    body_w, body_h = spec.get("body", (28, 14))
    body_w, body_h = round(body_w * spec.get("size", 1.0)), round(body_h * spec.get("size", 1.0))
    scene.add_sub("RectangleShape2D", "body_shape", [f"size = Vector2({body_w}, {body_h})"])
    if villager:
        clips = villager_clips(layout)
    else:
        source = spec["clips"] if isinstance(spec["clips"], dict) else CAST[spec["clips"]]["clips"]
        clips = {k: v for k, v in source.items() if isinstance(v, dict)}
        if source.get("walk"):
            clips.update(walk_clips(layout["rows"], bool(source.get("bob"))))
    ids = {name: clip(scene, name, c, layout, scale) for name, c in clips.items()}
    library = ["_data = {"] + [f'&"{name}": SubResource("{rid}"),' for name, rid in ids.items()]
    library[-1] = library[-1].rstrip(",")
    scene.add_sub("AnimationLibrary", "AnimationLibrary_1", library + ["}"])
    route = spec.get("route")
    if route:
        points = ", ".join(f"0, 0, 0, 0, {x}, {y}" for x, y in route)
        scene.add_sub("Curve2D", "Curve2D_route", ["_data = {", f'"points": PackedVector2Array({points})', "}",
            f"point_count = {len(route)}"])

    cell, foot = layout["cell"], layout["foot"]
    # The script sits on the root, so a placed villager's or animal's settings (its wander circle,
    # route, follow, climbing) are the instance's own: shown in the Inspector and kept on save.
    root = [f'[node name="{cid}" type="CharacterBody2D" node_paths=PackedStringArray('
        + ('"body", ' if villager else "") + '"visual", "animation")]',
        f"collision_layer = {spec.get('layer', 128)}",
        f"collision_mask = {spec.get('mask', 1027)}",
        "motion_mode = 1",
        "wall_min_slide_angle = 0.0"]
    if villager:
        walk = spec.get("walk")
        root += [f'script = ExtResource("{main_script}")', 'body = NodePath(".")', 'visual = NodePath("Visual")',
            'animation = NodePath("Animation")', f'character_id = "{cid}"', f'npc_definition_id = "{cid}"']
        if walk:
            root += [f"wander_speed = {fmt(walk[0])}", f"pause_min_ms = {fmt(walk[1])}", f"pause_max_ms = {fmt(walk[2])}"]
        root.append(f"body_bounds = Rect2({fmt(-body_w / 2)}, {fmt(-body_h)}, {body_w}, {body_h})")
        if spec.get("radius"):
            root.append(f"wander_radius = {fmt(spec['radius'])}")
        if spec.get("follow_radius"):
            root.append(f"follow_radius = {fmt(spec['follow_radius'])}")
        if spec.get("climb"):
            root.append("climbs_over = true")
            root += [f"{key} = {fmt(value)}" for key, value in spec["climb"].items()]
        root.append(f"name_tag_rise = {fmt(layout['height'] * spec.get('size', 1.0) + 6)}")
    else:
        root += [f'script = ExtResource("{main_script}")', 'visual = NodePath("Visual")', 'animation = NodePath("Animation")']
        for key, value in spec.get("props", {}).items():
            if isinstance(value, list):
                root.append(f"{key} = PackedStringArray({', '.join(json.dumps(v) for v in value)})")
            elif isinstance(value, str):
                root.append(f'{key} = "{value}"')
            elif isinstance(value, bool):
                # Before fmt: True would come out as 1, which the editor reads as false on an
                # instance's override (area write-back of west-village-b4, 2026-11-11).
                root.append(f"{key} = {'true' if value else 'false'}")
            else:
                root.append(f"{key} = {fmt(value)}")
        root.append(f"body_bounds = Rect2({fmt(-body_w / 2)}, {fmt(-body_h)}, {body_w}, {body_h})")
    scene.nodes.append("\n".join(root))
    shadow_w = max(6.0, body_w * 0.8)
    scene.nodes.append("\n".join([
        '[node name="Shadow" type="Node2D" parent="."]', "z_index = -1", f'script = ExtResource("{glow_script}")',
        f"radius = Vector2({fmt(shadow_w)}, {fmt(max(3.0, shadow_w * 0.3))})", "color = Color(0.05, 0.08, 0.03, 0.35)",
        "additive = false", "pulse = 0.0"]))
    scene.nodes.append("\n".join([
        '[node name="BodyShape" type="CollisionShape2D" parent="."]', f"position = Vector2(0, {fmt(-body_h / 2)})",
        'shape = SubResource("body_shape")']))
    scene.nodes.append("\n".join([
        '[node name="Visual" type="Sprite2D" parent="."]', f"scale = Vector2({fmt(scale)}, {fmt(scale)})",
        "centered = false", f"offset = Vector2({-cell // 2}, {-(cell - foot)})",
        f"hframes = {layout['columns']}", f"vframes = {len(layout['rows'])}", f'script = ExtResource("{sheet_script}")',
        f'sheet_path = "{layout["sheet"]}"']))
    scene.nodes.append("\n".join([
        '[node name="Animation" type="AnimationPlayer" parent="."]', f'script = ExtResource("{anim_script}")',
        "libraries/ = SubResource(\"AnimationLibrary_1\")", "callback_mode_process = 0", 'autoplay = &"idle"',
        "randomize_start = true"]))
    scene.nodes.append("\n".join([
        '[node name="WanderGuide" type="Node2D" parent="." node_paths=PackedStringArray("source")]',
        f'script = ExtResource("{guide_script}")', 'source = NodePath("..")']))
    if route:
        scene.nodes.append("\n".join(['[node name="Route" type="Path2D" parent="."]', 'curve = SubResource("Curve2D_route")']))
    out = (VILLAGER_DIR if villager else ANIMAL_DIR) / f"{cid}.tscn"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(scene.text(), encoding="utf-8")
    return out


def main() -> None:
    args = sys.argv[1:]
    force = "--force" in args
    wanted = [a for a in args if a != "--force"] or list(CAST)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for cid in wanted:
        if cid not in CAST:
            raise SystemExit(f"unknown: {cid}")
        if CAST[cid].get("sheet", cid) not in manifest:
            print(f"skip {cid}: not packed")
            continue
        out = (VILLAGER_DIR if CAST[cid]["kind"] == VILLAGER else ANIMAL_DIR) / f"{cid}.tscn"
        if out.exists() and not force:
            print(f"keep {out.relative_to(REPO)}")
            continue
        print(f"wrote {build(cid, manifest).relative_to(REPO)}")


if __name__ == "__main__":
    main()
