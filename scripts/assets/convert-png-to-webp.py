"""Converts every PNG that asset/assets.json maps to WebP (roadmap 10.1).

Each image goes through scripts/lib/game_webp.py (lossy quality 90 where the
visible pixels stay sharp, lossless otherwise, transparency always exact),
the manifest path is rewritten in place (the file's formatting is kept), and
the PNG is deleted. asset/Originals is never touched.

Usage:
  python scripts/assets/convert-png-to-webp.py            # report only
  python scripts/assets/convert-png-to-webp.py --write    # convert
Then run `node scripts/rehash-scene-ledger.mjs` (assets.json is a conversion
input) and `pnpm assets:check`.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts' / 'lib'))
from game_webp import encode_game_webp  # noqa: E402

MANIFEST = ROOT / 'asset' / 'assets.json'


def mapped_pngs(node: object) -> set[str]:
    found: set[str] = set()
    if isinstance(node, dict):
        for key, value in node.items():
            if key == 'path' and isinstance(value, str) and value.lower().endswith('.png'):
                found.add(value)
            else:
                found |= mapped_pngs(value)
    elif isinstance(node, list):
        for value in node:
            found |= mapped_pngs(value)
    return found


def main() -> None:
    write = '--write' in sys.argv
    with open(MANIFEST, encoding='utf8', newline='') as handle:
        text = handle.read()
    paths = sorted(mapped_pngs(json.loads(text)))
    before = after = 0
    kinds = {'lossy': 0, 'lossless': 0}
    for relative in paths:
        source = ROOT / 'asset' / relative
        target = source.with_suffix('.webp')
        data, kind, psnr = encode_game_webp(Image.open(source))
        size = source.stat().st_size
        before += size
        after += len(data)
        kinds[kind] += 1
        print(f'{kind:8} {psnr:5.1f} dB  {size / 1e6:6.2f} -> {len(data) / 1e6:5.2f} MB  {relative}')
        if not write:
            continue
        target.write_bytes(data)
        quoted = json.dumps(relative)
        if text.count(quoted) == 0:
            raise RuntimeError(f'{relative} not found verbatim in assets.json')
        text = text.replace(quoted, json.dumps(str(Path(relative).with_suffix('.webp')).replace('\\', '/')))
        source.unlink()
    if write:
        with open(MANIFEST, 'w', encoding='utf8', newline='') as handle:
            handle.write(text)
    print(f'{len(paths)} images: {before / 1e6:.1f} MB -> {after / 1e6:.1f} MB '
          f'({kinds["lossy"]} lossy, {kinds["lossless"]} lossless){"" if write else " (report only; pass --write)"}')


if __name__ == '__main__':
    main()
