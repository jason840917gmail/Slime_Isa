"""Gives the pieces that burn, glow, bubble, steam or wave an ambient loop
(docs/assets/AMBIENT_ANIMATION.md "Interior loops" and "Dungeon loops"; owner, 2026-11-12: "take a
look at interior decoration, like candles and caldarium", then "the town well, and the dungeons
art").

Each piece in PIECES is an object scene (godot/game/scenes/objects/<path>.tscn) and one tile of a
sheet under godot/asset/MAPS/ (the table names the sheet and the tile's frame). The script cuts the
tile, makes FRAMES frames of it with the piece's effects (all procedural: the frames are the tile's
own pixels moved or made brighter, so nothing drifts) and writes them side by side to
<the sheet's folder>/ambient/<scene name>.webp. A scene not yet rewired is rewired once: its Visual
becomes a sheet sprite on the strip (game/runtime/sheet_sprite.gd, so it shows before the editor
imports the strip) and it gets an AmbientAnimation player (clip "idle", random start); a scene that
has its player is left alone, so hand tuning in the editor stays.

Effects, in the tile's pixels (x right, y down):
- ("flame", x, foot y, half width, height, phase): a flame leans and stretches from its foot.
- ("glow", left, top, right, bottom, colour, strength, "flicker" | "pulse", phase): the pixels of
  that colour in the box get brighter and dimmer: a fire's uneven flicker, or a slow even pulse.
- ("bands", left, top, right, bottom, colour, strength[, length]): light bands `length` pixels
  apart run over a liquid (11), one wide glint over still water (20), a shine over crystals (70).
- ("wobble", left, top, right, bottom, reach): what is in the box heaves slowly (a simmering stew);
  it fades out at the box's edges.
- ("bob", x, y, radius, reach, phase): a bubble or a bucket bobs up and down, whole.
- ("sway", left, top, right, bottom, reach): steam leans sideways, more the higher it rises.
- ("fire", left, top, right, bottom, reach): flames ripple upward.
- ("auto", kind): the effects are found on the tile by colour: "lamp" (the light flickers), "fire"
  (the flames ripple, the light flickers), "water" (a glint over the water), "glow-<colour>" (that
  colour pulses). No boxes to measure. Candle flames are too pale for it: measure those.
- ("cloth", left, top, right, bottom, colour, reach): the cloth of that colour in the box (each row
  from its first to its last pixel of the colour, so its emblem moves with it) waves from its top
  row; what is behind it is filled from the row's nearest pixels.
The game draws these pieces at about half their pixels or less, so a loop must be bold to read
(AMBIENT_ANIMATION.md "A loop must read at the game's size").

    python scripts/art/build-ambient-strips.py [--preview=<dir>] [--boxes] [name ...]

--preview writes each piece's frames as a GIF and a sheet there instead of touching the game;
--boxes draws the effects' boxes on the preview.
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SCENES = ROOT / "godot/game/scenes/objects"
MAPS = ROOT / "godot/asset/MAPS"
MAPS_RES = "res://asset/MAPS"
FRAMES = 8
# a fire's flicker over the loop (uneven on purpose), -1..1
FLICKER = [0.1, 0.85, -0.6, 0.45, 1.0, -0.3, 0.6, -1.0]

# scene (under godot/game/scenes/objects/, without .tscn) -> (frames per second, its tile (sheet
# under godot/asset/MAPS/, the sheet's columns and rows, the tile's frame), effects)
PIECES: dict[str, tuple[int, tuple[str, int, int, int], list[tuple]]] = {
	"interiors/decor/interior-decor-lantern-lit": (9, ("interiors/128x128-tile_8x8-interior-decor-lighting-utility.webp", 8, 8, 7), [
		("glow", 42, 72, 82, 114, "warm", 0.24, "flicker", 0),
		("flame", 61, 102, 8, 18, 0.0),
	]),
	"interiors/decor/interior-decor-candles-triple-lit": (9, ("interiors/128x128-tile_8x8-interior-decor-lighting-utility.webp", 8, 8, 3), [
		("glow", 26, 40, 102, 86, "warm", 0.24, "flicker", 0),
		("flame", 47, 70, 7, 20, 0.0),
		("flame", 63, 78, 7, 20, 2.1),
		("flame", 79, 72, 7, 20, 4.2),
	]),
	"interiors/kitchen/interior-kitchen-cauldron-stew": (7, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 18), [
		("bands", 40, 60, 90, 86, "warm", 0.2),
		("wobble", 42, 62, 88, 84, 1.6),
	]),
	"interiors/kitchen/interior-kitchen-cauldron-stew-b": (7, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 19), [
		("bands", 40, 60, 90, 86, "warm", 0.2),
		("wobble", 42, 62, 88, 84, 1.6),
	]),
	"interiors/kitchen/interior-kitchen-clay-oven-baking": (9, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 14), [
		("glow", 44, 72, 86, 108, "warm", 0.24, "flicker", 0),
	]),
	"interiors/mushroom-furniture/interior-mushroom-furniture-cauldron-potion": (8, ("interiors/192x192-tile_8x8-interior-mushroom-furniture-props.webp", 8, 8, 42), [
		("bands", 48, 76, 140, 102, "green", 0.24),
		("bob", 60, 45, 8, 3.4, 0.0),
		("bob", 91, 43, 6, 3.4, 1.9),
		("bob", 44, 63, 9, 3.0, 3.8),
		("bob", 104, 58, 10, 3.0, 5.2),
		("bob", 80, 53, 4, 3.4, 2.7),
		("bob", 124, 62, 4, 3.0, 0.9),
		("glow", 28, 26, 132, 76, "green", 0.16, "pulse", 0),
	]),
	"interiors/mushroom-large/interior-mushroom-large-hearth-root-lit": (9, ("interiors/256x256-tile_4x4-interior-mushroom-large-furniture.webp", 4, 4, 8), [
		("fire", 86, 158, 168, 202, 2.6),
		("glow", 78, 150, 176, 206, "warm", 0.22, "flicker", 0),
		("sway", 104, 88, 150, 134, 3.5),
		("bands", 102, 126, 152, 144, "green", 0.22),
		("glow", 64, 126, 92, 162, "warm", 0.22, "flicker", 3),
		("flame", 77, 150, 6, 14, 1.0),
		("glow", 28, 184, 56, 214, "blue", 0.3, "pulse", 0),
		("glow", 204, 182, 234, 212, "blue", 0.3, "pulse", 3),
	]),
	"interiors/kitchen/interior-kitchen-tub-water": (6, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 41), [
		("bands", 32, 68, 98, 96, "water", 0.16),
		("wobble", 34, 70, 96, 94, 1.4),
	]),
	"interiors/kitchen/interior-kitchen-bucket-water": (6, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 44), [
		("bands", 40, 62, 86, 84, "water", 0.16),
		("wobble", 42, 64, 84, 82, 1.2),
	]),
	"interiors/kitchen/interior-kitchen-basin-stone": (6, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 42), [
		("bands", 32, 76, 90, 94, "water", 0.16),
		("wobble", 34, 78, 88, 92, 1.2),
	]),
	"interiors/mushroom-large/interior-mushroom-large-potion-shelf-tall": (8, ("interiors/256x256-tile_4x4-interior-mushroom-large-furniture.webp", 4, 4, 12), [
		("glow", 108, 42, 138, 76, "warm", 0.24, "flicker", 0),
		("flame", 123, 68, 5, 12, 0.0),
		("glow", 88, 52, 114, 94, "green", 0.24, "pulse", 0),
		("glow", 76, 68, 98, 98, "warm", 0.2, "pulse", 3),
		("glow", 76, 106, 122, 152, "blue", 0.24, "pulse", 5),
		("glow", 114, 122, 136, 154, "warm", 0.2, "pulse", 1),
		("glow", 106, 162, 136, 196, "blue", 0.22, "pulse", 2),
		("glow", 134, 162, 158, 196, "pink", 0.24, "pulse", 6),
	]),
	"interiors/mushroom-large/interior-mushroom-large-alchemy-workbench": (9, ("interiors/256x256-tile_4x4-interior-mushroom-large-furniture.webp", 4, 4, 7), [
		("glow", 38, 74, 72, 114, "warm", 0.22, "flicker", 0),
		("flame", 54, 99, 7, 18, 0.0),
		("glow", 26, 106, 54, 136, "warm", 0.22, "flicker", 2),
		("flame", 40, 123, 5, 12, 2.0),
		("glow", 184, 102, 212, 136, "warm", 0.22, "flicker", 5),
		("flame", 197, 123, 6, 14, 4.0),
		("glow", 76, 44, 104, 76, "warm", 0.2, "flicker", 4),
		("glow", 62, 72, 90, 124, "blue", 0.2, "pulse", 0),
		("glow", 82, 98, 106, 130, "pink", 0.2, "pulse", 4),
	]),
	# --- the town well, the dungeons ---
	"decoration-world-solid--village-well": (6, ("landmarks/320x256-tile_4x1-level-1-landmarks.webp", 4, 1, 2), [
		("bands", 144, 174, 194, 200, "water", 0.2, 20.0),
		("bob", 170, 185, 9, 1.6, 0.0),
	]),
	"brazier-lit": (10, ("props/caverns/256x256-tile_2x1-brazier.webp", 2, 1, 1), [
		("fire", 58, 0, 194, 124, 4.5),
		("glow", 48, 0, 204, 166, "warm", 0.2, "flicker", 0),
	]),
	"dungeon-decor/candelabra": (9, ("objects/dungeon/decor/candelabra.webp", 1, 1, 0), [
		("glow", 0, 0, 82, 72, "warm", 0.2, "flicker", 0),
		("flame", 11, 43, 5, 15, 0.0),
		("flame", 25, 56, 5, 15, 1.3),
		("flame", 43, 21, 6, 17, 2.6),
		("flame", 57, 54, 5, 15, 3.9),
		("flame", 71, 40, 5, 15, 5.2),
	]),
	"dungeon-decor/guard-table": (9, ("objects/dungeon/decor/guard-table.webp", 1, 1, 0), [
		("glow", 32, 0, 64, 46, "warm", 0.22, "flicker", 0),
		("flame", 48, 20, 5, 16, 0.0),
	]),
	"dungeon-decor/worm-head-statue": (6, ("objects/dungeon/decor/worm-head-statue.webp", 1, 1, 0), [
		("glow", 26, 70, 50, 94, "warm", 0.4, "pulse", 0),
		("glow", 60, 70, 86, 96, "warm", 0.4, "pulse", 0),
	]),
	"decoration-world-solid--war-banner": (6, ("objects/fattys-lair/war-banner.webp", 1, 1, 0), [
		("cloth", 36, 52, 160, 246, "red", 6.0),
	]),
	"crystal-pillar": (7, ("props/caverns/256x256-crystal-pillar.webp", 1, 1, 0), [
		("bands", 0, 0, 256, 256, "water", 0.3, 70.0),
	]),
	"ore-heap": (7, ("props/mine/256x256-ore-heap.webp", 1, 1, 0), [
		("bands", 0, 0, 256, 256, "blue", 0.3, 70.0),
	]),
	"rock-stump": (7, ("props/mine/256x256-rock-stump.webp", 1, 1, 0), [
		("bands", 0, 0, 256, 256, "blue", 0.3, 70.0),
	]),
	# the rebuilt Mine's dressing (2026-11-25, scripts/art/pack-mine-decor-art.py): the lantern's light
	# flickers, a shine travels over the crystals
	"dungeon-decor/mine-lantern-post": (9, ("objects/dungeon/decor/mine-lantern-post.webp", 1, 1, 0), [("auto", "lamp")]),
	"dungeon-decor/mine-slate-heap": (7, ("objects/dungeon/decor/mine-slate-heap.webp", 1, 1, 0), [
		("bands", 0, 0, 207, 171, "blue", 0.3, 70.0),
	]),
	"dungeon-decor/mine-tipped-cart": (7, ("objects/dungeon/decor/mine-tipped-cart.webp", 1, 1, 0), [
		("bands", 0, 0, 209, 164, "blue", 0.3, 70.0),
	]),
	# --- found by colour ("auto"): every other interior piece with fire, light or liquid; the forge ---
	"interiors/decor/interior-decor-candle-lit": (9, ("interiors/128x128-tile_8x8-interior-decor-lighting-utility.webp", 8, 8, 1), [("glow", 44, 41, 80, 80, "warm", 0.22, "flicker", 0), ("flame", 62, 70, 6, 17, 0.0)]),
	"interiors/decor/interior-decor-candlestick-lit": (9, ("interiors/128x128-tile_8x8-interior-decor-lighting-utility.webp", 8, 8, 5), [("glow", 46, 12, 82, 50, "warm", 0.22, "flicker", 0), ("flame", 64, 40, 6, 16, 0.0)]),
	"interiors/decor/interior-decor-sconce-double-lit": (9, ("interiors/128x128-tile_8x8-interior-decor-lighting-utility.webp", 8, 8, 11), [("glow", 57, 41, 93, 80, "warm", 0.22, "flicker", 0), ("flame", 75, 70, 6, 17, 0.0)]),
	"interiors/decor/interior-decor-sconce-iron-lit": (9, ("interiors/128x128-tile_8x8-interior-decor-lighting-utility.webp", 8, 8, 13), [("glow", 44, 33, 80, 72, "warm", 0.22, "flicker", 0), ("flame", 62, 62, 6, 17, 0.0)]),
	"interiors/decor/interior-decor-sconce-lit": (9, ("interiors/128x128-tile_8x8-interior-decor-lighting-utility.webp", 8, 8, 9), [("glow", 42, 34, 78, 73, "warm", 0.22, "flicker", 0), ("flame", 60, 63, 6, 17, 0.0)]),
	"interiors/decor/interior-decor-sconce-side-lit": (9, ("interiors/128x128-tile_8x8-interior-decor-lighting-utility.webp", 8, 8, 15), [("glow", 37, 42, 73, 81, "warm", 0.22, "flicker", 0), ("flame", 55, 71, 6, 17, 0.0)]),
	"interiors/specialty/interior-specialty-candle-cluster": (9, ("interiors/128x128-tile_8x8-interior-specialty-rooms.webp", 8, 8, 30), [("glow", 50, 11, 86, 50, "warm", 0.22, "flicker", 0), ("flame", 68, 40, 6, 17, 0.0), ("glow", 28, 40, 62, 77, "warm", 0.22, "flicker", 3), ("flame", 45, 67, 5, 15, 1.9), ("glow", 40, 49, 72, 83, "warm", 0.22, "flicker", 6), ("flame", 56, 73, 4, 12, 3.8)]),
	"interiors/mushroom-decor/interior-mushroom-decor-toadstool-candle-lit": (9, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 6), [("glow", 77, 63, 119, 110, "warm", 0.22, "flicker", 0), ("flame", 98, 100, 9, 25, 0.0)]),
	"interiors/mushroom-furniture/interior-mushroom-furniture-nightstand-mushroom-candle": (9, ("interiors/192x192-tile_8x8-interior-mushroom-furniture-props.webp", 8, 8, 18), [("glow", 73, 22, 115, 70, "warm", 0.22, "flicker", 0), ("flame", 94, 60, 9, 26, 0.0)]),
	"interiors/mushroom-decor/interior-mushroom-decor-lantern-acorn-hanging": (9, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 7), [("auto", "lamp")]),
	"interiors/mushroom-structure/interior-mushroom-structure-fence-post-lantern": (9, ("interiors/128x128-tile_8x8-interior-mushroom-structure.webp", 8, 8, 55), [("auto", "lamp"), ("auto", "glow-blue")]),
	"interiors/kitchen/interior-kitchen-firepit-large": (9, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 11), [("auto", "fire")]),
	"interiors/kitchen/interior-kitchen-firepit-medium": (9, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 10), [("auto", "fire")]),
	"interiors/kitchen/interior-kitchen-firepit-roaring": (9, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 12), [("auto", "fire")]),
	"interiors/kitchen/interior-kitchen-firepit-small": (9, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 9), [("auto", "fire")]),
	"interiors/kitchen/interior-kitchen-hearth-lit-e": (9, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 5), [("auto", "fire")]),
	"interiors/kitchen/interior-kitchen-hearth-lit-n": (9, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 6), [("auto", "fire")]),
	"interiors/kitchen/interior-kitchen-hearth-lit-s": (9, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 4), [("auto", "fire")]),
	"interiors/kitchen/interior-kitchen-hearth-lit-w": (9, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 7), [("auto", "fire")]),
	"interiors/mushroom-furniture/interior-mushroom-furniture-oven-clay-lit": (9, ("interiors/192x192-tile_8x8-interior-mushroom-furniture-props.webp", 8, 8, 44), [("auto", "fire")]),
	"interiors/workshop/interior-workshop-forge-lit": (9, ("interiors/128x128-tile_8x8-interior-workshop-crafting.webp", 8, 8, 1), [("auto", "fire")]),
	"interiors/kitchen/interior-kitchen-cauldron-stew-c": (7, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 20), [("bands", 40, 60, 90, 86, "warm", 0.2), ("wobble", 42, 62, 88, 84, 1.6)]),
	"interiors/kitchen/interior-kitchen-cauldron-stew-d": (7, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 21), [("bands", 40, 60, 90, 86, "warm", 0.2), ("wobble", 42, 62, 88, 84, 1.6)]),
	"interiors/kitchen/interior-kitchen-cauldron-stew-e": (7, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 22), [("bands", 40, 60, 90, 86, "warm", 0.2), ("wobble", 42, 62, 88, 84, 1.6)]),
	"interiors/mushroom-furniture/interior-mushroom-furniture-cauldron-soup": (7, ("interiors/192x192-tile_8x8-interior-mushroom-furniture-props.webp", 8, 8, 41), [("bands", 50, 70, 142, 108, "warm", 0.16), ("wobble", 54, 74, 138, 104, 1.4), ("sway", 62, 26, 112, 70, 3.0)]),
	"interiors/kitchen/interior-kitchen-cauldron-water": (6, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 17), [("auto", "water")]),
	"interiors/kitchen/interior-kitchen-washtub-towel": (6, ("interiors/128x128-tile_8x8-interior-kitchen-hearth.webp", 8, 8, 46), [("auto", "water")]),
	"interiors/storage/interior-storage-washtub-towel": (6, ("interiors/128x128-tile_8x8-interior-storage-states.webp", 8, 8, 55), [("auto", "water")]),
	"interiors/mushroom-furniture/interior-mushroom-furniture-bucket-water": (6, ("interiors/192x192-tile_8x8-interior-mushroom-furniture-props.webp", 8, 8, 38), [("auto", "water")]),
	"interiors/mushroom-furniture/interior-mushroom-furniture-wash-basin-stump": (6, ("interiors/192x192-tile_8x8-interior-mushroom-furniture-props.webp", 8, 8, 56), [("auto", "water")]),
	"interiors/mushroom-furniture/interior-mushroom-furniture-water-trough": (6, ("interiors/192x192-tile_8x8-interior-mushroom-furniture-props.webp", 8, 8, 57), [("auto", "water")]),
	"interiors/mushroom-large/interior-mushroom-large-water-basin-stump": (6, ("interiors/256x256-tile_4x4-interior-mushroom-large-furniture.webp", 4, 4, 14), [("auto", "water")]),
	"interiors/workshop/interior-workshop-quench-tub": (6, ("interiors/128x128-tile_8x8-interior-workshop-crafting.webp", 8, 8, 4), [("auto", "water")]),
	"interiors/mushroom-decor/interior-mushroom-decor-fairy-ring-glow": (6, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 45), [("auto", "glow-blue")]),
	"interiors/mushroom-decor/interior-mushroom-decor-glow-mushroom-cluster": (6, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 2), [("auto", "glow-blue")]),
	"interiors/mushroom-decor/interior-mushroom-decor-glow-mushroom-small": (6, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 0), [("auto", "glow-blue")]),
	"interiors/mushroom-decor/interior-mushroom-decor-glow-mushroom-tall": (6, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 1), [("auto", "glow-blue")]),
	"interiors/mushroom-decor/interior-mushroom-decor-planter-glow-hanging": (6, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 12), [("auto", "glow-blue")]),
	"interiors/mushroom-decor/interior-mushroom-decor-sconce-glow-mushroom": (6, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 15), [("auto", "glow-blue")]),
	"interiors/mushroom-floor/interior-mushroom-floor-mushrooms-glow": (6, ("interiors/128x128-tile_8x8-interior-mushroom-floor-decor.webp", 8, 8, 59), [("auto", "glow-blue")]),
	"interiors/mushroom-structure/interior-mushroom-structure-wall-glow-mushrooms": (6, ("interiors/128x128-tile_8x8-interior-mushroom-structure.webp", 8, 8, 10), [("auto", "glow-blue")]),
	"interiors/mushroom-structure/interior-mushroom-structure-window-crystal-glow": (6, ("interiors/128x128-tile_8x8-interior-mushroom-structure.webp", 8, 8, 37), [("auto", "glow-blue")]),
	"interiors/mushroom-decor/interior-mushroom-decor-crystal-ball-stump": (6, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 33), [("auto", "glow-blue")]),
	"interiors/mushroom-structure/interior-mushroom-structure-puddle-glow": (6, ("interiors/128x128-tile_8x8-interior-mushroom-structure.webp", 8, 8, 45), [("auto", "glow-blue")]),
	"interiors/mushroom-decor/interior-mushroom-decor-firefly-jar-lit": (6, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 3), [("auto", "glow-warm")]),
	"interiors/mushroom-decor/interior-mushroom-decor-potion-bottles": (6, ("interiors/192x192-tile_8x8-interior-mushroom-decor-lighting.webp", 8, 8, 32), [("auto", "glow-blue"), ("glow", 0, 0, 192, 192, "pink", 0.26, "pulse", 4)]),
	"house-world-solid--forge-red": (9, ("Houses/320-3x1.webp", 3, 1, 1), [("fire", 132, 254, 182, 288, 1.6), ("glow", 126, 248, 188, 292, "fire", 0.3, "flicker", 0)]),
	"interiors/mushroom-large/interior-mushroom-large-table-toadstool-dining": (9, ("interiors/256x256-tile_4x4-interior-mushroom-large-furniture.webp", 4, 4, 4), [
		("glow", 108, 62, 138, 96, "warm", 0.22, "flicker", 0), ("flame", 123, 85, 5, 11, 0.0),
		("glow", 128, 76, 156, 108, "warm", 0.22, "flicker", 3), ("flame", 142, 97, 5, 10, 1.9),
	]),
}


def hsv(array: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
	rgb = array[..., :3] / 255.0
	mx, mn = rgb.max(axis=2), rgb.min(axis=2)
	s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
	r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
	d = np.maximum(mx - mn, 1e-6)
	h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
	return h, s, mx


def colour(array: np.ndarray, name: str) -> np.ndarray:
	h, s, v = hsv(array)
	seen = array[..., 3] > 0
	if name == "warm":
		return seen & (h > 10) & (h < 68) & (s > 0.25) & (v > 0.5)
	if name == "green":
		return seen & (h > 65) & (h < 160) & (s > 0.35) & (v > 0.45)
	if name == "blue":
		return seen & (h > 160) & (h < 255) & (s > 0.3) & (v > 0.5)
	if name == "water":
		return seen & (h > 170) & (h < 250) & (s > 0.15) & (v > 0.4)
	if name == "fire":
		return seen & (h > 8) & (h < 65) & (s > 0.45) & (v > 0.8)
	if name == "flame":
		return seen & (h > 15) & (h < 62) & (s > 0.55) & (v > 0.92)
	if name == "red":
		return seen & ((h < 18) | (h > 342)) & (s > 0.55) & (v > 0.35)
	if name == "pink":
		return seen & (h > 265) & (h < 345) & (s > 0.3) & (v > 0.5)
	raise ValueError(name)


def sample(image: np.ndarray, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
	"""`image` (float, premultiplied) read at the points (xs, ys), between pixels by weight."""
	height, width = image.shape[:2]
	xs = np.clip(xs, 0, width - 1.001)
	ys = np.clip(ys, 0, height - 1.001)
	x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
	fx, fy = (xs - x0)[..., None], (ys - y0)[..., None]
	top = image[y0, x0] * (1 - fx) + image[y0, x0 + 1] * fx
	bottom = image[y0 + 1, x0] * (1 - fx) + image[y0 + 1, x0 + 1] * fx
	return top * (1 - fy) + bottom * fy


def smooth(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
	t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)


def inside(xx: np.ndarray, yy: np.ndarray, box: tuple, soft: float) -> np.ndarray:
	"""1 inside the box, falling to 0 over `soft` pixels at its edges."""
	left, top, right, bottom = box
	return (smooth(left, left + soft, xx) * smooth(right, right - soft, xx)
		* smooth(top, top + soft, yy) * smooth(bottom, bottom - soft, yy))


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


## the smallest part of flame colour that counts (pixels)
FLAME_PIXELS = 10


def resolved(tile: Image.Image, effects: list[tuple]) -> list[tuple]:
	"""`effects` with every ("auto", kind) replaced by the effects found on the tile by colour:
	"lamp" (the light flickers), "fire" (the flames ripple, the light flickers), "water" (a glint
	over the water), "glow-<colour>" (that colour pulses). A candle's flame is too pale to find by
	colour: candles are measured by hand ("flame" and "glow")."""
	out = []
	straight = np.asarray(tile, dtype=np.float64)
	height, width = straight.shape[:2]
	for effect in effects:
		if effect[0] != "auto":
			out.append(effect)
			continue
		kind = effect[1]
		if kind == "water":
			out.append(("bands", 0, 0, width, height, "water", 0.16))
		elif kind.startswith("glow-"):
			out.append(("glow", 0, 0, width, height, kind.removeprefix("glow-"), 0.26, "pulse", 0))
		elif kind == "lamp":
			out.append(("glow", 0, 0, width, height, "fire", 0.22, "flicker", 0))
		elif kind == "fire":
			# a flame is vivid and very bright; wax, clay and lit wood are paler or darker
			flames = [part for part in parts(colour(straight, "flame") & (straight[..., 3] > 160)) if len(part) >= FLAME_PIXELS]
			if not flames:
				raise RuntimeError("no flame found on the tile")
			every = np.concatenate(flames)
			top, left = (int(v) for v in every.min(axis=0))
			bottom, right = (int(v) for v in every.max(axis=0))
			out.append(("fire", left - 4, top - 5, right + 4, bottom + 2, max(1.5, (bottom - top) / 14.0)))
			out.append(("glow", left - 10, top - 10, right + 10, bottom + 10, "fire", 0.24, "flicker", 0))
		else:
			raise ValueError(kind)
	return out


def grow(mask: np.ndarray, by: int) -> np.ndarray:
	"""`mask` grown by `by` pixels on every side."""
	out = mask.copy()
	for _ in range(by):
		wide = out.copy()
		wide[1:] |= out[:-1]
		wide[:-1] |= out[1:]
		wide[:, 1:] |= out[:, :-1]
		wide[:, :-1] |= out[:, 1:]
		out = wide
	return out


def row_fill(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
	"""`image` with every `mask` pixel replaced by the nearest pixel of its row outside the mask
	(what shows behind a part that moves away)."""
	out = image.copy()
	columns = np.arange(mask.shape[1])
	for y in range(mask.shape[0]):
		row = mask[y]
		if not row.any():
			continue
		free = columns[~row]
		if len(free) == 0:
			out[y] = 0
			continue
		place = np.clip(np.searchsorted(free, columns[row]), 1, len(free) - 1)
		left, right = free[place - 1], free[place]
		out[y, row] = image[y, np.where(columns[row] - left <= right - columns[row], left, right)]
	return out


def cloth_mask(straight: np.ndarray, box: tuple, name: str) -> np.ndarray:
	"""The cloth in the box: each row from its first to its last pixel of the colour, a little
	wider for its outline."""
	left, top, right, bottom = box
	mask = np.zeros(straight.shape[:2], dtype=bool)
	part = colour(straight[top:bottom, left:right], name)
	for y in range(part.shape[0]):
		found = np.nonzero(part[y])[0]
		if len(found) >= 3:
			mask[top + y, left + found[0]:left + found[-1] + 1] = True
	wide = grow(mask, 2)
	wide[:top] = False
	return wide & (straight[..., 3] > 0)


def frames_of(tile: Image.Image, effects: list[tuple]) -> list[Image.Image]:
	straight = np.asarray(tile, dtype=np.float64)
	height, width = straight.shape[:2]
	yy, xx = np.mgrid[0:height, 0:width].astype(np.float64)
	base = straight.copy()
	base[..., :3] *= base[..., 3:4] / 255.0
	cloths = [(effect, cloth_mask(straight, effect[1:5], effect[5])) for effect in effects if effect[0] == "cloth"]
	out = []
	for k in range(FRAMES):
		turn = 2 * math.pi * k / FRAMES
		dx = np.zeros((height, width))
		dy = np.zeros((height, width))
		gain = np.ones((height, width))
		for effect in effects:
			kind = effect[0]
			if kind == "flame":
				_, x, foot, half, tall, phase = effect
				box = (x - half - 3, foot - tall - 6, x + half + 3, foot + 1)
				up = np.clip((foot - yy) / tall, 0, 1.4)
				weight = smooth(box[0], box[0] + 3, xx) * smooth(box[2], box[2] - 3, xx) * (yy >= box[1]) * (yy <= foot)
				lean = 0.2 * tall * up ** 1.4 * (0.7 * math.sin(turn + phase) + 0.3 * math.sin(2 * turn + phase * 1.7))
				stretch = 1 + 0.16 * math.sin(2 * turn + phase)
				dx += weight * lean
				dy += weight * ((foot - yy) * (1 - 1 / stretch)) * -1.0
			elif kind == "glow":
				_, left, top, right, bottom, name, strength, how, shift = effect
				mask = colour(straight, name) * inside(xx, yy, (left, top, right, bottom), 3)
				level = FLICKER[(k + shift) % FRAMES] if how == "flicker" else math.sin(turn + shift * 2 * math.pi / FRAMES)
				gain *= 1 + strength * level * mask
			elif kind == "bands":
				_, left, top, right, bottom, name, strength = effect[:7]
				mask = colour(straight, name) * inside(xx, yy, (left, top, right, bottom), 2)
				length = effect[7] if len(effect) > 7 else (20.0 if name == "water" else 11.0)
				phase = 2 * math.pi * ((xx * 0.8 + yy * 1.6) / length) - turn
				gain *= 1 + strength * (np.sin(phase) + 0.4 * np.sin(2 * phase + 1.3)) * mask
			elif kind == "wobble":
				_, left, top, right, bottom, reach = effect
				weight = inside(xx, yy, (left, top, right, bottom), 6)
				dy += weight * reach * np.sin(turn + xx * 0.1 + yy * 0.05)
				dx += weight * reach * 0.5 * np.sin(turn + yy * 0.12 + 1.0)
			elif kind == "bob":
				_, x, y, radius, reach, phase = effect
				near = 1 - smooth(radius + 1, radius + 6, np.hypot(xx - x, yy - y))
				dy += near * reach * math.sin(turn + phase)
			elif kind == "sway":
				_, left, top, right, bottom, reach = effect
				rise = np.clip((bottom - yy) / max(bottom - top, 1), 0, 1)
				weight = smooth(left, left + 5, xx) * smooth(right, right - 5, xx) * (yy >= top) * (yy <= bottom)
				dx += weight * reach * rise * np.sin(turn + rise * 2.6)
			elif kind == "fire":
				_, left, top, right, bottom, reach = effect
				rise = np.clip((bottom - yy) / max(bottom - top, 1), 0, 1)
				weight = inside(xx, yy, (left, top, right, bottom), 5)
				# a tall fire ripples in long waves, a small one in short ones
				length = max(13.0, (bottom - top) / 3.0)
				dx += weight * reach * (0.4 + rise) * np.sin(2 * math.pi * yy / length + turn)
				dy += weight * reach * 0.7 * rise * np.sin(2 * math.pi * xx / (length * 1.3) - turn)
			elif kind == "cloth":
				pass  # after the rest, below
			else:
				raise ValueError(kind)
		frame = sample(base, xx - dx, yy - dy)
		frame[..., :3] *= gain[..., None]
		for i, (effect, mask) in enumerate(cloths):
			top, bottom, reach = effect[2], effect[4], effect[6]
			depth = np.clip((yy - top) / max(bottom - top, 1), 0, 1)
			shift = reach * depth ** 1.1 * np.sin(turn - depth * 2.4 + i * 1.7)
			soft = mask.astype(np.float64)[..., None]
			from_cloth = sample(soft, xx - shift, yy)[..., 0] > 0.5
			moved = sample(frame * soft, xx - shift, yy)
			rest = np.where(mask[..., None], row_fill(frame, mask), frame)
			frame = np.where(from_cloth[..., None], moved + rest * (1 - moved[..., 3:4] / 255.0), rest)
		frame = np.clip(frame, 0, 255)
		alpha = np.maximum(frame[..., 3:4], 1e-6)
		frame[..., :3] = np.clip(frame[..., :3] * 255.0 / alpha, 0, 255)
		out.append(Image.fromarray(frame.astype(np.uint8), "RGBA"))
	return out


def tile_of(source: tuple[str, int, int, int]) -> Image.Image:
	"""The piece's tile on its sheet."""
	name, hframes, vframes, frame = source
	sheet = Image.open(MAPS / name).convert("RGBA")
	w, h = sheet.width // hframes, sheet.height // vframes
	return sheet.crop(((frame % hframes) * w, (frame // hframes) * h, (frame % hframes) * w + w, (frame // hframes) * h + h))


def rewire(text: str, strip_res: str, fps: int) -> str:
	"""The scene on its strip, with its ambient player."""
	step = 1.0 / fps
	visual = text.index('[node name="Visual"')
	end = text.find("\n[", visual + 1)
	end = len(text) if end < 0 else end + 1
	block = text[visual:end]
	resources = ""
	sheet_id = re.search(r'\[ext_resource type="Script" path="res://game/runtime/sheet_sprite.gd" id="([^"]+)"\]', text)
	texture = re.search(r'texture = ExtResource\("([^"]+)"\)\n', block)
	if texture:
		# a Texture2D on the old sheet: the sheet sprite reads the strip instead
		block = block.replace(texture.group(0), "")
		if text.count(f'ExtResource("{texture.group(1)}")') == 1:
			text_head = re.sub(r'\[ext_resource type="Texture2D"[^\]]*id="%s"\]\n' % re.escape(texture.group(1)), "", text[:visual])
		else:
			text_head = text[:visual]
	else:
		text_head = text[:visual]
	if sheet_id is None:
		resources += '[ext_resource type="Script" path="res://game/runtime/sheet_sprite.gd" id="ambient_sheet"]\n'
	resources += '[ext_resource type="Script" path="res://game/runtime/animation_player.gd" id="ambient_player"]\n'
	sheet_ref = sheet_id.group(1) if sheet_id else "ambient_sheet"
	block = re.sub(r"hframes = \d+\n", "", block)
	block = re.sub(r"vframes = \d+\n", "", block)
	block = re.sub(r"frame = \d+\n", "", block)
	block = re.sub(r'script = ExtResource\("[^"]+"\)\n', "", block)
	block = re.sub(r'sheet_path = "[^"]*"\n', "", block)
	block = block.rstrip("\n") + f'\nhframes = {FRAMES}\nscript = ExtResource("{sheet_ref}")\nsheet_path = "{strip_res}"\n\n'
	animation = (
		'[sub_resource type="Animation" id="ambient_idle"]\n'
		'resource_name = "object.ambient.idle"\n'
		f"length = {FRAMES * step:g}\n"
		"loop_mode = 1\n"
		f"step = {step:g}\n"
		'tracks/0/type = "value"\n'
		"tracks/0/imported = false\n"
		"tracks/0/enabled = true\n"
		'tracks/0/path = NodePath("Visual:frame")\n'
		"tracks/0/interp = 1\n"
		"tracks/0/loop_wrap = false\n"
		"tracks/0/keys = {\n"
		f'"times": PackedFloat32Array({", ".join(f"{k * step:g}" for k in range(FRAMES))}),\n'
		f'"transitions": PackedFloat32Array({", ".join(["1"] * FRAMES)}),\n'
		'"update": 1,\n'
		f'"values": [{", ".join(str(k) for k in range(FRAMES))}]\n'
		"}\n\n"
		'[sub_resource type="AnimationLibrary" id="ambient_library"]\n'
		'_data = {\n&"object.ambient.idle": SubResource("ambient_idle")\n}\n\n'
	)
	text = text_head + block + text[end:]
	# the new resources go after the scene's last ext_resource (or its header), the clip before its
	# first sub_resource or node
	found = list(re.finditer(r"^\[ext_resource [^\n]*\]\n", text, re.M))
	at = found[-1].end() if found else text.index("\n", text.index("[gd_scene")) + 2
	text = text[:at] + resources + text[at:]
	first = min(i for i in (text.find("[sub_resource "), text.find("[node ")) if i >= 0)
	text = text[:first] + animation + text[first:]
	return text.rstrip("\n") + (
		'\n\n[node name="AmbientAnimation" type="AnimationPlayer" parent="."]\n'
		"process_mode = 3\n"
		'libraries/ = SubResource("ambient_library")\n'
		'autoplay = &"object.ambient.idle"\n'
		'script = ExtResource("ambient_player")\n'
		"randomize_start = true\n"
	)


def main() -> None:
	preview = [arg.split("=", 1)[1] for arg in sys.argv[1:] if arg.startswith("--preview=")]
	boxes = "--boxes" in sys.argv
	wanted = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
	for rel, (fps, source, effects) in PIECES.items():
		name = rel.split("/")[-1]
		if wanted and not any(w in name for w in wanted):
			continue
		path = SCENES / f"{rel}.tscn"
		text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
		tile = tile_of(source)
		effects = resolved(tile, effects)
		frames = frames_of(tile, effects)
		if preview:
			out = Path(preview[0])
			out.mkdir(parents=True, exist_ok=True)
			shots = []
			for frame in frames:
				shot = Image.new("RGBA", frame.size, (92, 62, 40, 255))
				shot.alpha_composite(frame)
				if boxes:
					draw = ImageDraw.Draw(shot)
					for effect in effects:
						if effect[0] == "bob":
							draw.ellipse([effect[1] - effect[3], effect[2] - effect[3], effect[1] + effect[3], effect[2] + effect[3]], outline=(255, 255, 0, 255))
						elif effect[0] == "flame":
							draw.rectangle([effect[1] - effect[3], effect[2] - effect[4], effect[1] + effect[3], effect[2]], outline=(255, 0, 255, 255))
						else:
							draw.rectangle(list(effect[1:5]), outline=(0, 255, 255, 255))
				shots.append(shot.resize((frame.width * 3, frame.height * 3), Image.NEAREST).convert("RGB"))
			shots[0].save(out / f"{name}.gif", save_all=True, append_images=shots[1:], duration=round(1000 / fps), loop=0)
			sheet = Image.new("RGB", (shots[0].width * 4, shots[0].height))
			for i, k in enumerate((0, 2, 4, 6)):
				sheet.paste(shots[k], (i * shots[0].width, 0))
			sheet.save(out / f"{name}.png")
			print(f"{name}: preview")
			continue
		strip = Image.new("RGBA", (tile.width * FRAMES, tile.height), (0, 0, 0, 0))
		for k, frame in enumerate(frames):
			strip.alpha_composite(frame, (k * tile.width, 0))
		folder = Path(source[0]).parent / "ambient"
		(MAPS / folder).mkdir(parents=True, exist_ok=True)
		save_game_webp(strip, MAPS / folder / f"{name}.webp")
		if "AmbientAnimation" not in text:
			path.write_text(rewire(text, f"{MAPS_RES}/{folder.as_posix()}/{name}.webp", fps), encoding="utf-8", newline="\n")
			print(f"{name}: strip written, scene rewired ({fps} fps)")
		else:
			print(f"{name}: strip written")


if __name__ == "__main__":
	main()
