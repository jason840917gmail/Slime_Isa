"""Packs Chapter 2's item icons and the iron ore node (roadmap 8.3-8.6).

Sources (Magnific GPT-2 on white, cut out by scripts/lib/white_cutout.py):
- asset/Originals/items/chapter-2/<item>-raw.png: the weaver fang, iron bar,
  Reinforced Pickaxe, iron spear and iron axe icons.
- asset/Originals/props/iron-ore/iron-node{,-depleted}-raw.png.

Outputs:
- godot/asset/MAPS/items/chapter-2-5x2.webp: 64 px icons, frames in ICONS order
  (5 to 9 free for later Chapter 2 items).
- godot/asset/MAPS/rocks/128x128-tile_2x1-iron-ore.webp: frame 0 the iron node,
  frame 1 the mined-out rubble, sitting on the bottom edge.

Usage: python scripts/items/pack-chapter-2-art.py
"""
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from game_webp import save_game_webp  # noqa: E402
from white_cutout import cut_out, fit  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ITEMS = ROOT / 'asset' / 'Originals' / 'items' / 'chapter-2'
ORE = ROOT / 'asset' / 'Originals' / 'props' / 'iron-ore'
ICONS = ['weaver-fang', 'iron-bar', 'reinforced-pickaxe', 'iron-spear', 'iron-axe']
ICON = 64
NODE = 128


def main() -> None:
    icons = Image.new('RGBA', (ICON * 5, ICON * 2), (0, 0, 0, 0))
    for index, name in enumerate(ICONS):
        art = cut_out(ITEMS / f'{name}-raw.png')
        art.save(ITEMS / f'{name}.png')
        icons.alpha_composite(fit(art, ICON, fill=0.9), ((index % 5) * ICON, (index // 5) * ICON))
    out = ROOT / 'godot' / 'asset' / 'MAPS' / 'items' / 'chapter-2-5x2.webp'
    print(f'wrote {out.relative_to(ROOT)} ({save_game_webp(icons, out)})')

    nodes = Image.new('RGBA', (NODE * 2, NODE), (0, 0, 0, 0))
    for index, name in enumerate(['iron-node', 'iron-node-depleted']):
        art = cut_out(ORE / f'{name}-raw.png')
        art.save(ORE / f'{name}.png')
        # The rubble keeps its smaller size next to the full boulder.
        nodes.alpha_composite(fit(art, NODE, fill=0.94 if index == 0 else 0.7, anchor='bottom'), (index * NODE, 0))
    out = ROOT / 'godot' / 'asset' / 'MAPS' / 'rocks' / '128x128-tile_2x1-iron-ore.webp'
    print(f'wrote {out.relative_to(ROOT)} ({save_game_webp(nodes, out)})')


if __name__ == '__main__':
    main()
