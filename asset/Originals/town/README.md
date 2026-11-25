# Town set (West village, 2026-11-01)

Magnific GPT 2.5 (`gpt-2-mini`), transparent background, the interior mushroom furniture sheet
(`godot/asset/MAPS/interiors/192x192-tile_8x8-interior-mushroom-furniture-props.webp`) as style
reference, two results per prompt (`-a`, `-b`). Every prompt starts with the style block of
[docs/assets/visual-style-guide.md](../../../docs/assets/visual-style-guide.md#generating-assets) and
ends with "Isolated on a transparent background, no ground shadow plate, no scenery, no labels, no
grid lines."

The owner picked version a of the first four sheets ("All, version a"), and of `multi` and `large`
all but the apartment house and the manor (L2, L3: "I don't like"). Each picked sheet also has
`<sheet>-a-up.jpg`: Magnific Precision (sublime) 2x, grain 0, sharpness 7, which
`scripts/art/pack-town-art.py` uses for colour under the original's alpha.

| Sheet | Grid | Subject |
|---|---|---|
| `houses` | 3 x 2 | six small homes for a slime village: a lime jelly dome, a hollowed pumpkin, a tree-stump house, a cream and caramel snail shell, a narrow two-storey timber townhouse with a teal scalloped roof, a round cottage whose thatch is a water drop with a curled tip |
| `civic` | 2 x 2 | the town centre: a general store (striped awning, goo jars, jar sign), a two-storey inn (mug sign, porch), a stone and timber gatekeeper's house with a bell tower, a striped throwing-game booth with targets and rings |
| `garden` | 4 x 3 | cabbage bed, carrot bed, pumpkin patch, stone-edged tulip bed, boxwood hedge, its corner, white picket fence, gravel square with cobble edging, four stepping stones, raised herb planter, blueberry bush, sack scarecrow with a stitched slime face |
| `props` | 4 x 4 | goo fountain, market stall, signpost with blank arrows, notice board with blank papers, street lamp with a goo jar, three barrels, crates and a sack, bench, flower cart, mailbox, slime statue, clothesline, wheelbarrow of soil, rain barrel under a gutter, straw beehive, water trough |
| `multi` | 2 x 2 | shared homes, a door each: a duplex with a stone firewall (red and blue doors), a row of three townhouses (teal, red, honey roofs), two flats with an outside stair to an upper door, twin mushroom houses grown together (the houses and civic sheets as extra references) |
| `large` | 2 x 2 | large many-room buildings: a town hall with a clock tower and a jelly-drop finial, a three-storey apartment house with outside stairs and a door per flat, an L-shaped manor with a walled front courtyard, a goo bathhouse with three jelly domes and steam (the houses and civic sheets as extra references) |

`west-town-pick-board.jpg` and `west-town-pick-board-2.jpg` number every item (H, T, G, P, M, L);
`west-town-mockup.jpg` placed the version-a cut-outs on the West village's ground at game scale;
`west-town-render-1.jpg` to `-4.jpg` are the packed scenes rendered there in Godot (3: painted hedges; 4: garden soil and gravel paths)
(test placements; the world scene was not edited).
