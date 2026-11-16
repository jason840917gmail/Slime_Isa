"""Prompts for the balcony, cave mouth and wall hole of each wall style (from the meadow-rock ones of
2026-11-13, with stones the wall's size). `python prompts.py <style> <kind>` prints one; `--json`
dumps them all."""
import json
import sys

STYLE = ("Cozy storybook woodland game art, hand-painted 2D miniature, three-quarter top-down view, "
         "chunky rounded shapes, warm golden light from the upper left, soft painted shading with visible "
         "wood grain, moss and cloth texture, dark warm brown outline, earthy palette of honey wood, leaf "
         "green, cream and toadstool red, no text.")

# wall: the wall named; stones: the rim/frame pieces; floor: the balcony's top (and its short name);
# cave/hole: extra dressing; shape: the outer silhouette's pieces.
SPECS = {
    "snow-rock": dict(
        wall="snowy granite cliff wall",
        stones="rounded pale blue-grey granite boulders with white snow caps on their tops and frosty joints",
        floor="snow-covered", floor_short="snow",
        cave=", a few short icicles hanging from the top stones", hole=", a little snow on the top stones",
        shape="whole stones"),
    "desert-strata": dict(
        wall="layered sandstone canyon wall",
        stones="flat stacked slabs of layered orange sandstone in thin horizontal strata, with chipped "
               "edges and ochre and rust bands",
        floor="pale golden sand", floor_short="sand",
        cave=" and a few small dry desert tufts", hole="", shape="stacked slabs"),
    "castle-face": dict(
        wall="castle wall of dressed cream stone blocks",
        stones="pale cream dressed stone blocks with softly rounded edges and thin mortar joints, a few "
               "small tufts of grass in the joints",
        floor="pale cream flagstone", floor_short="paving",
        cave=", wedge-shaped blocks over the top of the arch", hole="", shape="whole blocks"),
    "crystal-rock": dict(
        wall="crystal cave wall of dark slate-blue boulders",
        stones="rounded dark slate-blue boulders with small violet and teal crystal clusters growing in "
               "their joints",
        floor="dark blue-grey stone cave", floor_short="stone floor",
        cave="", hole="", shape="whole stones"),
    "autumn-face": dict(
        wall="rust-orange earthen cliff face of tall rock columns",
        stones="chunky blocks of rust-orange and brown earthen rock with vertical ridges, a few dry grass "
               "tufts and fallen orange leaves",
        floor="leaf-strewn grassy", floor_short="grass",
        cave="", hole="", shape="rock blocks"),
    "cave-face": dict(
        wall="dark cave cliff face of tall slate-grey rock columns",
        stones="chunky dark slate-grey rock blocks with vertical ridges and cracks",
        floor="dark grey stone cave", floor_short="stone floor",
        cave="", hole="", shape="rock blocks"),
    "cave-rock": dict(
        wall="cave wall of rounded dark grey boulders",
        stones="rounded dark grey-brown boulders with tiny pale mushrooms and specks of blue crystal in "
               "their joints",
        floor="dark brown earthen cave", floor_short="earth",
        cave="", hole="", shape="whole stones"),
    "crystal-face": dict(
        wall="crystal cave cliff face of dark navy rock columns",
        stones="chunky dark navy-blue rock blocks with vertical ridges, studded with small violet and blue "
               "crystals",
        floor="dark navy stone cave", floor_short="stone floor",
        cave="", hole="", shape="rock blocks"),
    "desert-dirt": dict(
        wall="desert cliff of smooth wind-carved orange sand-rock",
        stones="smooth wind-carved lumps of orange desert sand-rock with wavy layers and small pebbles",
        floor="pale golden sand", floor_short="sand",
        cave="", hole="", shape="lumps of sand-rock"),
    "desert-face": dict(
        wall="desert canyon cliff face of tall orange rock columns and blocky ledges",
        stones="chunky blocky orange desert rock with flat tops and vertical cracks",
        floor="pale golden sand", floor_short="sand",
        cave=" and a few small dry desert tufts", hole="", shape="rock blocks"),
    "dungeon-face": dict(
        wall="dungeon wall of dark blue-grey rough stone blocks",
        stones="dark blue-grey rough-cut stone blocks with thin dark joints",
        floor="dark grey flagstone", floor_short="paving",
        cave=", wedge-shaped blocks over the top of the arch", hole="", shape="whole blocks"),
    "forest-face": dict(
        wall="forest cliff face of dark brown earth with mossy roots",
        stones="chunky lumps of dark brown earth and rock covered in green moss, with roots running over them",
        floor="mossy green forest", floor_short="moss",
        cave=", a few roots hanging from the top", hole="", shape="mossy lumps"),
    "ice-dirt": dict(
        wall="frozen earth cliff of brown soil with patches of snow and ice",
        stones="chunky lumps of frozen brown earth and rounded pebbles with patches of white snow on top",
        floor="snow-covered", floor_short="snow",
        cave=", a few short icicles hanging from the top", hole="", shape="frozen lumps"),
    "masonry": dict(
        wall="town wall of large dressed tan stone blocks",
        stones="large dressed tan stone blocks with bevelled edges and dark mortar joints",
        floor="tan flagstone", floor_short="paving",
        cave=", wedge-shaped blocks over the top of the arch", hole="", shape="whole blocks"),
    "meadow-face": dict(
        wall="meadow cliff face of tall golden-brown rock columns",
        stones="chunky golden-brown rock blocks with vertical ridges and small grass tufts",
        floor="grassy", floor_short="grass",
        cave="", hole="", shape="rock blocks"),
    "mossy-rock": dict(
        wall="mossy fieldstone wall of rounded grey-brown boulders",
        stones="rounded grey-brown boulders thickly covered in bright yellow-green moss",
        floor="mossy green", floor_short="moss",
        cave="", hole="", shape="whole stones"),
    "mountain-dirt": dict(
        wall="mountain cliff of reddish-brown earth with rounded stones and roots in it",
        stones="chunky lumps of reddish-brown earth with rounded grey pebbles and small roots in them",
        floor="grassy", floor_short="grass",
        cave="", hole="", shape="earth lumps"),
    "red-rock": dict(
        wall="red rock wall of rounded red-orange boulders",
        stones="rounded red-orange boulders with warm highlights",
        floor="leaf-strewn grassy", floor_short="grass",
        cave="", hole="", shape="whole stones"),
    "root-rock": dict(
        wall="forest wall of rounded dark brown boulders laced with tree roots",
        stones="rounded dark olive-brown boulders laced with thin tree roots and a few tiny mushrooms",
        floor="leaf-strewn dark forest earth", floor_short="earth",
        cave="", hole="", shape="whole stones"),
    "sandstone": dict(
        wall="sandstone wall of rounded honey-orange boulders",
        stones="rounded honey-orange sandstone boulders with soft layered highlights",
        floor="pale golden sand", floor_short="sand",
        cave="", hole="", shape="whole stones"),
    "snow-face": dict(
        wall="ice cliff face of tall pale blue ice columns capped with snow",
        stones="chunky pale blue ice blocks capped with white snow",
        floor="snow-covered", floor_short="snow",
        cave=", a few short icicles hanging from the top", hole="", shape="ice blocks"),
    "storybook-rock": dict(
        wall="wall of large rounded rectangular brown stone blocks",
        stones="large rounded rectangular warm brown stone blocks with soft bevelled edges",
        floor="grassy", floor_short="grass",
        cave="", hole="", shape="whole blocks"),
    "town-face": dict(
        wall="weathered town wall of mossy olive-yellow cobblestones",
        stones="rounded olive-yellow cobblestones with green moss and tiny flowers in their joints",
        floor="mossy cobblestone", floor_short="cobbles",
        cave="", hole="", shape="whole stones"),
    "volcanic-face": dict(
        wall="volcanic cliff face of tall dark charcoal basalt columns",
        stones="chunky dark charcoal basalt blocks with sharp vertical ridges and faint red-brown cracks, "
               "no glowing lava",
        floor="dark grey volcanic ash", floor_short="ash",
        cave="", hole="", shape="basalt blocks"),
}
BATCH = ["autumn-face", "cave-face", "cave-rock", "crystal-face", "desert-dirt", "desert-face",
         "dungeon-face", "forest-face", "ice-dirt", "masonry", "meadow-face", "mossy-rock", "mountain-dirt",
         "red-rock", "root-rock", "sandstone", "snow-face", "storybook-rock", "town-face", "volcanic-face"]

MATCH = ("The stones match the stones of the second reference image exactly: the same colour, the same "
         "shapes, the same dark brown outlines, and the same size: big stones, each as big as one stone "
         "of that wall, {count}.")


def prompt(style: str, kind: str) -> str:
    s = SPECS[style]
    if kind == "balcony":
        body = (f"A single game prop: a natural rock balcony ledge that juts straight out of a tall {s['wall']}, "
                "seen from the front and slightly from above. Its top is a flat, plain, empty "
                f"{s['floor']} floor to stand on, wide and shallow like half an oval. The back edge is open "
                "and cut perfectly straight and horizontal across the whole width, as if sliced with a knife "
                f"where it meets the wall: no stones along the back edge, the {s['floor_short']} runs right "
                "up to that straight cut. Only round the two sides and the rounded front runs a thick rim of "
                f"{s['stones']}, and under the rim a short chunky rock underside of the same stone that "
                "tapers back and down, darker in its own shade. "
                + MATCH.format(count="only about six of them along the front") +
                " Only the ledge itself, centred, filling most of the frame: no wall behind it, no cave, no "
                "door, no character, no plants standing on it, no glow, no haze.")
    elif kind == "cave-mouth":
        body = (f"A single game prop seen straight from the front: the mouth of a cave in a {s['wall']}. A "
                "wide arched opening, flat along the bottom where the floor is, its inside a deep warm dark "
                "brown fading to near black. All round the arch, on its two sides and over its top, a thick "
                f"irregular frame of {s['stones']}{s['cave']}. "
                + MATCH.format(count="only about seven of them round the whole arch") +
                f" Only the opening and its frame, with an uneven outer silhouette of {s['shape']}, centred, "
                "filling most of the frame: no wall around it, no ground, no door leaf, no torches, no "
                "character, no glow, no haze.")
    elif kind == "wall-hole":
        body = (f"A single game prop seen straight from the front: a small round burrow hole in a {s['wall']}, "
                "just big enough for a small creature to squeeze through. A rough round opening, its inside "
                "a deep warm dark brown fading to near black, ringed by a single thick ring of "
                f"{s['stones']}{s['hole']}. "
                + MATCH.format(count="only five or six of them round the whole ring") +
                f" Only the hole and its ring, with an uneven outer silhouette of {s['shape']}, centred, "
                "filling most of the frame: no wall around it, no ground, no character, no glow, no haze.")
    else:
        raise ValueError(kind)
    return f"{STYLE} {body} Isolated on a transparent background, no ground shadow plate, no scenery."


if __name__ == "__main__":
    if sys.argv[1] == "--json":
        print(json.dumps({f"{st}/{k}": prompt(st, k) for st in SPECS for k in ("balcony", "cave-mouth", "wall-hole")}, indent=1))
    else:
        print(prompt(sys.argv[1], sys.argv[2]))
