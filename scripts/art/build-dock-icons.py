"""Draws the Scenery dock's icons of the pieces that have no art of their own to show
(docs/godot/PROPS.md "The Scenery dock"; godot/addons/scenery_dock/scene_pictures.gd): markers the
editor draws as outlines (a room door, a room fight, a hazard, a hazard deck, a plank landing) and
the prize glint, which the game draws as a star. Each is 96 x 96, in the colours its script uses
in the editor, written to `godot/asset/MAPS/palettes/dock/` (a folder left out of exported games).

    python scripts/art/build-dock-icons.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parents[2]
ART = REPO / "godot" / "asset" / "MAPS" / "objects" / "dungeon"
OUT = REPO / "godot" / "asset" / "MAPS" / "palettes" / "dock"
SIZE, SS = 96, 4  # drawn SS times larger, then shrunk
DOOR_OK = (89, 217, 115)  # room_door.gd OK_COLOR
FIGHT = (255, 115, 64)  # room_fight.gd OUTLINE
HAZARD_EDGE = (255, 77, 153)  # hazard.gd EDITOR_EDGE
DECK_EDGE = (102, 230, 255)  # hazard_deck.gd EDITOR_EDGE
ABYSS = (7, 5, 12)  # hazard.gd ABYSS
GLINT_CORE, GLINT_HALO = (255, 250, 217), (255, 217, 102)  # prize_glint.gd


def canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def s(*values: float) -> tuple[float, ...]:
    return tuple(v * SS for v in values)


def done(image: Image.Image, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    image.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.png")
    print(f"wrote {(OUT / name).relative_to(REPO)}.png")


def frame_of(path: Path, columns: int, frame: int, box: tuple[int, int]) -> Image.Image:
    """A sheet's frame, fitted into `box` (px of the icon)."""
    sheet = Image.open(path).convert("RGBA")
    width = sheet.width // columns
    cell = sheet.crop((frame * width, 0, (frame + 1) * width, sheet.height))
    cell = cell.crop(cell.getbbox())
    scale = min(box[0] * SS / cell.width, box[1] * SS / cell.height)
    return cell.resize((round(cell.width * scale), round(cell.height * scale)), Image.LANCZOS)


def outlined(draw: ImageDraw.ImageDraw, colour: tuple[int, int, int], fill_alpha: int = 64) -> None:
    """The marker's area as the editor draws it: a see-through fill and an outline."""
    draw.rounded_rectangle(s(8, 8, 88, 88), radius=6 * SS, fill=colour + (fill_alpha,), outline=colour + (235,), width=4 * SS)


def arrow(draw: ImageDraw.ImageDraw, colour: tuple[int, int, int], tail: tuple[float, float], tip: tuple[float, float]) -> None:
    draw.line(s(*tail, *tip), fill=colour + (255,), width=6 * SS)
    angle = math.atan2(tip[1] - tail[1], tip[0] - tail[0])
    head = [tip] + [(tip[0] - 16 * math.cos(angle + turn), tip[1] - 16 * math.sin(angle + turn)) for turn in (0.5, -0.5)]
    draw.polygon([s(*point) for point in head], fill=colour + (255,))


def room_door() -> None:
    image, draw = canvas()
    outlined(draw, DOOR_OK)
    # a doorway and the way through it
    draw.rounded_rectangle(s(34, 22, 62, 60), radius=12 * SS, fill=(20, 28, 22, 230), outline=DOOR_OK + (255,), width=3 * SS)
    arrow(draw, DOOR_OK, (48, 80), (48, 40))
    done(image, "room-door")


def room_fight() -> None:
    image, draw = canvas()
    outlined(draw, FIGHT)
    for sign in (1, -1):  # two crossed swords
        hilt, tip = (48 - 26 * sign, 72), (48 + 24 * sign, 22)
        draw.line(s(*hilt, *tip), fill=(240, 240, 235, 255), width=7 * SS)
        draw.line(s(*hilt, *tip), fill=(170, 176, 186, 255), width=2 * SS)
        cross = (48 - 14 * sign, 60)
        draw.line(s(cross[0] - 9 * sign, cross[1] - 9, cross[0] + 9 * sign, cross[1] + 9), fill=FIGHT + (255,), width=6 * SS)
        draw.ellipse(s(hilt[0] - 5, hilt[1] - 5, hilt[0] + 5, hilt[1] + 5), fill=FIGHT + (255,))
    done(image, "room-fight")


def hazard() -> None:
    image, draw = canvas()
    draw.rounded_rectangle(s(8, 8, 88, 88), radius=6 * SS, fill=ABYSS + (235,))
    spikes = Image.open(ART / "spikes.webp").convert("RGBA").crop((0, 0, 128, 128)).resize((64 * SS, 64 * SS), Image.LANCZOS)
    image.alpha_composite(spikes, (16 * SS, 16 * SS))
    draw.rounded_rectangle(s(8, 8, 88, 88), radius=6 * SS, outline=HAZARD_EDGE + (235,), width=4 * SS)
    done(image, "hazard")


def deck(name: str, art: Path) -> None:
    """Safe ground over a hazard: the piece on the dark, in the deck's outline."""
    image, draw = canvas()
    draw.rounded_rectangle(s(8, 8, 88, 88), radius=6 * SS, fill=ABYSS + (235,))
    piece = frame_of(art, 2, 0, (64, 64))
    image.alpha_composite(piece, ((SIZE * SS - piece.width) // 2, (SIZE * SS - piece.height) // 2))
    draw.rounded_rectangle(s(8, 8, 88, 88), radius=6 * SS, outline=DECK_EDGE + (235,), width=4 * SS)
    done(image, name)


def prize_glint() -> None:
    image, draw = canvas()
    halo = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse(s(18, 18, 78, 78), fill=GLINT_HALO + (120,))
    image.alpha_composite(halo.filter(ImageFilter.GaussianBlur(8 * SS)))
    star = []
    for index in range(8):  # a four-pointed star
        radius = 40 if index % 2 == 0 else 9
        angle = math.pi / 4 * index - math.pi / 2
        star.append(s(48 + radius * math.cos(angle), 48 + radius * math.sin(angle)))
    draw.polygon(star, fill=(255, 236, 160, 255))
    draw.ellipse(s(40, 40, 56, 56), fill=GLINT_CORE + (255,))
    done(image, "prize-glint")


def main() -> None:
    room_door()
    room_fight()
    hazard()
    deck("hazard-deck", ART / "slab-2x1.webp")
    deck("plank-landing", ART / "plank-2x1.webp")
    prize_glint()


if __name__ == "__main__":
    main()
