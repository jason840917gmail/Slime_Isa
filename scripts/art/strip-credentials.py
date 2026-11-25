#!/usr/bin/env python3
"""Takes the generator's credentials block out of PNG sources, without touching a pixel.

Magnific (and other generators) embed a content-credentials record in each PNG they hand back, as one
`caBX` chunk. It holds no picture: it is the record of how the image was made, and for an edit of an
edit it carries the earlier pictures too, so it can be 20 to 50 MB on a sheet whose own image data is
1.5 MB (the Crystal Colossus's frame sheets, found 2026-11-25: 1.15 GB of it in asset/Originals/).
The game never reads these files (the art tools cut them into the runtime sheets in godot/asset/), so
the block only costs space in git.

This copies every other chunk of the file byte for byte (the header, the palette, the image data, in
their order) and leaves the `caBX` chunks out: the picture decodes to the same pixels.

Usage: python scripts/art/strip-credentials.py [--check] [<file or folder> ...]
       no path: asset/Originals/
       --check: change nothing, list the files that carry the block, exit 1 when there is one
                (run it before committing new sources)

Needs no package (Pillow only with --verify, which decodes each picture before and after).
"""
from __future__ import annotations

import os
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = ROOT / "asset" / "Originals"
SIGNATURE = b"\x89PNG\r\n\x1a\n"
DROPPED = (b"caBX",)
MB = 1024 * 1024


def chunks(data: bytes):
	"""Each chunk of a PNG as (type, whole chunk bytes with its length and checksum)."""
	at = len(SIGNATURE)
	while at + 8 <= len(data):
		length, kind = struct.unpack(">I4s", data[at:at + 8])
		end = at + 12 + length
		yield kind, data[at:end]
		at = end


def stripped(data: bytes) -> bytes | None:
	"""The file without its credentials chunks; None when it has none or is not a whole PNG."""
	if not data.startswith(SIGNATURE):
		return None
	kept = [SIGNATURE]
	dropped = False
	last = b""
	for kind, whole in chunks(data):
		last = kind
		if kind in DROPPED:
			dropped = True
		else:
			kept.append(whole)
	if not dropped or last != b"IEND":
		return None
	return b"".join(kept)


def pixels(path: Path) -> bytes:
	from PIL import Image
	Image.MAX_IMAGE_PIXELS = None
	with Image.open(path) as image:
		return image.mode.encode() + bytes(str(image.size), "ascii") + image.tobytes()


def files(paths: list[Path]):
	for path in paths:
		if path.is_dir():
			for folder, _dirs, names in os.walk(path):
				for name in sorted(names):
					if name.lower().endswith(".png"):
						yield Path(folder) / name
		elif path.suffix.lower() == ".png":
			yield path


def main() -> int:
	args = sys.argv[1:]
	check = "--check" in args
	verify = "--verify" in args
	paths = [Path(a) for a in args if not a.startswith("--")] or [DEFAULT]
	found = 0
	saved = 0
	for path in files(paths):
		data = path.read_bytes()
		out = stripped(data)
		if out is None:
			continue
		found += 1
		saved += len(data) - len(out)
		if check:
			print(f"{(len(data) - len(out)) / MB:8.2f} MB  {path}")
			continue
		before = pixels(path) if verify else b""
		scratch = path.with_name(path.name + ".stripping")
		scratch.write_bytes(out)
		if verify and pixels(scratch) != before:
			scratch.unlink()
			print(f"NOT STRIPPED (the picture would change): {path}")
			return 2
		os.replace(scratch, path)
	verb = "carry" if check else "stripped:"
	print(f"{found} files {verb} {saved / MB:.1f} MB of credentials blocks")
	return 1 if check and found else 0


if __name__ == "__main__":
	sys.exit(main())
