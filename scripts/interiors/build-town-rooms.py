"""Writes the West town's rooms (docs/godot/VILLAGERS.md "Rooms"): one room world behind every house
door, the shops and the family home with their villagers inside, the other homes (`HOMES`) furnished
by kind of home and empty for now.

Each room is level-1's slime-home shell (`godot/game/scenes/worlds/rooms/c4/slime-home.tscn`: 14 x 11
cells, the timber floor on `ground`, the walls and beams of the "interior structure" source on
`old-props`; the old room's furniture is left out), a `south` way out at the bottom wall (its leaves cut
from `interior-timber-door.webp`) that leads to the door `<room id>-door` in its town chunk, the
room's furniture as nodes (`ROOMS`: interior object scenes and where they stand), its villagers under
`NPCs`, and the house ambience and music. The owner improves the rooms in Godot ("we can improve the
rooms later", 2026-11-01): a room that exists is never rewritten unless `--force` names it.

    python scripts/interiors/build-town-rooms.py                  # every missing room
    python scripts/interiors/build-town-rooms.py --force west-village-inn
"""

from __future__ import annotations

import base64
import re
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GODOT = REPO / "godot"
SHELL = GODOT / "game" / "scenes" / "worlds" / "rooms" / "c4" / "slime-home.tscn"
OUT_DIR = GODOT / "game" / "scenes" / "worlds" / "rooms" / "west-village"
INTERIORS = "res://game/scenes/objects/interiors/"
VILLAGERS = "res://game/scenes/characters/villagers/"
TOWN = "west-village-b4"
# The old-props source that holds the walls and beams (props_tileset.tres "interior structure").
STRUCTURE_SOURCE = 16
DOOR_AT = (448, 694)
SPAWN = (448, 624)

# Every room's lights and plants: (scene under INTERIORS, x, y[, scale]).
COMMON = [("decor/interior-decor-lantern-lit", 112, 176), ("decor/interior-decor-lantern-lit", 784, 176),
    ("decor/interior-decor-plant-potted-large", 112, 600, 1.3), ("decor/interior-decor-plant-potted-large", 784, 600, 1.3)]
# room id -> furniture [(scene under INTERIORS, x, y[, scale])] (the art is drawn small for these
# rooms: the main pieces stand at 1.3 to 1.6), villagers [(id, x, y)], town (the chunk its door
# leads out to; TOWN when not given)
ROOMS: dict[str, dict] = {
    "west-village-shop": {
        "furniture": [("specialty/interior-specialty-counter-shop", 380, 330, 1.6), ("specialty/interior-specialty-counter-shop-side", 560, 330, 1.6),
            ("specialty/interior-specialty-potion-shelf", 240, 210, 1.4), ("mushroom-large/interior-mushroom-large-potion-shelf-tall", 660, 220, 1.2),
            ("specialty/interior-specialty-shelves-empty", 448, 200, 1.4), ("specialty/interior-specialty-merchant-scale", 300, 300, 1.3),
            ("storage/interior-storage-barrel-lidded", 160, 300, 1.4), ("storage/interior-storage-crate-open", 740, 330, 1.4),
            ("storage/interior-storage-sack-grain", 200, 520, 1.4), ("kitchen/interior-kitchen-basket-vegetables", 700, 520, 1.4),
            ("decor/interior-decor-rug-green-large", 448, 500, 1.6)],
        "villagers": [("dollop", 448, 270)],
    },
    "west-village-inn": {
        "furniture": [("specialty/interior-specialty-bar-counter", 280, 300, 1.5), ("specialty/interior-specialty-bar-counter-side", 420, 300, 1.5),
            ("specialty/interior-specialty-bottle-rack", 250, 200, 1.4), ("specialty/interior-specialty-wine-rack", 400, 200, 1.4),
            ("specialty/interior-specialty-keg-stand", 120, 260, 1.4), ("specialty/interior-specialty-mug-tray", 330, 290, 1.3),
            ("tables/interior-tables-dining-blue-runner-s", 640, 440, 1.3), ("seating/interior-seating-chair-blue-cushion-e", 550, 440, 1.3),
            ("seating/interior-seating-chair-blue-cushion-w", 730, 440, 1.3), ("specialty/interior-specialty-tavern-sign", 660, 190, 1.4),
            ("decor/interior-decor-rug-round-blue", 640, 470, 1.6), ("decor/interior-decor-firewood-basket", 760, 250, 1.3)],
        "villagers": [("burble", 330, 255), ("dune", 550, 470)],
    },
    "west-village-bakery": {
        "furniture": [("kitchen/interior-kitchen-clay-oven-baking", 448, 230, 1.6), ("kitchen/interior-kitchen-dough-board", 300, 360, 1.5),
            ("kitchen/interior-kitchen-prep-table", 600, 360, 1.5), ("kitchen/interior-kitchen-basket-bread", 180, 500, 1.5),
            ("specialty/interior-specialty-bread-cheese-platter", 600, 330, 1.3), ("kitchen/interior-kitchen-pantry-shelf", 720, 210, 1.4),
            ("kitchen/interior-kitchen-dish-shelf", 180, 210, 1.4), ("storage/interior-storage-sack-grain", 270, 230, 1.4),
            ("storage/interior-storage-sacks-bundled", 740, 500, 1.4), ("decor/interior-decor-rug-green-small", 448, 520, 1.6)],
        "villagers": [("crumb", 448, 360)],
    },
    "west-village-town-hall": {
        "furniture": [("tables/interior-tables-desk-with-chair-s", 448, 320, 1.4), ("storage/interior-storage-bookshelf-books-s", 220, 220, 1.4),
            ("storage/interior-storage-bookshelf-books-s", 676, 220, 1.4), ("decor/interior-decor-banner-green", 340, 180, 1.4),
            ("decor/interior-decor-banner-green", 556, 180, 1.4), ("decor/interior-decor-rug-green-large", 448, 500, 1.6),
            ("decor/interior-decor-books-stacked", 160, 500, 1.4), ("seating/interior-seating-bench-green-s", 300, 520, 1.3),
            ("seating/interior-seating-bench-green-s", 600, 520, 1.3)],
        "villagers": [("mayor-wobbleton", 448, 400)],
    },
    "west-village-tailor": {
        "town": "west-village-a4",
        "furniture": [("workshop/interior-workshop-cloth-bolt-rack", 240, 220, 1.5), ("workshop/interior-workshop-cloth-bolt-rack", 400, 210, 1.5),
            ("workshop/interior-workshop-basket-yarn", 640, 360, 1.4), ("workshop/interior-workshop-basket-wool", 720, 380, 1.4),
            ("decor/interior-decor-folding-screen", 690, 220, 1.4), ("tables/interior-tables-low-oval", 448, 360, 1.5),
            ("decor/interior-decor-rug-round-green", 448, 500, 1.6), ("storage/interior-storage-basket-laundry", 180, 500, 1.4)],
        "villagers": [("bobbin", 448, 300)],
    },
    "west-village-bathhouse": {
        "furniture": [("kitchen/interior-kitchen-tub-water", 280, 300, 2.2), ("kitchen/interior-kitchen-tub-water", 620, 300, 2.2),
            ("decor/interior-decor-towel-rack", 160, 230, 1.4), ("decor/interior-decor-towels-folded", 740, 240, 1.4),
            ("decor/interior-decor-wash-basin-soap", 740, 480, 1.4), ("decor/interior-decor-mat-woven", 448, 520, 1.6),
            ("kitchen/interior-kitchen-bucket-water", 180, 470, 1.4)],
        "villagers": [("auntie-suds", 448, 420)],
    },
    "west-village-herbalist": {
        "furniture": [("mushroom-large/interior-mushroom-large-herb-drying-rack", 230, 220, 1.2),
            ("mushroom-large/interior-mushroom-large-potion-shelf-tall", 660, 220, 1.2),
            ("mushroom-large/interior-mushroom-large-alchemy-workbench", 448, 330, 1.2),
            ("mushroom-furniture/interior-mushroom-furniture-cauldron-potion", 220, 440, 1.5),
            ("mushroom-decor/interior-mushroom-decor-herb-bundle-hanging", 360, 170, 1.3),
            ("mushroom-decor/interior-mushroom-decor-rug-moss-oval", 448, 520, 1.5),
            ("mushroom-furniture/interior-mushroom-furniture-basket-mushrooms", 700, 470, 1.4)],
        "villagers": [("granny-thistle", 448, 420)],
    },
    "west-village-family-home": {
        "town": "west-village-a4",
        "furniture": [("kitchen/interior-kitchen-cauldron-stew", 240, 280, 1.5), ("kitchen/interior-kitchen-prep-table", 380, 250, 1.4),
            ("kitchen/interior-kitchen-dish-shelf", 140, 210, 1.4), ("tables/interior-tables-dining-blue-runner-s", 448, 450, 1.3),
            ("seating/interior-seating-chair-green-cushion-e", 360, 450, 1.3), ("seating/interior-seating-chair-green-cushion-w", 536, 450, 1.3),
            ("beds/interior-beds-round-green-s", 600, 250, 1.1), ("beds/interior-beds-round-blue-s", 700, 250, 1.1),
            ("beds/interior-beds-cradle-s", 780, 350, 1.2), ("decor/interior-decor-rug-round-green", 448, 480, 1.6)],
        "villagers": [("may", 300, 320)],
    },
}


# The homes behind every other house door (owner, 2026-11-01: "a room behind each door"): furniture
# sets by kind of home, then (room id, chunk, kind). Nobody lives in them yet; the barn keeps a sheep
# and a hen ("animals": [(id, x, y)]).
HOME_KINDS: dict[str, list] = {
    "cottage": [("beds/interior-beds-round-green-s", 660, 240, 1.1), ("tables/interior-tables-dining-blue-runner-s", 448, 430, 1.3),
        ("seating/interior-seating-chair-green-cushion-e", 360, 430, 1.3), ("seating/interior-seating-chair-green-cushion-w", 536, 430, 1.3),
        ("kitchen/interior-kitchen-dish-shelf", 180, 210, 1.4), ("kitchen/interior-kitchen-cauldron-stew-b", 260, 290, 1.5),
        ("storage/interior-storage-bookshelf-books-s", 448, 210, 1.3), ("decor/interior-decor-rug-round-green", 448, 470, 1.6),
        ("seating/interior-seating-armchair-green-s", 700, 480, 1.3)],
    "flat": [("beds/interior-beds-straw-nest-s", 640, 260, 1.3), ("tables/interior-tables-low-round-small", 448, 400, 1.5),
        ("seating/interior-seating-chair-green-cushion-s", 448, 340, 1.3), ("kitchen/interior-kitchen-dish-shelf", 220, 210, 1.4),
        ("storage/interior-storage-chest-wood-closed-s", 760, 330, 1.3), ("decor/interior-decor-rug-blue-small", 448, 480, 1.6),
        ("kitchen/interior-kitchen-basket-bread", 220, 470, 1.4)],
    "mushroom": [("mushroom-large/interior-mushroom-large-bed-mushroom-cap-s", 660, 260, 1.1),
        ("mushroom-large/interior-mushroom-large-table-toadstool-dining", 448, 430, 1.1),
        ("mushroom-furniture/interior-mushroom-furniture-armchair-leaf-s", 300, 470, 1.3),
        ("mushroom-large/interior-mushroom-large-hearth-root-lit", 260, 240, 1.1),
        ("mushroom-large/interior-mushroom-large-bookshelf-hollow-stump", 448, 220, 1.1),
        ("mushroom-decor/interior-mushroom-decor-rug-mushroom", 448, 520, 1.5)],
    "farm": [("beds/interior-beds-double-round-s", 660, 250, 1.1), ("tables/interior-tables-dining-blue-runner-s", 448, 430, 1.3),
        ("kitchen/interior-kitchen-butter-churn", 220, 300, 1.4), ("kitchen/interior-kitchen-basin-stone", 300, 220, 1.4),
        ("kitchen/interior-kitchen-basket-vegetables", 180, 470, 1.4), ("storage/interior-storage-sack-grain", 740, 470, 1.4),
        ("storage/interior-storage-sacks-bundled", 760, 400, 1.4), ("decor/interior-decor-rug-green-large", 448, 470, 1.6)],
    "townhouse": [("beds/interior-beds-four-poster-s", 660, 250, 1.0), ("tables/interior-tables-dining-blue-runner-s", 448, 440, 1.3),
        ("seating/interior-seating-armchair-green-s", 260, 460, 1.3), ("storage/interior-storage-bookshelf-books-s", 260, 210, 1.3),
        ("decor/interior-decor-banner-blue", 448, 180, 1.4), ("decor/interior-decor-rug-round-blue", 448, 470, 1.6),
        ("decor/interior-decor-candles-triple-lit", 760, 420, 1.3)],
    "gatehouse": [("workshop/interior-workshop-armor-stand", 240, 230, 1.3), ("workshop/interior-workshop-helmet-stand", 340, 230, 1.3),
        ("workshop/interior-workshop-bow-rack", 560, 220, 1.3), ("workshop/interior-workshop-hammer-rack", 680, 220, 1.3),
        ("beds/interior-beds-straw-nest-s", 720, 360, 1.3), ("tables/interior-tables-low-round-small", 448, 420, 1.5),
        ("decor/interior-decor-banner-red-narrow", 448, 180, 1.4), ("decor/interior-decor-rug-green-small", 448, 500, 1.6)],
    "barn": [("storage/interior-storage-sacks-bundled", 200, 240, 1.5), ("storage/interior-storage-sack-grain", 280, 260, 1.5),
        ("storage/interior-storage-crate", 700, 240, 1.5), ("storage/interior-storage-crate-open", 760, 300, 1.5),
        ("workshop/interior-workshop-chopping-stump", 600, 470, 1.4), ("decor/interior-decor-broom", 160, 480, 1.4),
        ("storage/interior-storage-barrel", 760, 470, 1.5)],
}
HOMES = [
    ("west-village-a4-flat", "west-village-a4", "flat"), ("west-village-a4-duplex-1", "west-village-a4", "cottage"),
    ("west-village-a4-duplex-2", "west-village-a4", "flat"), ("west-village-a4-triplex-1", "west-village-a4", "cottage"),
    ("west-village-a4-triplex-2", "west-village-a4", "flat"), ("west-village-a4-triplex-3", "west-village-a4", "cottage"),
    ("west-village-a4-twin-mushroom-1", "west-village-a4", "mushroom"), ("west-village-a4-twin-mushroom-2", "west-village-a4", "mushroom"),
    ("west-village-a4-thatch-cottage", "west-village-a4", "cottage"), ("west-village-a4-snail-house", "west-village-a4", "flat"),
    ("west-village-a4-stump-house", "west-village-a4", "mushroom"), ("west-village-a4-barn", "west-village-a4", "barn"),
    ("west-village-b4-townhouse", "west-village-b4", "townhouse"), ("west-village-b4-gatehouse", "west-village-b4", "gatehouse"),
    ("west-village-a5-mushroom-farmhouse", "west-village-a5", "mushroom"), ("west-village-a5-pumpkin-farmhouse", "west-village-a5", "farm"),
    ("west-village-b5-thatch-cottage", "west-village-b5", "cottage"), ("west-village-b5-snail-house", "west-village-b5", "flat"),
    ("west-village-b5-townhouse", "west-village-b5", "townhouse"),
]
for _room, _town, _kind in HOMES:
    ROOMS[_room] = {"town": _town, "furniture": HOME_KINDS[_kind], "villagers": [],
        "animals": [("sheep", 448, 360), ("hen", 300, 420)] if _kind == "barn" else []}
ANIMALS = "res://game/scenes/objects/animals/"


def shell_layers() -> tuple[str, str, str]:
    """The shell's ground tile data, its old-props tile data kept to the walls, and the root's
    y-sort line (all as scene text)."""
    text = SHELL.read_text(encoding="utf-8")
    ground = re.search(r'\[node name="ground".*?tile_map_data = PackedByteArray\("([^"]+)"\)', text, re.S).group(1)
    props = re.search(r'\[node name="old-props".*?tile_map_data = PackedByteArray\("([^"]+)"\)', text, re.S).group(1)
    data = base64.b64decode(props)
    cells = [data[2 + i * 12:14 + i * 12] for i in range((len(data) - 2) // 12)]
    kept = [c for c in cells if struct.unpack("<hhHHHH", c)[2] == STRUCTURE_SOURCE]
    walls = base64.b64encode(data[:2] + b"".join(kept)).decode("ascii")
    return ground, walls, str(len(kept))


def scene_text(room: str, spec: dict, ground: str, walls: str) -> str:
    ext: list[str] = [
        '[ext_resource type="TileSet" path="res://game/world/terrain_tileset.tres" id="terrain"]',
        '[ext_resource type="Script" path="res://game/scripts/world_definition.gd" id="definition"]',
        '[ext_resource type="Script" path="res://game/scripts/door.gd" id="door"]',
        '[ext_resource type="TileSet" path="res://game/world/props/props_tileset.tres" id="old_props"]',
        '[ext_resource type="Script" path="res://game/world/props/prop_layer.gd" id="prop_layer"]',
        '[ext_resource type="TileSet" path="res://game/world/props/props_cell_tileset.tres" id="cell_props"]',
        '[ext_resource type="TileSet" path="res://game/world/props/props_detail_tileset.tres" id="detail_props"]',
        '[ext_resource type="Script" path="res://game/runtime/sfx_player.gd" id="sfx"]',
        '[ext_resource type="AudioStream" path="res://asset/audio/sfx/synth/world/interior-ambience.wav" id="ambience"]',
        '[ext_resource type="Script" path="res://game/world/world_ground.gd" id="world_ground"]',
        '[ext_resource type="Texture2D" path="res://asset/MAPS/Houses/doors/interior-timber-door.webp" id="door_art"]',
        '[ext_resource type="AudioStream" path="res://asset/audio/music/interior-a.wav" id="music_track"]',
    ]
    furniture = COMMON + spec["furniture"]
    scenes: dict[str, str] = {}
    animals = spec.get("animals", [])
    for path in [INTERIORS + f[0] + ".tscn" for f in furniture] + [VILLAGERS + v + ".tscn" for v, _, _ in spec["villagers"]] \
            + [ANIMALS + a + ".tscn" for a, _, _ in animals]:
        if path not in scenes:
            scenes[path] = f"s{len(scenes) + 1}"
            ext.append(f'[ext_resource type="PackedScene" path="{path}" id="{scenes[path]}"]')
    nodes = [
        f'[node name="{room}" type="Node2D"]\ny_sort_enabled = true',
        "\n".join(['[node name="ground" type="TileMapLayer" parent="."]', "z_index = -2",
            f'tile_map_data = PackedByteArray("{ground}")', 'tile_set = ExtResource("terrain")',
            'script = ExtResource("world_ground")', "metadata/columns = 14", "metadata/rows = 11"]),
        '[node name="TileCollision" type="Node2D" parent="ground"]',
        "\n".join(['[node name="old-props" type="TileMapLayer" parent="."]', "y_sort_enabled = true",
            f'tile_map_data = PackedByteArray("{walls}")', 'tile_set = ExtResource("old_props")',
            'script = ExtResource("prop_layer")']),
        "\n".join(['[node name="cell-props" type="TileMapLayer" parent="."]', "y_sort_enabled = true",
            'tile_set = ExtResource("cell_props")', 'script = ExtResource("prop_layer")']),
        "\n".join(['[node name="details" type="TileMapLayer" parent="."]', "y_sort_enabled = true",
            'tile_set = ExtResource("detail_props")', 'script = ExtResource("prop_layer")']),
        "\n".join(['[node name="world-definition" type="Node" parent="."]', 'script = ExtResource("definition")',
            f'map_id = "{room}"', "tile_size = 64", "columns = 14", "rows = 11", "metadata = {",
            '"objects": [],', '"player": {', '"entries": {', '"south": {', f'"x": {SPAWN[0]},', f'"y": {SPAWN[1]}',
            "}", "},", '"spawn": {', f'"x": {SPAWN[0]},', f'"y": {SPAWN[1]}', "}", "}", "}", 'camera_mode = "fixed"']),
        "\n".join(['[node name="player-spawn" type="Node2D" parent="."]', "y_sort_enabled = true",
            f"position = Vector2({SPAWN[0]}, {SPAWN[1]})"]),
        "\n".join(['[node name="house-door" type="Node2D" parent="."]', "y_sort_enabled = true",
            f"position = Vector2({DOOR_AT[0]}, {DOOR_AT[1]})"]),
        "\n".join(['[node name="door-script" type="Node" parent="house-door" node_paths=PackedStringArray("house_art")]',
            'script = ExtResource("door")', f'map_id = "{room}"', 'door_id = "house-door"',
            f'target_area_id = "{spec.get("town", TOWN)}"', f'target_door_id = "{room}-door"', 'side = "south"', 'kind = "door"',
            'house_art = NodePath("../../house-door-art")', "door_rect = Rect2(-57.5, -50.6, 114.8, 49.1)",
            "double_leaf = true"]),
        "\n".join(['[node name="house-door-art" type="Sprite2D" parent="."]', f"position = Vector2({DOOR_AT[0]}, 643)",
            "scale = Vector2(0.5, 0.5)", 'texture = ExtResource("door_art")', "centered = false",
            "offset = Vector2(-120, 0)"]),
        '[node name="Furniture" type="Node2D" parent="."]\ny_sort_enabled = true',
    ]
    used: dict[str, int] = {}
    for piece in furniture:
        scene, x, y = piece[:3]
        scale = piece[3] if len(piece) > 3 else 1.0
        name = scene.split("/")[-1].removeprefix("interior-")
        used[name] = used.get(name, 0) + 1
        label = name if used[name] == 1 else f"{name}{used[name]}"
        lines = [f'[node name="{label}" parent="Furniture" instance=ExtResource("{scenes[INTERIORS + scene + ".tscn"]}")]',
            f"position = Vector2({x}, {y})"]
        if scale != 1.0:
            lines.append(f"scale = Vector2({scale}, {scale})")
        nodes.append("\n".join(lines))
    nodes.append('[node name="NPCs" type="Node2D" parent="."]\ny_sort_enabled = true')
    for villager, x, y in spec["villagers"]:
        nodes.append(f'[node name="{villager}" parent="NPCs" instance=ExtResource("{scenes[VILLAGERS + villager + ".tscn"]}")]\n'
            f"position = Vector2({x}, {y})\nmetadata/instance_id = \"{room}-{villager}\"")
    if animals:
        nodes.append('[node name="Animals" type="Node2D" parent="."]\ny_sort_enabled = true')
        for animal, x, y in animals:
            nodes.append(f'[node name="{animal}" parent="Animals" instance=ExtResource("{scenes[ANIMALS + animal + ".tscn"]}")]\n'
                f"position = Vector2({x}, {y})\nwander_radius = 96.0")
    nodes.append("\n".join(['[node name="Ambience" type="AudioStreamPlayer" parent="."]', "process_mode = 3",
        'stream = ExtResource("ambience")', "volume_db = -9.1186", 'bus = &"Ambience"', 'script = ExtResource("sfx")',
        "loop = true", "autoplay_cue = true"]))
    nodes.append("\n".join(['[node name="MusicPlayer" type="AudioStreamPlayer" parent="."]', "process_mode = 3",
        'stream = ExtResource("music_track")', "volume_db = -6.0206", 'bus = &"Music"', 'script = ExtResource("sfx")',
        "loop = true", "autoplay_cue = true"]))
    return "\n\n".join(["[gd_scene format=4]", "\n".join(ext)] + nodes) + "\n"


def main() -> None:
    args = sys.argv[1:]
    force = "--force" in args
    wanted = [a for a in args if a != "--force"] or list(ROOMS)
    ground, walls, kept = shell_layers()
    missing = sorted({f[0] for spec in ROOMS.values() for f in COMMON + spec["furniture"]
        if not (GODOT / (INTERIORS + f[0] + ".tscn").removeprefix("res://")).exists()})
    if missing:
        raise SystemExit("missing furniture scenes: " + ", ".join(missing))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for room in wanted:
        if room not in ROOMS:
            raise SystemExit(f"unknown room: {room}")
        out = OUT_DIR / f"{room}.tscn"
        if out.exists() and not force:
            print(f"keep {out.relative_to(REPO)}")
            continue
        out.write_text(scene_text(room, ROOMS[room], ground, walls), encoding="utf-8")
        print(f"wrote {out.relative_to(REPO)} ({kept} wall cells)")


if __name__ == "__main__":
    main()
